// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";

import "../interfaces/curve/ICurve.sol";
import "../interfaces/Angle/IStableMaster.sol";
import "../interfaces/Angle/IAngleGauge.sol";
import "../interfaces/uniswap/IUni.sol";

contract StrategyAngleUSDC is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SafeMath for uint128;

    event Cloned(address indexed clone);

    bool public isOriginal = true;

    // variables for determining how much governance token to hold for voting rights
    uint256 public constant _denominator = 10000;
    address public constant weth =
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    uint256 public percentKeep;
    address public sanToken;
    address public angleToken;
    address public unirouter;
    address public angleStableMaster;
    address public sanTokenGauge;
    address public refer;
    address public treasury;
    address public poolManager;

    constructor(
        address _vault,
        address _sanToken,
        address _angleToken,
        address _unirouter,
        address _angleStableMaster,
        address _sanTokenGauge,
        address _poolManager
    ) public BaseStrategy(_vault) {
        // Constructor should initialize local variables
        _initializeStrategy(
            _sanToken,
            _angleToken,
            _unirouter,
            _angleStableMaster,
            _sanTokenGauge,
            _poolManager
        );
    }

    // Cloning & initialization code adapted from https://github.com/yearn/yearn-vaults/blob/43a0673ab89742388369bc0c9d1f321aa7ea73f6/contracts/BaseStrategy.sol#L866

    function _initializeStrategy(
        address _sanToken,
        address _angleToken,
        address _unirouter,
        address _angleStableMaster,
        address _sanTokenGauge,
        address _poolManager
    ) internal {
        sanToken = _sanToken;
        angleToken = _angleToken;
        unirouter = _unirouter;
        angleStableMaster = _angleStableMaster;
        sanTokenGauge = _sanTokenGauge;
        poolManager = _poolManager;

        percentKeep = 1000;
        treasury = address(0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde);
        healthCheck = 0xDDCea799fF1699e98EDF118e0629A974Df7DF012;

        IERC20(want).safeApprove(angleStableMaster, uint256(-1));
        IERC20(sanToken).safeApprove(sanTokenGauge, uint256(-1));
        IERC20(want).safeApprove(sanToken, uint256(-1));
        IERC20(sanToken).safeApprove(angleStableMaster, uint256(-1));
        IERC20(angleToken).safeApprove(unirouter, uint256(-1));
    }

    function initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _sanToken,
        address _angleToken,
        address _unirouter,
        address _angleStableMaster,
        address _sanTokenGauge,
        address _poolManager
    ) external {
        _initialize(_vault, _strategist, _rewards, _keeper);
        _initializeStrategy(
            _sanToken,
            _angleToken,
            _unirouter,
            _angleStableMaster,
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
        address _angleToken,
        address _unirouter,
        address _angleStableMaster,
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

        StrategyAngleUSDC(newStrategy).initialize(
            _vault,
            _strategist,
            _rewards,
            _keeper,
            _sanToken,
            _angleToken,
            _unirouter,
            _angleStableMaster,
            _sanTokenGauge,
            _poolManager
        );

        emit Cloned(newStrategy);
    }

    function name() external view override returns (string memory) {
        return string(abi.encodePacked("Angle", ERC20(address(want)).symbol()));
    }

    // returns sum of all assets, realized and unrealized
    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant().add(valueOfStake()).add(valueOfSanToken());
    }

    // claim profit and swap for want
    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // We might need to return want to the vault
        if (_debtOutstanding > 0) {
            uint256 _amountFreed = 0;
            (_amountFreed, _loss) = liquidatePosition(_debtOutstanding);
            _debtPayment = Math.min(_amountFreed, _debtOutstanding);
        }

        // harvest() will track profit by estimated total assets compared to debt.

        uint256 currentValue = estimatedTotalAssets();

        IAngleGauge(sanTokenGauge).claim_rewards();

        uint256 _tokensAvailable = IERC20(angleToken).balanceOf(address(this));
        if (_tokensAvailable > 0) {
            uint256 _tokensToGov =
                _tokensAvailable.mul(percentKeep).div(_denominator);
            if (_tokensToGov > 0) {
                IERC20(angleToken).safeTransfer(treasury, _tokensToGov);
            }
            uint256 _tokensRemain = IERC20(angleToken).balanceOf(address(this));
            _swap(_tokensRemain, address(angleToken));
        }

        uint256 afterValue = estimatedTotalAssets();

        if (afterValue > currentValue) {
            _profit = afterValue.sub(currentValue);
        }

        if (_profit > _loss) {
            _profit = _profit.sub(_loss);
            _loss = 0;
        } else {
            _loss = _loss.sub(_profit);
            _profit = 0;
        }
    }

    // Deposit value & stake
    function adjustPosition(uint256 _debtOutstanding) internal override {
        //emergency exit is dealt with in prepareReturn
        if (emergencyExit) {
            return;
        }

        uint256 _balanceOfWant = balanceOfWant();

        // do not invest if we have more debt than want
        if (_debtOutstanding > _balanceOfWant) {
            return;
        }

        // Invest the rest of the want
        uint256 _wantAvailable = _balanceOfWant.sub(_debtOutstanding);
        if (_wantAvailable > 0) {
            // deposit for sanToken
            depositToStableMaster(_wantAvailable);
        }

        // Stake any san tokens, whether they originated through the above deposit or some other means (e.g. migration)
        uint256 _sanTokenBalance = balanceOfSanToken();
        if (_sanTokenBalance > 0) {
            IAngleGauge(sanTokenGauge).deposit(_sanTokenBalance);
        }
    }

    function liquidateAllPositions()
        internal
        override
        returns (uint256 _amountFreed)
    {
        //shouldn't matter, logic is already in liquidatePosition
        (_amountFreed, ) = liquidatePosition(type(uint256).max);
    }

    //v0.4.3 includes logic for emergencyExit
    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 _balanceOfWant = balanceOfWant();
        if (_balanceOfWant < _amountNeeded) {
            // We need to withdraw to get back more want
            _withdrawSome(_amountNeeded.sub(_balanceOfWant));
            // reload balance of want after side effect
            _balanceOfWant = balanceOfWant();
        }

        if (_balanceOfWant >= _amountNeeded) {
            _liquidatedAmount = _amountNeeded;
        } else {
            _liquidatedAmount = _balanceOfWant;
            _loss = _amountNeeded.sub(_balanceOfWant);
        }
    }

    // withdraw some want from the vaults
    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        uint256 balanceOfWantBefore = balanceOfWant();

        IAngleGauge(sanTokenGauge).withdraw(balanceOfStake());

        uint256 sanAmount = balanceOfSanToken();
        IStableMaster(angleStableMaster).withdraw(
            sanAmount,
            address(this),
            address(this),
            poolManager
        );

        uint256 balanceOfWantAfter = balanceOfWant();

        if (balanceOfWantAfter < _amount) {
            balanceOfWantAfter = _amount;
        }
        uint256 redepositAmt = balanceOfWantAfter.sub(_amount);

        if (redepositAmt > 0) {
            depositToStableMaster(redepositAmt);
            sanAmount = balanceOfSanToken();
            IAngleGauge(sanTokenGauge).deposit(sanAmount);
        }

        uint256 difference = balanceOfWant().sub(balanceOfWantBefore);

        return difference;
    }

    // swaps rewarded tokens for want
    // needs to use Sushi. May want to include UniV2 / V3
    function _swap(uint256 _amountIn, address _token) internal {
        address[] memory path = new address[](3);
        path[0] = _token; // token to swap
        path[1] = weth;
        path[2] = address(want);

        IUni(unirouter).swapExactTokensForTokens(
            _amountIn,
            0,
            path,
            address(this),
            now
        );
    }

    // transfers all tokens to new strategy
    function prepareMigration(address _newStrategy) internal override {
        // want is transferred by the base contract's migrate function
        IAngleGauge(sanTokenGauge).claim_rewards();
        IAngleGauge(sanTokenGauge).withdraw(balanceOfStake());

        IERC20(sanToken).transfer(_newStrategy, balanceOfSanToken());
        IERC20(angleToken).transfer(_newStrategy, balanceOfAngleToken());
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](2);
        // (aka want) is already protected by default
        protected[0] = sanToken;
        protected[1] = angleToken;

        return protected;
    }

    // below for 0.4.3 upgrade
    function ethToWant(uint256 _amtInWei)
        public
        view
        override
        returns (uint256)
    {
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = address(want);

        uint256[] memory amounts =
            IUni(unirouter).getAmountsOut(_amtInWei, path);

        return amounts[amounts.length - 1];
    }

    // ---------------------- SETTERS -----------------------

    function setKeepInBips(uint256 _percentKeep) external onlyVaultManagers {
        percentKeep = _percentKeep;
    }

    function setReferrer(address _refer) external onlyVaultManagers {
        refer = _refer;
    }

    // where angleToken goes
    function setTreasury(address _treasury) external onlyVaultManagers {
        treasury = _treasury;
    }

    // ----------------- SUPPORT & UTILITY FUNCTIONS ----------

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfStake() public view returns (uint256) {
        return IERC20(sanTokenGauge).balanceOf(address(this));
    }

    function balanceOfSanToken() public view returns (uint256) {
        return IERC20(sanToken).balanceOf(address(this));
    }

    function balanceOfAngleToken() public view returns (uint256) {
        return IERC20(angleToken).balanceOf(address(this));
    }

    function valueOfSanToken() public view returns (uint256) {
        uint256 _balance = balanceOfSanToken();

        return _balance.mul(getSanRate()).div(1e18);
    }

    function valueOfStake() public view returns (uint256) {
        uint256 _balance = balanceOfStake();

        return _balance.mul(getSanRate()).div(1e18);
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
}
