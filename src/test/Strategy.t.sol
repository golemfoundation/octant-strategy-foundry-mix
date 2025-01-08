// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Base.t.sol";
import {DragonTokenizedStrategy} from "octant-v2-core/src/dragons/DragonTokenizedStrategy.sol";
import {Strategy} from "../Strategy.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "octant-v2-core/src/interfaces/IStrategy.sol";

contract StrategyTest is BaseTest {
    address management = makeAddr("management");
    address keeper = makeAddr("keeper");
    address dragonRouter = makeAddr("dragonRouter");
    uint256 maxReportDelay = 7 days;

    testTemps temps;
    address tokenizedStrategyImplementation;
    address moduleImplementation;
    IStrategy module;
    address yieldSource = makeAddr("yieldSource");
    IERC20 asset;

    function setUp() public {
        _configure(true, "polygon");
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
                "Strategy"
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
