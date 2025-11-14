// scripts/fundContract.js
const hre = require("hardhat");

async function main() {
  const tokenAddress = process.env.DRB_TOKEN;
  const contractAddress = process.env.DEPLOYED_ADDRESS;

  if (!tokenAddress || !contractAddress) {
    throw new Error("Set DRB_TOKEN and DEPLOYED_ADDRESS in .env");
  }

  const [signer] = await hre.ethers.getSigners();
  console.log("Using signer:", signer.address);

  // Get token contract
  const token = await hre.ethers.getContractAt("TestERC20", tokenAddress, signer);

  // Transfer 69 tokens to contract for testing
  const amount = hre.ethers.parseEther ? hre.ethers.parseEther("69") : hre.ethers.utils.parseEther("69");

  console.log(`Transferring 69 TDRB tokens to contract ${contractAddress}...`);
  const tx = await token.transfer(contractAddress, amount);
  await tx.wait();

  console.log("Tokens transferred successfully!");
  console.log(`Tx hash: ${tx.hash}`);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});