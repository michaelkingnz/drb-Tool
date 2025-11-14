// scripts/deployTestToken.js
const hre = require("hardhat");

async function main() {
  console.log("Deploying test DRB token...");

  const TestToken = await hre.ethers.getContractFactory("TestERC20");
  const token = await TestToken.deploy("Test DRB", "TDRB", hre.ethers.parseEther("1000000"));

  await token.waitForDeployment();
  const address = await token.getAddress();

  console.log(`Test DRB token deployed to: ${address}`);
  console.log(`Token symbol: TDRB`);
  console.log(`Initial supply: 1,000,000 TDRB`);

  // Update .env file with new token address
  console.log(`\nAdd this to your .env file:`);
  console.log(`DRB_TOKEN=${address}`);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});