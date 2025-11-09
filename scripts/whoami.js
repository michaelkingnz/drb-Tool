// scripts/whoami.js
const hre = require("hardhat");

async function main() {
  const signers = await hre.ethers.getSigners();
  if (!signers || signers.length === 0) {
    console.log("No signers available");
    return;
  }
  const s = signers[0];
  const address = s.address ? s.address : await s.getAddress();
  const balance = await hre.ethers.provider.getBalance(address);
  const fmt = hre.ethers.formatEther ? hre.ethers.formatEther(balance) : hre.ethers.utils.formatEther(balance);
  console.log("Signer:", address);
  console.log("Balance (ETH):", fmt.toString());
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
