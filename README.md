# Scripts Usage

- `npx hardhat run scripts/deploy.js --network baseSepolia`: Deploy the contract.
- `npx hardhat run scripts/setTreasury.js --network baseSepolia`: Set treasury address.
- `npx hardhat run scripts/setRouterAndToken.js --network baseSepolia`: Set Uniswap router and DRB token (if not set in constructor).
- `npx hardhat run scripts/getConfig.js --network baseSepolia`: Read current config from contract.
- `npx hardhat run scripts/harvest.js --network baseSepolia`: Harvest ETH to burn DRB.
- `npx hardhat run scripts/whoami.js --network baseSepolia`: Check signer address and balance.
- `npx hardhat run scripts/checkBalance.js --network baseSepolia`: Check contract balance.

# DRB Debt Relief Harvester

A decentralized protocol that burns $DRB tokens while funding real debt relief. Built on Base network.

## 🌟 What It Does

Users send ETH to the contract, which automatically:
- **50%** → Swaps to $DRB tokens and burns them permanently
- **50%** → Sends to community-controlled treasury for debt relief

## 🏗️ Architecture

### Smart Contract
- **Security**: ReentrancyGuard, Pausable, Access Controls
- **DEX Integration**: Uniswap V3 for ETH→DRB swaps
- **Treasury**: 3-of-5 multi-sig controlled by community
- **Transparency**: All transactions publicly verifiable

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
npx hardhat run scripts/deploy.js --network baseSepolia
```

### Configure Contract
```bash
npx hardhat run scripts/setRouterAndToken.js --network baseSepolia
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

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details.

## ⚠️ Disclaimer

This is experimental software. Use at your own risk. Always test on testnets first.

# Frontend

A simple web interface is provided in `index.html` and `app.js` for users to interact with the contract.

- Open `index.html` in a web browser with MetaMask installed
- Connect your wallet (ensure you're on Base Sepolia network)
- Enter the ETH amount to contribute
- Click "Harvest & Burn DRB" to execute the transaction

The interface shows the split: half to debt relief, half swapped and burned as DRB.
