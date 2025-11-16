// scripts/deploy.js
const hre = require("hardhat");

async function main() {
  // Validate required environment variables for network deployments
  const network = hre.network.name;
  if (network === "baseSepolia") {
    if (!process.env.BASE_SEPOLIA_RPC_URL) {
      throw new Error("BASE_SEPOLIA_RPC_URL is not set. Set it before running deploy.");
    }
    if (!process.env.PRIVATE_KEY || !/^0x[0-9a-fA-F]{64}$/.test(process.env.PRIVATE_KEY)) {
      throw new Error("PRIVATE_KEY is missing or invalid. Use a 0x-prefixed 64-hex-char private key.");
    }
  }

  const signers = await hre.ethers.getSigners();
  if (!signers || signers.length === 0) {
    throw new Error("No signer available. Check your network configuration and PRIVATE_KEY.");
  }

  const [deployer] = signers;
  console.log("Deploying with account:", deployer.address);

  // Your wallet or fee wallet
  const treasury = process.env.TREASURY_ADDRESS || "0xYOUR_WALLET_ADDRESS_HERE";
  const weth = "0x4200000000000000000000000000000000000006"; // Base WETH

  const Harvester = await hre.ethers.getContractFactory("DebtReliefHarvester");
  const harvester = await Harvester.deploy(treasury, process.env.ROUTER_ADDRESS || "0x2626664c2603336E57B271c5C0b26F421741e481", process.env.DRB_TOKEN || "0xd7f5d9d299a18a17e5cc6f7ff44e1f5a0165349c", process.env.ETH_PRICE_FEED || "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70");

  await harvester.waitForDeployment();
  console.log("DebtReliefHarvester deployed to:", await harvester.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error.message || error);
    process.exit(1);
  });
