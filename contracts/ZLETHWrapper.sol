// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ZLETHWrapper
 * @notice Private ETH wrapper using Zama FHEVM technology
 * @dev Converts ETH to ZLETH with encrypted balances for private transfers
 */
contract ZLETHWrapper is SepoliaConfig, ReentrancyGuard {
    uint8 private immutable DECIMALS;
    uint256 private immutable RATE;
    
    string public name;
    string public symbol;

    /// @dev Encrypted balances mapping
    mapping(address => euint64) private _balances;
    
    /// @dev Gateway decryption request ID to ETH receiver mapping
    mapping(uint256 requestID => address receiver) private _receivers;

    /// @dev Total ETH locked in the contract (for accounting)
    uint256 public totalEthLocked;

    event ETHWrapped(address indexed user, uint256 ethAmount, uint64 zlethAmount);
    event UnwrapRequested(address indexed user, uint256 requestId);
    event ETHUnwrapped(address indexed user, uint256 ethAmount);

    error InsufficientETH();
    error UnwrapFailed();
    error InvalidReceiver();
    error InvalidRequest();

    constructor() {
        name = "Zama Link ETH";
        symbol = "ZLETH";
        DECIMALS = 9; // 9 decimals for ZLETH (vs 18 for ETH)
        RATE = 10 ** 9; // 1 ETH = 1e9 ZLETH units
    }

    function decimals() public view returns (uint8) {
        return DECIMALS;
    }

    /**
     * @dev Returns the rate at which ETH is converted to ZLETH
     * 1 ETH = 1e9 ZLETH units (due to 9 decimals)
     */
    function rate() public view returns (uint256) {
        return RATE;
    }

    /**
     * @notice Wrap ETH to ZLETH (private tokens)
     * @param to Address to receive the wrapped ZLETH tokens
     * @dev Converts ETH to ZLETH at a 1:1 ratio (accounting for decimals)
     *      The ZLETH balance is encrypted using FHEVM
     */
    function deposit(address to) public payable nonReentrant {
        uint256 ethAmount = msg.value;
        if (ethAmount == 0) revert InsufficientETH();
        
        // Calculate ZLETH amount (18->9 decimals)
        uint64 zlethAmount = SafeCast.toUint64(ethAmount / rate());
        if (zlethAmount == 0) revert InsufficientETH();

        // Refund excess ETH
        uint256 excessETH = ethAmount % rate();
        if (excessETH > 0) {
            payable(msg.sender).transfer(excessETH);
        }

        // Update accounting
        totalEthLocked += (ethAmount - excessETH);

        // Mint confidential ZLETH tokens
        euint64 mintAmount = FHE.asEuint64(zlethAmount);
        _balances[to] = FHE.add(_balances[to], mintAmount);
        
        // Grant permissions
        FHE.allowThis(_balances[to]);
        FHE.allow(_balances[to], to);

        emit ETHWrapped(to, ethAmount - excessETH, zlethAmount);
    }

    /**
     * @notice Unwrap ZLETH back to ETH (async via oracle)
     * @param from Address to burn ZLETH from
     * @param to Address to receive ETH
     * @param amount Encrypted ZLETH amount to unwrap
     * @dev The caller must be `from` or be an approved operator
     *      Uses FHEVM oracle for private decryption
     */
    function withdraw(address from, address to, euint64 amount) public nonReentrant {
        if (to == address(0)) revert InvalidReceiver();
        require(from == msg.sender, "Unauthorized");

        _withdraw(from, to, amount);
    }

    /**
     * @notice Variant of withdraw that accepts external encrypted amount
     * @param from Address to burn ZLETH from  
     * @param to Address to receive ETH
     * @param encryptedAmount External encrypted ZLETH amount
     * @param inputProof ZK proof for the encrypted input
     */
    function withdraw(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public nonReentrant {
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
        withdraw(from, to, amount);
    }

    /**
     * @dev Internal withdraw logic
     */
    function _withdraw(address from, address to, euint64 amount) internal {
        if (to == address(0)) revert InvalidReceiver();

        // Burn the ZLETH tokens
        _balances[from] = FHE.sub(_balances[from], amount);
        FHE.allowThis(_balances[from]);
        FHE.allow(_balances[from], from);

        // Request decryption via FHEVM oracle
        bytes32[] memory cts = new bytes32[](1);
        cts[0] = euint64.unwrap(amount);
        uint256 requestID = FHE.requestDecryption(cts, this.finalizeWithdraw.selector);

        // Register who will receive the ETH
        _receivers[requestID] = to;

        emit UnwrapRequested(from, requestID);
    }

    /**
     * @notice Oracle callback to finalize ETH withdrawal
     * @param requestID Decryption request ID
     * @param zlethAmount Decrypted ZLETH amount
     * @param signatures Oracle signatures
     * @dev Called by the FHEVM gateway after decryption
     */
    function finalizeWithdraw(
        uint256 requestID, 
        uint64 zlethAmount, 
        bytes[] memory signatures
    ) public {
        // Verify oracle signatures
        FHE.checkSignatures(requestID, signatures);
        
        address to = _receivers[requestID];
        if (to == address(0)) revert InvalidRequest();
        
        // Clean up
        delete _receivers[requestID];

        // Convert ZLETH to ETH
        uint256 ethAmount = uint256(zlethAmount) * rate();
        
        if (ethAmount > address(this).balance) {
            ethAmount = address(this).balance; // Safety check
        }

        // Update accounting
        if (ethAmount <= totalEthLocked) {
            totalEthLocked -= ethAmount;
        } else {
            totalEthLocked = 0; // Prevent underflow
        }

        // Transfer ETH to recipient
        payable(to).transfer(ethAmount);

        emit ETHUnwrapped(to, ethAmount);
    }

    /**
     * @notice Transfer ZLETH tokens confidentially
     * @param to Recipient address
     * @param encryptedAmount External encrypted amount
     * @param inputProof ZK proof for encrypted input
     * @dev Public wrapper for confidential transfers
     */
    function confidentialTransfer(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external {
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
        _transfer(msg.sender, to, amount);
    }

    /**
     * @notice Transfer ZLETH using already-verified encrypted amount
     * @param to Recipient address  
     * @param amount Already-verified encrypted amount
     * @dev Used when amount is already processed by FHE.fromExternal in same transaction
     */
    function confidentialTransfer(address to, euint64 amount) external {
        _transfer(msg.sender, to, amount);
    }
    
    /**
     * @dev Internal transfer function
     */
    function _transfer(address from, address to, euint64 amount) internal {
        require(to != address(0), "Transfer to zero address");
        
        // Update balances
        _balances[from] = FHE.sub(_balances[from], amount);
        _balances[to] = FHE.add(_balances[to], amount);
        
        // Grant permissions
        FHE.allowThis(_balances[from]);
        FHE.allowThis(_balances[to]);
        FHE.allow(_balances[from], from);
        FHE.allow(_balances[to], to);
    }

    /**
     * @notice Get encrypted ZLETH balance
     * @param account Address to check
     * @return Encrypted balance (euint64)
     */
    function balanceOf(address account) public view returns (euint64) {
        return _balances[account];
    }

    /**
     * @notice Allow someone to decrypt your balance
     * @param spender Address to grant decryption permission
     * @dev Useful for dApps that need to read your balance
     */
    function allowDecryption(address spender) external {
        euint64 balance = _balances[msg.sender];
        FHE.allow(balance, spender);
    }

    /**
     * @notice Emergency function to recover excess ETH
     * @dev Only callable if contract balance exceeds locked amount
     */
    function emergencyWithdrawETH() external {
        // Emergency recovery for excess ETH only
        require(address(this).balance > totalEthLocked, "No excess ETH to withdraw");
        
        uint256 excess = address(this).balance - totalEthLocked;
        payable(msg.sender).transfer(excess);
    }

    /**
     * @notice Check contract health
     * @return ethBalance Current ETH balance
     * @return ethLocked Tracked locked ETH
     * @return isHealthy Whether accounting is consistent
     */
    function contractHealth() external view returns (
        uint256 ethBalance,
        uint256 ethLocked, 
        bool isHealthy
    ) {
        ethBalance = address(this).balance;
        ethLocked = totalEthLocked;
        isHealthy = ethBalance >= ethLocked;
    }

    // Accept ETH deposits directly
    receive() external payable {
        if (msg.value > 0) {
            deposit(msg.sender);
        }
    }
}
