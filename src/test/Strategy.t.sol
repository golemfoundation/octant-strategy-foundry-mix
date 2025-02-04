// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {BaseTest} from "./Base.t.sol";
import {DragonTokenizedStrategy} from "octant-v2-core/src/dragons/vaults/DragonTokenizedStrategy.sol";
import {Strategy} from "../Strategy.sol";

import {TokenizedStrategy__NotOperator} from "octant-v2-core/src/errors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "octant-v2-core/src/interfaces/IStrategy.sol";

contract StrategyTest is BaseTest {
    uint256 public constant INITIAL_DEPOSIT = 1e11;
    uint256 public constant MAX_BPS = 10_000;

    address public management = makeAddr("management");
    address public keeper = makeAddr("keeper");
    address public dragonRouter = makeAddr("dragonRouter");
    address public regenGovernance = makeAddr("regenGovernance");
    uint256 public maxReportDelay = 7 days;

    TestTemps public temps;
    address public tokenizedStrategyImplementation;
    address public moduleImplementation;
    IStrategy public module;
    address public yieldSource = makeAddr("yieldSource");
    IERC20 public asset;

    function setUp() public {
        _configure(true, "celo");
        moduleImplementation = address(new Strategy());
        tokenizedStrategyImplementation = address(new DragonTokenizedStrategy());

        temps = _testTemps(
            moduleImplementation,
            abi.encode(
                yieldSource,
                tokenizedStrategyImplementation,
                address(token),
                management,
                keeper,
                dragonRouter,
                maxReportDelay,
                "Strategy",
                regenGovernance
            )
        );
        module = IStrategy(payable(temps.module));
        asset = token;
    }

    function testCheckModuleInitialization() public view {
        assertTrue(module.owner() == temps.safe);
        assertTrue(module.keeper() == keeper);
        assertTrue(module.management() == management);
        assertTrue(module.dragonRouter() == dragonRouter);
        assertTrue(module.tokenizedStrategyImplementation() == address(tokenizedStrategyImplementation));
        assertTrue(module.maxReportDelay() == maxReportDelay);
        assertTrue(module.regenGovernance() == regenGovernance);
    }

    function testDeployFunds() public {
        // TODO: Implement to test deploy funds logic
        _deposit(INITIAL_DEPOSIT);

        vm.startPrank(temps.safe);

        assertTrue(module.balanceOf(temps.safe) == INITIAL_DEPOSIT);
        assertTrue(asset.balanceOf(address(module)) == INITIAL_DEPOSIT);
        assertTrue(asset.balanceOf(temps.safe) == 0);

        vm.stopPrank();
    }

    function testFreeFunds() public {
        // TODO: Implement to test free funds logic
        _deposit(INITIAL_DEPOSIT);

        vm.startPrank(temps.safe);

        module.withdraw(INITIAL_DEPOSIT, temps.safe, temps.safe, MAX_BPS);

        assertTrue(module.balanceOf(temps.safe) == 0);
        assertTrue(asset.balanceOf(address(module)) == 0);
        assertTrue(asset.balanceOf(temps.safe) == INITIAL_DEPOSIT);

        vm.stopPrank();
    }

    function testHarvestTrigger() public {
        // TODO: Implement to test harvest trigger logic
        assertTrue(!module.harvestTrigger(), "Should not trigger with no assets");

        // Deposit funds
        _deposit(INITIAL_DEPOSIT);

        // Should trigger after max delay
        vm.warp(block.timestamp + 10 days);
        assertTrue(module.harvestTrigger(), "Should trigger after delay");
    }

    function testHarvestAndReport() public {
        // TODO: Implement to test harvest and report logic
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

    // function testShutdownWithdraw() public {
    //     // TODO: Implement to test shutdown withdraw logic
    // }

    // function testTend() public {
    //     // TODO: Implement to test tend logic
    // }

    // function testEmergencyWithdraw() public {
    //     // TODO: Implement to test emergency withdraw logic
    // }

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
}
