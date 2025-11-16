# Scripts Usage

- `npx hardhat run scripts/deploy.js --network baseSepolia`: Deploy the contract.
- `npx hardhat run scripts/configurePool.js --network baseSepolia`: Configure Uniswap pool after deployment.
- `npx hardhat run scripts/setRouterAndToken.js --network baseSepolia`: Set Uniswap router and DRB token.
- `npx hardhat run scripts/getConfig.js --network baseSepolia`: Read current config from contract.
- `npx hardhat run scripts/harvest.js --network baseSepolia`: Harvest ETH to burn DRB.
- `npx hardhat run scripts/whoami.js --network baseSepolia`: Check signer address and balance.
- `npx hardhat run scripts/checkBalance.js --network baseSepolia`: Check contract balance.

# DRB Debt Relief Harvester

A decentralized protocol that burns $DRB tokens while funding real debt relief. Built on Base network.

## 🌟 What It Does

Users send ETH to the contract, which automatically:
- **50%** → Swaps to $DRB tokens and burns them permanently (via Uniswap V3 with TWAP pricing)
- **50%** → Sends to community-controlled treasury for debt relief

## 🏗️ Architecture

### Smart Contract Features
- **Security**: ReentrancyGuard, Pausable, Role-based Access Control, Timelocks
- **DEX Integration**: Uniswap V3 with TWAP pricing for fair swaps
- **Daily Caps**: 10 ETH global limit, 1 ETH per user limit to prevent abuse
- **Emergency Recovery**: Multiple withdrawal mechanisms for stuck funds
- **Gas Optimization**: Limits, unchecked math, variable caching, optimizer enabled
- **Audit Ready**: Comprehensive NatSpec documentation and clean code

### Governance
- **Community Votes**: Snapshot for debt relief allocation decisions
- **Multi-Sig Treasury**: Secure fund management
- **No Dev Control**: Fully decentralized after launch

## 🚀 Quick Start

### Prerequisites
- Node.js 18+
- npm or yarn
- MetaMask wallet

### Installation
```bash
git clone <your-repo-url>
cd drb-tool
npm install
```

### Environment Setup
```bash
cp .env.example .env
# Edit .env with your private key and addresses
```

### Deploy Contract
```bash
# 1. Deploy the contract
npx hardhat run scripts/deploy.js --network baseSepolia

# 2. Configure Uniswap pool (creates DRB/WETH pool if needed)
npx hardhat run scripts/configurePool.js --network baseSepolia

# 3. Set router and token addresses
npx hardhat run scripts/setRouterAndToken.js --network baseSepolia
```

### Test Contract
```bash
# Test harvest functionality
npx hardhat run scripts/harvest.js --network baseSepolia

# Check contract balance
npx hardhat run scripts/checkEthBalance.js --network baseSepolia
```

## 📜 Scripts Usage

- `npx hardhat run scripts/deploy.js --network baseSepolia`: Deploy the contract.
- `npx hardhat run scripts/setTreasury.js --network baseSepolia`: Set treasury address.
- `npx hardhat run scripts/setRouterAndToken.js --network baseSepolia`: Set Uniswap router and DRB token.
- `npx hardhat run scripts/getConfig.js --network baseSepolia`: Read current config from contract.
- `npx hardhat run scripts/harvest.js --network baseSepolia`: Harvest ETH to burn DRB.
- `npx hardhat run scripts/whoami.js --network baseSepolia`: Check signer address and balance.
- `npx hardhat run scripts/checkBalance.js --network baseSepolia`: Check contract balance.

## 🌐 Frontend

A simple web interface is provided in `index.html` and `app.js` for users to interact with the contract.

