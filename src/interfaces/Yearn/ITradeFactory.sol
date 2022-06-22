// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.12;

interface ITradeFactory {
    function enable(address rewards, address want) external;

    function grantRole(bytes32 role, address account) external;

    function STRATEGY() external view returns (bytes32);
}