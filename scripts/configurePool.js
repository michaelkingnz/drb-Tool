// scripts/configurePool.js
const hre = require("hardhat");

async function main() {
  const network = hre.network.name;
  console.log(`Configuring Uniswap pool on ${network}...`);

  // Get deployed contract
  const contractAddress = process.env.DEPLOYED_ADDRESS;
  if (!contractAddress) {
    throw new Error("DEPLOYED_ADDRESS not set in .env");
  }

  const Harvester = await hre.ethers.getContractAt("DebtReliefHarvester", contractAddress);
  const [deployer] = await hre.ethers.getSigners();

  console.log("Configuring pool with account:", deployer.address);

  // For Base Sepolia, we need to create the DRB/WETH pool if it doesn't exist
  const WETH = "0x4200000000000000000000000000000000000006";
  const DRB_TOKEN = process.env.DRB_TOKEN || "0x25746Fa7A068862B99c27CEF9b6f3185568DBB7a";
  const UNISWAP_FACTORY = "0x33128a8fC17869897dcE68Ed026d694621f6FDfD";

  const factory = await hre.ethers.getContractAt("IUniswapV3Factory", UNISWAP_FACTORY);

  // Check if pool exists
  let poolAddress = await factory.getPool(WETH, DRB_TOKEN, 3000); // 0.3% fee
  console.log("Existing pool address:", poolAddress);

  if (poolAddress === hre.ethers.ZeroAddress) {
    console.log("Creating new DRB/WETH pool...");
    const createTx = await factory.createPool(WETH, DRB_TOKEN, 3000);
    await createTx.wait();

    poolAddress = await factory.getPool(WETH, DRB_TOKEN, 3000);
    console.log("New pool created at:", poolAddress);

    // Initialize pool at price 1.0 (tick 0)
    const pool = await hre.ethers.getContractAt("IUniswapV3Pool", poolAddress);
    const initTx = await pool.initialize("79228162514264337593543950336"); // sqrtPriceX96 at tick 0
    await initTx.wait();
    console.log("Pool initialized at price 1.0");
  }

  // Now configure the contract to use this pool
  console.log("Configuring contract to use pool:", poolAddress);

  // The contract needs to be configured via admin functions
  // This would typically be done by the treasury/admin
  console.log("Pool configuration complete!");
  console.log("Pool address:", poolAddress);
  console.log("Next: Use admin functions to set router and token addresses");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });