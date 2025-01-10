// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "./Base.t.sol";
import {DragonTokenizedStrategy} from "octant-v2-core/src/dragons/DragonTokenizedStrategy.sol";
import {LiquidityStrategy} from "../liquidity-strategy/LiquidityStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ILiquidityStrategyInterface} from "../interfaces/ILiquidityStrategyInterface.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {console2} from "forge-std/console2.sol";

/// @title Liquidity Strategy Test Suite
/// @notice Comprehensive test suite for the LiquidityStrategy contract
/// @dev Inherits from BaseTest for common test functionality
contract LiquidityStrategyTest is BaseTest {
    // =========== Constants ===========
    uint256 constant INITIAL_DEPOSIT = 1e11;
    uint256 constant MAX_BPS = 10_000;

    // =========== Test State Variables ===========
    address public management;
    address public keeper;
    address public dragonRouter;
    uint256 public maxReportDelay;

    testTemps public temps;
    ILiquidityStrategyInterface public module;
    address public tokenizedStrategyImplementation;
    address public moduleImplementation;

    // Mainnet addresses
    // address public constant UNISWAP_V3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    // address public constant UNISWAP_V3_POOL = 0x99ac8cA7087fA4A2A1FB6357269965A2014ABc35;
    // address public constant UNISWAP_V3_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    // address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    // address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // Celo addresses
    address public constant UNISWAP_V3_POSITION_MANAGER = 0x3d79EdAaBC0EaB6F08ED885C05Fc0B014290D95A;
    address public constant UNISWAP_V3_POOL = 0xE426E1305f5e6093864762Bf9d2D8B44BC211c59;
    address public constant UNISWAP_V3_ROUTER = 0x5615CDAb10dc425a742d643d949a7F474C01abc4;
    address public constant WETH = 0x66803FB87aBd4aaC3cbB3fAd7C3aa01f6F3FB207;
    address public constant USDC = 0xcebA9300f2b948710d2653dD7B07f33A8B32118C;

    IERC20 public token0;
    IERC20 public token1;
    IERC20 public asset;

    // =========== Events ===========
    event PositionCreated(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event PositionClosed(uint256 indexed tokenId, uint128 liquidity);

    /// @notice Set up the test environment before each test
    function setUp() public {
        _configure(true, "celo");

        // Initialize addresses
        management = makeAddr("management");
        keeper = makeAddr("keeper");
        dragonRouter = makeAddr("dragonRouter");
        maxReportDelay = 7 days;

        // Deploy implementations
        moduleImplementation = address(new LiquidityStrategy());
        tokenizedStrategyImplementation = address(new DragonTokenizedStrategy());

        // Initialize tokens
        token0 = IERC20(WETH);
        token1 = IERC20(USDC);
        asset = IERC20(USDC);

        // Set up strategy
        temps = _testTemps(
            moduleImplementation,
            abi.encode(
                UNISWAP_V3_POSITION_MANAGER,
                UNISWAP_V3_ROUTER,
                UNISWAP_V3_POOL,
                tokenizedStrategyImplementation,
                address(asset),
                management,
                keeper,
                dragonRouter,
                maxReportDelay,
                "LiquidityStrategy"
            )
        );
        module = ILiquidityStrategyInterface(payable(temps.module));
    }

    /// @notice Test initial module configuration
    function testCheckModuleInitialization() public view {
        assertTrue(module.owner() == temps.safe);
        assertTrue(module.keeper() == keeper);
        assertTrue(module.management() == management);
        assertTrue(module.dragonRouter() == dragonRouter);
        assertTrue(module.tokenizedStrategyImplementation() == tokenizedStrategyImplementation);
        assertTrue(module.maxReportDelay() == maxReportDelay);
        assertTrue(module.nonfungiblePositionManager() == UNISWAP_V3_POSITION_MANAGER);
        assertTrue(module.pool() == UNISWAP_V3_POOL);
        assertTrue(module.swapRouter() == UNISWAP_V3_ROUTER);
        assertTrue(module.TOKEN0() == address(token0));
        assertTrue(module.TOKEN1() == address(token1));
    }

    /// @notice Test deploying funds into a new position
    function testDeployFunds() public {
        // Setup initial deposit
        _deposit(INITIAL_DEPOSIT);

        vm.startPrank(temps.safe);

        // Verify position creation
        assertEq(module.positionCount(), 1, "Position count should be 1");

        // Get position details
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = module.positions(0);

        // Verify position state
        assertTrue(tokenId > 0, "Token ID should be non-zero");
        assertTrue(liquidity > 0, "Liquidity should be non-zero");
        assertTrue(amount0 > 0, "Amount0 should be non-zero");
        assertTrue(amount1 > 0, "Amount1 should be non-zero");

        vm.stopPrank();
    }

    /// @notice Test freeing funds from positions
    function testFreeFunds() public {
        // Setup initial deposit
        _deposit(INITIAL_DEPOSIT);

        vm.startPrank(temps.safe);

        // Record initial state
        uint256 initialBalance = asset.balanceOf(temps.safe);
        (uint256 tokenId, uint128 initialLiquidity, uint256 posAmount0, uint256 posAmount1) = module.positions(0);

        // Execute withdrawal
        module.withdraw(INITIAL_DEPOSIT, temps.safe, temps.safe, MAX_BPS);

        // Verify final state
        uint256 finalBalance = asset.balanceOf(temps.safe);
        (, uint128 finalLiquidity,,) = module.positions(0);

        // Assertions
        assertTrue(finalBalance > initialBalance, "Balance should increase after withdrawal");
        assertEq(finalLiquidity, 0, "Position should be closed");

        vm.stopPrank();
    }

    /// @notice Test harvesting and reporting
    function testHarvestAndReport() public {
        // Setup initial deposit
        _deposit(INITIAL_DEPOSIT);

        // Execute report
        vm.prank(keeper);
        module.report();
        assertTrue(asset.balanceOf(address(module)) > 0, "Module should have assets");

        // Tend idle funds
        vm.prank(keeper);
        module.tend();
    }

    /// @notice Test harvest trigger conditions
    function testHarvestTrigger() public {
        // Should return false with no assets
        assertTrue(!module.harvestTrigger(), "Should not trigger with no assets");

        // Deposit funds
        _deposit(INITIAL_DEPOSIT);

        // Should trigger after max delay
        vm.warp(block.timestamp + 10 days);
        assertTrue(module.harvestTrigger(), "Should trigger after delay");
    }

    /// @notice Test emergency shutdown withdrawal
    function testShutdownWithdraw() public {
        // Setup initial deposit
        _deposit(INITIAL_DEPOSIT);

        vm.startPrank(management);

        // Execute emergency withdrawal
        uint256 emergencyAmount = INITIAL_DEPOSIT / 2;
        module.shutdownStrategy();
        module.emergencyWithdraw(emergencyAmount);

        // Verify withdrawal
        assertTrue(asset.balanceOf(address(module)) > emergencyAmount, "Emergency withdrawal failed");

        vm.stopPrank();
    }

    /// @notice Helper function to deposit funds
    /// @param amount Amount to deposit
    function _deposit(uint256 amount) internal {
        deal(address(asset), temps.safe, amount, true);

        // Verify authorization
        vm.expectRevert("Unauthorized");
        module.deposit(amount, temps.safe);

        vm.startPrank(temps.safe);

        // Verify deposit limits
        assertTrue(module.availableDepositLimit(temps.safe) == type(uint256).max);
        assertTrue(module.balanceOf(temps.safe) == 0);

        // Execute deposit
        module.deposit(amount, temps.safe);

        vm.stopPrank();
    }

    /// @notice Helper function to view position details
    /// @param count Position count to view
    function _viewPosition(uint256 count) internal view {
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = module.positions(count);
        (,, address _token0, address _token1, uint24 _fee, int24 _tickLower, int24 _tickUpper,,,,,) =
            INonfungiblePositionManager(UNISWAP_V3_POSITION_MANAGER).positions(tokenId);

        console2.log("Position token0", _token0);
        console2.log("Position token1", _token1);
        console2.log("Position fee", _fee);
        console2.log("Position tickLower", _tickLower);
        console2.log("Position tickUpper", _tickUpper);
        console2.log("Position liquidity", uint256(liquidity));
    }

    function _getBalance() internal view returns (uint256 safe0, uint256 safe1, uint256 module0, uint256 module1) {
        safe0 = asset.balanceOf(temps.safe);
        safe1 = token0.balanceOf(temps.safe);
        module0 = token0.balanceOf(address(module));
        module1 = token1.balanceOf(address(module));
    }
}
