// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

/// @title IVeANGLE
/// @author Angle Core Team
/// @notice Interface for the `VeANGLE` contract
interface IVeANGLE {
    // solhint-disable-next-line func-name-mixedcase
    function deposit_for(address addr, uint256 amount) external;
    function locked__end(address addr) external view returns(uint256);
    function create_lock(uint256 _value, uint256 _unlock_time) external;
    function increase_amount(uint256 _value) external;
    function increase_unlock_time(uint256 _unlock_time) external;
    function withdraw() external;
    function locked(address) external view returns(LockedBalance memory);

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }
}