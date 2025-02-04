// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from
    "../aerodrome-strategy/aerodrome/periphery/interfaces/INonfungiblePositionManager.sol";
import {DragonTokenizedStrategy} from "octant-v2-core/src/dragons/vaults/DragonTokenizedStrategy.sol";
import {TokenizedStrategy__NotOperator} from "octant-v2-core/src/errors.sol";
import {console2} from "forge-std/console2.sol";
import {BaseTest} from "./Base.t.sol";
import {AerodromeStrategy} from "../aerodrome-strategy/AerodromeStrategy.sol";
import {IAerodromeStrategyInterface} from "../interfaces/IAerodromeStrategyInterface.sol";

/// @title Aerodrome Strategy Test Suite
/// @notice Comprehensive test suite for the AerodromeStrategy contract
/// @dev Inherits from BaseTest for common test functionality
contract AerodromeStrategyTest is BaseTest {
    // =========== Constants ===========
    uint256 public constant INITIAL_DEPOSIT = 1e11;
    uint256 public constant MAX_BPS = 10_000;

    // =========== Test State Variables ===========
    address public management;
    address public keeper;
    address public dragonRouter;
    address public regenGovernance;
    uint256 public maxReportDelay;

    TestTemps public temps;
    IAerodromeStrategyInterface public module;
    address public tokenizedStrategyImplementation;
    address public moduleImplementation;

    // Base addresses
    address public constant AERODROME_POSITION_MANAGER = 0x827922686190790b37229fd06084350E74485b72;
    address public constant AERODROME_POOL = 0xBE00fF35AF70E8415D0eB605a286D8A45466A4c1;
    address public constant AERODROME_ROUTER = 0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5;
    address public constant WETH = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant USDC = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;

    IERC20 public token0;
    IERC20 public token1;
    IERC20 public asset;

    // =========== Events ===========
    event PositionCreated(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event PositionClosed(uint256 indexed tokenId, uint128 liquidity);

    /// @notice Set up the test environment before each test
    function setUp() public {
        _configure(true, "base");

        // Initialize addresses
        management = makeAddr("management");
        keeper = makeAddr("keeper");
        dragonRouter = makeAddr("dragonRouter");
        regenGovernance = makeAddr("regenGovernance");
        maxReportDelay = 7 days;

        // Deploy implementations
        moduleImplementation = address(new AerodromeStrategy());
        tokenizedStrategyImplementation = address(new DragonTokenizedStrategy());

        // Initialize tokens
        token0 = IERC20(WETH);
        token1 = IERC20(USDC);
        asset = IERC20(USDC);

        // Set up strategy
        temps = _testTemps(
            moduleImplementation,
            abi.encode(
                AERODROME_POSITION_MANAGER,
                AERODROME_ROUTER,
                AERODROME_POOL,
                tokenizedStrategyImplementation,
                address(asset),
                management,
                keeper,
                dragonRouter,
                maxReportDelay,
                "AerodromeStrategy",
                regenGovernance
            )
        );
        module = IAerodromeStrategyInterface(payable(temps.module));
    }

    /// @notice Test initial module configuration
    function testCheckModuleInitialization() public view {
        assertTrue(module.owner() == temps.safe);
        assertTrue(module.keeper() == keeper);
        assertTrue(module.management() == management);
        assertTrue(module.dragonRouter() == dragonRouter);
        assertTrue(module.tokenizedStrategyImplementation() == tokenizedStrategyImplementation);
        assertTrue(module.maxReportDelay() == maxReportDelay);
        assertTrue(module.nonfungiblePositionManager() == AERODROME_POSITION_MANAGER);
        assertTrue(module.pool() == AERODROME_POOL);
        assertTrue(module.swapRouter() == AERODROME_ROUTER);
        assertTrue(module.token0() == address(token0));
        assertTrue(module.token1() == address(token1));
        assertTrue(module.regenGovernance() == regenGovernance);
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
        assertTrue((amount0 == 0 && amount1 > 0) || (amount0 > 0 && amount1 == 0), "Amounts should be split");

        vm.stopPrank();
    }

    /// @notice Test freeing funds from positions
    function testFreeFunds() public {
        // Setup initial deposit
        _deposit(INITIAL_DEPOSIT);

        vm.startPrank(temps.safe);

        // Record initial state
        uint256 initialBalance = asset.balanceOf(temps.safe);

        // Execute withdrawal
        module.withdraw(INITIAL_DEPOSIT / 2, temps.safe, temps.safe, MAX_BPS);

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
        assertTrue(asset.balanceOf(address(module)) >= emergencyAmount, "Emergency withdrawal failed");

        vm.stopPrank();
    }

    function testTendTrigger() public view {
        (bool trigger,) = module.tendTrigger();
        assertTrue(trigger);
    }

    /// @notice Helper function to deposit funds
    /// @param amount Amount to deposit
    function _deposit(uint256 amount) internal {
        deal(address(asset), temps.safe, amount, true);

        // Verify authorization
        vm.expectRevert(TokenizedStrategy__NotOperator.selector);
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
        (uint256 tokenId, uint128 liquidity,,) = module.positions(count);
        (,, address _token0, address _token1, int24 _tickSpacing, int24 _tickLower, int24 _tickUpper,,,,,) =
            INonfungiblePositionManager(AERODROME_POSITION_MANAGER).positions(tokenId);

        console2.log("Position token0", _token0);
        console2.log("Position token1", _token1);
        console2.log("Position tickSpacing", _tickSpacing);
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
