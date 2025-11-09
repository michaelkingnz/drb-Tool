// scripts/getConfig.js
const hre = require("hardhat");

function isAddress(a) {
  return /^0x[0-9a-fA-F]{40}$/.test(a);
}

async function main() {
  const deployed = process.env.DEPLOYED_ADDRESS || process.argv[2];
  if (!deployed || !isAddress(deployed)) throw new Error("Provide DEPLOYED_ADDRESS as env or first arg");

  const [signer] = await hre.ethers.getSigners();
  const harvester = await hre.ethers.getContractAt("DebtReliefHarvester", deployed, signer);

  let router = "<error>";
  let token = "<error>";
  let slippage = "<error>";
  let treasury = "<error>";

  try {
    router = await harvester.swapRouter();
  } catch (e) {
    console.error("Failed reading swapRouter:", e.message || e);
  }

  try {
    token = await harvester.drbToken();
  } catch (e) {
    console.error("Failed reading drbToken:", e.message || e);
  }

  try {
    slippage = await harvester.minSlippagePercent();
  } catch (e) {
    console.error("Failed reading minSlippagePercent:", e.message || e);
  }

  try {
    treasury = await harvester.treasury();
  } catch (e) {
    console.error("Failed reading treasury:", e.message || e);
  }

  console.log({ deployed, router, token, slippage: String(slippage), treasury });
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
