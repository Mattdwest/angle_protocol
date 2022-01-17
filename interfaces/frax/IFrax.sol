// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IFrax {

    function earned(address account)
        external
        view
        returns (uint256 profit);

    function combinedWeightOf(address account)
        external
        view
        returns (uint256 amount);

    function userStakedFrax(address account)
        external
        view
        returns (uint256 stakedFrax);

    function veFXSMultiplier(address account)
        external
        view
        returns (uint256 multiplier);

    function withdrawalsPaused() external view returns (bool);

    function stakeLocked(uint256 token_id, uint256 _seconds) external;

    function withdrawLocked(uint256 token_id) external;

    function getReward() external;

}
