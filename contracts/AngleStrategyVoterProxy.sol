// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {YearnAngleVoter} from "./YearnAngleVoter.sol";

import "../interfaces/curve/ICurve.sol";
import "../interfaces/Angle/IStableMaster.sol";
import "../interfaces/Angle/IAngleGauge.sol";
import "../interfaces/uniswap/IUni.sol";

library SafeVoter {
    function safeExecute(
        YearnAngleVoter voter,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        (bool success, ) = voter.execute(to, value, data);
        require(success);
    }
}

contract AngleStrategyProxy {
    using SafeVoter for YearnAngleVoter;
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    YearnAngleVoter public yearnAngleVoter;
    address public constant angle = address(0x31429d1856aD1377A8A0079410B297e1a9e214c2);

    // gauge => strategies
    mapping(address => address) public strategies;
    mapping(address => bool) public voters;
    address public governance;

    uint256 lastTimeCursor;

    constructor(address _voter) public {
        governance = msg.sender;
        yearnAngleVoter = YearnAngleVoter(_voter);
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function approveStrategy(address _gauge, address _strategy) external {
        require(msg.sender == governance, "!governance");
        strategies[_gauge] = _strategy;
    }

    function revokeStrategy(address _gauge) external {
        require(msg.sender == governance, "!governance");
        strategies[_gauge] = address(0);
    }

    function approveVoter(address _voter) external {
        require(msg.sender == governance, "!governance");
        voters[_voter] = true;
    }

    function revokeVoter(address _voter) external {
        require(msg.sender == governance, "!governance");
        voters[_voter] = false;
    }

    function lock() external {
        uint256 amount = IERC20(angle).balanceOf(address(yearnAngleVoter));
        if (amount > 0) yearnAngleVoter.increaseAmount(amount);
    }

    function vote(address _gauge, uint256 _amount) public {
        require(voters[msg.sender], "!voter");
        yearnAngleVoter.safeExecute(_gauge, 0, abi.encodeWithSignature("vote_for_gauge_weights(address,uint256)", _gauge, _amount));
    }

    function withdraw(
        address _gauge,
        address _token,
        uint256 _amount
    ) public returns (uint256) {
        require(strategies[_gauge] == msg.sender, "!strategy");
        uint256 _balance = IERC20(_token).balanceOf(address(yearnAngleVoter));
        yearnAngleVoter.safeExecute(_gauge, 0, abi.encodeWithSignature("withdraw(uint256)", _amount));
        _balance = IERC20(_token).balanceOf(address(yearnAngleVoter)).sub(_balance);
        yearnAngleVoter.safeExecute(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _balance));
        return _balance;
    }

    function withdrawFromStableMaster(address stableMaster, uint256 amount, 
        address poolManager, address token) external {
        require(strategies[stableMaster] == msg.sender, "!strategy");

        IERC20(token).safeTransfer(address(yearnAngleVoter), amount);

        yearnAngleVoter.safeExecute(token, 0, abi.encodeWithSignature("approve(address,uint256)", stableMaster, 0));
        yearnAngleVoter.safeExecute(token, 0, abi.encodeWithSignature("approve(address,uint256)", stableMaster, amount));

        yearnAngleVoter.safeExecute(stableMaster, 0, abi.encodeWithSignature(
            "withdraw(uint256,address,address,address)", 
            amount,
            address(yearnAngleVoter),
            msg.sender,
            poolManager
            ));
    }

    function balanceOf(address _gauge) public view returns (uint256) {
        return IERC20(_gauge).balanceOf(address(yearnAngleVoter));
    }

    function withdrawAll(address _gauge, address _token) external returns (uint256) {
        require(strategies[_gauge] == msg.sender, "!strategy");
        return withdraw(_gauge, _token, balanceOf(_gauge));
    }

    function deposit(address gauge, uint256 amount, address token) external {
        require(strategies[gauge] == msg.sender, "!strategy");

        yearnAngleVoter.safeExecute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, 0));
        yearnAngleVoter.safeExecute(token, 0, abi.encodeWithSignature("approve(address,uint256)", gauge, amount));

        yearnAngleVoter.safeExecute(gauge, 0, abi.encodeWithSignature(
            "deposit(uint256)", 
            amount
            ));
    }

    function depositToStableMaster(address stableMaster, uint256 amount, 
        address poolManager, address token) external {
        require(strategies[stableMaster] == msg.sender, "!strategy");
        
        IERC20(token).safeTransfer(address(yearnAngleVoter), amount);

        yearnAngleVoter.safeExecute(token, 0, abi.encodeWithSignature("approve(address,uint256)", stableMaster, 0));
        yearnAngleVoter.safeExecute(token, 0, abi.encodeWithSignature("approve(address,uint256)", stableMaster, amount));
        yearnAngleVoter.safeExecute(stableMaster, 0, abi.encodeWithSignature(
            "deposit(uint256,address,address)", 
            amount,
            address(yearnAngleVoter),
            poolManager
            ));
    }

    function claimRewards(address _gauge, address _token) external {
        require(strategies[_gauge] == msg.sender, "!strategy");
        // Gauge(_gauge).claim_rewards(address(yearnAngleVoter));
        yearnAngleVoter.safeExecute(
            _gauge, 
            0, 
            abi.encodeWithSelector(
                IAngleGauge.claim_rewards.selector
            )
        );
        yearnAngleVoter.safeExecute(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, IERC20(_token).balanceOf(address(yearnAngleVoter))));
    }

    function balanceOfSanToken(address sanToken) public view returns (uint256) {
        return IERC20(sanToken).balanceOf(address(yearnAngleVoter));
    }
}