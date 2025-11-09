// scripts/getTreasury.js
const hre = require("hardhat");

function isAddress(a) {
  return /^0x[0-9a-fA-F]{40}$/.test(a);
}

async function main() {
  const deployed = process.env.DEPLOYED_ADDRESS || process.argv[2];
  if (!deployed || !isAddress(deployed)) throw new Error("Provide DEPLOYED_ADDRESS as env or first arg");

  const [signer] = await hre.ethers.getSigners();
  const harvester = await hre.ethers.getContractAt("DebtReliefHarvester", deployed, signer);
  const treasury = await harvester.treasury();
  console.log("Treasury:", treasury);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
