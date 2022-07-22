// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
import "forge-std/console.sol";

import {StrategyFixture} from "./utils/StrategyFixture.sol";
import {IVault} from "../interfaces/Yearn/Vault.sol";
import {Strategy} from "../Strategy.sol";
import {AngleStrategyVoterProxy} from "../AngleStrategyVoterProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@yearnvaults/contracts/yToken.sol";
import "../interfaces/Angle/IStableMaster.sol";
import "../interfaces/Yearn/ITradeFactory.sol";

contract AngleVoterLock is StrategyFixture {
    // setup is run on before each test
    function setUp() public override {
        // setup vault
        super.setUp();
    }

    function testLockAngle(uint256 _fuzzAmount) public {
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
                console.log("Less than 18 decimals");
                uint256 _decimalDifference = 18 - _wantDecimals;

                _amount = _amount / (10 ** _decimalDifference);
            }
            deal(address(want), user, _amount);

            // Deposit to the vault
            vm.prank(user);
            want.approve(address(vault), _amount);
            vm.prank(user);
            vault.deposit(_amount);
            assertRelApproxEq(want.balanceOf(address(vault)), _amount, DELTA);

            skip(1);
            vm.prank(strategist);
            strategy.harvest();
            assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

            _mockSLPProfits(strategy);

            // Airdrop 1 angle for every $1000
            deal(address(angleToken), address(strategy), _fuzzAmount / 1000);

            uint256 _proxyAngleBalanceBefore = angleToken.balanceOf(address(voterProxy));
            vm.prank(strategist);
            strategy.tend();
            uint256 _angleTokenBalance = strategy.balanceOfAngleToken();
            assertGt(_angleTokenBalance, 0);

            uint256 _proxyAngleBalanceAfter = angleToken.balanceOf(address(voterProxy));
            assertGt(_proxyAngleBalanceAfter, _proxyAngleBalanceBefore);
            assertRelApproxEq(_proxyAngleBalanceAfter - _proxyAngleBalanceBefore, _angleTokenBalance / 9, DELTA);

            // 4 years
            uint256 _unlockTime = block.timestamp + 4 * 365 * 86_400;
            vm.prank(gov);
            voterProxy.lock(_proxyAngleBalanceAfter / 2, _unlockTime);
            uint256 _balance = veAngleToken.balanceOf(address(voter));
            assertGt(_balance, 0);

            // increase amount
            uint256 toLock = angleToken.balanceOf(address(voterProxy));
            vm.prank(gov);
            voterProxy.increaseAmount(toLock);
            assertGt(veAngleToken.balanceOf(address(voter)), _balance);
            
            skip(4 * 365 * 86_400 + 1);
            vm.prank(gov);
            voter.release();
            assert(veAngleToken.balanceOf(address(voter)) == 0);
            assert(angleToken.balanceOf(address(voter)) == _proxyAngleBalanceAfter);
        }
    }
}