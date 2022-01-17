// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IUniV3Pool {

    struct slot0Struct {
        uint160 sqrtPrice96;
        int24 tick;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observactionCardinalityNext;
        uint8 feeProtocol;
        bool unlocked;
    }

    function slot0()
        external
        view
        returns (uint160,int24,uint16,uint16,uint16,uint8,bool);

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data)
        external
        returns(int256 amount0, int256 amount1);



}
