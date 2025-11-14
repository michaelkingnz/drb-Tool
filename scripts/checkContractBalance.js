// scripts/checkContractBalance.js
const hre = require("hardhat");

async function main() {
  const tokenAddress = process.env.DRB_TOKEN;
  const contractAddress = process.env.DEPLOYED_ADDRESS;

  if (!tokenAddress || !contractAddress) {
    throw new Error("Set DRB_TOKEN and DEPLOYED_ADDRESS in .env");
  }

  const tokenContract = await hre.ethers.getContractAt("TestERC20", tokenAddress);
  const balance = await tokenContract.balanceOf(contractAddress);
  const symbol = await tokenContract.symbol();

  const fmt = hre.ethers.formatEther ? hre.ethers.formatEther(balance) : hre.ethers.utils.formatEther(balance);
  console.log(`Contract ${symbol} balance: ${fmt} (${balance.toString()} wei)`);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});