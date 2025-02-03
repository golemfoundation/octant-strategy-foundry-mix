// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {DragonBaseStrategy} from "octant-v2-core/src/dragons/vaults/DragonBaseStrategy.sol";
import {Module} from "zodiac/core/Module.sol";
import {AerodromeManager} from "./AerodromeManager.sol";

/// @title Liquidity Strategy for Uniswap V3
/// @notice A strategy that manages liquidity positions in Uniswap V3 pools
/// @dev Inherits from Module, DragonBaseStrategy, and LiquidityManager
contract AerodromeStrategy is Module, DragonBaseStrategy, AerodromeManager {
    // =========== Errors ===========
    error InvalidPool();
    error InvalidAmount();

    // =========== Structs ===========
    /// @notice Represents a liquidity position in Uniswap V3
    struct Position {
        uint256 tokenId; // NFT token ID of the position
        uint128 liquidity; // Current liquidity amount
        uint256 amount0; // Amount of token0
        uint256 amount1; // Amount of token1
    }

    // =========== State Variables ===========
    /// @notice Number of active positions
    uint256 public positionCount;

    /// @notice Mapping of position index to Position struct
    mapping(uint256 => Position) public positions;

    constructor() {
        _disableInitializers();
    }

    /// @dev Initialize function, will be triggered when a new proxy is deployed
    /// @dev owner of this module will the safe multisig that calls setUp function
    /// @param initializeParams Parameters of initialization encoded
    function setUp(bytes memory initializeParams) public override initializer {
        (address _owner, bytes memory data) = abi.decode(initializeParams, (address, bytes));

        (
            address _nonfungiblePositionManager,
            address _swapRouter,
            address _poolAddress,
            address _tokenizedStrategyImplementation,
            address _asset,
            address _management,
            address _keeper,
            address _dragonRouter,
            uint256 _maxReportDelay,
            string memory _name,
            address _regenGovernance
        ) = abi.decode(
            data, (address, address, address, address, address, address, address, address, uint256, string, address)
        );

        // Validate pool contains strategy asset
        if (IUniswapV3Pool(_poolAddress).token0() != _asset && IUniswapV3Pool(_poolAddress).token1() != _asset) {
            revert InvalidPool();
        }

        // Initialize managers
        __LiquidityManager_init(_nonfungiblePositionManager, _poolAddress, _swapRouter);
        __Ownable_init(msg.sender);
        __BaseStrategy_init(
            _tokenizedStrategyImplementation,
            _asset,
            _owner,
            _management,
            _keeper,
            _dragonRouter,
            _maxReportDelay,
            _name,
            _regenGovernance
        );

        // Set up module permissions
        setAvatar(_owner);
        setTarget(_owner);
        transferOwnership(_owner);
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Can deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy can attempt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        // Input validation
        if (_amount == 0) revert InvalidAmount();

        // Determine which token is the strategy asset
        bool isToken0 = address(asset) == token0;
        // address otherToken = isToken0 ? TOKEN1 : token0;

        // // Split amount for balanced liquidity (half and half)
        // uint256 amount0 = _amount / 2;
        // if (amount0 == 0) return;

        // // Calculate swap amount
        // uint256 swapAmount = _amount - amount0;

        // // Swap half for other token
        // uint256 amount1 = swapExactInputSingle(address(asset), otherToken, swapAmount, 0);
        // if (amount1 == 0) return;

        // // Order amounts based on token0/token1
        // (uint256 token0Amount, uint256 token1Amount) = isToken0 ? (amount0, amount1) : (amount1, amount0);

        uint256 token0Amount = isToken0 ? _amount : 0;
        uint256 token1Amount = isToken0 ? 0 : _amount;

        // Calculate optimal tick range for position
        (int24 tickLower, int24 tickUpper) = calculateOptimalTicks(token0Amount, token1Amount);

        // Create new liquidity position
        (uint256 tokenId, uint128 liquidity, uint256 finalAmount0, uint256 finalAmount1) =
            mintNewPosition(token0Amount, token1Amount, tickLower, tickUpper);

        // Store position details
        positions[positionCount] =
            Position({tokenId: tokenId, liquidity: liquidity, amount0: finalAmount0, amount1: finalAmount1});

        // Increment position counter
        unchecked {
            ++positionCount;
        }
    }

    /// @notice Collect fees from all positions and swap to strategy asset
    /// @return Total amount collected in strategy asset
    function collectAllAndSwap() internal returns (uint256) {
        bool isToken0 = address(asset) == token0;
        uint256 totalAmountOut0;
        uint256 totalAmountOut1;

        // Collect fees from all positions
        for (uint256 i = 0; i < positionCount;) {
            Position memory position = positions[i];
            (uint256 amount0, uint256 amount1) = collectAllFees(position.tokenId);

            unchecked {
                totalAmountOut0 += amount0;
                totalAmountOut1 += amount1;
                ++i;
            }
        }

        // Swap collected fees to strategy asset
        address swapToken = isToken0 ? token1 : token0;
        uint256 swapAmount = isToken0 ? totalAmountOut1 : totalAmountOut0;

        if (swapAmount > 0) {
            uint256 amountOut = swapExactInputSingle(swapToken, address(asset), swapAmount, 0);
            if (isToken0) {
                totalAmountOut0 += amountOut;
            } else {
                totalAmountOut1 += amountOut;
            }
        }

        return isToken0 ? totalAmountOut0 : totalAmountOut1;
    }

    /**
     * @dev Should attempt to free the '_amount' of 'asset'.
     *
     * NOTE: The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        if (_amount == 0) revert InvalidAmount();

        // Remove liquidity from all positions
        for (uint256 i = 0; i < positionCount;) {
            Position storage position = positions[i];

            (uint128 liquidity, uint256 amount0, uint256 amount1) = removeLiquidity(position.tokenId);

            unchecked {
                position.amount0 -= amount0;
                position.amount1 -= amount1;
                position.liquidity -= liquidity;
                ++i;
            }
        }

        // Collect and swap all assets
        uint256 amountOut = collectAllAndSwap();

        // Redeploy excess funds if any
        uint256 restFund = amountOut > _amount ? amountOut - _amount : 0;
        if (restFund > 0) {
            _deployFunds(restFund);
        }
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        _freeFunds(type(uint256).max);
        return asset.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwichable strategies.
     *
     *   EX:
     *       return asset.balanceOf(yieldSource);
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The available amount that can be withdrawn in terms of `asset`
     */
    function availableWithdrawLimit(address /*_owner*/ ) public view override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Gets the max amount of `asset` that an address can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The available amount the `_owner` can deposit in terms of `asset`
     */
    function availableDepositLimit(address /*_owner*/ ) public view override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a permissioned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed position maintenance or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * This will have no effect on PPS of the strategy till report() is called.
     *
     */
    function _tend(uint256 /*_totalIdle*/ ) internal override {
        _deployFunds(asset.balanceOf(address(this)));
    }

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     */
    function _tendTrigger() internal view override returns (bool) {
        return true;
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(_amount);
    }
}
