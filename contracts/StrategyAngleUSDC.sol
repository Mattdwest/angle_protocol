// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {BaseStrategyInitializable} from "@yearn/contracts/BaseStrategy.sol";

import "../../interfaces/curve/ICurve.sol";
import "../../interfaces/Angle/IAngle.sol";
import "../../interfaces/Angle/IAngleStake.sol";
import "../../interfaces/uniswap/IUni.sol";




interface IName {
    function name() external view returns (string memory);
}

contract StrategyAngleUSDC is BaseStrategyInitializable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SafeMath for uint128;


    // variables for determining how much governance token to hold for voting rights
    uint256 public constant _denominator = 10000;
    uint256 public percentKeep;
    address public sanToken;
    address public angleToken;
    address public unirouter;
    address public angle;
    address public angleStake;
    address public refer;
    address public treasury;
    address public poolManager;

    constructor(
        address _vault,
        address _sanToken,
        address _angleToken,
        address _unirouter,
        address _angle,
        address _angleStake,
        address _poolManager
    ) public BaseStrategyInitializable(_vault) {
        // Constructor should initialize local variables
        _initializeThis(
            _sanToken,
            _angleToken,
            _unirouter,
            _angle,
            _angleStake,
            _poolManager
        );
    }

    // initializetime
    function _initializeThis(
        address _sanToken,
        address _angleToken,
        address _unirouter,
        address _angle,
        address _angleStake,
        address _poolManager
    ) internal {
        require(
            address(sanToken) == address(0),
            "StrategyAngleUSDC already initialized"
        );

        sanToken = _sanToken;
        angleToken = _angleToken;
        unirouter = _unirouter;
        angle = _angle;
        angleStake = _angleStake;
        poolManager = _poolManager;

        percentKeep = 1000;

        IERC20(want).safeApprove(angle, uint256(-1));
        IERC20(sanToken).safeApprove(angleStake, uint256(-1));
        IERC20(want).safeApprove(sanToken, uint256(-1));
        IERC20(sanToken).safeApprove(angle, uint256(-1));
        IERC20(angleToken).safeApprove(unirouter, uint256(-1));
    }

    function _initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _sanToken,
        address _angleToken,
        address _unirouter,
        address _angle,
        address _angleStake,
        address _poolManager
    ) internal {
        // Parent initialize contains the double initialize check
        super._initialize(_vault, _strategist, _rewards, _keeper);
        _initializeThis(
            _sanToken,
            _angleToken,
            _unirouter,
            _angle,
            _angleStake,
            _poolManager
        );
    }

    function initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _sanToken,
        address _angleToken,
        address _unirouter,
        address _angle,
        address _angleStake,
        address _poolManager
    ) external {
        _initialize(
            _vault,
            _strategist,
            _rewards,
            _keeper,
            _sanToken,
            _angleToken,
            _unirouter,
            _angle,
            _angleStake,
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
        address _angle,
        address _angleStake,
        address _poolManager
    ) external returns (address newStrategy) {
        // Copied from https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol
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
            _angle,
            _angleStake,
            _poolManager
        );
    }

    function name() external view override returns (string memory) {
        return
            string(
                abi.encodePacked("Angle ", IName(address(want)).name())
            );
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


    // returns sum of all assets, realized and unrealized
    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant().add(balanceOfStake()).add(balanceOfSanToken());
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
        uint256 balanceOfWantBefore = balanceOfWant();
        uint256 debt = vault.strategies(address(this)).totalDebt;

        uint256 currentValue = estimatedTotalAssets();

        IAngleStake(angleStake).getReward();

        uint256 _tokensAvailable = IERC20(angleToken).balanceOf(address(this));
        if(_tokensAvailable > 0){
            _swap(_tokensAvailable, address(angleToken));
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

            //deposit for sanToken
            IAngle(angle).deposit(_wantAvailable,address(this),poolManager);

            uint256 sanBalance = balanceOfSanToken();
            IAngleStake(angleStake).stake(sanBalance);

        }
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

        IAngleStake(angleStake).exit();

        uint256 _tokensAvailable = IERC20(angleToken).balanceOf(address(this));
        if(_tokensAvailable > 0){
            _swap(_tokensAvailable, address(angleToken));
        }


        address thisStrat = address(this);
        uint256 sanAmount = balanceOfSanToken();
        IAngle(angle).withdraw(sanAmount,thisStrat,thisStrat,poolManager);

        uint256 balanceOfWantAfter = balanceOfWant();

        uint256 redepositAmt = balanceOfWantAfter.sub(_amount);

        if (emergencyExit) {
            redepositAmt == 0;
        }

        if (redepositAmt > 0) {
        IAngle(angle).deposit(redepositAmt,thisStrat,poolManager);
        sanAmount = balanceOfSanToken();
        IAngleStake(angleStake).stake(sanAmount);
        }

        uint256 difference = balanceOfWant().sub(balanceOfWantBefore);

        return difference;
    }

    // transfers all tokens to new strategy
    function prepareMigration(address _newStrategy) internal override {
        // want is transferred by the base contract's migrate function
        IAngleStake(angleStake).exit();

        IERC20(sanToken).transfer(
            _newStrategy,
            IERC20(sanToken).balanceOf(address(this))
        );
        IERC20(angleToken).transfer(
            _newStrategy,
            IERC20(angleToken).balanceOf(address(this))
        );

    }

    // returns balance of want token
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfStake() public view returns (uint256) {
        return IAngleStake(angleStake).balanceOf(address(this));
    }

    function balanceOfSanToken() public view returns (uint256) {
        return IERC20(sanToken).balanceOf(address(this));
    }


    // swaps rewarded tokens for want
    // needs to use Sushi. May want to include UniV2 / V3
    function _swap(uint256 _amountIn, address _token) internal {
        address[] memory path = new address[](3);
        path[0] = _token; // token to swap
        path[1] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // weth
        path[2] = address(want);

        IUni(unirouter).swapExactTokensForTokens(
            _amountIn,
            0,
            path,
            address(this),
            now
        );
    }


    function setReferrer(address _refer) external onlyGovernance {
        refer = _refer;
    }


    // below for 0.4.3 upgrade
    function ethToWant(uint256 _amtInWei)
        public
        view
        override
        returns (uint256)
    {
        address[] memory path = new address[](2);
        path[0] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // weth
        path[1] = address(want);

        uint256[] memory amounts = IUni(unirouter).getAmountsOut(_amtInWei, path);

        return amounts[amounts.length - 1];
    }

    function liquidateAllPositions()
        internal
        override
        returns (uint256 _amountFreed)
    {
        //shouldn't matter, logic is already in liquidatePosition
        (_amountFreed, ) = liquidatePosition(420_69);
    }

}