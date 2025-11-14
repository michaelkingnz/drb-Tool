// scripts/checkContractState.js
const hre = require("hardhat");

async function main() {
  const contractAddress = process.env.DEPLOYED_ADDRESS;

  if (!contractAddress) {
    throw new Error("Set DEPLOYED_ADDRESS in .env");
  }

  const harvester = await hre.ethers.getContractAt("DebtReliefHarvester", contractAddress);
  const treasury = await harvester.treasury();
  const drbToken = await harvester.drbToken();
  const paused = await harvester.paused();
  const router = await harvester.swapRouter();

  console.log("Contract state:");
  console.log("Treasury:", treasury);
  console.log("DRB Token:", drbToken);
  console.log("Paused:", paused);
  console.log("Swap Router:", router);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});