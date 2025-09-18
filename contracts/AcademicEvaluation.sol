// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@fhevm/solidity/contracts/FHE.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title AcademicEvaluation
 * @dev Anonymous academic paper evaluation system using Zama FHE
 * @notice This contract allows reviewers to submit encrypted evaluations for academic papers
 */
contract AcademicEvaluation is Ownable, ReentrancyGuard {
    using FHE for ebool;
    using FHE for euint8;
    using FHE for euint32;

    // Encrypted evaluation data
    struct EncryptedEvaluation {
        uint256 paperId;
        address reviewer;
        ebool recommendation; // Encrypted boolean for accept/reject
        euint8 originality;   // Encrypted score 1-10
        euint8 quality;       // Encrypted score 1-10
        euint8 clarity;       // Encrypted score 1-10
        euint8 significance;  // Encrypted score 1-10
        string comments;      // Plain text comments (optional)
        uint256 timestamp;
    }

    // Paper information
    struct Paper {
        uint256 id;
        string title;
        string authors;
        string ipfsHash;
        address submitter;
        uint256 submissionDate;
        bool isActive;
        uint32 evaluationCount;
    }

    // State variables
    mapping(uint256 => EncryptedEvaluation) public evaluations;
    mapping(uint256 => Paper) public papers;
    mapping(address => uint256[]) public reviewerEvaluations;
    mapping(uint256 => uint256[]) public paperEvaluations;
    
    uint256 public evaluationCount;
    uint256 public paperCount;
    uint256 public activeReviewers;
    
    // Events
    event PaperSubmitted(
        uint256 indexed paperId,
        string title,
        address indexed submitter,
        uint256 timestamp
    );
    
    event EvaluationSubmitted(
        uint256 indexed evaluationId,
        uint256 indexed paperId,
        address indexed reviewer,
        uint256 timestamp
    );
    
    event EvaluationRevealed(
        uint256 indexed evaluationId,
        uint256 indexed paperId,
        bool recommendation,
        uint8 overallScore
    );

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Submit a paper for evaluation
     * @param title Title of the paper
     * @param authors Authors of the paper
     * @param ipfsHash IPFS hash of the paper document
     */
    function submitPaper(
        string memory title,
        string memory authors,
        string memory ipfsHash
    ) external {
        paperCount++;
        
        papers[paperCount] = Paper({
            id: paperCount,
            title: title,
            authors: authors,
            ipfsHash: ipfsHash,
            submitter: msg.sender,
            submissionDate: block.timestamp,
            isActive: true,
            evaluationCount: 0
        });
        
        emit PaperSubmitted(paperCount, title, msg.sender, block.timestamp);
    }

    /**
     * @dev Submit an encrypted evaluation for a paper
     * @param paperId ID of the paper being evaluated
     * @param _recommendation Plain boolean recommendation (will be encrypted internally)
     * @param _originality Originality score 1-10
     * @param _quality Technical quality score 1-10
     * @param _clarity Clarity score 1-10
     * @param _significance Significance score 1-10
     * @param comments Optional comments for the authors
     */
    function submitEvaluation(
        uint256 paperId,
        bool _recommendation,
        uint8 _originality,
        uint8 _quality,
        uint8 _clarity,
        uint8 _significance,
        string memory comments
    ) external nonReentrant {
        require(paperId > 0 && paperId <= paperCount, "Invalid paper ID");
        require(papers[paperId].isActive, "Paper is not active");
        require(_originality >= 1 && _originality <= 10, "Originality score must be 1-10");
        require(_quality >= 1 && _quality <= 10, "Quality score must be 1-10");
        require(_clarity >= 1 && _clarity <= 10, "Clarity score must be 1-10");
        require(_significance >= 1 && _significance <= 10, "Significance score must be 1-10");
        
        evaluationCount++;
        
        // Encrypt the evaluation data using FHE
        evaluations[evaluationCount] = EncryptedEvaluation({
            paperId: paperId,
            reviewer: msg.sender,
            recommendation: FHE.asBool(_recommendation), // Auto-encrypt boolean
            originality: FHE.asEuint8(_originality),     // Auto-encrypt score
            quality: FHE.asEuint8(_quality),             // Auto-encrypt score
            clarity: FHE.asEuint8(_clarity),             // Auto-encrypt score
            significance: FHE.asEuint8(_significance),   // Auto-encrypt score
            comments: comments,
            timestamp: block.timestamp
        });
        
        // Update mappings
        reviewerEvaluations[msg.sender].push(evaluationCount);
        paperEvaluations[paperId].push(evaluationCount);
        
        // Update counters
        papers[paperId].evaluationCount++;
        
        // Track if this is a new reviewer
        if (reviewerEvaluations[msg.sender].length == 1) {
            activeReviewers++;
        }
        
        emit EvaluationSubmitted(evaluationCount, paperId, msg.sender, block.timestamp);
    }

    /**
     * @dev Reveal encrypted recommendation for authorized parties (paper submitter or contract owner)
     * @param evaluationId ID of the evaluation to reveal
     * @return Decrypted recommendation boolean
     */
    function revealRecommendation(uint256 evaluationId) 
        external 
        view 
        returns (bool) 
    {
        require(evaluationId > 0 && evaluationId <= evaluationCount, "Invalid evaluation ID");
        
        EncryptedEvaluation memory evaluation = evaluations[evaluationId];
        Paper memory paper = papers[evaluation.paperId];
        
        // Only paper submitter or contract owner can reveal
        require(
            msg.sender == paper.submitter || msg.sender == owner(),
            "Not authorized to reveal this evaluation"
        );
        
        return FHE.decrypt(evaluation.recommendation);
    }

    /**
     * @dev Reveal encrypted scores for authorized parties
     * @param evaluationId ID of the evaluation to reveal
     * @return Decrypted scores (originality, quality, clarity, significance)
     */
    function revealScores(uint256 evaluationId) 
        external 
        view 
        returns (uint8, uint8, uint8, uint8) 
    {
        require(evaluationId > 0 && evaluationId <= evaluationCount, "Invalid evaluation ID");
        
        EncryptedEvaluation memory evaluation = evaluations[evaluationId];
        Paper memory paper = papers[evaluation.paperId];
        
        // Only paper submitter or contract owner can reveal
        require(
            msg.sender == paper.submitter || msg.sender == owner(),
            "Not authorized to reveal this evaluation"
        );
        
        return (
            FHE.decrypt(evaluation.originality),
            FHE.decrypt(evaluation.quality),
            FHE.decrypt(evaluation.clarity),
            FHE.decrypt(evaluation.significance)
        );
    }

    /**
     * @dev Get public information about an evaluation (non-encrypted data only)
     * @param evaluationId ID of the evaluation
     * @return paperId, reviewer, comments, timestamp
     */
    function getEvaluationInfo(uint256 evaluationId) 
        external 
        view 
        returns (uint256, address, string memory, uint256) 
    {
        require(evaluationId > 0 && evaluationId <= evaluationCount, "Invalid evaluation ID");
        
        EncryptedEvaluation memory evaluation = evaluations[evaluationId];
        return (
            evaluation.paperId,
            evaluation.reviewer,
            evaluation.comments,
            evaluation.timestamp
        );
    }

    /**
     * @dev Get paper information
     * @param paperId ID of the paper
     * @return Paper struct data
     */
    function getPaper(uint256 paperId) 
        external 
        view 
        returns (Paper memory) 
    {
        require(paperId > 0 && paperId <= paperCount, "Invalid paper ID");
        return papers[paperId];
    }

    /**
     * @dev Get evaluation IDs for a specific paper
     * @param paperId ID of the paper
     * @return Array of evaluation IDs
     */
    function getPaperEvaluations(uint256 paperId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        require(paperId > 0 && paperId <= paperCount, "Invalid paper ID");
        return paperEvaluations[paperId];
    }

    /**
     * @dev Get evaluation IDs for a specific reviewer
     * @param reviewer Address of the reviewer
     * @return Array of evaluation IDs
     */
    function getReviewerEvaluations(address reviewer) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return reviewerEvaluations[reviewer];
    }

    /**
     * @dev Get total number of evaluations
     * @return Total evaluation count
     */
    function getEvaluationCount() external view returns (uint256) {
        return evaluationCount;
    }

    /**
     * @dev Get total number of papers
     * @return Total paper count
     */
    function getPaperCount() external view returns (uint256) {
        return paperCount;
    }

    /**
     * @dev Get number of active reviewers
     * @return Active reviewer count
     */
    function getActiveReviewers() external view returns (uint256) {
        return activeReviewers;
    }

    /**
     * @dev Deactivate a paper (only owner)
     * @param paperId ID of the paper to deactivate
     */
    function deactivatePaper(uint256 paperId) external onlyOwner {
        require(paperId > 0 && paperId <= paperCount, "Invalid paper ID");
        papers[paperId].isActive = false;
    }

    /**
     * @dev Reactivate a paper (only owner)
     * @param paperId ID of the paper to reactivate
     */
    function reactivatePaper(uint256 paperId) external onlyOwner {
        require(paperId > 0 && paperId <= paperCount, "Invalid paper ID");
        papers[paperId].isActive = true;
    }

    /**
     * @dev Emergency function to pause evaluations (only owner)
     */
    function emergencyPause() external onlyOwner {
        // Implementation for emergency pause functionality
        // This could disable new evaluations while allowing reads
    }
}