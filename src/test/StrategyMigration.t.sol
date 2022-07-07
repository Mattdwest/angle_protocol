// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {StrategyFixture} from "./utils/StrategyFixture.sol";
import {IVault} from "../interfaces/Yearn/Vault.sol";
import {Strategy} from "../Strategy.sol";
import {AngleStrategyVoterProxy} from "../AngleStrategyVoterProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@yearnvaults/contracts/yToken.sol";
// NOTE: if the name of the strat or file changes this needs to be updated

contract StrategyMigrationTest is StrategyFixture {
    function setUp() public override {
        super.setUp();
    }

    function testMigration(uint256 _fuzzAmount) public {
        vm.assume(_fuzzAmount > minFuzzAmt && _fuzzAmount < maxFuzzAmt);
        for(uint8 i = 0; i < assetFixtures.length; ++i) {
            AssetFixture memory _assetFixture = assetFixtures[i];
            IVault vault = _assetFixture.vault;
            Strategy strategy = _assetFixture.strategy;
            IERC20 want = _assetFixture.want;
            AngleStrategyVoterProxy voterProxy = strategy.strategyProxy();

            uint256 _amount = _fuzzAmount;
            uint8 _wantDecimals = IERC20Metadata(address(want)).decimals();
            if (_wantDecimals != 18) {
                uint256 _decimalDifference = 18 - _wantDecimals;

                _amount = _amount / (10 ** _decimalDifference);
            }

            deal(address(want), user, _amount);

            // Deposit to the vault and harvest
            string memory tokenSymbol = IERC20Metadata(address(want)).symbol();
            vm.prank(user);
            want.approve(address(vault), _amount);
            vm.prank(user);
            vault.deposit(_amount);
            skip(1);
            vm.prank(strategist);
            strategy.harvest();
            assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

            // Migrate to a new strategy
            vm.prank(strategist);
            Strategy newStrategy = Strategy(deployStrategy(address(vault), address(voterProxy), IERC20Metadata(address(want)).symbol(), false)); 
            vm.prank(gov);
            strategy.claimRewards(); // manual claim rewards
            vm.prank(gov);
            vault.migrateStrategy(address(strategy), address(newStrategy));
            vm.prank(gov);
            voterProxy.approveStrategy(gaugeAddrs[tokenSymbol], address(newStrategy));
            assertRelApproxEq(newStrategy.estimatedTotalAssets(), _amount, DELTA);
        }
    }
}
