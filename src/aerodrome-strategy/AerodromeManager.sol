// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;
pragma abicoder v2;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TickMath} from "./aerodrome/core/libraries/TickMath.sol";
import {TransferHelper} from "./aerodrome/core/libraries/TransferHelper.sol";
import {INonfungiblePositionManager} from "./aerodrome/periphery/interfaces/INonfungiblePositionManager.sol";
import {ICLPool} from "./aerodrome/core/interfaces/ICLPool.sol";
import {ISwapRouter} from "./aerodrome/periphery/interfaces/ISwapRouter.sol";

abstract contract AerodromeManager is IERC721Receiver, Initializable, ReentrancyGuard {
    // =========== State Variables ===========
    /// @notice Aerodrome position manager contract
    INonfungiblePositionManager public nonfungiblePositionManager;

    /// @notice Aerodrome pool contract
    ICLPool public pool;

    /// @notice Address of token0 in the pool
    address public token0;

    /// @notice Address of token1 in the pool
    address public token1;

    /// @notice Pool tick spacing
    int24 public tickSpacing;

    /// @notice Aerodrome swap router contract
    ISwapRouter public swapRouter;

    // =========== Structs ===========
    /// @notice Represents the deposit of an NFT position
    /// @param owner Address of the position owner
    /// @param liquidity Amount of liquidity in the position
    /// @param token0 Address of token0
    /// @param token1 Address of token1
    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    /// @notice Mapping of tokenId to Deposit details
    mapping(uint256 => Deposit) public deposits;

    // =========== Events ===========
    event PositionMinted(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event PositionBurned(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event FeesCollected(uint256 indexed tokenId, uint256 amount0, uint256 amount1);

    // =========== Errors ===========
    error NotAerodromeNFT();
    error NotPositionOwner();
    error InvalidTokenAmount();

    /// @notice Initialize the Aerodrome Manager
    /// @param _nonfungiblePositionManager Address of Aerodrome NFT manager
    /// @param _poolAddress Address of Aerodrome pool
    /// @param _swapRouter Address of Aerodrome swap router
    function __AerodromeManager_init(address _nonfungiblePositionManager, address _poolAddress, address _swapRouter)
        internal
        onlyInitializing
    {
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        pool = ICLPool(_poolAddress);
        swapRouter = ISwapRouter(_swapRouter);
        token0 = pool.token0();
        token1 = pool.token1();
        tickSpacing = pool.tickSpacing();
    }

    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    // Note that the operator is recorded as the owner of the deposited NFT
    function onERC721Received(address operator, address, uint256 tokenId, bytes calldata)
        external
        override
        returns (bytes4)
    {
        if (msg.sender != address(nonfungiblePositionManager)) {
            revert NotAerodromeNFT();
        }
        _createDeposit(operator, tokenId);
        return this.onERC721Received.selector;
    }

    function _createDeposit(address owner, uint256 tokenId) internal {
        (,, address _token0, address _token1,,,, uint128 liquidity,,,,) = nonfungiblePositionManager.positions(tokenId);
        // set the owner and data for position
        deposits[tokenId] = Deposit({owner: owner, liquidity: liquidity, token0: _token0, token1: _token1});
    }

    /// @notice Calls the mint function defined in periphery, mints the same amount of each token.
    /// @param amount0ToMint Amount of token0 to add
    /// @param amount1ToMint Amount of token1 to add
    /// @param tickLower Lower tick of the position
    /// @param tickUpper Upper tick of the position
    /// @return tokenId The id of the newly minted ERC721
    /// @return liquidity The amount of liquidity for the position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mintNewPosition(uint256 amount0ToMint, uint256 amount1ToMint, int24 tickLower, int24 tickUpper)
        internal
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        // Approve the position manager
        TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), amount0ToMint);
        TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), amount1ToMint);

        // The values for tickLower and tickUpper may not work for all tick spacings.
        // Setting amount0Min and amount1Min to 0 is unsafe.
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            tickSpacing: tickSpacing,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp,
            sqrtPriceX96: 0
        });

        // Note that the pool defined by token0/token1 and fee tier 0.3% must already be created and initialized in order to mint
        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);

        // Create a deposit
        _createDeposit(msg.sender, tokenId);
        emit PositionMinted(tokenId, liquidity, amount0, amount1);

        // Remove allowance and refund in both assets.
        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), 0);
            uint256 refund0 = amount0ToMint - amount0;
            TransferHelper.safeTransfer(token0, msg.sender, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amount1ToMint - amount1;
            TransferHelper.safeTransfer(token1, msg.sender, refund1);
        }
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collectAllFees(uint256 tokenId) internal returns (uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);
        emit FeesCollected(tokenId, amount0, amount1);
    }

    /// @notice Remove liquidity from a position
    /// @param tokenId The id of the erc721 token
    /// @return liquidity The amount of liquidity removed
    /// @return amount0 The amount received back in token0
    /// @return amount1 The amount returned back in token1
    function removeLiquidity(uint256 tokenId)
        internal
        nonReentrant
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        // caller must be the owner of the NFT
        if (msg.sender != deposits[tokenId].owner) revert NotPositionOwner();

        // Get and update liquidity
        liquidity = deposits[tokenId].liquidity;
        deposits[tokenId].liquidity = 0;

        // Remove liquidity
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        // Decrease liquidity
        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);

        emit PositionBurned(tokenId, liquidity, amount0, amount1);
    }

    /// @notice Swaps exact amount of tokens
    /// @param tokenIn The token address to swap from
    /// @param tokenOut The token address to swap to
    /// @param amountIn The amount of tokenIn to swap
    /// @param amountOutMinimum The minimum amount of tokenOut to receive
    /// @return amountOut The amount of tokenOut received
    function swapExactInputSingle(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMinimum)
        internal
        returns (uint256 amountOut)
    {
        // Approve the router to spend the token
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        // Create and execute swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            tickSpacing: tickSpacing,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        // Execute the swap
        amountOut = swapRouter.exactInputSingle(params);
    }

    /// @notice Calculates the optimal tickUpper based on input parameters
    /// @param amount0 The amount of token0
    /// @param amount1 The amount of token1
    /// @return tickLower The suggested lower tick for the position
    /// @return tickUpper The suggested upper tick for the position
    function calculateOptimalTicks(uint256 amount0, uint256 amount1)
        public
        view
        returns (int24 tickLower, int24 tickUpper)
    {
        bool isToken0 = false;
        if (amount1 == 0) isToken0 = true;
        if (amount0 == 0) isToken0 = false;
        if (amount0 != 0 && amount1 != 0) revert InvalidTokenAmount();

        // Get current tick and spacing
        (, int24 currentTick,,,,) = pool.slot0();

        // Calculate range
        int24 baseRange = tickSpacing * 100;

        // Calculate ticks
        tickLower = isToken0 ? currentTick + tickSpacing : currentTick - baseRange;
        tickUpper = isToken0 ? currentTick + baseRange : currentTick - tickSpacing;

        // Validate bounds
        tickLower = _boundTick(tickLower);
        tickUpper = _boundTick(tickUpper);
    }

    /// @notice Ensure tick is within valid bounds
    /// @param tick Tick to bound
    function _boundTick(int24 tick) private view returns (int24) {
        tick = (tick / tickSpacing) * tickSpacing;
        if (tick < TickMath.MIN_TICK) {
            return TickMath.MIN_TICK;
        } else if (tick > TickMath.MAX_TICK) {
            return TickMath.MAX_TICK;
        }
        return tick;
    }
}
