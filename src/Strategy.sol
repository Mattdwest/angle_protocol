// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";
import {IERC20Metadata} from "@yearnvaults/contracts/yToken.sol";

import "./interfaces/Angle/IStableMaster.sol";
import "./interfaces/Angle/IAngleGauge.sol";
import "./interfaces/Yearn/ITradeFactory.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;

    event Cloned(address indexed clone);

    bool public isOriginal = true;

    IERC20 public constant angleToken = IERC20(0x31429d1856aD1377A8A0079410B297e1a9e214c2);
    IStableMaster public constant angleStableMaster = IStableMaster(0x5adDc89785D75C86aB939E9e15bfBBb7Fc086A87);
    uint256 public constant MAX_BPS = 10000;

    // variable for determining how much governance token to hold for voting rights
    uint256 public percentKeep;
    IERC20 public sanToken;
    IAngleGauge public sanTokenGauge;
    address public treasury;
    address public poolManager;
    address public tradeFactory = address(0);

    constructor(
        address _vault,
        address _sanToken,
        address _sanTokenGauge,
        address _poolManager
    ) public BaseStrategy(_vault) {
        // Constructor should initialize local variables
        _initializeStrategy(
            _sanToken,
            _sanTokenGauge,
            _poolManager
        );
    }

    // Cloning & initialization code adapted from https://github.com/yearn/yearn-vaults/blob/43a0673ab89742388369bc0c9d1f321aa7ea73f6/contracts/BaseStrategy.sol#L866

    function _initializeStrategy(
        address _sanToken,
        address _sanTokenGauge,
        address _poolManager
    ) internal {
        sanToken = IERC20(_sanToken);
        sanTokenGauge = IAngleGauge(_sanTokenGauge);
        poolManager = _poolManager;

        percentKeep = 1000;
        treasury = 0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde;
        healthCheck = 0xDDCea799fF1699e98EDF118e0629A974Df7DF012;
        doHealthCheck = true;

        IERC20(want).safeApprove(address(angleStableMaster), type(uint256).max);
        IERC20(sanToken).safeApprove(_sanTokenGauge, type(uint256).max);
    }

    function initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _sanToken,
        address _sanTokenGauge,
        address _poolManager
    ) external {
        _initialize(_vault, _strategist, _rewards, _keeper);
        _initializeStrategy(
            _sanToken,
            _sanTokenGauge,
            _poolManager
        );
    }

    function cloneAngle(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _sanToken,
        address _sanTokenGauge,
        address _poolManager
    ) external returns (address newStrategy) {
        require(isOriginal, "!clone");
        bytes20 addressBytes = bytes20(address(this));

        assembly {
            // EIP-1167 bytecode
            let clone_code := mload(0x40)
            mstore(
                clone_code,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone_code, 0x14), addressBytes)
            mstore(
                add(clone_code, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            newStrategy := create(0, clone_code, 0x37)
        }

        Strategy(newStrategy).initialize(
            _vault,
            _strategist,
            _rewards,
            _keeper,
            _sanToken,
            _sanTokenGauge,
            _poolManager
        );

        emit Cloned(newStrategy);
    }

    function name() external view override returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "StrategyAngle",
                    IERC20Metadata(address(want)).symbol()
                )
            );
    }

    // returns sum of all assets, realized and unrealized
    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant() + valueOfStakedSanToken() + valueOfSanToken();
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // Run initial profit + loss calculations.

        uint256 _totalAssets = estimatedTotalAssets();
        uint256 _totalDebt = vault.strategies(address(this)).totalDebt;

        if (_totalAssets >= _totalDebt) {
            // Implicitly, _profit & _loss are 0 before we change them.
            _profit = _totalAssets - _totalDebt;
        } else {
            _loss = _totalDebt - _totalAssets;
        }

        // Free up _debtOutstanding + our profit, and make any necessary adjustments to the accounting.

        (uint256 _amountFreed, uint256 _liquidationLoss) =
            liquidatePosition(_debtOutstanding + _profit);

        _loss = _loss + _liquidationLoss;

        _debtPayment = Math.min(_debtOutstanding, _amountFreed);

        if (_loss > _profit) {
            _loss = _loss - _profit;
            _profit = 0;
        } else {
            _profit = _profit - _loss;
            _loss = 0;
        }
    }

    // Deposit value & stake
    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }

        // Claim rewards here so that we can chain tend() -> yswap sell -> harvest() in a single transaction
        sanTokenGauge.claim_rewards();

        uint256 _tokensAvailable = balanceOfAngleToken();
        if (_tokensAvailable > 0) {
            uint256 _tokensToGov =
                (_tokensAvailable * percentKeep) / MAX_BPS;
            if (_tokensToGov > 0) {
                angleToken.transfer(treasury, _tokensToGov);
            }
        }

        uint256 _balanceOfWant = balanceOfWant();

        // do not invest if we have more debt than want
        if (_debtOutstanding > _balanceOfWant) {
            return;
        }

        // Invest the rest of the want
        uint256 _wantAvailable = _balanceOfWant - _debtOutstanding;
        if (_wantAvailable > 0) {
            // deposit for sanToken
            depositToStableMaster(_wantAvailable);
        }

        // Stake any san tokens, whether they originated through the above deposit or some other means (e.g. migration)
        uint256 _sanTokenBalance = balanceOfSanToken();
        if (_sanTokenBalance > 0) {
            sanTokenGauge.deposit(_sanTokenBalance);
        }
    }

    function liquidateAllPositions()
        internal
        override
        returns (uint256 _amountFreed)
    {
        (_amountFreed, ) = liquidatePosition(estimatedTotalAssets());
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`
        _amountNeeded = Math.min(_amountNeeded, estimatedTotalAssets()); // This makes it safe to request to liquidate more than we have

        uint256 _balanceOfWant = balanceOfWant();
        if (_balanceOfWant < _amountNeeded) {
            // We need to withdraw to get back more want
            _withdrawSome(_amountNeeded - _balanceOfWant);
            // reload balance of want after side effect
            _balanceOfWant = balanceOfWant();
        }

        if (_balanceOfWant >= _amountNeeded) {
            _liquidatedAmount = _amountNeeded;
        } else {
            _liquidatedAmount = _balanceOfWant;
            _loss = _amountNeeded - _balanceOfWant;
        }
    }

    // withdraw some want from Angle
    function _withdrawSome(uint256 _amount) internal {
        uint256 _amountInSanToken = wantToSanToken(_amount);

        uint256 _sanTokenBalance = balanceOfSanToken();
        if (_amountInSanToken > _sanTokenBalance) {
            sanTokenGauge.withdraw(
                _amountInSanToken - _sanTokenBalance
            );
        }

        withdrawFromStableMaster(_amountInSanToken);
    }

    // transfers all tokens to new strategy
    function prepareMigration(address _newStrategy) internal override {
        // want is transferred by the base contract's migrate function
        sanTokenGauge.claim_rewards();
        sanTokenGauge.withdraw(balanceOfStakedSanToken());

        IERC20(sanToken).safeTransfer(_newStrategy, balanceOfSanToken());
        IERC20(angleToken).transfer(_newStrategy, balanceOfAngleToken());
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}


    function ethToWant(uint256 _amtInWei)
        public
        view
        override
        returns (uint256)
    {
        return _amtInWei;
    }

    // ---------------------- SETTERS -----------------------

    function setKeepInBips(uint256 _percentKeep) external onlyVaultManagers {
        require(
            _percentKeep <= MAX_BPS,
            "_percentKeep can't be larger than 10,000"
        );
        percentKeep = _percentKeep;
    }

    // where angleToken goes
    function setTreasury(address _treasury) external onlyVaultManagers {
        require(_treasury != address(0), "!zero_address");
        treasury = _treasury;
    }

    // ----------------- SUPPORT & UTILITY FUNCTIONS ----------

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfStakedSanToken() public view returns (uint256) {
        return IERC20(address(sanTokenGauge)).balanceOf(address(this));
    }

    function balanceOfSanToken() public view returns (uint256) {
        return sanToken.balanceOf(address(this));
    }

    function balanceOfAngleToken() public view returns (uint256) {
        return angleToken.balanceOf(address(this));
    }

    function valueOfSanToken() public view returns (uint256) {
        return sanTokenToWant(balanceOfSanToken());
    }

    function valueOfStakedSanToken() public view returns (uint256) {
        return sanTokenToWant(balanceOfStakedSanToken());
    }

    function sanTokenToWant(uint256 _sanTokenAmount)
        public
        view
        returns (uint256)
    {
        return (_sanTokenAmount * getSanRate()) / 1e18;
    }

    function wantToSanToken(uint256 _wantAmount) public view returns (uint256) {
        return ((_wantAmount * 1e18) / getSanRate()) + 1;
    }

    // Get rate of conversion between sanTokens and want
    function getSanRate() public view returns (uint256) {
        (, , , , , uint256 _sanRate, , , ) =
            IStableMaster(angleStableMaster).collateralMap(poolManager);

        return _sanRate;
    }

    function depositToStableMaster(uint256 _amount) internal {
        IStableMaster(angleStableMaster).deposit(
            _amount,
            address(this),
            poolManager
        );
    }

    function withdrawFromStableMaster(uint256 _amountInSanToken) internal {
        IStableMaster(angleStableMaster).withdraw(
            _amountInSanToken,
            address(this),
            address(this),
            poolManager
        );
    }

    // ---------------------- YSWAPS FUNCTIONS ----------------------

    function setTradeFactory(address _tradeFactory) external onlyGovernance {
        if (tradeFactory != address(0)) {
            _removeTradeFactoryPermissions();
        }
        angleToken.safeApprove(_tradeFactory, type(uint256).max);
        ITradeFactory tf = ITradeFactory(_tradeFactory);
        tf.enable(address(angleToken), address(want));
        tradeFactory = _tradeFactory;
    }

    function removeTradeFactoryPermissions() external onlyEmergencyAuthorized {
        _removeTradeFactoryPermissions();
    }

    function _removeTradeFactoryPermissions() internal {
        angleToken.safeApprove(tradeFactory, 0);
        tradeFactory = address(0);
    }
}