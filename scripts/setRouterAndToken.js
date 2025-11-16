// scripts/setRouterAndToken.js
const hre = require("hardhat");

function isAddress(a) {
  return /^0x[0-9a-fA-F]{40}$/.test(a);
}

async function main() {
  const deployed = process.env.DEPLOYED_ADDRESS || process.argv[2];
  const router = process.env.ROUTER_ADDRESS || process.argv[3];
  const token = process.env.DRB_TOKEN || process.argv[4];

  if (!deployed || !isAddress(deployed)) throw new Error("Provide DEPLOYED_ADDRESS as env or first arg");
  if (!router || !isAddress(router)) throw new Error("Provide ROUTER_ADDRESS as env or second arg");
  if (!token || !isAddress(token)) throw new Error("Provide DRB_TOKEN as env or third arg");

  const [signer] = await hre.ethers.getSigners();
  console.log("Using signer:", signer.address);

  const harvester = await hre.ethers.getContractAt("DebtReliefHarvester", deployed, signer);
  
  // Schedule the change
  console.log("Scheduling router and token change...");
  const scheduleTx = await harvester.scheduleSetRouterAndToken(router, token);
  console.log("Schedule tx:", scheduleTx.hash);
  await scheduleTx.wait();
  
  console.log("Router and token change scheduled!");
  console.log("Note: In production, wait 1 day then call executeSetRouterAndToken()");
  console.log("For testing, you can execute immediately on local network");
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
