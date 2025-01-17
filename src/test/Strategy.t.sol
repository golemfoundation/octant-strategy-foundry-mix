// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {BaseTest} from "./Base.t.sol";
import {DragonTokenizedStrategy} from "octant-v2-core/src/dragons/vaults/DragonTokenizedStrategy.sol";
import {Strategy} from "../Strategy.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "octant-v2-core/src/interfaces/IStrategy.sol";

contract StrategyTest is BaseTest {
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
    }

    function testFreeFunds() public {
        // TODO: Implement to test free funds logic
    }

    function testHarvestTrigger() public {
        // TODO: Implement to test harvest trigger logic
    }

    function testHarvestAndReport() public {
        // TODO: Implement to test harvest and report logic
    }

    function testShutdownWithdraw() public {
        // TODO: Implement to test shutdown withdraw logic
    }

    function testTend() public {
        // TODO: Implement to test tend logic
    }

    function testEmergencyWithdraw() public {
        // TODO: Implement to test emergency withdraw logic
    }
}
