// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {StrategyFixture} from "./utils/StrategyFixture.sol";
import {IVault} from "../interfaces/Yearn/Vault.sol";
import {Strategy} from "../Strategy.sol";
import {AngleStrategyVoterProxy} from "../AngleStrategyVoterProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@yearnvaults/contracts/yToken.sol";

contract HandleAngleHackTest is StrategyFixture {
    function setUp() public override {
        super.setUp();
    }

    function testHandleAngleHack(uint256 _fuzzAmount) public {
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
            string memory tokenSymbol = IERC20Metadata(address(want)).symbol();
            vm.prank(gov);
            voterProxy.approveStrategy(gaugeAddrs[tokenSymbol], address(strategy));

            uint256 _balanceBefore = want.balanceOf(address(user));

            vm.prank(user);
            want.approve(address(vault), _amount);

            vm.prank(user);
            vault.deposit(_amount);

            skip(3 minutes);
            vm.prank(strategist);
            strategy.harvest();
            uint256 _assetsAtT = strategy.estimatedTotalAssets();
            assertRelApproxEq(_assetsAtT, _amount, DELTA);

            skip(7 days);

            // We simulate a hack by sending away all of the strat's gauge tokens
            address sanTokenGauge = address(strategy.sanTokenGauge());
            address yearnVoter = address(voterProxy.yearnAngleVoter());
            vm.startPrank(address(yearnVoter));
            IERC20(sanTokenGauge).transfer(address(0), IERC20(sanTokenGauge).balanceOf(yearnVoter));
            vm.stopPrank();

            // skip(1);
            vm.prank(gov);
            strategy.setDoHealthCheck(false);

            vm.prank(strategist);
            strategy.harvest();
            uint256 _assetsAtTPlusOne = strategy.estimatedTotalAssets();
            assertLt(_assetsAtTPlusOne, _assetsAtT);

            vm.prank(user);
            vault.withdraw();
        }
    }
}
