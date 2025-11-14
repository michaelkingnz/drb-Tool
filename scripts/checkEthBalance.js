// scripts/checkEthBalance.js
const hre = require("hardhat");

async function main() {
  const address = process.env.TREASURY_ADDRESS;

  if (!address) {
    throw new Error("Set TREASURY_ADDRESS in .env");
  }

  const balance = await hre.ethers.provider.getBalance(address);
  const fmt = hre.ethers.formatEther ? hre.ethers.formatEther(balance) : hre.ethers.utils.formatEther(balance);
  console.log(`Treasury ETH balance: ${fmt} ETH (${balance.toString()} wei)`);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});