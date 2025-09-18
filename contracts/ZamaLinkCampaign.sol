// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE, euint32, euint64, externalEuint64, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface IZLETHWrapper {
    function deposit(address to) external payable;
    function confidentialTransfer(address to, euint64 amount) external;
    function withdraw(address from, address to, euint64 amount) external;
    function balanceOf(address account) external view returns (euint64);
    function allowDecryption(address spender) external;
    function rate() external view returns (uint256);
}

/**
 * @title ZamaLinkCampaign
 * @notice Private donation campaign platform using ZLETH and Zama FHEVM
 * @dev All donations are private with automatic ETH-ZLETH wrapping
 */
contract ZamaLinkCampaign is SepoliaConfig, ReentrancyGuard, Pausable, Ownable {
    
    IZLETHWrapper public immutable zlethWrapper;

    // Campaign categories
    enum CampaignCategory {
        DISASTER_RELIEF,
        MEDICAL,
        EDUCATION,
        ENVIRONMENT,
        SOCIAL,
        EMERGENCY,
        OTHER
    }

    struct Campaign {
        bytes32 id;
        address organizer;
        string title;
        string description;
        string imageUrl;
        uint256 targetAmount; // Target in wei (ETH)
        uint256 deadline;
        euint64 totalZLETHDonations; // Private total in ZLETH
        euint32 donationCount; // Private count
        uint256 publicDonorCount; // Public social proof counter
        bool isActive;
        bool isCompleted;
        CampaignCategory category;
        uint256 createdAt;
    }

    struct DonationMeta {
        address donor; // address(0) if anonymous
        bytes32 campaignId;
        uint256 timestamp;
        bool isAnonymous;
        // All donations are private with ZLETH
    }

    // Storage
    mapping(bytes32 => Campaign) public campaigns;
    mapping(bytes32 => DonationMeta[]) public campaignDonations;
    mapping(address => bytes32[]) public donorCampaigns;
    mapping(address => mapping(bytes32 => bool)) public hasDonatedTo;
    mapping(address => bytes32[]) public organizerCampaigns;

    // Campaign lists
    bytes32[] public allCampaigns;
    bytes32[] public activeCampaigns;
    mapping(bytes32 => uint256) private activeIdx; // O(1) removal index

    // Events
    event CampaignCreated(bytes32 indexed campaignId, address indexed organizer, string title, uint256 targetAmount, uint256 deadline);
    event PrivateDonationMade(bytes32 indexed campaignId, address indexed donor, uint256 timestamp, bool isAnonymous);
    event CampaignCompleted(bytes32 indexed campaignId, uint256 timestamp);
    event FundsClaimedPrivate(bytes32 indexed campaignId, address indexed organizer, uint256 requestId);

    // Modifiers
    modifier validCampaign(bytes32 campaignId) {
        require(campaigns[campaignId].organizer != address(0), "Campaign does not exist");
        _;
    }

    modifier onlyActiveCampaign(bytes32 campaignId) {
        require(campaigns[campaignId].isActive, "Campaign not active");
        require(block.timestamp < campaigns[campaignId].deadline, "Campaign deadline passed");
        _;
    }

    modifier onlyCampaignOrganizer(bytes32 campaignId) {
        require(campaigns[campaignId].organizer == msg.sender, "Not campaign organizer");
        _;
    }

    constructor(address _zlethWrapper) Ownable(msg.sender) {
        zlethWrapper = IZLETHWrapper(_zlethWrapper);
    }

    /**
     * @notice Create a new fundraising campaign
     * @param campaignId Unique campaign identifier
     * @param title Campaign title
     * @param description Campaign description
     * @param imageUrl Campaign image URL
     * @param targetAmount Target amount in wei (ETH)
     * @param duration Campaign duration in seconds
     * @param category Campaign category
     */
    function createCampaign(
        bytes32 campaignId,
        string calldata title,
        string calldata description,
        string calldata imageUrl,
        uint256 targetAmount,
        uint256 duration,
        CampaignCategory category
    ) external whenNotPaused {
        require(campaigns[campaignId].organizer == address(0), "Campaign ID exists");
        require(bytes(title).length > 0, "Title required");
        require(targetAmount > 0, "Target amount required");
        require(duration > 0, "Duration required");

        uint256 deadline = block.timestamp + duration;

        // Initialize encrypted counters
        euint64 zeroZLETH = FHE.asEuint64(0);
        euint32 zeroCount = FHE.asEuint32(0);

        Campaign storage c = campaigns[campaignId];
        c.id = campaignId;
        c.organizer = msg.sender;
        c.title = title;
        c.description = description;
        c.imageUrl = imageUrl;
        c.targetAmount = targetAmount;
        c.deadline = deadline;
        c.totalZLETHDonations = zeroZLETH;
        c.donationCount = zeroCount;
        c.publicDonorCount = 0;
        c.isActive = true;
        c.isCompleted = false;
        c.category = category;
        c.createdAt = block.timestamp;

        // Grant permissions for future homomorphic operations
        FHE.allowThis(c.totalZLETHDonations);
        FHE.allowThis(c.donationCount);

        // Update registries
        activeIdx[campaignId] = activeCampaigns.length;
        activeCampaigns.push(campaignId);
        allCampaigns.push(campaignId);
        organizerCampaigns[msg.sender].push(campaignId);

        emit CampaignCreated(campaignId, msg.sender, title, targetAmount, deadline);
    }

    /**
     * @notice Donate with automatic ETH->ZLETH wrapping for complete privacy
     * @param campaignId Target campaign
     * @param isAnonymous Whether to hide donor identity
     * @dev All donations are private: ETH is automatically wrapped to ZLETH and transferred privately
     */
    function donate(
        bytes32 campaignId,
        bool isAnonymous
    )
        external
        payable
        validCampaign(campaignId)
        onlyActiveCampaign(campaignId)
        nonReentrant
        whenNotPaused
    {
        require(msg.value > 0, "Must send ETH");
        
        Campaign storage c = campaigns[campaignId];
        address organizer = c.organizer;

        // Step 1: Wrap ETH to ZLETH (sender receives ZLETH)
        zlethWrapper.deposit{value: msg.value}(msg.sender);

        // Step 2: Calculate ZLETH amount received
        uint256 zlethRate = zlethWrapper.rate();
        uint64 zlethAmount = SafeCast.toUint64(msg.value / zlethRate);
        
        // Step 3: Transfer ZLETH privately to campaign organizer
        euint64 encryptedZLETHAmount = FHE.asEuint64(zlethAmount);
        
        // Grant temporary permission to contract for the transfer
        FHE.allowThis(encryptedZLETHAmount);
        FHE.allowTransient(encryptedZLETHAmount, address(zlethWrapper));
        
        // Transfer ZLETH to organizer
        zlethWrapper.confidentialTransfer(organizer, encryptedZLETHAmount);

        // Step 4: Update campaign stats (homomorphically)
        c.totalZLETHDonations = FHE.add(c.totalZLETHDonations, encryptedZLETHAmount);
        c.donationCount = FHE.add(c.donationCount, FHE.asEuint32(1));
        
        // Maintain permissions
        FHE.allowThis(c.totalZLETHDonations);
        FHE.allowThis(c.donationCount);

        // Step 5: Update public social proof
        c.publicDonorCount += 1;

        // Step 6: Record donation metadata (amounts private)
        campaignDonations[campaignId].push(DonationMeta({
            donor: isAnonymous ? address(0) : msg.sender,
            campaignId: campaignId,
            timestamp: block.timestamp,
            isAnonymous: isAnonymous
        }));

        if (!isAnonymous) {
            donorCampaigns[msg.sender].push(campaignId);
            hasDonatedTo[msg.sender][campaignId] = true;
        }

        emit PrivateDonationMade(campaignId, isAnonymous ? address(0) : msg.sender, block.timestamp, isAnonymous);
    }

    /**
     * @notice Claim ZLETH donations and unwrap to ETH
     * @param campaignId Campaign to claim from
     * @dev Automatically unwraps ZLETH back to ETH for organizer
     */
    function claimFunds(bytes32 campaignId)
        external
        validCampaign(campaignId)
        onlyCampaignOrganizer(campaignId)
        nonReentrant
    {
        // Get organizer's ZLETH balance
        euint64 zlethBalance = zlethWrapper.balanceOf(msg.sender);
        
        // Unwrap all ZLETH to ETH (async via oracle)
        zlethWrapper.withdraw(msg.sender, msg.sender, zlethBalance);
        
        // ETH received via oracle callback
        emit FundsClaimedPrivate(campaignId, msg.sender, block.timestamp);
    }

    /**
     * @notice Complete campaign (organizer only)
     * @param campaignId Campaign to complete
     */
    function completeCampaign(bytes32 campaignId)
        external
        validCampaign(campaignId)
        onlyCampaignOrganizer(campaignId)
    {
        Campaign storage c = campaigns[campaignId];
        require(c.isActive, "Already completed");

        c.isActive = false;
        c.isCompleted = true;

        // Remove from active campaigns
        uint256 idx = activeIdx[campaignId];
        uint256 last = activeCampaigns.length - 1;
        if (idx != last) {
            bytes32 lastId = activeCampaigns[last];
            activeCampaigns[idx] = lastId;
            activeIdx[lastId] = idx;
        }
        activeCampaigns.pop();
        delete activeIdx[campaignId];

        emit CampaignCompleted(campaignId, block.timestamp);
    }

    /**
     * @notice Allow organizer to decrypt campaign stats
     * @param campaignId Campaign ID
     * @dev Grants decryption permissions to organizer
     */
    function allowOrganizerDecrypt(bytes32 campaignId)
        external
        validCampaign(campaignId)
        onlyCampaignOrganizer(campaignId)
    {
        Campaign storage c = campaigns[campaignId];
        FHE.allow(c.totalZLETHDonations, msg.sender);
        FHE.allow(c.donationCount, msg.sender);
    }

    // View functions

    function getCampaignInfo(bytes32 campaignId)
        external
        view
        validCampaign(campaignId)
        returns (
            address organizer,
            string memory title,
            string memory description,
            string memory imageUrl,
            uint256 targetAmount,
            uint256 deadline,
            uint256 publicDonorCount,
            bool isActive,
            CampaignCategory category,
            uint256 createdAt
        )
    {
        Campaign storage c = campaigns[campaignId];
        return (
            c.organizer,
            c.title,
            c.description,
            c.imageUrl,
            c.targetAmount,
            c.deadline,
            c.publicDonorCount,
            c.isActive,
            c.category,
            c.createdAt
        );
    }

    function getActiveCampaigns() external view returns (bytes32[] memory) {
        return activeCampaigns;
    }

    function getAllCampaigns() external view returns (bytes32[] memory) {
        return allCampaigns;
    }

    function getCampaignsByOrganizer(address organizer) external view returns (bytes32[] memory) {
        return organizerCampaigns[organizer];
    }

    function getRecentDonations(bytes32 campaignId, uint256 limit)
        external
        view
        validCampaign(campaignId)
        returns (
            address[] memory donors,
            uint256[] memory timestamps,
            bool[] memory isAnonymous
        )
    {
        DonationMeta[] storage donations = campaignDonations[campaignId];
        uint256 n = donations.length;
        uint256 m = n > limit ? limit : n;

        donors = new address[](m);
        timestamps = new uint256[](m);
        isAnonymous = new bool[](m);

        for (uint256 i = 0; i < m; i++) {
            uint256 idx = n - m + i; // Get latest donations
            donors[i] = donations[idx].donor;
            timestamps[i] = donations[idx].timestamp;
            isAnonymous[i] = donations[idx].isAnonymous;
        }
    }

    /**
     * @notice Get encrypted campaign totals (organizer only)
     * @param campaignId Campaign ID
     * @return totalZLETH Encrypted ZLETH total
     * @return donationCount Encrypted donation count
     */
    function getEncryptedTotals(bytes32 campaignId)
        external
        view
        validCampaign(campaignId)
        returns (euint64 totalZLETH, euint32 donationCount)
    {
        Campaign storage c = campaigns[campaignId];
        return (c.totalZLETHDonations, c.donationCount);
    }

    // Admin functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function updateZLETHWrapper(address newWrapper) external view onlyOwner {
        // TODO: Implement proper wrapper update logic
        require(newWrapper != address(0), "Invalid wrapper");
    }

    // Reject direct ETH transfers
    receive() external payable {
        revert("Use donate() function for private donations");
    }
}
