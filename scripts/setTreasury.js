// scripts/setTreasury.js
const hre = require("hardhat");

function isAddress(a) {
  return /^0x[0-9a-fA-F]{40}$/.test(a);
}

async function main() {
  const contractAddress = process.env.DEPLOYED_ADDRESS || process.argv[2];
  const treasury = process.env.TREASURY_ADDRESS || process.argv[3];

  if (!contractAddress || !isAddress(contractAddress)) {
    throw new Error("Provide deployed contract address as DEPLOYED_ADDRESS in .env or as first argument (0x...)");
  }
  if (!treasury || !isAddress(treasury)) {
    throw new Error("Provide TREASURY_ADDRESS in .env or as second argument (0x...)");
  }

  const signers = await hre.ethers.getSigners();
  if (!signers || signers.length === 0) throw new Error("No signer available. Check PRIVATE_KEY and network config.");
  const signer = signers[0];
  console.log("Using deployer:", signer.address);

  const harvester = await hre.ethers.getContractAt("DebtReliefHarvester", contractAddress, signer);
  console.log(`Setting treasury to ${treasury} on ${contractAddress}...`);
  const tx = await harvester.setTreasury(treasury);
  console.log("Transaction submitted:", tx.hash);
  const receipt = await tx.wait();
  console.log("Transaction confirmed in block", receipt.blockNumber);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err.message || err);
    process.exit(1);
  });
