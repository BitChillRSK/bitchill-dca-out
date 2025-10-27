# BitChill DCA Out Protocol

A simplified, permissionless protocol for automatically selling Bitcoin (rBTC) for stablecoins (DOC) on Rootstock.

## 🎯 Overview

BitChill DCA Out enables users to:
- **Schedule periodic rBTC sales** with customizable amounts and intervals
- **Automatically mint DOC** through the Money on Chain (MoC) protocol
- **Earn while waiting** - no complex lending integrations needed
- **Pay transparent fees** - Simple 1% flat fee charged in DOC after minting

### Why DCA Out?

With Bitcoin approaching ATH, the market dynamics favor taking profits. This protocol complements the existing BitChill DCA In by providing a simple exit strategy without the complexity of lending protocols (which only yield ~0.3% APY on rBTC anyway).

## 🏗️ Architecture

### Single Contract Design

Unlike the DCA In protocol, this implementation uses **a single deployed contract** for maximum simplicity:

```
DcaOutManager (Main & Only Deployed Contract)
├── Ownable (Owner functions)
├── AccessControl (SWAPPER_ROLE for bot authorization)
├── ReentrancyGuard (rBTC deposit/withdrawal safety)
└── FeeHandler (Abstract - fee calculation logic)

Interfaces:
- IMocProxy (MoC protocol interaction)
- IDcaOutManager (External interface)
- IFeeHandler (Fee handler interface)
```

**Why simpler?**
- ❌ No lending protocols → No OperationsAdmin needed
- ❌ No multiple handlers → Single purchase flow (MoC only)
- ❌ No complex token routing → Direct rBTC → DOC
- ✅ Just AccessControl for swapper authorization
- ✅ Clean, auditable, gas-efficient

## 📋 Features

### Core Functionality

- **Schedule Creation**: Users create DCA schedules with custom rBTC amount and period
- **rBTC Deposits**: Users deposit rBTC to their schedules (native currency handling)
- **Automated Execution**: Authorized swappers execute mints when schedules are ready
- **Batch Processing**: Multiple users can be processed in a single transaction for gas efficiency
- **DOC Withdrawals**: Users withdraw their accumulated DOC anytime
- **Fee Management**: Owner-controlled fee parameters with sliding scale option

### Security Features

- ✅ ReentrancyGuard on all financial operations
- ✅ AccessControl for role-based permissions
- ✅ Schedule ID validation to prevent unauthorized actions
- ✅ Owner-controlled parameters (min amounts, periods, fees)
- ✅ Comprehensive test coverage (22/22 tests passing)

## 🚀 Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd bitchill-dca-out

# Install dependencies
forge install

# Build contracts
forge build
```

### Running Tests

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test test_CreateSchedule -vvv

# Generate gas report
forge test --gas-report
```

### Deployment

```bash
# Deploy to local Anvil
forge script script/DeployDcaOut.s.sol:DeployDcaOut --rpc-url http://localhost:8545 --broadcast

# Deploy to Rootstock Testnet
forge script script/DeployDcaOut.s.sol \
  --rpc-url $RSK_TESTNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --verifier blockscout \
  --verifier-url $BLOCKSCOUT_API_URL \
  --legacy

# Deploy to Rootstock Mainnet
forge script script/DeployDcaOut.s.sol \
  --rpc-url $RSK_MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --verifier blockscout \
  --verifier-url $BLOCKSCOUT_API_URL \
  --legacy
```

## 📖 Usage

### For Users

1. **Create a Schedule with Initial Deposit**
   ```solidity
   dcaOutManager.createSchedule{value: 1 ether}(
       0.01 ether,  // Sell 0.01 rBTC per period
       1 days       // Every day
   );
   ```

2. **Deposit More rBTC (Optional)**
   ```solidity
   bytes32 scheduleId = getSchedule(user, scheduleIndex).scheduleId;
   dcaOutManager.depositRbtc{value: 1 ether}(scheduleIndex, scheduleId);
   ```

3. **Wait for Execution** (automated by swapper bot)

4. **Withdraw DOC**
   ```solidity
   uint256 balance = dcaOutManager.getUserDocBalance(msg.sender);
   dcaOutManager.withdrawDoc();
   ```

### For Swappers (Bots)

1. **Get Swapper Role** (granted by admin)
   
2. **Execute Single Sell**
   ```solidity
   dcaOutManager.sellRbtc(userAddress, scheduleIndex, scheduleId);
   ```

