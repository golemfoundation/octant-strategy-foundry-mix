// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {BaseStrategy, ERC20} from "octant-v2-core/src/dragons/BaseStrategy.sol";
import {Module} from "zodiac/core/Module.sol";

import {IStrategy} from "octant-v2-core/src/interfaces/IStrategy.sol";

contract Strategy is Module, BaseStrategy {
    /// @dev Yearn Polygon Aave V3 USDC Lender Vault
    address public constant yieldSource = 0x52367C8E381EDFb068E9fBa1e7E9B2C847042897;

    /// @dev Initialize function, will be triggered when a new proxy is deployed
    /// @dev owner of this module will the safe multisig that calls setUp function
    /// @param initializeParams Parameters of initialization encoded
    function setUp(bytes memory initializeParams) public override initializer {
        /// @dev Strategy specific parameters
        address _asset = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
        /// @dev USDC Polygon
        string memory _name = "Octant Polygon USDC Strategy";

        (address _owner, bytes memory data) = abi.decode(initializeParams, (address, bytes));

        (
            address _tokenizedStrategyImplementation,
            address _management,
            address _keeper,
            address _dragonRouter,
            uint256 _maxReportDelay
        ) = abi.decode(data, (address, address, address, address, uint256));

        __Ownable_init(msg.sender);
        __BaseStrategy_init(
            _tokenizedStrategyImplementation,
            _asset,
            _owner,
            _management,
            _keeper,
            _dragonRouter,
            _maxReportDelay,
            _name
        );

        ERC20(_asset).approve(yieldSource, type(uint256).max);
        IStrategy(yieldSource).approve(_owner, type(uint256).max);

        setAvatar(_owner);
        setTarget(_owner);
        transferOwnership(_owner);
    }

    function _deployFunds(uint256 _amount) internal override {
        IStrategy(yieldSource).deposit(_amount, address(this));
    }

    function _freeFunds(uint256 _amount) internal override {
        IStrategy(yieldSource).withdraw(_amount, address(this), address(this));
    }

    /* @dev As we are using yearn vault, the strategy accrues yield in the vault. so the value of strategy's shares
     * is increased therfore to accrue rewards to the dragon router we have to withdraw all funds and deposit back the remaining funds after
     * shares of dragon router are allocated.
     */
    function _harvestAndReport() internal override returns (uint256) {
        uint256 _withdrawAmount = IStrategy(yieldSource).maxWithdraw(address(this));
        IStrategy(yieldSource).withdraw(_withdrawAmount, address(this), address(this));
        return ERC20(asset).balanceOf(address(this));
    }

    function _tend(uint256 /*_idle*/ ) internal override {
        uint256 balance = ERC20(asset).balanceOf(address(this));
        if (balance > 0) {
            IStrategy(yieldSource).deposit(balance, address(this));
        }
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        IStrategy(yieldSource).withdraw(_amount, address(this), address(this));
    }

    function _tendTrigger() internal pure override returns (bool) {
        return true;
    }
}
