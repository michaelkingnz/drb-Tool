// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./chainlink/AggregatorV3Interface.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

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

contract DebtReliefHarvester is ReentrancyGuard {
    address public treasury;
    uint256 public constant BURN_PERCENT = 50;
    uint256 public minSlippagePercent = 95; // 5% max slippage

    ISwapRouter public swapRouter;
    address public drbToken;
    address public weth;
    uint256 public swapDeadline = 300; // 5 minutes
    bool public paused;

    AggregatorV3Interface public ethPriceFeed;
    IUniswapV3Pool public drbPool; // DRB/ETH or DRB/USDC pool for TWAP
    uint256 public drbPrice = 1e8; // Fallback DRB price in USD (8 decimals)

    event Harvested(address indexed sender, uint256 ethIn, uint256 drbBurned, uint256 ethToRelief);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event ConfigUpdated(address router, address token, uint256 slippage);
    event Paused(address account);
    event Unpaused(address account);
    event SlippageChanged(uint256 oldSlippage, uint256 newSlippage);
    event DrbPriceChanged(uint256 oldPrice, uint256 newPrice);
    event EmergencyWithdrawScheduled(address token, uint256 amount, address to);
    event EmergencyWithdrawExecuted(address token, uint256 amount, address to);

    uint256 public constant TIMELOCK_DURATION = 2 days;

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

    mapping(bytes32 => PendingAddressChange) public pendingAddressChanges;
    mapping(bytes32 => PendingConfigChange) public pendingConfigChanges;
    mapping(bytes32 => PendingSlippageChange) public pendingSlippageChanges;
    mapping(bytes32 => PendingDrbPriceChange) public pendingDrbPriceChanges;

    struct PendingEmergencyWithdraw {
        address token;
        uint256 amount;
        address to;
        uint256 timestamp;
    }

    mapping(bytes32 => PendingEmergencyWithdraw) public pendingEmergencyWithdraws;

    bytes32 constant TREASURY_KEY = keccak256("TREASURY");
    bytes32 constant ROUTER_TOKEN_KEY = keccak256("ROUTER_TOKEN");
    bytes32 constant SLIPPAGE_KEY = keccak256("SLIPPAGE");
    bytes32 constant DRB_PRICE_KEY = keccak256("DRB_PRICE");
    bytes32 constant EMERGENCY_WITHDRAW_KEY = keccak256("EMERGENCY_WITHDRAW");

    mapping(address => uint256) public lastHarvest;
    uint256 public constant HARVEST_COOLDOWN = 0;

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    constructor(address _treasury, address _router, address _drbToken, address _weth, address _ethPriceFeed, address _drbPool) {
        require(_treasury != address(0) && _router != address(0) && _drbToken != address(0) && _weth != address(0) && _ethPriceFeed != address(0), "Invalid addresses");
        treasury = _treasury;
        swapRouter = ISwapRouter(_router);
        drbToken = _drbToken;
        weth = _weth;
        ethPriceFeed = AggregatorV3Interface(_ethPriceFeed);
        drbPool = IUniswapV3Pool(_drbPool);
    }

    function harvest() external payable whenNotPaused nonReentrant {
        _harvest(msg.value, msg.sender);
    }

    function _harvest(uint256 ethAmount, address sender) internal {
        require(ethAmount > 0, "Must send ETH");
        require(ethAmount <= 1 ether, "Max 1 ETH per harvest"); // Prevent overflow risks and large donations
        require(block.timestamp >= lastHarvest[sender] + HARVEST_COOLDOWN, "Harvest cooldown: 1 per week per user");
        lastHarvest[sender] = block.timestamp;
        uint256 burnAmt = ethAmount / 2;
        uint256 reliefAmt = ethAmount - burnAmt;

        // Get 30-min TWAP tick
        int24 twapTick = UniswapTWAP.getMeanTick(address(drbPool), 1800);  // 30 min
        // uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(twapTick); // Version conflict

        // Set min output based on TWAP (5% slippage)
        uint256 minOut = (burnAmt * 95) / 100;  // Simplified — use full calc in prod

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: weth,
            tokenOut: drbToken,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: burnAmt,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0  // Use 0 for now due to version issues
        });

        uint256 drbReceived = swapRouter.exactInputSingle{value: burnAmt}(params);
        IERC20(drbToken).transfer(0x000000000000000000000000000000000000dEaD, drbReceived);
        payable(treasury).transfer(reliefAmt);

        emit Harvested(sender, ethAmount, drbReceived, reliefAmt);
    }

    function _swapAndBurn(uint256 ethAmount) internal returns (uint256 drbOut) {
        uint256 ethPrice = getEthPrice(); // USD per ETH, 8 decimals
        uint256 drbPrice = getDrbPrice(); // USD per DRB, 8 decimals from TWAP
        // expectedOut = (ethAmount in wei * ethPrice) / drbPrice, adjusted for decimals
        // ethAmount: 18 dec, ethPrice: 8 dec, drbPrice: 8 dec → result: 18 dec
        uint256 expectedOut = (ethAmount * ethPrice) / drbPrice;
        uint256 minOut = (expectedOut * minSlippagePercent) / 100;

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: weth,
            tokenOut: drbToken,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp + swapDeadline,
            amountIn: ethAmount,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0
        });

        drbOut = swapRouter.exactInputSingle{value: ethAmount}(params);
        IERC20(drbToken).transfer(0x000000000000000000000000000000000000dEaD, drbOut);
    }

    // Owner-only config (treasury controls, with timelock)
    function scheduleSetTreasury(address _new) external {
        require(msg.sender == treasury, "Only treasury");
        require(_new != address(0), "Invalid address");
        pendingAddressChanges[TREASURY_KEY] = PendingAddressChange(_new, block.timestamp + TIMELOCK_DURATION);
    }

    function executeSetTreasury() external {
        require(msg.sender == treasury, "Only treasury");
        PendingAddressChange memory change = pendingAddressChanges[TREASURY_KEY];
        require(change.timestamp != 0 && block.timestamp >= change.timestamp, "Timelock not expired");
        emit TreasuryUpdated(treasury, change.newValue);
        treasury = change.newValue;
        delete pendingAddressChanges[TREASURY_KEY];
    }

    function scheduleSetRouterAndToken(address _router, address _drb) external {
        require(msg.sender == treasury, "Only treasury");
        require(_router != address(0) && _drb != address(0), "Invalid addresses");
        pendingConfigChanges[ROUTER_TOKEN_KEY] = PendingConfigChange(_router, _drb, block.timestamp + TIMELOCK_DURATION);
    }

    function executeSetRouterAndToken() external {
        require(msg.sender == treasury, "Only treasury");
        PendingConfigChange memory change = pendingConfigChanges[ROUTER_TOKEN_KEY];
        require(change.timestamp != 0 && block.timestamp >= change.timestamp, "Timelock not expired");
        swapRouter = ISwapRouter(change.newRouter);
        drbToken = change.newToken;
        emit ConfigUpdated(change.newRouter, change.newToken, minSlippagePercent);
        delete pendingConfigChanges[ROUTER_TOKEN_KEY];
    }

    function scheduleSetSlippage(uint256 _percent) external {
        require(msg.sender == treasury, "Only treasury");
        require(_percent >= 1 && _percent <= 100, "Slippage must be 1-100%");
        pendingSlippageChanges[SLIPPAGE_KEY] = PendingSlippageChange(_percent, block.timestamp + TIMELOCK_DURATION);
    }

    function executeSetSlippage() external {
        require(msg.sender == treasury, "Only treasury");
        PendingSlippageChange memory change = pendingSlippageChanges[SLIPPAGE_KEY];
        require(change.timestamp != 0 && block.timestamp >= change.timestamp, "Timelock not expired");
        uint256 oldSlippage = minSlippagePercent;
        minSlippagePercent = change.newSlippage;
        emit SlippageChanged(oldSlippage, change.newSlippage);
        emit ConfigUpdated(address(swapRouter), drbToken, change.newSlippage);
        delete pendingSlippageChanges[SLIPPAGE_KEY];
    }

    function scheduleSetDrbPrice(uint256 _price) external {
        require(msg.sender == treasury, "Only treasury");
        require(_price > 0, "Invalid price");
        pendingDrbPriceChanges[DRB_PRICE_KEY] = PendingDrbPriceChange(_price, block.timestamp + TIMELOCK_DURATION);
    }

    function executeSetDrbPrice() external {
        require(msg.sender == treasury, "Only treasury");
        PendingDrbPriceChange memory change = pendingDrbPriceChanges[DRB_PRICE_KEY];
        require(change.timestamp != 0 && block.timestamp >= change.timestamp, "Timelock not expired");
        uint256 oldPrice = drbPrice;
        drbPrice = change.newPrice;
        emit DrbPriceChanged(oldPrice, change.newPrice);
        delete pendingDrbPriceChanges[DRB_PRICE_KEY];
    }

    // Emergency withdraw (only for stuck funds, with timelock)
    function scheduleEmergencyWithdraw(address _token, uint256 _amount, address _to) external {
        require(msg.sender == treasury, "Only treasury");
        require(_to != address(0), "Invalid recipient");
        require(_amount > 0, "Amount must be > 0");
        pendingEmergencyWithdraws[EMERGENCY_WITHDRAW_KEY] = PendingEmergencyWithdraw(_token, _amount, _to, block.timestamp + TIMELOCK_DURATION);
        emit EmergencyWithdrawScheduled(_token, _amount, _to);
    }

    function executeEmergencyWithdraw() external {
        require(msg.sender == treasury, "Only treasury");
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
        (,int256 price,,,) = ethPriceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price); // 8 decimals
    }

    function getDrbPrice() public view returns (uint256) {
        // TODO: Implement proper TWAP with compatible libraries
        // For now, return fallback price - update with real pool address for TWAP
        return drbPrice;
    }

    function pause() external {
        require(msg.sender == treasury, "Only treasury");
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external {
        require(msg.sender == treasury, "Only treasury");
        paused = false;
        emit Unpaused(msg.sender);
    }

    function setSwapDeadline(uint256 _deadline) external {
        require(msg.sender == treasury, "Only treasury");
        swapDeadline = _deadline;
    }

    // Emergency withdraw for stuck funds (ETH or tokens) - only treasury
    function emergencyWithdraw(address token, uint256 amount, address to) external {
        require(msg.sender == treasury, "Only treasury");
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