# LiquidityStrategy.sol

## High-Level Overview

LiquidityStrategy is a specialized yield-generating strategy contract that integrates Uniswap's CL Pool. The strategy inherits from Module (Zodiac), DragonBaseStrategy and LiquidityManager and implements a modular architecture, enabling secure multisig control and standardized strategy operations. 

The strategy's primary purpose is to automatically deposit asset into Uniswap's single sided CL Pool, optimize yields, and handle withdrawals efficiently while maintaining proper access control through a Safe multisig owner and enforcing octant protocol invariants through DragonTokenzizedStrategy delegated calls.

## Functionality Breakdown

### Vault Integration System:
- Implementation: Interfaces with Uniswap's NonfungiblePositionManager through standardized deposit/withdraw operations
- Security Considerations: 
  - Requires approvals to NonfungiblePositionManager before deposit
  - Uses safe approve pattern for asset transfers
  - Maintains separate approve flows for owners
- Key Interactions:
  - Direct deposit/withdraw with position NFTs
  - Asset approval management
  - Balance of position fee and idle assets tracking and reporting
  - Swap non-asset token to asset token while harvesting, collecting and withdrawing

### Modular Security Framework:
- Implementation: Utilizes Zodiac's Module system for enhanced access control
- Security Considerations:
  - Multisig ownership structure
  - Avatar and target pattern for controlled execution
  - Ownership transfer protections
- Key Interactions:
  - Setup configuration
  - Permission management
  - Safe multisig integration

## Contract Summary

Main functions:
- `setUp(bytes)`: Initializes strategy with configuration parameters
- `_deployFunds(uint256)`: Deposits funds into Uniswap
- `_freeFunds(uint256)`: Withdraws funds from Uniswap
- `_harvestAndReport()`: Performs yield harvesting and reports total assets
- `_tend(uint256)`: Manages idle funds by depositing into Uniswap
- `_emergencyWithdraw(uint256)`: Emergency withdrawal functionality
- `collectAllAndSwap()`: Collects all fees from all positions and swaps non-asset token to asset token

## Inherited Contracts

1. Module (Zodiac):
- Provides avatar-based access control system, and sets the module's avatar on setup
- Enables integration with Gnosis Safe
- Used for multisig authorization

2. DragonBaseStrategy:
- Implements core strategy functionality
- Provides standardized interfaces
- Manages basic fund operations

3. LiquidityManager:
- Manages position NFTs
- Manages position liquidity
- Manages position fees
- Manages position tokens
- Manages swapping actions

## Security Analysis

### Storage Layout

Storage variables and types:
```solidity
    /// @notice Uniswap position manager contract
    INonfungiblePositionManager public nonfungiblePositionManager;

    /// @notice Uniswap pool contract
    IUniswapV3Pool public pool;

    /// @notice Address of token0 in the pool
    address public token0;

    /// @notice Address of token1 in the pool
    address public token1;

    /// @notice Pool fee tier (0.3% = 3000)
    uint24 public constant POOL_FEE = 3000;

    /// @notice Uniswap V3 swap router contract
    IV3SwapRouter public swapRouter;

    /// @notice Mapping of tokenId to Deposit details
    mapping(uint256 => Deposit) public deposits;
```

Storage considerations:
- Storage slot collisions prevented by inheritance pattern
- Upgrade considerations rely on Module and DragonBaseStrategy patterns

### Method Analysis

#### Method: setUp

Initializes the strategy with required parameters and configurations.

```solidity
01  function setUp(bytes memory initializeParams) public override initializer {
02      (address _owner, bytes memory data) = abi.decode(initializeParams, (address, bytes));
03      (
04          address _nonfungiblePositionManager,
05          address _swapRouter,
06          address _poolAddress,
07          address _tokenizedStrategyImplementation,
08          address _asset,
09          address _management,
10          address _keeper,
11          address _dragonRouter,
12          uint256 _maxReportDelay,
13          string memory _name,
14          address _regenGovernance
15      ) = abi.decode(
16          data, (address, address, address, address, address, address, address, address, uint256, string, address)
17      );
18      // Validate pool contains strategy asset
19      if (IUniswapV3Pool(_poolAddress).token0() != _asset && IUniswapV3Pool(_poolAddress).token1() != _asset) {
20          revert InvalidPool();
21      }
22      // Initialize managers
23      __LiquidityManager_init(_nonfungiblePositionManager, _poolAddress, _swapRouter);
24      __Ownable_init(msg.sender);
25      __BaseStrategy_init(
26          _tokenizedStrategyImplementation,
27          _asset,
28          _owner,
29          _management,
30          _keeper,
31          _dragonRouter,
32          _maxReportDelay,
33          _name,
34          _regenGovernance
35      );
36      // Set up module permissions
37      setAvatar(_owner);
38      setTarget(_owner);
39      transferOwnership(_owner);
40  }
```

01 - Public initialization function with initializer modifier to prevent multiple calls.

02-17 - Decodes initialization parameters from bytes.

18-21 - Validates pool contains strategy asset.

22-23 - Initializes LiquidityManager.

24-35 - Initializes ownership and base strategy functionality.

36-40 - Configures Zodiac Module parameters and transfers ownership.

#### Method: _harvestAndReport

Handles yield harvesting and assets reporting.

```solidity
01  function _harvestAndReport() internal override returns (uint256 _totalAssets) {
02      _freeFunds(type(uint256).max);
03      return asset.balanceOf(address(this));
04  }
```