3. **Execute Batch Sell** (gas efficient)
   ```solidity
   address[] memory users = [user1, user2, user3];
   uint256[] memory schedules = [0, 0, 1];
   bytes32[] memory scheduleIds = [id1, id2, id3];
   
   dcaOutManager.batchSellRbtc(users, schedules, scheduleIds);
   ```

## ⚙️ Configuration

### Protocol Parameters (in `Constants.sol`)

```solidity
MIN_SALE_AMOUNT = 0.0005 ether;     // ~25 DOC minimum
MIN_FEE_RATE = 100;                  // 1% (basis points)
MAX_FEE_RATE = 100;                  // 1% flat rate
MIN_SALE_PERIOD = 1 days;            // Minimum time between sells
MAX_SCHEDULES_PER_USER = 10;         // Maximum schedules per user
```

### Network Addresses

**Rootstock Mainnet:**
- DOC Token: `0xe700691dA7b9851F2F35f8b8182c69c53CcaD9Db`
- MoC Proxy: `0xf773B590aF754D597770937Fa8ea7AbDf2668370`

**Rootstock Testnet:**
- DOC Token: `0xCB46c0ddc60D18eFEB0E586C17Af6ea36452Dae0`
- MoC Proxy: `0x2820f6d4D199B8D8838A4B26F9917754B86a0c1F`

## 🧪 Testing

The protocol includes comprehensive test coverage:

### Test Categories

- **Schedule Management** (7 tests)
  - Create/delete schedules
  - Multiple schedules
  - Validation (amount, period, max schedules)

- **Deposits** (3 tests)
  - Single and multiple deposits
  - Schedule ID validation

- **Execution** (4 tests)
  - Single execution
  - Fee collection
  - Authorization checks
  - Balance/timing validations

- **Withdrawals** (3 tests)
  - DOC withdrawal
  - rBTC withdrawal
  - Schedule deletion

- **Batch Operations** (1 test)
  - Multi-user batch minting

- **Access Control** (2 tests)
  - Grant/revoke swapper role

- **Getters** (3 tests)
  - Protocol parameters

**Result: 22/22 tests passing ✅**

## 📁 Project Structure

```
bitchill-dca-out/
├── src/
│   ├── DcaOutManager.sol         # Main contract (580+ lines)
│   ├── FeeHandler.sol             # Abstract fee handler
│   └── interfaces/
│       ├── IDcaOutManager.sol     # Main interface
│       ├── IFeeHandler.sol        # Fee interface
│       └── IMocProxy.sol          # MoC interface
├── script/
│   ├── Constants.sol              # Protocol constants
│   ├── HelperConfig.s.sol         # Network configs + mocks
│   └── DeployDcaOut.s.sol         # Deployment script
├── test/
│   └── DcaOutManagerTest.t.sol    # Test suite (22 tests)
├── lib/
│   ├── forge-std/                 # Foundry standard library
│   └── openzeppelin-contracts/    # OpenZeppelin v4.9.3
└── foundry.toml                   # Foundry configuration
```

## 🔐 Security Considerations

1. **Reentrancy Protection**: All state-changing functions with external calls use `nonReentrant`
2. **Access Control**: Role-based permissions using OpenZeppelin's AccessControl
3. **Input Validation**: All parameters validated before state changes
4. **Schedule Validation**: Schedule IDs prevent unauthorized operations
5. **Safe Transfers**: SafeERC20 for all DOC token transfers

### Audit Status

⚠️ **Not yet audited** - Use at your own risk. Recommended for testnet only until audited.

## 🤝 Contributing

This is a personal project by the BitChill team. For issues or suggestions, please open an issue.

## 📄 License

MIT License - see LICENSE file for details

## 👥 Team

**BitChill Team**
- Lead Developer: Antonio Rodríguez-Ynyesto ([@ynyesto](https://github.com/ynyesto))

## 🔗 Related Projects

- [BitChill DCA In](../bitchill-contracts) - The original DCA protocol for accumulating BTC with yield

## 📊 Gas Optimization

The protocol is optimized for gas efficiency:
- Single contract deployment
- Batch processing for multiple users
- Minimal storage operations
- Efficient data structures

## 🌟 Acknowledgments

- OpenZeppelin for secure contract primitives
- Foundry for the excellent development framework
- Money on Chain for the DOC minting infrastructure
- The Rootstock community

---

**Note**: This protocol is designed for the current market phase (BTC near ATH). Always do your own research and never invest more than you can afford to lose.
