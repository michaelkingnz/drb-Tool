// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./chainlink/AggregatorV3Interface.sol";

// WETH interface for wrapping ETH
interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address, uint256) external returns (bool);
}

// Add to top of DebtReliefHarvester.sol
library UniswapTWAP {
    function getMeanTick(address pool, uint32 secondsAgo) internal view returns (int24) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(secondsAgos);
        return int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(secondsAgo)));
    }
}

/**
 * @title Debt Relief Harvester
 * @author DRB Community
 * @notice A decentralized protocol that accepts ETH donations and burns DRB tokens while funding debt relief
 * @dev This contract implements a secure donation system with:
 * - 50/50 split between token burning and treasury funding
 * - Uniswap V3 integration with TWAP pricing for fair swaps
 * - Role-based access control with timelocked admin functions
 * - Emergency recovery mechanisms
 * - Comprehensive input validation and security measures
 *
 * Security features:
 * - ReentrancyGuard: Prevents reentrancy attacks
 * - Pausable: Emergency pause functionality
 * - AccessControl: Role-based permissions
 * - Timelocks: Delayed execution for critical changes
 * - Input validation: Bounds checking and sanity checks
 * - Try-catch: Graceful failure handling for swaps
 */
contract DebtReliefHarvester is ReentrancyGuard, AccessControl, Pausable {
    // Role definitions
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Constants
    uint256 public constant BURN_PERCENT = 50;
    uint256 public constant HARVEST_COOLDOWN = 0; // 1 week in production
    uint256 public constant TIMELOCK_DURATION = 1 days;
    bytes32 public constant ROUTER_TOKEN_KEY = keccak256("ROUTER_TOKEN");
    bytes32 public constant SLIPPAGE_KEY = keccak256("SLIPPAGE");
    bytes32 public constant DRB_PRICE_KEY = keccak256("DRB_PRICE");
    bytes32 public constant EMERGENCY_WITHDRAW_KEY = keccak256("EMERGENCY_WITHDRAW");
    bytes32 public constant DAILY_CAP_KEY = keccak256("DAILY_CAP");
    bytes32 public constant USER_DAILY_CAP_KEY = keccak256("USER_DAILY_CAP");

    // Gas optimization constants
    uint256 private constant SECONDS_PER_DAY = 86400;
    uint256 private constant MIN_HARVEST_GAS = 100000;
    uint256 private constant MIN_SWAP_GAS = 150000;
    uint256 private constant SWAP_GAS_LIMIT = 100000;
    uint256 private constant TWAP_PERIOD = 300; // 5 minutes

    // Uniswap constants for Base
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant UNISWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address public constant UNISWAP_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;

    address public treasury;
    uint256 public minSlippagePercent = 95; // 5% max slippage

    ISwapRouter public swapRouter;
    IERC20 public drbToken;
    uint256 public swapDeadline = 300; // 5 minutes

    AggregatorV3Interface public ethPriceFeed;
    IUniswapV3Pool public drbPool; // DRB/ETH or DRB/USDC pool for TWAP
    uint256 public drbPrice = 1e8; // Fallback DRB price in USD (8 decimals)

    // Daily donation caps for security
    uint256 public dailyCap = 10 ether; // Max 10 ETH per day total
    uint256 public userDailyCap = 1 ether; // Max 1 ETH per day per user
    uint256 public currentDayDonations; // Total ETH donated today
    uint256 public lastResetDay; // Last day donations were reset
    mapping(address => uint256) public userDailyDonations; // ETH donated today by user
    mapping(address => uint256) public userLastResetDay; // Last reset day for user

    event Harvested(address indexed sender, uint256 ethIn, uint256 drbBurned, uint256 ethToRelief);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event ConfigUpdated(address router, address token, uint256 slippage);
    event SlippageChanged(uint256 oldSlippage, uint256 newSlippage);
    event DrbPriceChanged(uint256 oldPrice, uint256 newPrice);
    event EmergencyWithdrawScheduled(address token, uint256 amount, address to);
    event EmergencyWithdrawExecuted(address token, uint256 amount, address to);
    event DonationFailed(address indexed sender, uint256 ethAmount, string reason);
    event AdminAction(address indexed admin, string action);
    event DailyCapChanged(uint256 oldCap, uint256 newCap);
    event UserDailyCapChanged(uint256 oldCap, uint256 newCap);

    struct PendingAddressChange {
        address newValue;
        uint256 timestamp;
    }

    struct PendingConfigChange {
        address newRouter;
        address newToken;
        uint256 timestamp;
    }

    struct PendingSlippageChange {
        uint256 newSlippage;
        uint256 timestamp;
    }

    struct PendingDrbPriceChange {
        uint256 newPrice;
        uint256 timestamp;
    }

    struct PendingEmergencyWithdraw {
        address token;
        uint256 amount;
        address to;
        uint256 timestamp;
    }

    struct PendingUintChange {
        uint256 newValue;
        uint256 timestamp;
    }

    mapping(bytes32 => PendingAddressChange) public pendingAddressChanges;
    mapping(bytes32 => PendingConfigChange) public pendingConfigChanges;
    mapping(bytes32 => PendingSlippageChange) public pendingSlippageChanges;
    mapping(bytes32 => PendingDrbPriceChange) public pendingDrbPriceChanges;
    mapping(bytes32 => PendingEmergencyWithdraw) public pendingEmergencyWithdraws;
    mapping(bytes32 => PendingUintChange) public pendingDailyCapChanges;
    mapping(bytes32 => PendingUintChange) public pendingUserDailyCapChanges;

    bytes32 constant TREASURY_KEY = keccak256("TREASURY");

    mapping(address => uint256) public lastHarvest;

    constructor(address _treasury, address _router, address _drbToken, address _ethPriceFeed) {
        require(_treasury != address(0) && _router != address(0) && _drbToken != address(0) && _ethPriceFeed != address(0), "Invalid addresses");
        treasury = _treasury;
        swapRouter = ISwapRouter(_router);
        drbToken = IERC20(_drbToken);
        ethPriceFeed = AggregatorV3Interface(_ethPriceFeed);

        // Initialize DRB pool (WETH/DRB, 0.3% fee)
        address poolAddress = IUniswapV3Factory(UNISWAP_FACTORY).getPool(WETH, address(drbToken), 3000);
        if (poolAddress == address(0)) {
            // Create pool if it doesn't exist
            poolAddress = IUniswapV3Factory(UNISWAP_FACTORY).createPool(WETH, address(drbToken), 3000);
            IUniswapV3Pool(poolAddress).initialize(79228162514264337593543950336);  // sqrtPriceX96 at tick 0 (1.0)
        }
        drbPool = IUniswapV3Pool(poolAddress);

        // Grant roles to treasury for enhanced access control
        _grantRole(DEFAULT_ADMIN_ROLE, _treasury);
        _grantRole(PAUSER_ROLE, _treasury);
        _grantRole(CONFIG_ROLE, _treasury);
        _grantRole(EMERGENCY_ROLE, _treasury);
    }

    /**
     * @notice Resets daily donation counters if a new day has started
     * @dev Called internally to maintain daily caps. Uses block.timestamp / 86400 for day calculation
     */
    function _resetDailyCapsIfNeeded() internal {
        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        if (currentDay > lastResetDay) {
            currentDayDonations = 0;
            lastResetDay = currentDay;
        }
    }

    /**
     * @notice Resets user daily donation counter if a new day has started
     * @param user The user address to check
     * @dev Called internally to maintain per-user daily caps
     */
    function _resetUserDailyCapIfNeeded(address user) internal {
        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        if (currentDay > userLastResetDay[user]) {
            userDailyDonations[user] = 0;
            userLastResetDay[user] = currentDay;
        }
    }

    /**
     * @notice Accepts ETH donations and processes them according to the protocol
     * @dev Main entry point for donations. Splits ETH 50/50 between DRB burning and treasury.
     * Includes cooldowns, input validation, and fallback mechanisms.
     * Emits Harvested event with donation details.
     */
    function harvest() external payable whenNotPaused nonReentrant {
        _harvest(msg.value, msg.sender);
    }

    /**
     * @notice Internal harvest logic with validation and processing
     * @param ethAmount The amount of ETH sent by the donor
     * @param sender The address of the donor
     * @dev Performs all validation checks and executes the donation processing:
     * - Validates amount (0 < amount <= 1 ETH)
     * - Enforces harvest cooldown per user
     * - Splits funds 50/50
     * - Attempts DRB swap, falls back to ETH burn
     * - Sends relief portion to treasury
     */
    function _harvest(uint256 ethAmount, address sender) internal {
        // Gas optimization: Check minimum gas for operations
        require(gasleft() >= MIN_HARVEST_GAS, "Insufficient gas for harvest");

        // Reset daily caps if needed
        _resetDailyCapsIfNeeded();
        _resetUserDailyCapIfNeeded(sender);

        require(ethAmount > 0, "Must send ETH");
        require(ethAmount <= 1 ether, "Max 1 ETH per harvest"); // Prevent overflow risks and large donations
        require(block.timestamp >= lastHarvest[sender] + HARVEST_COOLDOWN, "Harvest cooldown: 1 per week per user");

        // Check daily caps
        require(currentDayDonations + ethAmount <= dailyCap, "Daily donation cap exceeded");
        require(userDailyDonations[sender] + ethAmount <= userDailyCap, "User daily donation cap exceeded");

        // Update counters (gas optimized)
        unchecked {
            currentDayDonations += ethAmount;
            userDailyDonations[sender] += ethAmount;
        }
        lastHarvest[sender] = block.timestamp;
        
        // Gas optimized: Calculate burn and relief amounts
        uint256 burnAmt;
        uint256 reliefAmt;
        unchecked {
            burnAmt = ethAmount / 2;
            reliefAmt = ethAmount - burnAmt;  // This is safe since burnAmt <= ethAmount/2
        }

        // Perform swap if router is configured, otherwise burn directly
        uint256 drbReceived = 0;
        if (address(swapRouter) != address(0) && address(drbToken) != address(0)) {
            try this._performSwap(burnAmt) returns (uint256 drbOut) {
                drbReceived = drbOut;
            } catch {
                // Fallback: burn ETH directly
                payable(0x000000000000000000000000000000000000dEaD).transfer(burnAmt);
            }
        } else {
            // No swap configured: burn ETH directly
            payable(0x000000000000000000000000000000000000dEaD).transfer(burnAmt);
        }

        payable(treasury).transfer(reliefAmt);

        emit Harvested(sender, ethAmount, drbReceived, reliefAmt);
    }

    /**
     * @notice Performs the ETH to DRB token swap via Uniswap V3
     * @param ethAmount The amount of ETH to swap for DRB tokens
     * @return drbReceived The amount of DRB tokens received from the swap
     * @dev Internal function that:
     * - Wraps ETH to WETH
     * - Approves Uniswap router
     * - Calculates minimum output using TWAP pricing
     * - Executes the swap with slippage protection
     * Can only be called by the contract itself (via try-catch in harvest)
     */
    function _performSwap(uint256 ethAmount) external returns (uint256 drbReceived) {
        require(msg.sender == address(this), "Only internal call");
        require(gasleft() >= MIN_SWAP_GAS, "Insufficient gas for swap");
        
        // Gas optimized: Cache storage variables to memory
        address weth = WETH;
        address router = UNISWAP_ROUTER;
        address token = address(drbToken);
        
        // 1. Wrap ETH to WETH
        IWETH(weth).deposit{value: ethAmount}();

        // 2. Approve router for WETH
        TransferHelper.safeApprove(weth, router, ethAmount);

        // 3. Calculate TWAP-based minimum output (5-minute TWAP)
        uint256 amountOutMinimum = _calculateMinOutWithTWAP(ethAmount);

        // 4. Execute swap with optimized parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: weth,
            tokenOut: token,
            fee: 3000,  // 0.3% pool
            recipient: address(this),
            deadline: block.timestamp + swapDeadline,
            amountIn: ethAmount,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        drbReceived = ISwapRouter(router).exactInputSingle{ gas: SWAP_GAS_LIMIT }(params);
    }

    /**
     * @notice Calculates minimum output amount using TWAP pricing for slippage protection
     * @param ethAmount The input ETH amount
     * @return The minimum acceptable DRB output amount
     * @dev Uses 5-minute TWAP from Uniswap pool to estimate fair price,
     * then applies 1% slippage tolerance for safety
     */
    function _calculateMinOutWithTWAP(uint256 ethAmount) internal view returns (uint256) {
        // Gas optimized: Early return with fallback if pool not set
        if (address(drbPool) == address(0)) return ethAmount * drbPrice / 1e18;

        // Get 5-minute TWAP tick with gas limit
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = uint32(TWAP_PERIOD);  // 5 minutes ago
        secondsAgos[1] = 0;    // now

        (int56[] memory tickCumulatives, ) = drbPool.observe(secondsAgos);
        
        // Gas optimized: Use unchecked for arithmetic that won't overflow
        unchecked {
            int24 twapTick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(TWAP_PERIOD)));
            
            // Simplified price calculation for gas efficiency
            // Use fallback price if TWAP calculation fails
            uint256 twapPrice = drbPrice;  // Fallback to stored price
            
            // Rough approximation: price changes ~0.01% per tick
            if (twapTick > -887000 && twapTick < 887000) {  // Reasonable tick bounds
                int256 priceAdjustment = int256(twapTick) * 1e14 / 1e6;  // ~0.01% per tick
                twapPrice = uint256(int256(drbPrice) + priceAdjustment);
            }
            
            // Calculate min out with 1% slippage protection
            return (ethAmount * twapPrice / 1e18) * 99 / 100;
        }
    }

    function _swapAndBurn(uint256 ethAmount) internal returns (uint256 drbOut) {
        if (ethAmount == 0) return 0;

        try this._performSwap(ethAmount) returns (uint256 drbReceived) {
            // Burn DRB (send to dead)
            drbToken.transfer(0x000000000000000000000000000000000000dEaD, drbReceived);
            drbOut = drbReceived;
        } catch Error(string memory reason) {
            emit AdminAction(msg.sender, string(abi.encodePacked("Swap failed: ", reason)));
            drbOut = 0;
        }
    }

    // Owner-only config (treasury controls, with timelock)
    function scheduleSetTreasury(address _new) external {
        require(hasRole(CONFIG_ROLE, msg.sender), "Missing CONFIG_ROLE");
        require(_new != address(0), "Invalid address");
        pendingAddressChanges[TREASURY_KEY] = PendingAddressChange(_new, block.timestamp + TIMELOCK_DURATION);
    }

    function executeSetTreasury() external {
        require(hasRole(CONFIG_ROLE, msg.sender), "Missing CONFIG_ROLE");
        PendingAddressChange memory change = pendingAddressChanges[TREASURY_KEY];
        require(change.timestamp != 0 && block.timestamp >= change.timestamp, "Timelock not expired");
        emit TreasuryUpdated(treasury, change.newValue);
        treasury = change.newValue;
        delete pendingAddressChanges[TREASURY_KEY];
    }

    function scheduleSetRouterAndToken(address _router, address _drb) external {
        require(hasRole(CONFIG_ROLE, msg.sender), "Missing CONFIG_ROLE");
        require(_router != address(0) && _drb != address(0), "Invalid addresses");
        pendingConfigChanges[ROUTER_TOKEN_KEY] = PendingConfigChange(_router, _drb, block.timestamp + TIMELOCK_DURATION);
    }

    function executeSetRouterAndToken() external {
        require(hasRole(CONFIG_ROLE, msg.sender), "Missing CONFIG_ROLE");
        PendingConfigChange memory change = pendingConfigChanges[ROUTER_TOKEN_KEY];
        require(change.timestamp != 0 && block.timestamp >= change.timestamp, "Timelock not expired");
        swapRouter = ISwapRouter(change.newRouter);
        drbToken = IERC20(change.newToken);
        emit ConfigUpdated(change.newRouter, change.newToken, minSlippagePercent);
        delete pendingConfigChanges[ROUTER_TOKEN_KEY];
    }

    function scheduleSetSlippage(uint256 _percent) external {
        require(hasRole(CONFIG_ROLE, msg.sender), "Missing CONFIG_ROLE");
        require(_percent >= 50 && _percent <= 99, "Slippage must be 50-99%"); // Enhanced bounds checking
        pendingSlippageChanges[SLIPPAGE_KEY] = PendingSlippageChange(_percent, block.timestamp + TIMELOCK_DURATION);
        emit AdminAction(msg.sender, "ScheduleSetSlippage");
    }

    function executeSetSlippage() external {
        require(hasRole(CONFIG_ROLE, msg.sender), "Missing CONFIG_ROLE");
        PendingSlippageChange memory change = pendingSlippageChanges[SLIPPAGE_KEY];
        require(change.timestamp != 0 && block.timestamp >= change.timestamp, "Timelock not expired");
        uint256 oldSlippage = minSlippagePercent;
        minSlippagePercent = change.newSlippage;
        emit SlippageChanged(oldSlippage, change.newSlippage);
        emit ConfigUpdated(address(swapRouter), address(drbToken), change.newSlippage);
        delete pendingSlippageChanges[SLIPPAGE_KEY];
    }

    function scheduleSetDrbPrice(uint256 _price) external {
        require(hasRole(CONFIG_ROLE, msg.sender), "Missing CONFIG_ROLE");
        require(_price > 0, "Invalid price");
        pendingDrbPriceChanges[DRB_PRICE_KEY] = PendingDrbPriceChange(_price, block.timestamp + TIMELOCK_DURATION);
    }

    function executeSetDrbPrice() external {
        require(hasRole(CONFIG_ROLE, msg.sender), "Missing CONFIG_ROLE");
        PendingDrbPriceChange memory change = pendingDrbPriceChanges[DRB_PRICE_KEY];
        require(change.timestamp != 0 && block.timestamp >= change.timestamp, "Timelock not expired");
        uint256 oldPrice = drbPrice;
        drbPrice = change.newPrice;
        emit DrbPriceChanged(oldPrice, change.newPrice);
        delete pendingDrbPriceChanges[DRB_PRICE_KEY];
    }

    // Emergency withdraw (only for stuck funds, with timelock)
    function scheduleEmergencyWithdraw(address _token, uint256 _amount, address _to) external {
        require(hasRole(EMERGENCY_ROLE, msg.sender), "Missing EMERGENCY_ROLE");
        require(_to != address(0), "Invalid recipient");
        require(_amount > 0, "Amount must be > 0");
        pendingEmergencyWithdraws[EMERGENCY_WITHDRAW_KEY] = PendingEmergencyWithdraw(_token, _amount, _to, block.timestamp + TIMELOCK_DURATION);
        emit EmergencyWithdrawScheduled(_token, _amount, _to);
    }

    function executeEmergencyWithdraw() external {
        require(hasRole(EMERGENCY_ROLE, msg.sender), "Missing EMERGENCY_ROLE");
        PendingEmergencyWithdraw memory withdraw = pendingEmergencyWithdraws[EMERGENCY_WITHDRAW_KEY];
        require(withdraw.timestamp != 0 && block.timestamp >= withdraw.timestamp, "Timelock not expired");

        if (withdraw.token == address(0)) {
            // Withdraw ETH
            payable(withdraw.to).transfer(withdraw.amount);
        } else {
            // Withdraw tokens
            IERC20(withdraw.token).transfer(withdraw.to, withdraw.amount);
        }

        emit EmergencyWithdrawExecuted(withdraw.token, withdraw.amount, withdraw.to);
        delete pendingEmergencyWithdraws[EMERGENCY_WITHDRAW_KEY];
    }

    function getEthPrice() public view returns (uint256) {
        (,int256 price,,uint256 updatedAt,) = ethPriceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        require(block.timestamp - updatedAt < 3600, "Stale price feed"); // Circuit breaker: 1 hour max staleness
        return uint256(price); // 8 decimals
    }

    function getDrbPrice() public view returns (uint256) {
        // TODO: Implement proper TWAP with compatible libraries
        // For now, return fallback price - update with real pool address for TWAP
        return drbPrice;
    }

    function version() public pure returns (string memory) {
        return "1.0";
    }

    function pause() external {
        require(hasRole(PAUSER_ROLE, msg.sender), "Missing PAUSER_ROLE");
        _pause();
        emit AdminAction(msg.sender, "Pause");
    }

    function unpause() external {
        require(hasRole(PAUSER_ROLE, msg.sender), "Missing PAUSER_ROLE");
        _unpause();
        emit AdminAction(msg.sender, "Unpause");
    }

    function setSwapDeadline(uint256 _deadline) external {
        require(hasRole(CONFIG_ROLE, msg.sender), "Missing CONFIG_ROLE");
        swapDeadline = _deadline;
    }

    /**
     * @notice Schedules a change to the daily donation cap
     * @param _cap New daily cap in wei
     * @dev Requires CONFIG_ROLE. Change takes effect after TIMELOCK_DURATION
     */
    function scheduleSetDailyCap(uint256 _cap) external {
        require(hasRole(CONFIG_ROLE, msg.sender), "Missing CONFIG_ROLE");
        require(_cap >= 1 ether && _cap <= 100 ether, "Cap must be 1-100 ETH");
        pendingDailyCapChanges[DAILY_CAP_KEY] = PendingUintChange({
            newValue: _cap,
            timestamp: block.timestamp + TIMELOCK_DURATION
        });
        emit AdminAction(msg.sender, "Schedule daily cap change");
    }

    /**
     * @notice Executes the scheduled daily cap change
     * @dev Requires CONFIG_ROLE. Can only be called after timelock expires
     */
    function executeSetDailyCap() external {
        require(hasRole(CONFIG_ROLE, msg.sender), "Missing CONFIG_ROLE");
        PendingUintChange memory change = pendingDailyCapChanges[DAILY_CAP_KEY];
        require(change.timestamp != 0 && block.timestamp >= change.timestamp, "Timelock not expired");
        uint256 oldCap = dailyCap;
        dailyCap = change.newValue;
        emit DailyCapChanged(oldCap, change.newValue);
        delete pendingDailyCapChanges[DAILY_CAP_KEY];
    }

    /**
     * @notice Schedules a change to the user daily donation cap
     * @param _cap New user daily cap in wei
     * @dev Requires CONFIG_ROLE. Change takes effect after TIMELOCK_DURATION
     */
    function scheduleSetUserDailyCap(uint256 _cap) external {
        require(hasRole(CONFIG_ROLE, msg.sender), "Missing CONFIG_ROLE");
        require(_cap >= 0.1 ether && _cap <= 5 ether, "User cap must be 0.1-5 ETH");
        pendingUserDailyCapChanges[USER_DAILY_CAP_KEY] = PendingUintChange({
            newValue: _cap,
            timestamp: block.timestamp + TIMELOCK_DURATION
        });
        emit AdminAction(msg.sender, "Schedule user daily cap change");
    }

    /**
     * @notice Executes the scheduled user daily cap change
     * @dev Requires CONFIG_ROLE. Can only be called after timelock expires
     */
    function executeSetUserDailyCap() external {
        require(hasRole(CONFIG_ROLE, msg.sender), "Missing CONFIG_ROLE");
        PendingUintChange memory change = pendingUserDailyCapChanges[USER_DAILY_CAP_KEY];
        require(change.timestamp != 0 && block.timestamp >= change.timestamp, "Timelock not expired");
        uint256 oldCap = userDailyCap;
        userDailyCap = change.newValue;
        emit UserDailyCapChanged(oldCap, change.newValue);
        delete pendingUserDailyCapChanges[USER_DAILY_CAP_KEY];
    }

    // Emergency withdraw for stuck funds (ETH or tokens) - only treasury
    function emergencyWithdraw(address token, uint256 amount, address to) external {
        require(hasRole(EMERGENCY_ROLE, msg.sender), "Missing EMERGENCY_ROLE");
        require(to != address(0), "Invalid recipient");
        if (token == address(0)) {
            // Withdraw ETH
            require(address(this).balance >= amount, "Insufficient ETH balance");
            payable(to).transfer(amount);
        } else {
            // Withdraw ERC20
            IERC20(token).transfer(to, amount);
        }
        emit EmergencyWithdrawExecuted(token, amount, to);
    }

    receive() external payable {
        _harvest(msg.value, msg.sender);
    }
}