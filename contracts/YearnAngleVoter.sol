// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {IVoteEscrow} from "../interfaces/Angle/IVoteEscrow.sol";

contract YearnAngleVoter {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    address constant public angle = address(0x31429d1856aD1377A8A0079410B297e1a9e214c2);
    
    address constant public veAngle = address(0x0C462Dbb9EC8cD1630f1728B2CFD2769d09f0dd5);
    
    address public governance;
    address public strategy;
    
    constructor() public {
        governance = msg.sender;
    }
    
    function getName() external pure returns (string memory) {
        return "YearnAngleVoter";
    }
    
    function setStrategy(address _strategy) external {
        require(msg.sender == governance, "!governance");
        strategy = _strategy;
    }
    
    function createLock(uint256 _value, uint256 _unlockTime) external {
        require(msg.sender == strategy || msg.sender == governance, "!authorized");
        IERC20(angle).safeApprove(veAngle, 0);
        IERC20(angle).safeApprove(veAngle, _value);
        IVoteEscrow(veAngle).create_lock(_value, _unlockTime);
    }
    
    function increaseAmount(uint _value) external {
        require(msg.sender == strategy || msg.sender == governance, "!authorized");
        IERC20(angle).safeApprove(veAngle, 0);
        IERC20(angle).safeApprove(veAngle, _value);
        IVoteEscrow(veAngle).increase_amount(_value);
    }
    
    function release() external {
        require(msg.sender == strategy || msg.sender == governance, "!authorized");
        IVoteEscrow(veAngle).withdraw();
    }
    
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }
    
    function execute(address to, uint value, bytes calldata data) external returns (bool, bytes memory) {
        require(msg.sender == strategy || msg.sender == governance, "!governance");
        (bool success, bytes memory result) = to.call.value(value)(data);
        
        return (success, result);
    }
}