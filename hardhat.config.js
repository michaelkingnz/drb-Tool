require("dotenv").config({ override: true });
require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
// Only include PRIVATE_KEY if it looks like a valid 32-byte hex string (0x + 64 hex chars)
const privateKey = process.env.PRIVATE_KEY && /^0x[0-9a-fA-F]{64}$/.test(process.env.PRIVATE_KEY)
  ? process.env.PRIVATE_KEY
  : undefined;

module.exports = {
  solidity: "0.8.20",
  networks: {
    baseSepolia: {
      url: process.env.BASE_SEPOLIA_RPC_URL || "https://sepolia.base.org",
      accounts: privateKey ? [privateKey] : [],
      chainId: 84532
    },
    mainnet: {
      url: process.env.MAINNET_RPC_URL || "https://eth.llamarpc.com",
      accounts: privateKey ? [privateKey] : [],
      chainId: 1
    }
  }
  ,
  etherscan: {
    // Add API keys for scanning (set ETHERSCAN_API_KEY and BASESCAN_API_KEY in your .env)
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || "",
      baseSepolia: process.env.BASESCAN_API_KEY || ""
    },
    customChains: [
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org"
        }
      }
    ]
  }
};
