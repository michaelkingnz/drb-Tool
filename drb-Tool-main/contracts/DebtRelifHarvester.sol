// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract DebtReliefHarvester {
    address public treasury;
    uint256 public constant BURN_PERCENT = 50;

    constructor(address _treasury) {
        treasury = _treasury;
    }

    function harvest() external payable {
        uint256 burnAmt = (msg.value * BURN_PERCENT) / 100;
        uint256 reliefAmt = msg.value - burnAmt;

        if (burnAmt > 0) {
            // Placeholder: send ETH to dead address (later: swap + burn $DRB)
            payable(address(0xdead)).transfer(burnAmt);
        }

        if (reliefAmt > 0) {
            payable(treasury).transfer(reliefAmt);
        }
    }

    function setTreasury(address _new) external {
        require(msg.sender == treasury, "Only treasury");
        treasury = _new;
    }
}
