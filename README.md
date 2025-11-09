# Scripts Usage

- `npx hardhat run scripts/deploy.js --network baseSepolia`: Deploy the contract.
- `npx hardhat run scripts/setTreasury.js --network baseSepolia`: Set treasury address.
- `npx hardhat run scripts/setRouterAndToken.js --network baseSepolia`: Set Uniswap router and DRB token (if not set in constructor).
- `npx hardhat run scripts/getConfig.js --network baseSepolia`: Read current config from contract.
- `npx hardhat run scripts/harvest.js --network baseSepolia`: Harvest ETH to burn DRB.
- `npx hardhat run scripts/whoami.js --network baseSepolia`: Check signer address and balance.
- `npx hardhat run scripts/checkBalance.js --network baseSepolia`: Check contract balance.

Solidity + JS, deployable on Base.) It's the v1 core: Fee harvester that burns $DRB and feeds a relief pool.

# Frontend

A simple web interface is provided in `index.html` and `app.js` for users to interact with the contract.

- Open `index.html` in a web browser with MetaMask installed
- Connect your wallet (ensure you're on Base Sepolia network)
- Enter the ETH amount to contribute
- Click "Harvest & Burn DRB" to execute the transaction

The interface shows the split: half to debt relief, half swapped and burned as DRB.
