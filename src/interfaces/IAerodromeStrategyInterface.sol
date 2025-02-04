// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStrategy} from "octant-v2-core/src/interfaces/IStrategy.sol";

interface IAerodromeStrategyInterface is IStrategy {
    // TODO: Add methods to be implemented by the strategy
    function pool() external view returns (address);
    function nonfungiblePositionManager() external view returns (address);
    function swapRouter() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function positions(uint256 index)
        external
        view
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function positionCount() external view returns (uint256);
}
