// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DebtReliefHarvester is ReentrancyGuard {
    address public treasury;
    uint256 public constant BURN_PERCENT = 50;
    uint256 public minSlippagePercent = 95; // 5% max slippage

    ISwapRouter public swapRouter;
    address public drbToken;
    address public weth;
    uint256 public swapDeadline = 300; // 5 minutes
    bool public paused;

    event Harvested(address indexed sender, uint256 ethIn, uint256 drbBurned, uint256 ethToRelief);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event ConfigUpdated(address router, address token, uint256 slippage);

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    constructor(address _treasury, address _router, address _drbToken, address _weth) {
        require(_treasury != address(0) && _router != address(0) && _drbToken != address(0) && _weth != address(0), "Invalid addresses");
        treasury = _treasury;
        swapRouter = ISwapRouter(_router);
        drbToken = _drbToken;
        weth = _weth;
    }

    function harvest() external payable whenNotPaused nonReentrant {
        require(msg.value > 0, "Send ETH");
        uint256 burnAmt = msg.value / 2;
        uint256 reliefAmt = msg.value - burnAmt;

        uint256 drbBurned = _swapAndBurn(burnAmt);
        payable(treasury).transfer(reliefAmt);

        emit Harvested(msg.sender, msg.value, drbBurned, reliefAmt);
    }

    function _swapAndBurn(uint256 ethAmount) internal returns (uint256 drbOut) {
        // Rough price estimate: assume ETH = 2000 USD, DRB = 1 USD, 18 decimals
        // expectedOut = ethAmount * 2000 (in wei equivalent)
        uint256 expectedOut = ethAmount * 2000;
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
        IERC20(drbToken).transfer(address(0xdead), drbOut);
    }

    // Owner-only config (you control until mainnet)
    function setTreasury(address _new) external {
        require(msg.sender == treasury, "Only treasury");
        emit TreasuryUpdated(treasury, _new);
        treasury = _new;
    }

    function setRouterAndToken(address _router, address _drb) external {
        require(msg.sender == treasury, "Only treasury");
        require(_router != address(0) && _drb != address(0), "Invalid addresses");
        swapRouter = ISwapRouter(_router);
        drbToken = _drb;
        emit ConfigUpdated(_router, _drb, minSlippagePercent);
    }

    function setSlippage(uint256 _percent) external {
        require(msg.sender == treasury && _percent > 0 && _percent <= 100, "Only treasury, 1-100");
        minSlippagePercent = _percent;
        emit ConfigUpdated(address(swapRouter), drbToken, _percent);
    }

    function pause() external {
        require(msg.sender == treasury, "Only treasury");
        paused = true;
    }

    function unpause() external {
        require(msg.sender == treasury, "Only treasury");
        paused = false;
    }

    function setSwapDeadline(uint256 _deadline) external {
        require(msg.sender == treasury, "Only treasury");
        swapDeadline = _deadline;
    }

    receive() external payable {}
}