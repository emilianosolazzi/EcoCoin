// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title EcoCoin
 * @dev ERC20 Token for various environmental impact projects.
 * Coded by Emiliano Solazzi, 2024. All rights reserved.
 *
 * LICENSE: This code is licensed under the MIT License.
 * Ownership of this code belongs to Emiliano Solazzi. 
 * Permission from Emiliano Solazzi is required for any commercial or 
 * non-commercial usage beyond the terms set by the MIT License. 
 * For questions on licensing and use permissions, contact Emiliano Solazzi. main@bitcoincab.net
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title EcoCoin
 * @dev ERC20 Token for various environmental impact projects
 * Supports multiple project types including but not limited to:
 * - Carbon Credits
 * - Renewable Energy
 * - Ocean Cleanup
 * - Reforestation
 * - Biodiversity Protection
 * - Sustainable Agriculture
 */
contract EcoCoin is ERC20, ERC20Burnable, ERC20Pausable, AccessControl, ReentrancyGuard {
    uint256 private constant INITIAL_SUPPLY = 10_000_000 * 1e18;
    uint256 private constant MAX_SUPPLY = 1_000_000_000 * 1e18;
    
    uint256 private _ecoFeePercentage = 150; // 1.5% initial fee (150 basis points)
    address private _feeRecipient;
    uint256 private _accumulatedFees;
    
    uint256 public constant MAX_FEE_PERCENTAGE = 500; // 5% maximum fee
    uint256 public constant MINIMUM_FEE = 1e16; // Minimum fee threshold (0.01 tokens)

    enum ProjectCategory {
        CarbonCredit,
        RenewableEnergy,
        OceanCleanup,
        Reforestation,
        Biodiversity,
        SustainableAg,
        WasteManagement,
        WaterConservation
    }

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant PROJECT_MANAGER_ROLE = keccak256("PROJECT_MANAGER_ROLE");

    uint256 private constant TIMELOCK_DELAY = 2 days;
    mapping(bytes32 => uint256) private _pendingOperations;
    
    struct Project {
        string name;
        ProjectCategory category;
        string description;
        string location;
        address projectOwner;
        uint256 verifiedImpact;
        string impactMetric;
        uint256 tokensIssued;
        bool active;
        mapping(address => bool) authorizedVerifiers;
    }
    
    struct ImpactReport {
        uint256 timestamp;
        uint256 impactAmount;
        string evidence;
        address verifier;
    }
    
    mapping(uint256 => Project) public projects;
    mapping(uint256 => ImpactReport[]) public projectReports;
    mapping(ProjectCategory => uint256) public categoryMultipliers;
    uint256 public nextProjectId;

    event ProjectRegistered(uint256 indexed projectId, string name, ProjectCategory indexed category, address indexed projectOwner);
    event ImpactReported(uint256 indexed projectId, uint256 impactAmount, string evidence, address indexed verifier);
    event TokensMinted(address indexed to, uint256 amount, uint256 indexed projectId, ProjectCategory indexed category);
    event ProjectVerifierAdded(uint256 indexed projectId, address indexed verifier);
    event ProjectVerifierRemoved(uint256 indexed projectId, address indexed verifier);
    event CategoryMultiplierUpdated(ProjectCategory indexed category, uint256 multiplier);
    event EcoFeePercentageUpdated(uint256 newPercentage);
    event FeeRecipientUpdated(address indexed newRecipient);
    event FeesCollected(address indexed from, address indexed to, uint256 amount);
    event FeesWithdrawn(address indexed recipient, uint256 amount);
    event ProjectDeactivated(uint256 indexed projectId);
    event ProjectReactivated(uint256 indexed projectId);

    constructor(address admin) ERC20("EcoCoin", "ECO") {
        require(admin != address(0), "Admin address cannot be zero");
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(FEE_MANAGER_ROLE, admin);
        _grantRole(VERIFIER_ROLE, admin);
        _grantRole(PROJECT_MANAGER_ROLE, admin);

        _mint(admin, INITIAL_SUPPLY);
        _feeRecipient = admin;

        categoryMultipliers[ProjectCategory.CarbonCredit] = 1e18;
        categoryMultipliers[ProjectCategory.RenewableEnergy] = 1e17;
        categoryMultipliers[ProjectCategory.OceanCleanup] = 2e18;
        categoryMultipliers[ProjectCategory.Reforestation] = 5e17;
        categoryMultipliers[ProjectCategory.Biodiversity] = 1e19;
        categoryMultipliers[ProjectCategory.SustainableAg] = 3e17;
        categoryMultipliers[ProjectCategory.WasteManagement] = 5e17;
        categoryMultipliers[ProjectCategory.WaterConservation] = 2e17;
    }

    function registerProject(
        string memory name,
        ProjectCategory category,
        string memory description,
        string memory location,
        string memory impactMetric,
        address projectOwner
    ) external onlyRole(PROJECT_MANAGER_ROLE) returns (uint256) {
        require(bytes(name).length > 0, "Project name required");
        require(projectOwner != address(0), "Invalid project owner");
        
        uint256 projectId = nextProjectId++;
        Project storage newProject = projects[projectId];
        
        newProject.name = name;
        newProject.category = category;
        newProject.description = description;
        newProject.location = location;
        newProject.projectOwner = projectOwner;
        newProject.impactMetric = impactMetric;
        newProject.active = true;
        
        emit ProjectRegistered(projectId, name, category, projectOwner);
        return projectId;
    }

    function addProjectVerifier(uint256 projectId, address verifier) external onlyRole(PROJECT_MANAGER_ROLE) {
        require(verifier != address(0), "Invalid verifier address");
        require(projects[projectId].active, "Project not active");
        
        projects[projectId].authorizedVerifiers[verifier] = true;
        emit ProjectVerifierAdded(projectId, verifier);
    }

    function reportImpact(
        uint256 projectId,
        uint256 impactAmount,
        string memory evidence
    ) external {
        Project storage project = projects[projectId];
        require(project.active, "Project not active");
        require(project.authorizedVerifiers[msg.sender], "Not authorized verifier");
        
        project.verifiedImpact += impactAmount;
        
        ImpactReport memory report = ImpactReport({
            timestamp: block.timestamp,
            impactAmount: impactAmount,
            evidence: evidence,
            verifier: msg.sender
        });
        
        projectReports[projectId].push(report);
        
        emit ImpactReported(projectId, impactAmount, evidence, msg.sender);
    }

    function mintImpactTokens(uint256 projectId, uint256 impactAmount) external onlyRole(MINTER_ROLE) {
        Project storage project = projects[projectId];
        require(project.active, "Project not active");
        require(project.verifiedImpact >= project.tokensIssued + impactAmount, "Impact not verified");
        
        uint256 tokenAmount = (impactAmount * categoryMultipliers[project.category]) / 1e18;
        require(totalSupply() + tokenAmount <= MAX_SUPPLY, "Exceeds max supply");
        
        project.tokensIssued += impactAmount;
        _mint(project.projectOwner, tokenAmount);
        
        emit TokensMinted(project.projectOwner, tokenAmount, projectId, project.category);
    }

    function updateCategoryMultiplier(ProjectCategory category, uint256 multiplier) external onlyRole(PROJECT_MANAGER_ROLE) {
        categoryMultipliers[category] = multiplier;
        emit CategoryMultiplierUpdated(category, multiplier);
    }

    function deactivateProject(uint256 projectId) external onlyRole(PROJECT_MANAGER_ROLE) {
        require(projects[projectId].active, "Project already inactive");
        projects[projectId].active = false;
        emit ProjectDeactivated(projectId);
    }

    function scheduleEcoFeeUpdate(uint256 newPercentage) external onlyRole(FEE_MANAGER_ROLE) {
        require(newPercentage <= MAX_FEE_PERCENTAGE, "Fee exceeds maximum");
        
        bytes32 operationId = keccak256(abi.encode("UPDATE_FEE", newPercentage));
        _pendingOperations[operationId] = block.timestamp + TIMELOCK_DELAY;
        
        emit EcoFeePercentageUpdated(newPercentage);
    }

    function executeEcoFeeUpdate(uint256 newPercentage) external onlyRole(FEE_MANAGER_ROLE) {
        bytes32 operationId = keccak256(abi.encode("UPDATE_FEE", newPercentage));
        require(_pendingOperations[operationId] > 0, "No pending update");
        require(block.timestamp >= _pendingOperations[operationId], "Timelock not passed");
        
        _ecoFeePercentage = newPercentage;
        delete _pendingOperations[operationId];
        
        emit EcoFeePercentageUpdated(newPercentage);
    }

    function _calculateFee(uint256 amount) internal view returns (uint256) {
        uint256 fee = (amount * _ecoFeePercentage) / 10000;
        return fee < MINIMUM_FEE ? MINIMUM_FEE : fee;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual override {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");

        if (from != address(this) && to != address(this) && from != _feeRecipient && _ecoFeePercentage > 0) {
            uint256 fee = _calculateFee(amount);
            require(amount > fee, "Transfer amount too small");

            super._transfer(from, address(this), fee);
            _accumulatedFees += fee;
            
            super._transfer(from, to, amount - fee);
            emit FeesCollected(from, to, fee);
        } else {
            super._transfer(from, to, amount);
        }
    }

    function withdrawAccumulatedFees() external nonReentrant {
        require(msg.sender == _feeRecipient, "Only fee recipient");
        require(_accumulatedFees > 0, "No fees to withdraw");
        
        uint256 amount = _accumulatedFees;
        _accumulatedFees = 0;
        
        _transfer(address(this), _feeRecipient, amount);
        emit FeesWithdrawn(_feeRecipient, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
