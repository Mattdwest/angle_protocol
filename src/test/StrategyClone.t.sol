// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
import "forge-std/console.sol";

import {StrategyFixture} from "./utils/StrategyFixture.sol";
import {IVault} from "../interfaces/Yearn/Vault.sol";
import {Strategy} from "../Strategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@yearnvaults/contracts/yToken.sol";
import "../interfaces/Angle/IStableMaster.sol";
import "../interfaces/Yearn/ITradeFactory.sol";

contract StrategyCloneTest is StrategyFixture {
    // setup is run on before each test
    function setUp() public override {
        // setup vault
        super.setUp();
    }

    function testStrategyClone(uint256 _fuzzAmount) public {
        vm.assume(_fuzzAmount > minFuzzAmt && _fuzzAmount < maxFuzzAmt);
        for(uint8 i = 0; i < assetFixtures.length; ++i) {
            AssetFixture memory _assetFixture = assetFixtures[i];
            IVault vault = _assetFixture.vault;
            Strategy strategy = _assetFixture.strategy;
            IERC20 want = _assetFixture.want;

            uint256 _amount = _fuzzAmount;
            uint8 _wantDecimals = IERC20Metadata(address(want)).decimals();
            if (_wantDecimals != 18) {
                uint256 _decimalDifference = 18 - _wantDecimals;

                _amount = _amount / (10 ** _decimalDifference);
            }

            deal(address(want), user, _amount);

            string memory _tokenSymbol = IERC20Metadata(address(want)).symbol();

            address _newStrategy = strategy.cloneAngle(
                address(vault),
                strategist,
                rewards,
                keeper,
                sanTokenAddrs[_tokenSymbol], 
                gaugeAddrs[_tokenSymbol],
                poolManagerAddrs[_tokenSymbol],
                address(voterProxy)
            );

            vm.prank(gov);
            vault.migrateStrategy(address(strategy), _newStrategy);

            strategy = Strategy(_newStrategy);

            uint256 _balanceBefore = want.balanceOf(address(user));

            vm.prank(user);
            want.approve(address(vault), _amount);

            vm.prank(user);
            vault.deposit(_amount);

            skip(3 minutes);
            vm.prank(strategist);
            strategy.harvest();
            assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

            vm.prank(strategist);
            skip(1);
            strategy.tend();

            vm.prank(user);
            vault.withdraw();

            assertRelApproxEq(want.balanceOf(user), _balanceBefore, DELTA);
        }
    }

    function testStrategyCloneOfClone(uint256 _fuzzAmount) public {
        vm.assume(_fuzzAmount > minFuzzAmt && _fuzzAmount < maxFuzzAmt);
        for(uint8 i = 0; i < assetFixtures.length; ++i) {
            AssetFixture memory _assetFixture = assetFixtures[i];
            IVault vault = _assetFixture.vault;
            Strategy strategy = _assetFixture.strategy;
            IERC20 want = _assetFixture.want;

            uint256 _amount = _fuzzAmount;
            uint8 _wantDecimals = IERC20Metadata(address(want)).decimals();
            if (_wantDecimals != 18) {
                uint256 _decimalDifference = 18 - _wantDecimals;

                _amount = _amount / (10 ** _decimalDifference);
            }

            deal(address(want), user, _amount);

            string memory _tokenSymbol = IERC20Metadata(address(want)).symbol();

            address _newStrategy = strategy.cloneAngle(
                address(vault),
                strategist,
                rewards,
                keeper,
                sanTokenAddrs[_tokenSymbol], 
                gaugeAddrs[_tokenSymbol],
                poolManagerAddrs[_tokenSymbol],
                address(voterProxy)
            );

            vm.prank(gov);
            vault.migrateStrategy(address(strategy), _newStrategy);

            strategy = Strategy(_newStrategy);

            vm.expectRevert(abi.encodePacked("!clone"));
            strategy.cloneAngle(
                address(vault),
                strategist,
                rewards,
                keeper,
                sanTokenAddrs[_tokenSymbol], 
                gaugeAddrs[_tokenSymbol],
                poolManagerAddrs[_tokenSymbol],
                address(voterProxy)
            );
        }
    }

    function testStrategyDoubleInitialize(uint256 _fuzzAmount) public {
        vm.assume(_fuzzAmount > minFuzzAmt && _fuzzAmount < maxFuzzAmt);
        for(uint8 i = 0; i < assetFixtures.length; ++i) {
            AssetFixture memory _assetFixture = assetFixtures[i];
            IVault vault = _assetFixture.vault;
            Strategy strategy = _assetFixture.strategy;
            IERC20 want = _assetFixture.want;

            uint256 _amount = _fuzzAmount;
            uint8 _wantDecimals = IERC20Metadata(address(want)).decimals();
            if (_wantDecimals != 18) {
                uint256 _decimalDifference = 18 - _wantDecimals;

                _amount = _amount / (10 ** _decimalDifference);
            }

            deal(address(want), user, _amount);

            string memory _tokenSymbol = IERC20Metadata(address(want)).symbol();

            address _newStrategy = strategy.cloneAngle(
                address(vault),
                strategist,
                rewards,
                keeper,
                sanTokenAddrs[_tokenSymbol], 
                gaugeAddrs[_tokenSymbol],
                poolManagerAddrs[_tokenSymbol],
                address(voterProxy)
            );

            vm.prank(gov);
            vault.migrateStrategy(address(strategy), _newStrategy);

            strategy = Strategy(_newStrategy);

            vm.expectRevert(abi.encodePacked("Strategy already initialized"));
            strategy.initialize(
                address(vault),
                strategist,
                rewards,
                keeper,
                sanTokenAddrs[_tokenSymbol], 
                gaugeAddrs[_tokenSymbol],
                poolManagerAddrs[_tokenSymbol],
                address(voterProxy)
            );
        }
    }
}