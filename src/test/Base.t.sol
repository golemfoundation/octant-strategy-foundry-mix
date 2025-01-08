// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {TestPlus} from "solady/test/utils/TestPlus.sol";
import {ModuleProxyFactory} from "../ModuleProxyFactory.sol";
import {TestERC20} from "octant-v2-core/src/test/TestERC20.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/Safe.sol";
import {ISafe} from "octant-v2-core/src/interfaces/Safe.sol";

contract BaseTest is Test, TestPlus {
    struct testTemps {
        address owner;
        uint256 ownerPrivateKey;
        address safe;
        address module;
    }

    string TEST_RPC_URL;
    address safeSingleton;
    address proxyFactory;

    uint256 threshold = 1;
    uint256 fork;
    ModuleProxyFactory public moduleFactory;
    TestERC20 public token;
    address[] public owners;

    function _configure(bool _useFork, string memory _chain) internal {
        if (_useFork) {
            if (keccak256(abi.encode(_chain)) == keccak256(abi.encode("polygon"))) {
                TEST_RPC_URL = vm.envString("TEST_RPC_URL_POLYGON");
                safeSingleton = vm.envAddress("TEST_SAFE_SINGLETON_POLYGON");
                proxyFactory = vm.envAddress("TEST_SAFE_PROXY_FACTORY_POLYGON");
            } else if (keccak256(abi.encode(_chain)) == keccak256(abi.encode("eth"))) {
                TEST_RPC_URL = vm.envString("TEST_RPC_URL");
                safeSingleton = vm.envAddress("TEST_SAFE_SINGLETON");
                proxyFactory = vm.envAddress("TEST_SAFE_PROXY_FACTORY");
            } else if (keccak256(abi.encode(_chain)) == keccak256(abi.encode("celo"))) {
                TEST_RPC_URL = vm.envString("TEST_RPC_URL_CELO");
                safeSingleton = vm.envAddress("TEST_SAFE_SINGLETON_CELO");
                proxyFactory = vm.envAddress("TEST_SAFE_PROXY_FACTORY_CELO");
            }
            fork = vm.createFork(TEST_RPC_URL);
            vm.selectFork(fork);
        } else {
            safeSingleton = address(new Safe());
            proxyFactory = address(new SafeProxyFactory());
        }

        // deploy module proxy factory and test erc20 asset
        moduleFactory = new ModuleProxyFactory();

        token = new TestERC20();
    }

    function _testTemps(address moduleImplementation, bytes memory moduleData) internal returns (testTemps memory t) {
        (t.owner, t.ownerPrivateKey) = _randomSigner();
        owners = [t.owner];
        // Deploy a new Safe Multisig using the Proxy Factory
        SafeProxyFactory factory = SafeProxyFactory(proxyFactory);
        bytes memory data = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners,
            threshold,
            moduleFactory,
            abi.encodeWithSignature(
                "deployAndEnableModuleFromSafe(address,bytes,uint256)",
                moduleImplementation,
                moduleData,
                block.timestamp
            ),
            address(0),
            address(0),
            0,
            address(0)
        );

        SafeProxy proxy = factory.createProxyWithNonce(safeSingleton, data, block.timestamp);

        token.mint(address(proxy), 100 ether);

        t.safe = address(proxy);
        (address[] memory array,) = ISafe(address(proxy)).getModulesPaginated(address(0x1), 1);
        t.module = array[0];
    }
}
