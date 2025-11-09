// scripts/setSlippage.js
const hre = require("hardhat");

async function main() {
  const deployed = process.env.DEPLOYED_ADDRESS || process.argv[2];
  const percentArg = process.env.SLIPPAGE_PERCENT || process.argv[3];

  if (!deployed) throw new Error("Provide DEPLOYED_ADDRESS as env or first arg");
  if (!percentArg) throw new Error("Provide SLIPPAGE_PERCENT as env or second arg (integer percent)");

  const percent = parseInt(percentArg, 10);
  if (isNaN(percent) || percent < 0 || percent > 100) throw new Error("SLIPPAGE_PERCENT must be 0-100 integer");

  const [signer] = await hre.ethers.getSigners();
  const harvester = await hre.ethers.getContractAt("DebtReliefHarvester", deployed, signer);
  const tx = await harvester.setSlippage(percent);
  console.log("Submitted tx:", tx.hash);
  await tx.wait();
  console.log("Slippage updated to", percent);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
