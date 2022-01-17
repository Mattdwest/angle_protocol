// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IUniNFT {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external;

    function getAmountsOut(uint256 amountIn, address[] memory path)
        external
        view
        returns (uint256[] memory amounts);

     struct nftStruct {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(nftStruct calldata params) external payable returns(
        uint256 token_id,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1)
        ;

    function positions(uint256 tokenId) external view returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1);


    struct decreaseStruct {
        uint256 token_id;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function decreaseLiquidity(decreaseStruct calldata params) external payable returns(
        uint256 amount0,
        uint256 amount1)
    ;

    struct collectStruct {
        uint256 token_id;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function collect(collectStruct calldata params) external payable returns(
        uint256 amount0,
        uint256 amount1
    );

    struct increaseStruct {
        uint256 token_id;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function increaseLiquidity(increaseStruct calldata params) external payable returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function ownerOf(uint256 tokenID) external view returns(address);

}
