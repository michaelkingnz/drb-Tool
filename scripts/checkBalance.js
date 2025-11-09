// scripts/checkBalance.js
const hre = require("hardhat");

async function main() {
  const address = process.env.DEPLOYED_ADDRESS || process.env.TREASURY_ADDRESS || process.argv[2];
  if (!address) throw new Error("Provide address as DEPLOYED_ADDRESS, TREASURY_ADDRESS env, or first arg");

  const balance = await hre.ethers.provider.getBalance(address);
  const fmt = hre.ethers.formatEther ? hre.ethers.formatEther(balance) : hre.ethers.utils.formatEther(balance);
  console.log(`Balance of ${address}: ${fmt} ETH`);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});