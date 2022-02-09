// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IAngle {

    // interface for StableMasterFront

    /// @notice Lets a SLP enter the protocol by sending collateral to the system in exchange of sanTokens
    /// @param user Address of the SLP to send sanTokens to
    /// @param amount Amount of collateral sent
    /// @param poolManager Address of the `PoolManager` of the required collateral -> 0xe9f183FC656656f1F17af1F2b0dF79b8fF9ad8eD
    function deposit(uint256 amount,address user,address poolManager) external;

    /// @notice Lets a user burn agTokens (stablecoins) and receive the collateral specified by the `poolManager`
    /// in exchange
    /// @param amount Amount of stable asset burnt
    /// @param burner Address from which the agTokens will be burnt
    /// @param dest Address where collateral is going to be
    /// @param poolManager Collateral type requested by the user burning
    /// @param minCollatAmount Minimum amount of collateral that the user is willing to get for this transaction
    /// @dev The `msg.sender` should have approval to burn from the `burner` or the `msg.sender` should be the `burner`
    /// @dev If there are not enough reserves this transaction will revert and the user will have to come back to the
    /// protocol with a correct amount. Checking for the reserves currently available in the `PoolManager`
    /// is something that should be handled by the front interacting with this contract
    /// @dev In case there are not enough reserves, strategies should be harvested or their debt ratios should be adjusted
    /// by governance to make sure that users, HAs or SLPs withdrawing always have free collateral they can use
    /// @dev From a user perspective, this function is equivalent to a swap from stablecoins to collateral
    function burn(uint256 amount, address burner, address dest, address poolManager, uint256 minCollatAmount) external;

    function withdraw(uint256 amount, address burner, address dest, address poolManager) external;


    function collateralMap(address poolManager) external view returns (
        address token,
        address sanToken,
        address perpetualManager,
        address oracle,
        uint256 stocksUsers,
        uint256 sanRate,
        uint256 collatBase,
        uint256 slpData,
        uint256 feeData
    );

}