01 - Internal function overriding base strategy's harvest and report method.

02 - Withdraws entire balance from vault.

03-04 - Returns current balance as total assets.

#### Method: _deployFunds

Deposits funds into the Uniswap protocol.

```solidity
01  function _deployFunds(uint256 _amount) internal override {
02      // Input validation
03      if (_amount == 0) revert InvalidAmount();
04      // Determine which token is the strategy asset
05      bool isToken0 = address(asset) == token0;
06      uint256 token0Amount = isToken0 ? _amount : 0;
07      uint256 token1Amount = isToken0 ? 0 : _amount;
08      // Calculate optimal tick range for position
09      (int24 tickLower, int24 tickUpper) = calculateOptimalTicks(token0Amount, token1Amount);
10      // Create new liquidity position
11      (uint256 tokenId, uint128 liquidity, uint256 finalAmount0, uint256 finalAmount1) =
12          mintNewPosition(token0Amount, token1Amount, tickLower, tickUpper);
13      // Store position details
14      positions[positionCount] =
15          Position({tokenId: tokenId, liquidity: liquidity, amount0: finalAmount0, amount1: finalAmount1});
16      // Increment position counter
17      unchecked {
18          ++positionCount;
19      }
20  }
```

01 - Internal function to send assets into the Uniswap protocol.

02-04 - Input validation.

05-07 - Amount check and token determination.

08-09 - Calculates optimal tick range for position.

10-12 - Creates new liquidity position.

13-15 - Stores position details.

16-20 - Increments position counter.

#### Method: _freeFunds

Withdraws funds from the Uniswap protocol.

```solidity
01  function _freeFunds(uint256 _amount) internal override {
02      if (_amount == 0) revert InvalidAmount();
03      // Remove liquidity from all positions
04      for (uint256 i = 0; i < positionCount;) {
05          Position storage position = positions[i];
06          (uint128 liquidity, uint256 amount0, uint256 amount1) = removeLiquidity(position.tokenId);
07          unchecked {
08              position.amount0 -= amount0;
09              position.amount1 -= amount1;
10              position.liquidity -= liquidity;
11              ++i;
12          }
13      }
14      // Collect and swap all assets
15      uint256 amountOut = collectAllAndSwap();
16      // Redeploy excess funds if any
17      uint256 restFund = amountOut > _amount ? amountOut - _amount : 0;
18      if (restFund > 0) {
19          _deployFunds(restFund);
20      }
21  }
```

01 - Internal function overriding base strategy's withdrawal method.

02-04 - Input validation.

03-13 - Removes liquidity from all positions.

14-15 - Collects and swaps all assets.

16-21 - Redeploys excess funds if any.

#### Method: _tend

Manages idle funds by depositing them into the vault.

```solidity
01  function _tend(uint256 /*_totalIdle*/ ) internal override {
02      uint256 balance = asset.balanceOf(address(this));
03      if (balance > 0) {
04          _deployFunds(balance);
05      }
06  }
```

01 - Internal function overriding base strategy's tend method, idle parameter unused.

02 - Gets current asset balance of the strategy.

03-05 - If balance exists, deposits entire amount into Uniswap protocol.

#### Method: _emergencyWithdraw

Emergency withdrawal function to recover funds from vault.

```solidity
01  function _emergencyWithdraw(uint256 _amount) internal override {
02      _freeFunds(_amount);
03  }
```

01 - Internal function overriding base strategy's emergency withdrawal.

02-03 - Withdraws specified amount from vault, similar to _freeFunds but used in emergency scenarios, passes through to underlying, must be called by correct role in exposed version and withdraws amount from the Uniswap protocol.

#### Method: _tendTrigger

Determines if tending should occur.

```solidity
01  function _tendTrigger() internal pure override returns (bool) {
02      return true;
03  }
```

01 - Internal pure function overriding base strategy's tend trigger.

02-03 - Always returns true, indicating tending should always be possible however this could allow keeper to realize losses any time.

#### Method: collectAllAndSwap

Collects all fees from all positions and swaps non-asset token to asset token.

```solidity
01  function collectAllAndSwap() internal returns (uint256) {
02      bool isToken0 = address(asset) == token0;
03      uint256 totalAmountOut0;
04      uint256 totalAmountOut1;
05      // Collect fees from all positions
06      for (uint256 i = 0; i < positionCount;) {
07          Position memory position = positions[i];
08          (uint256 amount0, uint256 amount1) = collectAllFees(position.tokenId);
09          unchecked {
10          totalAmountOut0 += amount0;
11          totalAmountOut1 += amount1;
12          ++i;
13          }
14      }
15      // Swap collected fees to strategy asset
16      address swapToken = isToken0 ? token1 : token0;
17      uint256 swapAmount = isToken0 ? totalAmountOut1 : totalAmountOut0;
18      if (swapAmount > 0) {
19          uint256 amountOut = swapExactInputSingle(swapToken, address(asset), swapAmount, 0);
20          if (isToken0) {
21          totalAmountOut0 += amountOut;
22          } else {
23          totalAmountOut1 += amountOut;
24          }
25      }
26      return isToken0 ? totalAmountOut0 : totalAmountOut1;
27  }
```

01 - Internal function to collect all fees from all positions and swap non-asset token to asset token.

02 - Determines which token is the asset.

03-14 - Collects all fees from all positions.

15-25 - Swaps non-asset token to asset token.

26-27 - Returns total amount of asset tokens received.
