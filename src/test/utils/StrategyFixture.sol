// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ExtendedTest} from "./ExtendedTest.sol";
import {Vm} from "forge-std/Vm.sol";
import {IVault} from "../../interfaces/Yearn/Vault.sol";
import "../../interfaces/Angle/IStableMaster.sol";
import "../../interfaces/Yearn/ITradeFactory.sol";

// NOTE: if the name of the strat or file changes this needs to be updated
import {Strategy} from "../../Strategy.sol";

// Artifact paths for deploying from the deps folder, assumes that the command is run from
// the project root.
string constant vaultArtifact = "artifacts/Vault.json";

// Base fixture deploying Vault
contract StrategyFixture is ExtendedTest {
    using SafeERC20 for IERC20;

    struct AssetFixture { // To test multiple assets
        IVault vault;
        Strategy strategy;
        IERC20 want;
    }

    IERC20 public weth;

    AssetFixture[] public assetFixtures;

    mapping(string => address) public tokenAddrs;
    mapping(string => uint256) public tokenPrices;
    mapping(string => address) public sanTokenAddrs;
    mapping(string => address) public poolManagerAddrs;
    mapping(string => address) public gaugeAddrs;

    address public gov = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
    address public user = address(1);
    address public whale = address(2);
    address public rewards = address(3);
    address public guardian = address(4);
    address public management = address(5);
    address public strategist = address(6);
    address public keeper = address(7);
    address public yMech = 0x2C01B4AD51a67E2d8F02208F54dF9aC4c0B778B6;
    address public angleTokenWhale = 0xe02F8E39b8cFA7d3b62307E46077669010883459;
    address public constant sushiswapSwapper = 0x408Ec47533aEF482DC8fA568c36EC0De00593f44;
    address public constant angleFeeManager = 0x97B6897AAd7aBa3861c04C0e6388Fc02AF1F227f;
    address public constant yearnTreasuryVault = 0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde;

    ITradeFactory public constant tradeFactory = ITradeFactory(0x7BAF843e06095f68F4990Ca50161C2C4E4e01ec6);
    IERC20 public constant angleToken = IERC20(0x31429d1856aD1377A8A0079410B297e1a9e214c2);

    IStableMaster public constant stableMaster = IStableMaster(0x5adDc89785D75C86aB939E9e15bfBBb7Fc086A87);

    uint256 public minFuzzAmt = 1 ether; // 10 cents
    // @dev maximum amount of want tokens deposited based on @maxDollarNotional
    uint256 public maxFuzzAmt = 25_000_000 ether; // $25M
    // Used for integer approximation
    uint256 public constant DELTA = 10**4;

    function setUp() public virtual {
        _setTokenPrices();
        _setTokenAddrs();
        _setSanTokenAddrs();
        _setPoolManagerAddrs();
        _setGaugeAddrs();

        weth = IERC20(tokenAddrs["WETH"]);

        string[2] memory _tokensToTest = ["USDC", "DAI"];

        for (uint8 i = 0; i < _tokensToTest.length; ++i) {
            string memory _tokenToTest = _tokensToTest[i];
            IERC20 _want = IERC20(tokenAddrs[_tokenToTest]);

            (address _vault, address _strategy) = deployVaultAndStrategy(
                address(_want),
                _tokenToTest,
                gov,
                rewards,
                "",
                "",
                guardian,
                management,
                keeper,
                strategist
            );

            assetFixtures.push(AssetFixture(IVault(_vault), Strategy(_strategy), _want));

            vm.label(address(_vault), string(abi.encodePacked(_tokenToTest, "Vault")));
            vm.label(address(_strategy), string(abi.encodePacked(_tokenToTest, "Strategy")));
            vm.label(address(_want), _tokenToTest);
        }

        // add more labels to make your traces readable
        vm.label(gov, "Gov");
        vm.label(user, "User");
        vm.label(whale, "Whale");
        vm.label(rewards, "Rewards");
        vm.label(guardian, "Guardian");
        vm.label(management, "Management");
        vm.label(strategist, "Strategist");
        vm.label(keeper, "Keeper");
    }

    // Deploys a vault
    function deployVault(
        address _token,
        address _gov,
        address _rewards,
        string memory _name,
        string memory _symbol,
        address _guardian,
        address _management
    ) public returns (address) {
        vm.prank(_gov);
        address _vaultAddress = deployCode(vaultArtifact);
        IVault _vault = IVault(_vaultAddress);

        vm.prank(_gov);
        _vault.initialize(
            _token,
            _gov,
            _rewards,
            _name,
            _symbol,
            _guardian,
            _management
        );

        vm.prank(_gov);
        _vault.setDepositLimit(type(uint256).max);

        return address(_vault);
    }

    // Deploys a strategy
    function deployStrategy(
        address _vault,
        string memory _tokenSymbol
    ) public returns (address) {
        Strategy _strategy = new Strategy(
            _vault, 
            sanTokenAddrs[_tokenSymbol], 
            gaugeAddrs[_tokenSymbol],
            poolManagerAddrs[_tokenSymbol]
        );

        vm.startPrank(yMech);
        tradeFactory.grantRole(
            tradeFactory.STRATEGY(),
            address(_strategy)
        );
        vm.stopPrank();

        vm.prank(gov);
        _strategy.setTradeFactory(address(tradeFactory));

        return address(_strategy);
    }

    // Deploys a vault and strategy attached to vault
    function deployVaultAndStrategy(
        address _token,
        string memory _tokenSymbol,
        address _gov,
        address _rewards,
        string memory _name,
        string memory _symbol,
        address _guardian,
        address _management,
        address _keeper,
        address _strategist
    ) public returns (address _vaultAddr, address _strategyAddr) {
        _vaultAddr = deployVault(
            _token,
            _gov,
            _rewards,
            _name,
            _symbol,
            _guardian,
            _management
        );
        IVault _vault = IVault(_vaultAddr);

        vm.prank(_strategist);
        _strategyAddr = deployStrategy(
            _vaultAddr,
            _tokenSymbol
        );
        Strategy _strategy = Strategy(_strategyAddr);

        vm.prank(_strategist);
        _strategy.setKeeper(_keeper);

        vm.prank(_gov);
        _vault.addStrategy(_strategyAddr, 10_000, 0, type(uint256).max, 1_000);

        return (address(_vault), address(_strategy));
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function _setSanTokenAddrs() internal {
        sanTokenAddrs["DAI"] = 0x7B8E89b0cE7BAC2cfEC92A371Da899eA8CBdb450; 
        sanTokenAddrs["USDC"] = 0x9C215206Da4bf108aE5aEEf9dA7caD3352A36Dad; 
        sanTokenAddrs["FEI"] = 0x5d8D3Ac6D21C016f9C935030480B7057B21EC804; 
        sanTokenAddrs["FRAX"] = 0xb3B209Bb213A5Da5B947C56f2C770b3E1015f1FE; 
        sanTokenAddrs["WETH"] = 0x30c955906735e48D73080fD20CB488518A6333C8; 
    }

    function _setPoolManagerAddrs() internal {
        poolManagerAddrs["DAI"] = 0xc9daabC677F3d1301006e723bD21C60be57a5915; 
        poolManagerAddrs["USDC"] = 0xe9f183FC656656f1F17af1F2b0dF79b8fF9ad8eD; 
        poolManagerAddrs["FEI"] = 0x5d8D3Ac6D21C016f9C935030480B7057B21EC804; 
        poolManagerAddrs["FRAX"] = 0x6b4eE7352406707003bC6f6b96595FD35925af48; 
        poolManagerAddrs["WETH"] = 0x3f66867b4b6eCeBA0dBb6776be15619F73BC30A2; 
    }

    function _setGaugeAddrs() internal {
        gaugeAddrs["DAI"] = 0x8E2c0CbDa6bA7B65dbcA333798A3949B07638026; 
        gaugeAddrs["USDC"] = 0x51fE22abAF4a26631b2913E417c0560D547797a7; 
        gaugeAddrs["FEI"] = 0x7c0fF11bfbFA3cC2134Ce62034329a4505408924; 
        gaugeAddrs["FRAX"] = 0xb40432243E4F317cE287398e72Ab8f0312fc2FE8; 
    }

    function _setTokenPrices() internal {
        tokenPrices["WBTC"] = 60_000;
        tokenPrices["WETH"] = 4_000;
        tokenPrices["LINK"] = 20;
        tokenPrices["YFI"] = 35_000;
        tokenPrices["USDT"] = 1;
        tokenPrices["USDC"] = 1;
        tokenPrices["DAI"] = 1;
    }

    // Testing utilities

    function _mockSLPProfits(Strategy strategy) internal {
        address _poolManager = strategy.poolManager();
        (,,,,,,,SLPData memory _slpData,) = stableMaster.collateralMap(_poolManager);
        uint256 _maxProfitPerBlock = _slpData.maxInterestsDistributed;

        for (uint8 i = 0; i < 50; ++i) {
            vm.prank(_poolManager);
            stableMaster.accumulateInterest(_maxProfitPerBlock);
            skip(1);
            vm.roll(block.number + 1);
        }
    }

    
}
