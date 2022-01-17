// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IAngleStake {

    //it stakes.
    function stake(uint256 amount) external;

    //gimme profit
    function getReward() external;

    //gimme principal
    function withdraw(uint256 amount) external;

    //getReward and Withdraw in same go
    function exit() external;

    //basically a sweep in case things get weird
    function recoverERC20(address tokenAddress, address to, uint256 amount) external;

    function balanceOf(address account) external view returns(uint256);

}

