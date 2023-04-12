// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {MakerUtility, IMakerUtility} from 'src/utilities/MakerUtility.sol';
import {Router, IRouter} from 'src/Router.sol';
import {IAgent} from 'src/interfaces/IAgent.sol';
import {IParam} from 'src/interfaces/IParam.sol';
import {SpenderPermitUtils} from 'test/utils/SpenderPermitUtils.sol';
import {MakerCommonUtils, IMakerManager, IMakerVat, IDSProxyRegistry} from 'test/utils/MakerCommonUtils.sol';
import {SafeCast160} from 'permit2/libraries/SafeCast160.sol';

contract MakerUtilityTest is Test, MakerCommonUtils, SpenderPermitUtils {
    using SafeCast160 for uint256;

    uint256 public constant SKIP = 0x8000000000000000000000000000000000000000000000000000000000000000;
    address public constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public user;
    uint256 public userPrivateKey;
    address public userDSProxy;
    IRouter public router;
    IAgent public agent;
    IMakerUtility public makerUtility;
    address public makerUtilityDSProxy;

    // Empty arrays
    address[] public tokensReturnEmpty;
    IParam.Fee[] public feesEmpty;
    IParam.Input[] public inputsEmpty;

    function setUp() external {
        (user, userPrivateKey) = makeAddrAndKey('User');
        router = new Router(makeAddr('WrappedNative'), makeAddr('Pauser'), makeAddr('FeeCollector'));
        makerUtility = new MakerUtility(address(router), PROXY_REGISTRY, CDP_MANAGER, PROXY_ACTIONS, DAI_TOKEN, JUG);
        makerUtilityDSProxy = IDSProxyRegistry(PROXY_REGISTRY).proxies(address(makerUtility));

        // Setup
        vm.startPrank(user);
        userDSProxy = IDSProxyRegistry(PROXY_REGISTRY).build();
        agent = IAgent(router.newAgent());
        vm.stopPrank();

        // Setup permit2
        spenderSetUp(user, userPrivateKey, router, agent);
        permitToken(IERC20(GEM));

        // Label
        vm.label(address(userDSProxy), 'UserDSProxy');
        vm.label(address(router), 'Router');
        vm.label(address(agent), 'Agent');
        vm.label(address(makerUtility), 'MakerUtility');
        vm.label(address(makerUtilityDSProxy), 'MakerUtilityDSProxy');

        _makerCommonSetUp();
    }

    function testOpenLockETHAndDraw(uint256 ethLockAmount, uint256 daiDrawAmount) external {
        // Calculate minimum collateral amount of ETH and drawing random amount of DAI between minimum and maximum
        IMakerVat vat = IMakerVat(VAT);
        bytes32 ilkETH = bytes32(bytes(ETH_JOIN_NAME));
        (, uint256 rate, uint256 spot, , uint256 dust) = vat.ilks(ilkETH);
        (uint256 daiDrawMin, uint256 minCollateral) = _getDAIDrawMinAndMinCollateral(spot, dust);

        ethLockAmount = bound(ethLockAmount, minCollateral, 1e22);
        deal(user, ethLockAmount);
        uint256 daiDrawMax = _getDAIDrawMaxAmount(ethLockAmount, daiDrawMin, spot, rate);
        daiDrawAmount = bound(daiDrawAmount, daiDrawMin, daiDrawMax);

        // Encode logic
        IParam.Logic[] memory logics = new IParam.Logic[](1);
        logics[0] = _logicOpenLockETHAndDraw(ethLockAmount, daiDrawAmount);

        // Get param before execute
        uint256 userDAIBalanceBefore = IERC20(DAI_TOKEN).balanceOf(user);
        uint256 userCdpCountBefore = IMakerManager(CDP_MANAGER).count(userDSProxy);

        // Execute
        address[] memory tokensReturn = new address[](1);
        tokensReturn[0] = address(DAI_TOKEN);
        vm.prank(user);
        router.execute{value: ethLockAmount}(logics, feesEmpty, tokensReturn, SIGNER_REFERRAL);

        assertEq(IERC20(DAI_TOKEN).balanceOf(address(agent)), 0);
        assertEq(IERC20(DAI_TOKEN).balanceOf(address(makerUtility)), 0);
        assertEq(IERC20(DAI_TOKEN).balanceOf(address(makerUtilityDSProxy)), 0);
        assertEq(address(agent).balance, 0);
        assertEq(address(makerUtility).balance, 0);
        assertEq(address(makerUtilityDSProxy).balance, 0);
        assertEq(IERC20(DAI_TOKEN).balanceOf(user) - userDAIBalanceBefore, daiDrawAmount);
        assertEq(IMakerManager(CDP_MANAGER).count(userDSProxy) - userCdpCountBefore, 1); // cdp count should increase by 1
    }

    function testOpenLockGemAndDraw(uint256 tokenLockAmount, uint256 daiDrawAmount) external {
        // Calculate minimum collateral amount of token and drawing random amount of DAI between minimum and maximum
        IMakerVat vat = IMakerVat(VAT);
        bytes32 ilkToken = bytes32(bytes(TOKEN_JOIN_NAME));
        (, uint256 rate, uint256 spot, , uint256 dust) = vat.ilks(ilkToken);
        (uint256 daiDrawMin, uint256 minCollateral) = _getDAIDrawMinAndMinCollateral(spot, dust);

        tokenLockAmount = bound(tokenLockAmount, minCollateral, 1e23);
        deal(GEM, user, tokenLockAmount);
        uint256 daiDrawMax = _getDAIDrawMaxAmount(tokenLockAmount, daiDrawMin, spot, rate);
        daiDrawAmount = bound(daiDrawAmount, daiDrawMin, daiDrawMax);

        // Encode logic
        IParam.Logic[] memory logics = new IParam.Logic[](3);
        logics[0] = logicSpenderPermit2ERC20PullToken(IERC20(GEM), tokenLockAmount.toUint160());
        logics[1] = _logicTransferERC20ToMakerUtility(GEM, tokenLockAmount);
        logics[2] = _logicOpenLockGemAndDraw(tokenLockAmount, daiDrawAmount);

        // Get param before execute
        uint256 userDAIBalanceBefore = IERC20(DAI_TOKEN).balanceOf(user);
        uint256 userCdpCountBefore = IMakerManager(CDP_MANAGER).count(userDSProxy);

        // Execute
        address[] memory tokensReturn = new address[](1);
        tokensReturn[0] = address(DAI_TOKEN);
        vm.prank(user);
        router.execute(logics, feesEmpty, tokensReturn, SIGNER_REFERRAL);

        assertEq(IERC20(DAI_TOKEN).balanceOf(address(agent)), 0);
        assertEq(IERC20(DAI_TOKEN).balanceOf(address(makerUtility)), 0);
        assertEq(IERC20(DAI_TOKEN).balanceOf(address(makerUtilityDSProxy)), 0);
        assertEq(IERC20(GEM).balanceOf(address(agent)), 0);
        assertEq(IERC20(GEM).balanceOf(address(makerUtility)), 0);
        assertEq(IERC20(GEM).balanceOf(address(makerUtilityDSProxy)), 0);
        assertEq(IERC20(DAI_TOKEN).balanceOf(user) - userDAIBalanceBefore, daiDrawAmount);
        assertEq(IMakerManager(CDP_MANAGER).count(userDSProxy) - userCdpCountBefore, 1); // cdp count should increase by 1
    }

    function _getDAIDrawMinAndMinCollateral(uint256 spot, uint256 dust) internal pure returns (uint256, uint256) {
        uint256 daiDrawMin = dust / 1000000000 ether; // at least draw this much DAI
        uint256 minCollateral = (((daiDrawMin * 1000000000 ether) / spot) * 105) / 100;
        return (daiDrawMin, minCollateral);
    }

    function _getDAIDrawMaxAmount(
        uint256 ilkAmount,
        uint256 daiDrawMin,
        uint256 spot,
        uint256 rate
    ) internal pure returns (uint256) {
        uint256 daiDrawMax = (ilkAmount * spot) / rate;
        return daiDrawMax > daiDrawMin ? daiDrawMax : daiDrawMin;
    }

    function _logicOpenLockETHAndDraw(uint256 value, uint256 amountOutMin) public view returns (IParam.Logic memory) {
        // Data for openLockETHAndDraw
        bytes memory data = abi.encodeWithSelector(
            IMakerUtility.openLockETHAndDraw.selector,
            value,
            ETH_JOIN_A,
            DAI_JOIN,
            bytes32(bytes(ETH_JOIN_NAME)),
            amountOutMin
        );

        // Encode inputs
        IParam.Input[] memory inputs = new IParam.Input[](1);
        inputs[0].token = NATIVE;
        inputs[0].amountBps = SKIP;
        inputs[0].amountOrOffset = value;

        return
            IParam.Logic(
                address(makerUtility),
                data,
                inputs,
                IParam.WrapMode.NONE,
                address(0), // approveTo
                address(0) // callback
            );
    }

    function _logicTransferERC20ToMakerUtility(
        address token,
        uint256 amount
    ) internal view returns (IParam.Logic memory) {
        return
            IParam.Logic(
                token,
                abi.encodeWithSelector(IERC20.transfer.selector, makerUtility, amount),
                inputsEmpty,
                IParam.WrapMode.NONE,
                address(0), // approveTo
                address(0) // callback
            );
    }

    function _logicOpenLockGemAndDraw(uint256 value, uint256 amountOutMin) public view returns (IParam.Logic memory) {
        bytes memory data = abi.encodeWithSelector(
            IMakerUtility.openLockGemAndDraw.selector,
            GEM_JOIN_LINK_A,
            DAI_JOIN,
            bytes32(bytes(TOKEN_JOIN_NAME)),
            value,
            amountOutMin
        );

        return
            IParam.Logic(
                address(makerUtility),
                data,
                inputsEmpty,
                IParam.WrapMode.NONE,
                address(0), // approveTo
                address(0) // callback
            );
    }
}
