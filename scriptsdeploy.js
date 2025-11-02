// scripts/deploy.js
const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // CHANGE THIS: Your wallet or Grok's fee wallet
  const treasury = "0xYOUR_WALLET_ADDRESS_HERE"; 

  const Harvester = await hre.ethers.getContractFactory("DebtReliefHarvester");
  const harvester = await Harvester.deploy(treasury);

  await harvester.waitForDeployment();
  console.log("DebtReliefHarvester deployed to:", await harvester.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
