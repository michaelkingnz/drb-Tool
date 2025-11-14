// scripts/checkTokenBalance.js
const hre = require("hardhat");

async function main() {
  const tokenAddress = process.env.DRB_TOKEN || process.argv[2];
  const holderAddress = process.env.TREASURY_ADDRESS || process.argv[3];

  if (!tokenAddress || !holderAddress) {
    throw new Error("Provide DRB_TOKEN and TREASURY_ADDRESS as env vars or args");
  }

  // Check if token contract exists
  const code = await hre.ethers.provider.getCode(tokenAddress);
  if (code === '0x') {
    throw new Error(`No contract found at ${tokenAddress}`);
  }

  console.log(`Token contract exists at: ${tokenAddress}`);

  // Get token balance
  const tokenContract = await hre.ethers.getContractAt("TestERC20", tokenAddress);
  const balance = await tokenContract.balanceOf(holderAddress);
  const symbol = await tokenContract.symbol();

  const fmt = hre.ethers.formatEther ? hre.ethers.formatEther(balance) : hre.ethers.utils.formatEther(balance);
  console.log(`Treasury ${symbol} balance: ${fmt} (${balance.toString()} wei)`);
  console.log(`Token decimals: 18 (assumed for test token)`);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});