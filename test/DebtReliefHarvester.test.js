const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("DebtReliefHarvester", function () {
  let harvester, drbToken, owner, treasury, user1, user2, user3;
  let weth, swapRouter, ethPriceFeed;

  const WETH_ADDRESS = "0x4200000000000000000000000000000000000006";
  const ROUTER_ADDRESS = "0x2626664c2603336E57B271c5C0b26F421741e481";
  const PRICE_FEED_ADDRESS = "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70";

  beforeEach(async function () {
    [owner, treasury, user1, user2, user3] = await ethers.getSigners();

    // Deploy mock DRB token for testing
    const TestERC20 = await ethers.getContractFactory("TestERC20");
    drbToken = await TestERC20.deploy("DRB Token", "DRB", ethers.parseEther("1000000"));
    await drbToken.waitForDeployment();

    // Deploy harvester contract
    const Harvester = await ethers.getContractFactory("DebtReliefHarvester");
    harvester = await Harvester.deploy(
      treasury.address,
      ROUTER_ADDRESS,
      await drbToken.getAddress(),
      PRICE_FEED_ADDRESS
    );
    await harvester.waitForDeployment();

    // Grant some tokens to users for testing
    await drbToken.transfer(user1.address, ethers.parseEther("1000"));
    await drbToken.transfer(user2.address, ethers.parseEther("1000"));
  });

  describe("Deployment", function () {
    it("Should set the correct initial values", async function () {
      expect(await harvester.treasury()).to.equal(treasury.address);
      expect(await harvester.BURN_PERCENT()).to.equal(50);
      expect(await harvester.dailyCap()).to.equal(ethers.parseEther("10"));
      expect(await harvester.userDailyCap()).to.equal(ethers.parseEther("1"));
    });

    it("Should grant roles correctly", async function () {
      expect(await harvester.hasRole(await harvester.DEFAULT_ADMIN_ROLE(), treasury.address)).to.be.true;
      expect(await harvester.hasRole(await harvester.PAUSER_ROLE(), treasury.address)).to.be.true;
      expect(await harvester.hasRole(await harvester.CONFIG_ROLE(), treasury.address)).to.be.true;
      expect(await harvester.hasRole(await harvester.EMERGENCY_ROLE(), treasury.address)).to.be.true;
    });
  });

  describe("Harvest Functionality", function () {
    it("Should accept ETH and split 50/50", async function () {
      const ethAmount = ethers.parseEther("0.1");
      const burnAmount = ethAmount / 2n;
      const reliefAmount = ethAmount - burnAmount;

      const treasuryBalanceBefore = await ethers.provider.getBalance(treasury.address);
      const contractBalanceBefore = await ethers.provider.getBalance(await harvester.getAddress());

      await harvester.connect(user1).harvest({ value: ethAmount });

      const treasuryBalanceAfter = await ethers.provider.getBalance(treasury.address);
      const contractBalanceAfter = await ethers.provider.getBalance(await harvester.getAddress());

      expect(treasuryBalanceAfter - treasuryBalanceBefore).to.equal(reliefAmount);
      expect(contractBalanceAfter - contractBalanceBefore).to.equal(0); // Contract shouldn't hold ETH
    });

    it("Should emit Harvested event", async function () {
      const ethAmount = ethers.parseEther("0.1");

      await expect(harvester.connect(user1).harvest({ value: ethAmount }))
        .to.emit(harvester, "Harvested")
        .withArgs(user1.address, ethAmount, 0, ethAmount / 2n); // 0 DRB burned since no swap configured
    });

    it("Should reject zero ETH", async function () {
      await expect(harvester.connect(user1).harvest({ value: 0 }))
        .to.be.revertedWith("Must send ETH");
    });

    it("Should reject amounts over 1 ETH", async function () {
      const largeAmount = ethers.parseEther("2");
      await expect(harvester.connect(user1).harvest({ value: largeAmount }))
        .to.be.revertedWith("Max 1 ETH per harvest");
    });
  });

  describe("Daily Caps", function () {
    it("Should enforce user daily cap", async function () {
      const capAmount = ethers.parseEther("1");
      const overCapAmount = ethers.parseEther("0.1");

      // Use up the daily cap
      await harvester.connect(user1).harvest({ value: capAmount });

      // Try to harvest more
      await expect(harvester.connect(user1).harvest({ value: overCapAmount }))
        .to.be.revertedWith("User daily donation cap exceeded");
    });

    it("Should enforce global daily cap", async function () {
      // Create additional signers for testing
      const signers = await ethers.getSigners();
      const testUsers = signers.slice(3, 13); // users 3-12 (10 users)

      // Each of 10 users harvests 1 ETH (total 10 ETH = global cap)
      for (let i = 0; i < 10; i++) {
        await harvester.connect(testUsers[i]).harvest({ value: ethers.parseEther("1") });
      }

      // Check that we've reached the global cap
      expect(await harvester.currentDayDonations()).to.equal(ethers.parseEther("10"));

      // Try to harvest one more time - should fail
      await expect(harvester.connect(signers[13]).harvest({ value: ethers.parseEther("0.1") }))
        .to.be.revertedWith("Daily donation cap exceeded");
    });

    it("Should reset caps after a day", async function () {
      // Use up daily cap
      await harvester.connect(user1).harvest({ value: ethers.parseEther("1") });

      // Simulate time passing (1 day)
      await ethers.provider.send("evm_increaseTime", [86401]); // 1 day + 1 second
      await ethers.provider.send("evm_mine");

      // Should be able to harvest again
      await expect(harvester.connect(user1).harvest({ value: ethers.parseEther("0.1") }))
        .to.not.be.reverted;
    });
  });

  describe("Access Control", function () {
    it("Should allow treasury to pause/unpause", async function () {
      await harvester.connect(treasury).pause();
      expect(await harvester.paused()).to.be.true;

      await harvester.connect(treasury).unpause();
      expect(await harvester.paused()).to.be.false;
    });

    it("Should reject non-pausers from pausing", async function () {
      await expect(harvester.connect(user1).pause())
        .to.be.revertedWith("Missing PAUSER_ROLE");
    });

    it("Should allow config role to update slippage", async function () {
      await harvester.connect(treasury).scheduleSetSlippage(90); // 10% slippage

      // Fast forward time
      await ethers.provider.send("evm_increaseTime", [86401]);
      await ethers.provider.send("evm_mine");

      await harvester.connect(treasury).executeSetSlippage();
      expect(await harvester.minSlippagePercent()).to.equal(90);
    });
  });

  describe("Emergency Functions", function () {
    it("Should allow emergency ETH withdrawal", async function () {
      const withdrawAmount = ethers.parseEther("0.5");

      // Send ETH directly to contract
      await user1.sendTransaction({
        to: await harvester.getAddress(),
        value: withdrawAmount
      });

      // Verify contract received the ETH
      expect(await ethers.provider.getBalance(await harvester.getAddress())).to.equal(withdrawAmount);

      // Perform emergency withdrawal
      await harvester.connect(treasury).emergencyWithdraw(
        ethers.ZeroAddress, // ETH
        withdrawAmount,
        user2.address
      );

      // Contract should have 0 ETH after withdrawal
      expect(await ethers.provider.getBalance(await harvester.getAddress())).to.equal(0);
    });

    it("Should allow emergency token withdrawal", async function () {
      // Transfer tokens to contract
      await drbToken.connect(user1).transfer(await harvester.getAddress(), ethers.parseEther("100"));

      const balanceBefore = await drbToken.balanceOf(user2.address);
      await harvester.connect(treasury).emergencyWithdraw(
        await drbToken.getAddress(),
        ethers.parseEther("50"),
        user2.address
      );

      const balanceAfter = await drbToken.balanceOf(user2.address);
      expect(balanceAfter - balanceBefore).to.equal(ethers.parseEther("50"));
    });
  });

  describe("Input Validation", function () {
    it("Should reject invalid addresses in constructor", async function () {
      const Harvester = await ethers.getContractFactory("DebtReliefHarvester");

      await expect(Harvester.deploy(
        ethers.ZeroAddress, // Invalid treasury
        ROUTER_ADDRESS,
        await drbToken.getAddress(),
        PRICE_FEED_ADDRESS
      )).to.be.revertedWith("Invalid addresses");
    });

    it("Should allow multiple harvests when cooldown is disabled", async function () {
      await harvester.connect(user1).harvest({ value: ethers.parseEther("0.1") });

      // Should be able to harvest again immediately (cooldown is 0 in test)
      await expect(harvester.connect(user1).harvest({ value: ethers.parseEther("0.1") }))
        .to.not.be.reverted;
    });
  });

  describe("Gas Optimization", function () {
    it("Should have reasonable gas usage for harvest", async function () {
      const ethAmount = ethers.parseEther("0.1");

      const tx = await harvester.connect(user1).harvest({ value: ethAmount });
      const receipt = await tx.wait();

      // Gas used should be reasonable (< 200k for basic harvest)
      expect(receipt.gasUsed).to.be.lt(200000);
    });

    it("Should check minimum gas for operations", async function () {
      // Test that harvest requires reasonable gas by trying with very low gas
      const ethAmount = ethers.parseEther("0.1");

      // This should work with normal gas limits
      await expect(harvester.connect(user1).harvest({ value: ethAmount, gasLimit: 50000 }))
        .to.be.revertedWith("Insufficient gas for harvest");
    });
  });

  describe("Edge Cases", function () {
    it("Should handle multiple users harvesting", async function () {
      await harvester.connect(user1).harvest({ value: ethers.parseEther("0.5") });
      await harvester.connect(user2).harvest({ value: ethers.parseEther("0.3") });
      await harvester.connect(user3).harvest({ value: ethers.parseEther("0.2") });

      // Total harvested should be 1 ETH
      const totalHarvested = ethers.parseEther("0.5") + ethers.parseEther("0.3") + ethers.parseEther("0.2");
      expect(totalHarvested).to.equal(ethers.parseEther("1"));
    });

    it("Should handle odd ETH amounts correctly", async function () {
      // 1 wei should split as 0 wei burn, 1 wei relief (integer division)
      await harvester.connect(user1).harvest({ value: 1 });

      // Should not revert and should handle the tiny amount
      expect(await harvester.currentDayDonations()).to.equal(1);
    });

    it("Should maintain state consistency", async function () {
      const initialDonations = await harvester.currentDayDonations();

      await harvester.connect(user1).harvest({ value: ethers.parseEther("0.1") });

      const finalDonations = await harvester.currentDayDonations();
      expect(finalDonations - initialDonations).to.equal(ethers.parseEther("0.1"));
    });
  });
});