# Hello FHEVM: Your First Confidential dApp Tutorial

A complete, step-by-step guide to building your first privacy-preserving application using Zama's Fully Homomorphic Encryption Virtual Machine (FHEVM).

## 🎯 What You'll Build

In this tutorial, you'll create an **Anonymous Academic Peer Review System** - a complete dApp that demonstrates core FHEVM concepts through a real-world use case. The application allows researchers to:

- Submit academic papers for review
- Provide anonymous, encrypted peer reviews
- Maintain complete privacy of reviewer identities and scores
- Prevent conflicts of interest (self-reviews)

## 🏁 Prerequisites

### Required Knowledge
- **Solidity basics**: Ability to write and deploy simple smart contracts
- **JavaScript fundamentals**: Understanding of async/await, functions, and DOM manipulation
- **Web3 basics**: Familiarity with MetaMask and blockchain transactions

### Required Tools
- [Node.js](https://nodejs.org/) (v16 or higher)
- [Git](https://git-scm.com/)
- [MetaMask](https://metamask.io/) browser extension
- Code editor (VS Code recommended)

### No Prior Knowledge Needed
- ❌ Advanced mathematics or cryptography
- ❌ FHE (Fully Homomorphic Encryption) theory
- ❌ Zama protocol internals

## 📚 Learning Objectives

By the end of this tutorial, you'll understand how to:

1. **Initialize FHEVM contracts** with proper imports and setup
2. **Encrypt sensitive data** using Zama's FHE library
3. **Store encrypted values** on the blockchain securely
4. **Control access** to encrypted data based on business logic
5. **Build frontend interfaces** that interact with encrypted smart contract data
6. **Handle encrypted operations** in real-world scenarios

## 🧠 FHEVM Core Concepts

Before diving into code, let's understand what makes FHEVM special:

### Traditional Smart Contracts
```solidity
// ❌ Traditional: Data is visible to everyone
bool public recommendation = true;  // Anyone can see this
uint8 public score = 4;            // Anyone can see this
```

### FHEVM Smart Contracts
```solidity
// ✅ FHEVM: Data is encrypted and private
ebool encryptedRecommendation;     // Encrypted boolean
euint8 encryptedScore;             // Encrypted 8-bit integer
```

### Why This Matters
- **Privacy**: Sensitive data remains confidential even on a public blockchain
- **Computation**: You can perform operations on encrypted data without decrypting it
- **Access Control**: Only authorized parties can decrypt and view the data

---

## 🏗️ Part 1: Setting Up Your Development Environment

### Step 1: Clone the Repository

```bash
git clone https://github.com/OswaldHeaney/AcademicReview.git
cd AcademicReview
```

### Step 2: Install Dependencies

For this tutorial, we'll use a minimal setup without complex build tools:

```bash
# No npm install needed - we'll use CDN imports for simplicity
mkdir my-fhevm-dapp
cd my-fhevm-dapp
```

### Step 3: Configure MetaMask for Sepolia

1. Open MetaMask
2. Click the network dropdown (top center)
3. Select "Add Network" → "Add Network Manually"
4. Enter Sepolia testnet details:
   - **Network Name**: Sepolia Testnet
   - **RPC URL**: `https://sepolia.infura.io/v3/`
   - **Chain ID**: `11155111`
   - **Currency Symbol**: `SEP`
   - **Block Explorer**: `https://sepolia.etherscan.io/`

### Step 4: Get Test ETH

Visit [Sepolia Faucet](https://sepoliafaucet.com/) to get free test ETH for transactions.

---

## 🔧 Part 2: Understanding the Smart Contract

Let's examine the core FHEVM smart contract step by step:

### Step 1: Contract Setup and Imports

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// 🔑 Key Import: FHEVM library for encryption
import "fhevm/lib/TFHE.sol";

// Standard OpenZeppelin imports for security
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
```

**📝 Explanation:**
- `TFHE.sol`: The core FHEVM library that provides encrypted data types
- Security imports: Standard practices for safe smart contract development

### Step 2: Encrypted Data Structures

```solidity
struct Review {
    uint256 paperId;
    address reviewer;
    // 🔐 Encrypted fields - the magic happens here!
    ebool encryptedRecommendation; // FHE encrypted boolean (accept/reject)
    euint8 encryptedQuality;       // FHE encrypted quality score (1-4)
    string comments;               // Public comments (not encrypted)
    uint256 timestamp;
}
```

**📝 Explanation:**
- `ebool`: Encrypted boolean type (true/false values remain private)
- `euint8`: Encrypted 8-bit unsigned integer (numbers 0-255 remain private)
- Regular fields like `string` and `address` remain public as usual

### Step 3: Core Encryption Logic

```solidity
function submitReview(
    uint256 _paperId,
    bool _recommendation,      // Plain input from user
    uint8 _quality,           // Plain input from user
    string memory _comments
) external nonReentrant {
    // Validation logic here...

    // 🔐 The encryption magic happens here:
    ebool encryptedRecommendation = TFHE.asEbool(_recommendation ? 1 : 0);
    euint8 encryptedQuality = TFHE.asEuint8(_quality);

    // Store encrypted values in the struct
    reviews[reviewCounter] = Review({
        paperId: _paperId,
        reviewer: msg.sender,
        encryptedRecommendation: encryptedRecommendation,
        encryptedQuality: encryptedQuality,
        comments: _comments,
        timestamp: block.timestamp
    });
}
```

**📝 Explanation:**
- `TFHE.asEbool()`: Converts a regular boolean/number to encrypted boolean
- `TFHE.asEuint8()`: Converts a regular number to encrypted 8-bit integer
- Once encrypted, these values cannot be read by unauthorized parties

### Step 4: Access Control for Encrypted Data

```solidity
function getEncryptedReview(
    uint256 _reviewId
) external view returns (ebool encryptedRecommendation, euint8 encryptedQuality) {
    require(_reviewId > 0 && _reviewId <= reviewCounter, "Invalid review ID");

    Review memory review = reviews[_reviewId];
    Paper memory paper = papers[review.paperId];

    // 🔐 Access control: Only paper author or contract owner can access
    require(
        msg.sender == paper.author || msg.sender == owner(),
        "Only paper author or owner can access"
    );

    return (review.encryptedRecommendation, review.encryptedQuality);
}
```

**📝 Explanation:**
- Encrypted data can be returned, but only authorized addresses can decrypt it
- The smart contract enforces who can access encrypted values
- Even if someone gets the encrypted data, they can't decrypt it without authorization

---

## 🎨 Part 3: Building the Frontend Interface

Now let's create a web interface that interacts with our FHEVM contract:

### Step 1: Create the HTML Structure

Create `index.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Hello FHEVM - Anonymous Academic Review</title>

    <!-- 📚 Import Ethers.js for blockchain interaction -->
    <script src="https://cdn.jsdelivr.net/npm/ethers@6.8.0/dist/ethers.umd.min.js"></script>

    <style>
        /* Add your CSS styles here - see full example in repository */
        body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #0f172a 0%, #1e293b 50%);
            color: white;
            margin: 0;
            padding: 20px;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        .card {
            background: rgba(15, 23, 42, 0.8);
            border: 1px solid #475569;
            border-radius: 12px;
            padding: 2rem;
            margin: 1rem 0;
        }
        .btn {
            background: linear-gradient(135deg, #3b82f6, #1d4ed8);
            color: white;
            border: none;
            padding: 0.75rem 2rem;
            border-radius: 8px;
            cursor: pointer;
        }
        .btn:hover { transform: translateY(-2px); }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🔐 Hello FHEVM: Anonymous Academic Review</h1>
            <p>Your first confidential dApp using Fully Homomorphic Encryption</p>
        </header>

        <!-- Wallet Connection Section -->
        <div class="card">
            <h2>Step 1: Connect Your Wallet</h2>
            <div id="walletStatus">
                <button class="btn" id="connectWallet">Connect MetaMask</button>
                <p id="connectionStatus">Not connected</p>
            </div>
        </div>

        <!-- Paper Submission Section -->
        <div class="card">
            <h2>Step 2: Submit a Paper</h2>
            <form id="submitForm">
                <div>
                    <label>Paper Title:</label>
                    <input type="text" id="paperTitle" required
                           placeholder="e.g., Advanced Machine Learning Techniques">
                </div>
                <div>
                    <label>Abstract:</label>
                    <textarea id="paperAbstract" required
                              placeholder="Brief description of your research..."></textarea>
                </div>
                <div>
                    <label>Category:</label>
                    <select id="paperCategory" required>
                        <option value="">Select category</option>
                        <option value="computer-science">Computer Science</option>
                        <option value="mathematics">Mathematics</option>
                        <option value="physics">Physics</option>
                        <option value="biology">Biology</option>
                    </select>
                </div>
                <button type="submit" class="btn">Submit Paper</button>
            </form>
        </div>

        <!-- Review Section -->
        <div class="card">
            <h2>Step 3: Review Papers (Encrypted)</h2>
            <div id="papersList">
                <p>Loading available papers...</p>
            </div>
        </div>

        <!-- Review Form (Hidden by default) -->
        <div class="card" id="reviewCard" style="display: none;">
            <h2>Submit Encrypted Review</h2>
            <div>
                <label>Quality Assessment:</label>
                <div id="qualityOptions">
                    <button class="option-btn" data-quality="4">Excellent (4)</button>
                    <button class="option-btn" data-quality="3">Good (3)</button>
                    <button class="option-btn" data-quality="2">Acceptable (2)</button>
                    <button class="option-btn" data-quality="1">Poor (1)</button>
                </div>
            </div>
            <div>
                <label>Recommendation:</label>
                <div id="recommendationOptions">
                    <button class="option-btn" data-recommendation="true">Accept</button>
                    <button class="option-btn" data-recommendation="false">Reject</button>
                </div>
            </div>
            <div>
                <label>Comments (Public):</label>
                <textarea id="reviewComments"
                          placeholder="Your review comments (visible to all)"></textarea>
            </div>
            <button class="btn" id="submitReview">Submit Encrypted Review</button>
            <button class="btn" id="cancelReview">Cancel</button>
        </div>

        <div id="alerts"></div>
    </div>

    <script>
        // JavaScript code goes here (next step)
    </script>
</body>
</html>
```

### Step 2: Implement Wallet Connection

Add this JavaScript to handle MetaMask connection:

```javascript
// 🔧 Contract Configuration
const CONTRACT_ADDRESS = '0xBeb1a83923072478B2Ec4451Fb9BEb9b354B25ca';
const CONTRACT_ABI = [
    // Add your contract ABI here (see full example in repository)
    {
        "inputs": [
            {"internalType": "string", "name": "_title", "type": "string"},
            {"internalType": "string", "name": "_paperAbstract", "type": "string"},
            {"internalType": "string", "name": "_category", "type": "string"}
        ],
        "name": "submitPaper",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "uint256", "name": "_paperId", "type": "uint256"},
            {"internalType": "bool", "name": "_recommendation", "type": "bool"},
            {"internalType": "uint8", "name": "_quality", "type": "uint8"},
            {"internalType": "string", "name": "_comments", "type": "string"}
        ],
        "name": "submitReview",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    }
    // ... add other functions as needed
];

// Global variables
let provider, signer, contract, userAddress;
let selectedQuality = null;
let selectedRecommendation = null;

// 🔌 Connect to MetaMask
async function connectWallet() {
    try {
        if (typeof window.ethereum === "undefined") {
            throw new Error("MetaMask not installed!");
        }

        // Request account access
        await window.ethereum.request({method: "eth_requestAccounts"});

        // Create provider and signer
        provider = new ethers.BrowserProvider(window.ethereum);
        signer = await provider.getSigner();
        userAddress = await signer.getAddress();

        // Check if we're on Sepolia testnet
        const network = await provider.getNetwork();
        if (Number(network.chainId) !== 11155111) {
            await switchToSepolia();
        }

        // Initialize contract
        contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);

        // Update UI
        document.getElementById('connectionStatus').textContent =
            `Connected: ${userAddress.slice(0, 6)}...${userAddress.slice(-4)}`;
        document.getElementById('connectWallet').textContent = 'Connected ✅';

        console.log('✅ Wallet connected successfully!');

        // Load available papers
        await loadPapers();

    } catch (error) {
        console.error('❌ Error connecting wallet:', error);
        alert('Failed to connect wallet: ' + error.message);
    }
}

// Switch to Sepolia testnet
async function switchToSepolia() {
    try {
        await window.ethereum.request({
            method: 'wallet_switchEthereumChain',
            params: [{ chainId: '0xaa36a7' }], // Sepolia chain ID in hex
        });
    } catch (switchError) {
        // Add Sepolia if it doesn't exist
        if (switchError.code === 4902) {
            await window.ethereum.request({
                method: 'wallet_addEthereumChain',
                params: [{
                    chainId: '0xaa36a7',
                    chainName: 'Sepolia Testnet',
                    nativeCurrency: {
                        name: 'SepoliaETH',
                        symbol: 'SEP',
                        decimals: 18,
                    },
                    rpcUrls: ['https://sepolia.infura.io/v3/'],
                    blockExplorerUrls: ['https://sepolia.etherscan.io/'],
                }],
            });
        }
    }
}
```

### Step 3: Implement Paper Submission

```javascript
// 📝 Submit a paper to the blockchain
async function submitPaper(title, abstract, category) {
    try {
        if (!contract) {
            throw new Error('Please connect your wallet first');
        }

        console.log('📝 Submitting paper:', title);

        // Call the smart contract function
        const tx = await contract.submitPaper(title, abstract, category);

        showAlert('Transaction submitted! Waiting for confirmation...', 'info');
        console.log('Transaction hash:', tx.hash);

        // Wait for transaction confirmation
        const receipt = await tx.wait();
        console.log('✅ Paper submitted successfully!', receipt);

        showAlert('Paper submitted successfully!', 'success');

        // Clear the form
        document.getElementById('submitForm').reset();

        // Reload papers list
        await loadPapers();

    } catch (error) {
        console.error('❌ Error submitting paper:', error);
        showAlert('Failed to submit paper: ' + error.message, 'error');
    }
}

// Handle form submission
document.getElementById('submitForm').addEventListener('submit', async (e) => {
    e.preventDefault();

    const title = document.getElementById('paperTitle').value;
    const abstract = document.getElementById('paperAbstract').value;
    const category = document.getElementById('paperCategory').value;

    await submitPaper(title, abstract, category);
});
```

### Step 4: Implement Encrypted Review Submission

This is where the FHEVM magic happens:

```javascript
// 🔐 Submit an encrypted review (the core FHEVM functionality!)
async function submitEncryptedReview(paperId, quality, recommendation, comments) {
    try {
        if (!contract) {
            throw new Error('Please connect your wallet first');
        }

        console.log('🔐 Submitting encrypted review for paper:', paperId);
        console.log('Quality (will be encrypted):', quality);
        console.log('Recommendation (will be encrypted):', recommendation);

        // 🔑 This is where FHEVM encryption happens automatically!
        // The smart contract will encrypt these values using TFHE.asEuint8() and TFHE.asEbool()
        const tx = await contract.submitReview(
            paperId,
            recommendation, // This boolean will be encrypted as ebool
            quality,        // This number will be encrypted as euint8
            comments        // This remains public
        );

        showAlert('🔐 Encrypted review submitted! Waiting for confirmation...', 'info');
        console.log('Transaction hash:', tx.hash);

        // Wait for confirmation
        const receipt = await tx.wait();
        console.log('✅ Encrypted review confirmed!', receipt);

        showAlert('✅ Review submitted and encrypted on blockchain!', 'success');

        // Reset form
        resetReviewForm();

        // Reload papers
        await loadPapers();

    } catch (error) {
        console.error('❌ Error submitting review:', error);

        // Handle specific error cases
        if (error.message.includes('Cannot review your own paper')) {
            showAlert('❌ You cannot review your own paper!', 'error');
        } else if (error.message.includes('Already reviewed')) {
            showAlert('❌ You have already reviewed this paper!', 'error');
        } else {
            showAlert('❌ Failed to submit review: ' + error.message, 'error');
        }
    }
}
```

### Step 5: Load and Display Papers

```javascript
// 📚 Load papers available for review
async function loadPapers() {
    try {
        if (!contract) {
            document.getElementById('papersList').innerHTML =
                '<p>Please connect your wallet to see papers</p>';
            return;
        }

        console.log('📚 Loading papers from blockchain...');

        // Get papers from smart contract
        const papers = await contract.getPapersForReview();

        console.log('Found', papers.length, 'papers available for review');

        if (papers.length === 0) {
            document.getElementById('papersList').innerHTML =
                '<p>No papers available for review. Submit a paper first!</p>';
            return;
        }

        // Display papers
        let papersHtml = '<h3>Available Papers for Review:</h3>';

        papers.forEach((paper, index) => {
            papersHtml += `
                <div class="paper-item" style="border: 1px solid #475569; border-radius: 8px; padding: 1rem; margin: 1rem 0; cursor: pointer;"
                     onclick="startReview(${Number(paper.id)})">
                    <h4>${paper.title}</h4>
                    <p><strong>Category:</strong> ${paper.category}</p>
                    <p><strong>Abstract:</strong> ${paper.paperAbstract.substring(0, 150)}...</p>
                    <p><strong>Submitted:</strong> ${new Date(Number(paper.timestamp) * 1000).toLocaleDateString()}</p>
                    <p style="color: #3b82f6;">🔐 Click to submit encrypted review</p>
                </div>
            `;
        });

        document.getElementById('papersList').innerHTML = papersHtml;

    } catch (error) {
        console.error('❌ Error loading papers:', error);
        document.getElementById('papersList').innerHTML =
            '<p>Error loading papers: ' + error.message + '</p>';
    }
}

// Start the review process for a specific paper
function startReview(paperId) {
    window.currentReviewPaperId = paperId;
    document.getElementById('reviewCard').style.display = 'block';
    document.getElementById('reviewCard').scrollIntoView({ behavior: 'smooth' });

    console.log('Starting review for paper ID:', paperId);
}
```

### Step 6: Handle Review Form Interactions

```javascript
// Handle quality and recommendation selection
document.addEventListener('click', (e) => {
    if (e.target.classList.contains('option-btn')) {
        const parent = e.target.parentElement;

        // Remove selection from siblings
        parent.querySelectorAll('.option-btn').forEach(btn => {
            btn.classList.remove('selected');
            btn.style.background = '';
        });

        // Highlight selected option
        e.target.classList.add('selected');
        e.target.style.background = '#3b82f6';

        // Store selection
        if (e.target.dataset.quality) {
            selectedQuality = parseInt(e.target.dataset.quality);
            console.log('Selected quality:', selectedQuality);
        } else if (e.target.dataset.recommendation) {
            selectedRecommendation = e.target.dataset.recommendation === 'true';
            console.log('Selected recommendation:', selectedRecommendation);
        }
    }
});

// Submit review button handler
document.getElementById('submitReview').addEventListener('click', async () => {
    if (!selectedQuality || selectedRecommendation === null) {
        showAlert('Please select both quality and recommendation', 'error');
        return;
    }

    if (!window.currentReviewPaperId) {
        showAlert('No paper selected for review', 'error');
        return;
    }

    const comments = document.getElementById('reviewComments').value || '';

    await submitEncryptedReview(
        window.currentReviewPaperId,
        selectedQuality,
        selectedRecommendation,
        comments
    );
});

// Cancel review
document.getElementById('cancelReview').addEventListener('click', resetReviewForm);

function resetReviewForm() {
    selectedQuality = null;
    selectedRecommendation = null;
    window.currentReviewPaperId = null;

    document.getElementById('reviewCard').style.display = 'none';
    document.getElementById('reviewComments').value = '';

    // Remove selections
    document.querySelectorAll('.option-btn').forEach(btn => {
        btn.classList.remove('selected');
        btn.style.background = '';
    });
}

// Utility function to show alerts
function showAlert(message, type) {
    const alertDiv = document.createElement('div');
    alertDiv.style.cssText = `
        padding: 1rem;
        margin: 1rem 0;
        border-radius: 8px;
        color: white;
        background: ${type === 'success' ? '#059669' : type === 'error' ? '#dc2626' : '#3b82f6'};
    `;
    alertDiv.textContent = message;

    document.getElementById('alerts').appendChild(alertDiv);

    setTimeout(() => alertDiv.remove(), 5000);
}

// Initialize when page loads
document.getElementById('connectWallet').addEventListener('click', connectWallet);

// Auto-connect if already connected
window.addEventListener('load', async () => {
    if (typeof window.ethereum !== 'undefined') {
        const accounts = await window.ethereum.request({method: 'eth_accounts'});
        if (accounts.length > 0) {
            await connectWallet();
        }
    }
});
```

---

## 🧪 Part 4: Testing Your FHEVM dApp

### Step 1: Local Testing

1. **Open your HTML file** in a web browser
2. **Connect MetaMask** and ensure you're on Sepolia testnet
3. **Submit a test paper** with sample data
4. **Review another paper** with encrypted scores

### Step 2: Understanding What Happens

When you submit a review:

1. **Frontend**: Collects plain values (quality: 3, recommendation: true)
2. **Smart Contract**: Automatically encrypts using `TFHE.asEuint8(3)` and `TFHE.asEbool(true)`
3. **Blockchain**: Stores encrypted values that only authorized parties can decrypt
4. **Privacy**: Other users see that a review exists, but cannot see the actual scores

### Step 3: Verification on Blockchain

1. Visit [Sepolia Etherscan](https://sepolia.etherscan.io/)
2. Search for your contract address: `0xBeb1a83923072478B2Ec4451Fb9BEb9b354B25ca`
3. View your transactions in the transaction list
4. Notice that encrypted values appear as complex encoded data

---

## 🔍 Part 5: Understanding FHEVM in Depth

### What Makes FHEVM Special?

#### Traditional Blockchain
```
User Input: quality = 3
→ Stored on chain: quality = 3 (visible to everyone)
→ Privacy: ❌ None
```

#### FHEVM Blockchain
```
User Input: quality = 3
→ Smart Contract: TFHE.asEuint8(3)
→ Stored on chain: encryptedQuality = [encrypted_blob]
→ Privacy: ✅ Complete
```

### Key FHEVM Data Types

| Type | Description | Example Use Case |
|------|-------------|------------------|
| `ebool` | Encrypted boolean | Accept/reject decisions |
| `euint8` | Encrypted 8-bit integer (0-255) | Ratings, scores |
| `euint16` | Encrypted 16-bit integer | Larger numbers |
| `euint32` | Encrypted 32-bit integer | Votes, counts |

### Access Control Patterns

```solidity
// Pattern 1: Only data owner can access
require(msg.sender == dataOwner, "Not authorized");

// Pattern 2: Role-based access
require(hasRole(REVIEWER_ROLE, msg.sender), "Not a reviewer");

// Pattern 3: Time-based access
require(block.timestamp > revealTime, "Too early to reveal");
```

---

## 🚀 Part 6: Deployment and Next Steps

### Deploying Your Own Contract

1. **Install Hardhat**:
```bash
npm install --save-dev hardhat
npx hardhat init
```

2. **Configure for FHEVM**:
```javascript
// hardhat.config.js
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: "0.8.24",
  networks: {
    sepolia: {
      url: "https://sepolia.infura.io/v3/YOUR_INFURA_KEY",
      accounts: ["YOUR_PRIVATE_KEY"]
    }
  }
};
```

3. **Deploy Script**:
```javascript
// scripts/deploy.js
async function main() {
  const AcademicReview = await ethers.getContractFactory("AcademicReview");
  const contract = await AcademicReview.deploy();
  await contract.deployed();
  console.log("Contract deployed to:", contract.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
```

### Enhancing Your dApp

#### Add More Encrypted Features
```solidity
// Encrypted voting
euint32 encryptedVoteCount;

// Encrypted identity verification
ebool encryptedIsVerified;

// Encrypted financial data
euint64 encryptedSalary;
```

#### Implement Advanced Access Control
```solidity
// Multi-signature access
mapping(bytes32 => uint256) public approvals;

// Time-locked revelations
mapping(uint256 => uint256) public revealTimes;

// Hierarchical permissions
mapping(address => uint8) public accessLevels;
```

### Production Considerations

1. **Gas Optimization**: FHEVM operations are more expensive than regular operations
2. **Key Management**: Plan how encryption keys are managed and rotated
3. **Upgrade Patterns**: Consider using proxy contracts for upgradability
4. **Monitoring**: Implement comprehensive logging for encrypted operations

---

## 🛠️ Part 7: Troubleshooting Common Issues

### Connection Issues

**Problem**: "MetaMask not connecting"
```javascript
// Solution: Check for MetaMask availability
if (typeof window.ethereum === 'undefined') {
    console.error('MetaMask not installed');
    alert('Please install MetaMask to use this dApp');
    return;
}
```

**Problem**: "Wrong network"
```javascript
// Solution: Implement automatic network switching
const network = await provider.getNetwork();
if (Number(network.chainId) !== 11155111) {
    await switchToSepolia();
}
```

### Transaction Issues

**Problem**: "Transaction failed"
```javascript
// Solution: Better error handling
try {
    const tx = await contract.submitReview(paperId, recommendation, quality, comments);
    await tx.wait();
} catch (error) {
    if (error.message.includes('Cannot review your own paper')) {
        alert('You cannot review your own paper');
    } else if (error.message.includes('Already reviewed')) {
        alert('You have already reviewed this paper');
    } else {
        console.error('Unexpected error:', error);
    }
}
```

**Problem**: "Gas estimation failed"
```javascript
// Solution: Provide manual gas limits for FHEVM operations
const tx = await contract.submitReview(
    paperId, recommendation, quality, comments,
    { gasLimit: 500000 } // Manual gas limit
);
```

### FHEVM-Specific Issues

**Problem**: "Encrypted data not accessible"
```solidity
// Solution: Implement proper access control
function getEncryptedData(uint256 _id) external view returns (euint8) {
    require(msg.sender == dataOwner[_id], "Not authorized");
    return encryptedValues[_id];
}
```

**Problem**: "Type conversion errors"
```solidity
// Solution: Use proper TFHE conversion functions
ebool encrypted = TFHE.asEbool(boolValue ? 1 : 0);  // Convert bool to ebool
euint8 encrypted = TFHE.asEuint8(uint8Value);        // Convert uint8 to euint8
```

---

## 📖 Part 8: Best Practices and Security

### FHEVM Development Best Practices

#### 1. Efficient Encryption
```solidity
// ✅ Good: Encrypt only sensitive data
struct Review {
    uint256 public paperId;           // Public: no encryption needed
    address public reviewer;          // Public: no encryption needed
    ebool private recommendation;     // Private: encrypt this
    euint8 private quality;          // Private: encrypt this
}

// ❌ Avoid: Encrypting non-sensitive data unnecessarily
struct BadReview {
    euint256 paperId;    // Unnecessary encryption
    euint256 timestamp;  // Unnecessary encryption
}
```

#### 2. Access Control Patterns
```solidity
// ✅ Implement granular access control
modifier onlyAuthorized(uint256 _dataId) {
    require(
        msg.sender == dataOwner[_dataId] ||
        hasRole(ADMIN_ROLE, msg.sender),
        "Not authorized to access this data"
    );
    _;
}

// ✅ Use time-based revelations when appropriate
modifier afterRevealTime(uint256 _dataId) {
    require(
        block.timestamp >= revealTimes[_dataId],
        "Data not yet available for revelation"
    );
    _;
}
```

#### 3. Gas Optimization
```solidity
// ✅ Batch operations when possible
function submitMultipleReviews(
    uint256[] calldata paperIds,
    bool[] calldata recommendations,
    uint8[] calldata qualities
) external {
    require(paperIds.length == recommendations.length, "Array length mismatch");

    for (uint i = 0; i < paperIds.length; i++) {
        // Process each review
        _submitSingleReview(paperIds[i], recommendations[i], qualities[i]);
    }
}

// ✅ Use events for off-chain indexing
event EncryptedReviewSubmitted(
    uint256 indexed paperId,
    address indexed reviewer,
    uint256 indexed reviewId
);
```

### Security Considerations

#### 1. Prevent Information Leakage
```solidity
// ❌ Don't leak information through public functions
function isRecommendationPositive(uint256 _reviewId) public view returns (bool) {
    // This reveals encrypted data!
    return TFHE.decrypt(reviews[_reviewId].encryptedRecommendation);
}

// ✅ Keep encrypted data encrypted
function getEncryptedRecommendation(uint256 _reviewId) public view
    onlyAuthorized(_reviewId) returns (ebool) {
    return reviews[_reviewId].encryptedRecommendation;
}
```

#### 2. Validate Inputs Properly
```solidity
function submitReview(
    uint256 _paperId,
    bool _recommendation,
    uint8 _quality,
    string memory _comments
) external {
    // ✅ Validate all inputs
    require(_paperId > 0 && _paperId <= paperCounter, "Invalid paper ID");
    require(_quality >= 1 && _quality <= 5, "Quality must be 1-5");
    require(bytes(_comments).length <= 1000, "Comments too long");
    require(papers[_paperId].author != msg.sender, "Cannot review own paper");
    require(!hasReviewed[msg.sender][_paperId], "Already reviewed");

    // Process review...
}
```

#### 3. Handle Edge Cases
```solidity
// ✅ Handle contract state edge cases
function getPapersForReview() external view returns (Paper[] memory) {
    if (paperCounter == 0) {
        return new Paper[](0);  // Return empty array
    }

    // Count available papers first
    uint256 availableCount = 0;
    for (uint256 i = 1; i <= paperCounter; i++) {
        if (_isPaperAvailableForReview(i, msg.sender)) {
            availableCount++;
        }
    }

    if (availableCount == 0) {
        return new Paper[](0);  // Return empty array
    }

    // Build and return array...
}
```

---

## 🏆 Conclusion: You've Built Your First FHEVM dApp!

Congratulations! You've successfully built a complete privacy-preserving application using FHEVM. Let's review what you've accomplished:

### ✅ What You've Learned

1. **FHEVM Fundamentals**:
   - How to use encrypted data types (`ebool`, `euint8`, etc.)
   - Converting plain data to encrypted data using `TFHE` functions
   - Implementing access control for encrypted information

2. **Smart Contract Development**:
   - Writing privacy-preserving business logic
   - Handling encrypted operations securely
   - Implementing proper validation and security measures

3. **Frontend Integration**:
   - Connecting to FHEVM contracts with Ethers.js
   - Handling encrypted transactions from the UI
   - Managing user interactions with encrypted data

4. **Real-World Application**:
   - Built a complete anonymous peer review system
   - Demonstrated practical use of privacy-preserving smart contracts
   - Learned deployment and testing strategies

### 🚀 Next Steps

Now that you understand FHEVM basics, consider exploring:

#### Advanced FHEVM Features
- **Compute on encrypted data**: Perform arithmetic operations on encrypted values
- **Comparison operations**: Compare encrypted values without revealing them
- **Complex access control**: Multi-party computation and threshold schemes

#### Other Use Cases
- **Private voting systems**: Elections with encrypted vote tallies
- **Confidential auctions**: Sealed-bid auctions with privacy guarantees
- **Private DeFi**: Trading and lending with encrypted balances
- **Healthcare records**: Medical data with patient privacy protection

#### Scaling and Optimization
- **Layer 2 solutions**: Deploy on FHEVM-compatible L2 networks
- **Gas optimization**: Advanced techniques for reducing transaction costs
- **Key management**: Implement sophisticated encryption key rotation

### 📚 Additional Resources

- **Zama Documentation**: [docs.zama.ai](https://docs.zama.ai)
- **FHEVM GitHub**: [github.com/zama-ai/fhevm](https://github.com/zama-ai/fhevm)
- **Community Discord**: Join the Zama developer community
- **Example Applications**: Explore more FHEVM dApp examples

### 🎉 Share Your Success

You've completed the "Hello FHEVM" tutorial! Consider sharing your experience:

- Tweet about your first FHEVM dApp with #HelloFHEVM
- Contribute improvements to this tutorial on GitHub
- Build and share your own FHEVM application ideas
- Help other developers in the Zama community

**Remember**: You've just scratched the surface of what's possible with fully homomorphic encryption. The future of privacy-preserving applications is in your hands!

---

## 📝 Quick Reference

### Essential FHEVM Code Snippets

```solidity
// Import FHEVM
import "fhevm/lib/TFHE.sol";

// Encrypted data types
ebool encryptedBool;
euint8 encryptedNumber;
euint32 encryptedLargeNumber;

// Convert to encrypted
ebool encrypted = TFHE.asEbool(plainValue ? 1 : 0);
euint8 encrypted = TFHE.asEuint8(plainNumber);

// Access control for encrypted data
require(msg.sender == authorizedAddress, "Not authorized");
```

### JavaScript Contract Interaction

```javascript
// Connect to contract
const contract = new ethers.Contract(address, abi, signer);

// Submit encrypted data
await contract.submitEncryptedData(plainValue1, plainValue2);

// Handle FHEVM-specific errors
catch (error) {
    if (error.message.includes("not authorized")) {
        // Handle access control error
    }
}
```

**You're now ready to build the next generation of privacy-preserving applications with FHEVM!** 🎉
