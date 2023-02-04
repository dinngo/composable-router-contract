// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {SafeERC20, IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {ERC20} from 'openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import {Router, IRouter} from '../src/Router.sol';
import {SpenderAaveV2Delegation, ISpenderAaveV2Delegation, IAaveV2Provider} from '../src/SpenderAaveV2Delegation.sol';

contract SpenderAaveV2DelegationTest is Test {
    using SafeERC20 for IERC20;

    enum InterestRateMode {
        NONE,
        STABLE,
        VARIABLE
    }

    IAaveV2Provider public constant aaveV2Provider = IAaveV2Provider(0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5);

    address public user;
    IRouter public router;
    ISpenderAaveV2Delegation public spender;
    IERC20 public mockERC20Debt;

    function setUp() external {
        user = makeAddr('User');

        router = new Router();
        spender = new SpenderAaveV2Delegation(address(router), address(aaveV2Provider));
        mockERC20Debt = new ERC20('mockERC20Debt', 'mock');

        // User approved spender aave v2 delegation
        vm.mockCall(
            address(mockERC20Debt),
            0,
            abi.encodeWithSignature('borrowAllowance(address,address)', user, address(spender)),
            abi.encode(type(uint256).max)
        );

        vm.label(address(router), 'Router');
        vm.label(address(spender), 'SpenderAaveV2Delegation');
        vm.label(address(mockERC20Debt), 'mERC20Debt');
        vm.label(address(aaveV2Provider), 'AaveV2Provider');
    }

    // Cannot call spender directly
    function testCannotBeCalledByNonRouter(uint128 amount) external {
        vm.assume(amount > 0);
        deal(address(mockERC20Debt), user, amount);

        vm.startPrank(user);
        vm.expectRevert(ISpenderAaveV2Delegation.InvalidRouter.selector);
        spender.borrow(address(mockERC20Debt), amount, uint256(InterestRateMode.VARIABLE));
        vm.stopPrank();
    }
}
