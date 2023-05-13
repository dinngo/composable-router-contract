// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IAgent2} from './IAgent2.sol';
import {IParam2} from './IParam2.sol';

interface IRouter2 {
    event SignerAdded(address indexed signer);

    event SignerRemoved(address indexed signer);

    event FeeCollectorSet(address indexed feeCollector_);

    event PauserSet(address indexed pauser);

    event Paused();

    event Resumed();

    event Execute(address indexed user, address indexed agent, uint256 indexed referralCode);

    event AgentCreated(address indexed agent, address indexed user);

    error Reentrancy();

    error RouterIsPaused();

    error InvalidPauser();

    error InvalidFeeCollector();

    error InvalidNewPauser();

    error SignatureExpired(uint256 deadline);

    error InvalidSigner(address signer);

    error InvalidSignature();

    error AgentAlreadyCreated();

    function agentImplementation() external view returns (address);

    function agents(address user) external view returns (IAgent2);

    function signers(address signer) external view returns (bool);

    function currentUser() external view returns (address);

    function feeCollector() external view returns (address);

    function pauser() external view returns (address);

    function paused() external view returns (bool);

    function owner() external view returns (address);

    function domainSeparator() external view returns (bytes32);

    function getAgent(address user) external view returns (address);

    function getUserAgent() external view returns (address, address);

    function calcAgent(address user) external view returns (address);

    function addSigner(address signer) external;

    function removeSigner(address signer) external;

    function setFeeCollector(address feeCollector_) external;

    function setPauser(address pauser_) external;

    function rescue(address token, address receiver, uint256 amount) external;

    function pause() external;

    function resume() external;

    function execute(
        IParam2.Logic[] calldata logics,
        address[] calldata tokensReturn,
        uint256 referralCode
    ) external payable;

    function executeWithSignature(
        IParam2.LogicBatch calldata logicBatch,
        address signer,
        bytes calldata signature,
        address[] calldata tokensReturn,
        uint256 referralCode
    ) external payable;

    function newAgent() external returns (address payable);

    function newAgent(address user) external returns (address payable);
}