- Open `index.html` in a web browser with MetaMask installed
- Connect your wallet (ensure you're on Base Sepolia network)
- Enter the ETH amount to contribute
- Click "Harvest & Burn DRB" to execute the transaction

The interface shows the split: half to debt relief, half swapped and burned as DRB.

## 🔧 Configuration

### Networks
- **Base Sepolia**: Testnet deployment
- **Ethereum Mainnet**: Production deployment

### Environment Variables
```env
PRIVATE_KEY=your_private_key
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
MAINNET_RPC_URL=https://eth.llamarpc.com
TREASURY_ADDRESS=treasury_wallet_address
DEPLOYED_ADDRESS=contract_address
DRB_TOKEN=drb_token_address
ROUTER_ADDRESS=uniswap_router_address
ETHERSCAN_API_KEY=your_etherscan_key
BASESCAN_API_KEY=your_basescan_key
```

## 🛡️ Security Features

- **Reentrancy Protection**: OpenZeppelin ReentrancyGuard
- **Emergency Pause**: Contract can be paused by treasury
- **Access Control**: Only treasury can modify critical settings
- **Slippage Protection**: Configurable minimum output amounts
- **Input Validation**: Comprehensive checks on all inputs

## 📊 Contract Addresses

### Base Sepolia (Testnet)
- **Contract**: `0x88546aCf5B2a1CC71DCc1C2a0862959729534f6B`
- **DRB Token**: `0x3ec2156D4c0A9CBdAB4a016633b7BcF6a8d68Ea2`
- **Uniswap Router**: `0x2626664c2603336E57B271c5C0b26F421741e481`
- **Treasury**: `0xcc52c6A9f64930D01538ab6056A722f5C914E603`

## Uniswap Swap + Burn Flow

1. **Donation** → `harvest()` called with ETH  
2. **50% ETH** → Swapped to $DRB via Uniswap V3  
   - Router: `0x2626664c...`  
   - Pool: DRB/WETH (0.3% fee)  
3. **$DRB received** → Sent to `0x000...dEaD` (burned forever)  
4. **Other 50% ETH** → Treasury (real debt relief)  

**TWAP Protection**: 30-min average price used to prevent manipulation.  
**Live on Base Sepolia**: [0x41c1...4DC3](https://sepolia.basescan.org/address/0x41c1c1997058697b93cCbFD3dfF46a64b0d74DC3)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details.

## 📜 DRB Debt Relief Harvester – **Gated** Roadmap & Continuity Plan  
*(v1.0 – Deployed on Base | MIT Licensed | **Community-Governed** | Updated: November 16, 2025 – 06:56 PM NZDT)*

> **Burn $DRB → Uniswap V3 TWAP → Feed the Relief Pool**  
> This is the **v1 core** on-chain fee harvester.  
> **Only verified community members may merge to `master`.**

---

### 🛡️ **Security & Governance Rules** (Enforced via GitHub)

| Rule | How It's Enforced |
|------|-------------------|
| **All PRs need 2 approvals** from `CODEOWNERS` | GitHub branch protection |
| **No direct pushes to `master`** | Branch protection |
| **Contract upgrades require on-chain vote** | `DebtReliefHarvester.proposeUpgrade()` |
| **Emergency pause** | Multisig `onlyOwner` → `pause()` |

> **`.github/CODEOWNERS`** (current trusted approvers):  
> ```text
> *       @DonnieLemon69
> ```

---

### 🗺️ **Roadmap** – Community-Voted Milestones

| Phase | Goal | Status | Vote Required | Target (NZDT) |
|-------|------|--------|---------------|---------------|
| **v1.0** | Core harvester: burn $DRB + feed relief pool | ✅ Live on Base | — | Nov 2025 |
| **v1.1** | Uniswap V3 TWAP + slippage guard | ✅ Merged | — | Nov 2025 |
| **v1.2** | On-chain vote to adjust treasury % | 🔄 In Progress | Snapshot vote | Dec 1, 2025 |
| **v1.3** | React + wagmi dashboard (view burns, pool balance) | ⏳ Planned | Discord poll | Q1 2026 |
| **v2.0** | Multi-chain (Base → Arbitrum) + bridge | ⏳ Planned | On-chain proposal | TBD |

> **To propose a change**: Open an **Issue** with label `proposal` →

## ⚠️ Disclaimer

This is experimental software. Use at your own risk. Always test on testnets first.

## Uniswap Swap + Burn Flow

1. **Donation** → `harvest()` called with ETH  
2. **50% ETH** → Swapped to $DRB via Uniswap V3  
   - Router: `0x2626664c...`  
   - Pool: DRB/WETH (0.3% fee)  
3. **$DRB received** → Sent to `0x000...dEaD` (burned forever)  
4. **Other 50% ETH** → Treasury (real debt relief)  

**TWAP Protection**: 30-min average price used to prevent manipulation.  
**Live on Base Sepolia**: [0x41c1...4DC3](https://sepolia.basescan.org/address/0x41c1c1997058697b93cCbFD3dfF46a64b0d74DC3)
