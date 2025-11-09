const contractAddress = '0x88546aCf5B2a1CC71DCc1C2a0862959729534f6B';
const abi = [
    {
        "inputs": [],
        "name": "harvest",
        "outputs": [],
        "stateMutability": "payable",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "treasury",
        "outputs": [
            {
                "internalType": "address",
                "name": "",
                "type": "address"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "drbToken",
        "outputs": [
            {
                "internalType": "address",
                "name": "",
                "type": "address"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    }
];

let provider;
let signer;
let contract;

const connectWalletBtn = document.getElementById('connectWallet');
const harvestBtn = document.getElementById('harvestBtn');
const ethAmountInput = document.getElementById('ethAmount');
const statusDiv = document.getElementById('status');

async function connectWallet() {
    if (typeof window.ethereum !== 'undefined') {
        try {
            await window.ethereum.request({ method: 'eth_requestAccounts' });
            provider = new ethers.providers.Web3Provider(window.ethereum);
            signer = provider.getSigner();
            contract = new ethers.Contract(contractAddress, abi, signer);

            const address = await signer.getAddress();
            connectWalletBtn.textContent = `Connected: ${address.slice(0, 6)}...${address.slice(-4)}`;
            connectWalletBtn.disabled = true;
            harvestBtn.disabled = false;

            // Check network
            const network = await provider.getNetwork();
            if (network.chainId !== 84532) {
                showStatus('Please switch to Base Sepolia network', 'error');
                return;
            }

            showStatus('Wallet connected successfully!', 'success');
        } catch (error) {
            console.error(error);
            showStatus('Failed to connect wallet', 'error');
        }
    } else {
        showStatus('Please install MetaMask or another Web3 wallet', 'error');
    }
}

async function harvest() {
    const ethAmount = ethAmountInput.value;
    if (!ethAmount || parseFloat(ethAmount) <= 0) {
        showStatus('Please enter a valid ETH amount', 'error');
        return;
    }

    try {
        harvestBtn.disabled = true;
        harvestBtn.textContent = 'Processing...';

        const tx = await contract.harvest({
            value: ethers.utils.parseEther(ethAmount)
        });

        showStatus('Transaction submitted! Waiting for confirmation...', 'success');

        await tx.wait();

        showStatus(`Success! Harvested ${ethAmount} ETH. Half sent to relief, half swapped and burned as DRB.`, 'success');
        harvestBtn.textContent = 'Harvest & Burn DRB';
        harvestBtn.disabled = false;
    } catch (error) {
        console.error(error);
        showStatus('Transaction failed: ' + error.message, 'error');
        harvestBtn.textContent = 'Harvest & Burn DRB';
        harvestBtn.disabled = false;
    }
}

function showStatus(message, type) {
    statusDiv.textContent = message;
    statusDiv.className = `status ${type}`;
    statusDiv.style.display = 'block';
}

connectWalletBtn.addEventListener('click', connectWallet);
harvestBtn.addEventListener('click', harvest);

// Check if already connected
if (typeof window.ethereum !== 'undefined') {
    window.ethereum.on('accountsChanged', () => {
        window.location.reload();
    });
    window.ethereum.on('chainChanged', () => {
        window.location.reload();
    });
}