// scripts/harvest.js
const hre = require("hardhat");
const { ethers } = hre;

function isAddress(a) {
  return /^0x[0-9a-fA-F]{40}$/.test(a);
}

async function main() {
  const contractAddress = process.env.DEPLOYED_ADDRESS || process.argv[2];
  const amountArg = process.env.HARVEST_AMOUNT || process.argv[3] || "0.01"; // in ETH

  if (!contractAddress || !isAddress(contractAddress)) {
    throw new Error("Provide deployed contract address as DEPLOYED_ADDRESS in .env or as first argument (0x...)");
  }

  // parse amount
  let value;
  console.log('raw amountArg:', amountArg);
  try {
    // ethers v6 exposes parseEther at the top level; use whichever exists
    if (ethers.parseEther) {
      value = ethers.parseEther(amountArg.toString());
    } else {
      value = ethers.utils.parseEther(amountArg.toString());
    }
  } catch (e) {
    throw new Error("Invalid amount provided for harvest (ETH)");
  }

  const signers = await hre.ethers.getSigners();
  if (!signers || signers.length === 0) throw new Error("No signer available. Check PRIVATE_KEY and network config.");
  const signer = signers[0];
  console.log("Using signer:", signer.address);

  const harvester = await hre.ethers.getContractAt("DebtReliefHarvester", contractAddress, signer);
  const fmt = ethers.formatEther ? ethers.formatEther(value) : ethers.utils.formatEther(value);
  console.log(`Calling harvest() with value ${fmt} ETH on ${contractAddress}...`);
  const tx = await harvester.harvest({ value });
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
