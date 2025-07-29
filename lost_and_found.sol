// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Lost and Found DAO
 * @dev A decentralized platform for reporting lost items and incentivizing their recovery
 * @author Lost and Found DAO Team
 */
contract Project is ReentrancyGuard, Ownable {
    
    // State variables
    uint256 private itemCounter;
    uint256 public platformFeePercent = 5; // 5% platform fee
    
    /**
     * @dev Constructor sets the deployer as the initial owner
     */
    constructor() Ownable(msg.sender) {
        // Contract is initialized with deployer as owner
    }
    
    enum ItemStatus { 
        Lost, 
        Found, 
        Returned, 
        Cancelled 
    }
    
    struct LostItem {
        uint256 id;
        address owner;
        string description;
        uint256 bountyAmount;
        ItemStatus status;
        address finder;
        uint256 timestamp;
        bool isActive;
    }
    
    // Mappings
    mapping(uint256 => LostItem) public lostItems;
    mapping(address => uint256[]) public userItems;
    mapping(address => uint256) public userReputation;
    
    // Events
    event ItemReported(uint256 indexed itemId, address indexed owner, uint256 bounty);
    event ItemFound(uint256 indexed itemId, address indexed finder);
    event ItemReturned(uint256 indexed itemId, address indexed owner, address indexed finder, uint256 bounty);
    event BountyUpdated(uint256 indexed itemId, uint256 newBounty);
    
    /**
     * @dev Core Function 1: Report a lost item with bounty
     * @param _description Description of the lost item
     * @param _bountyAmount Amount offered as reward for finding the item
     */
    function reportLostItem(
        string memory _description, 
        uint256 _bountyAmount
    ) external payable nonReentrant returns (uint256) {
        require(bytes(_description).length > 0, "Description cannot be empty");
        require(_bountyAmount > 0, "Bounty must be greater than 0");
        require(msg.value >= _bountyAmount, "Insufficient payment for bounty");
        
        itemCounter++;
        uint256 itemId = itemCounter;
        
        lostItems[itemId] = LostItem({
            id: itemId,
            owner: msg.sender,
            description: _description,
            bountyAmount: _bountyAmount,
            status: ItemStatus.Lost,
            finder: address(0),
            timestamp: block.timestamp,
            isActive: true
        });
        
        userItems[msg.sender].push(itemId);
        
        emit ItemReported(itemId, msg.sender, _bountyAmount);
        return itemId;
    }
    
    /**
     * @dev Core Function 2: Claim that you found a lost item
     * @param _itemId ID of the item claimed to be found
     */
    function claimItemFound(uint256 _itemId) external nonReentrant {
        LostItem storage item = lostItems[_itemId];
        
        require(item.isActive, "Item is not active");
        require(item.status == ItemStatus.Lost, "Item is not in lost status");
        require(item.owner != msg.sender, "Cannot claim your own item");
        require(item.finder == address(0), "Item already claimed by someone");
        
        item.status = ItemStatus.Found;
        item.finder = msg.sender;
        
        emit ItemFound(_itemId, msg.sender);
    }
    
    /**
     * @dev Core Function 3: Confirm item return and release bounty
     * @param _itemId ID of the item to confirm return
     */
    function confirmItemReturn(uint256 _itemId) external nonReentrant {
        LostItem storage item = lostItems[_itemId];
        
        require(msg.sender == item.owner, "Only item owner can confirm return");
        require(item.status == ItemStatus.Found, "Item must be in found status");
        require(item.finder != address(0), "No finder assigned");
        
        // Calculate platform fee and finder reward
        uint256 platformFee = (item.bountyAmount * platformFeePercent) / 100;
        uint256 finderReward = item.bountyAmount - platformFee;
        
        // Update item status
        item.status = ItemStatus.Returned;
        item.isActive = false;
        
        // Update reputations
        userReputation[item.owner] += 1;
        userReputation[item.finder] += 2; // Finders get more reputation points
        
        // Transfer payments
        payable(item.finder).transfer(finderReward);
        payable(owner()).transfer(platformFee);
        
        emit ItemReturned(_itemId, item.owner, item.finder, finderReward);
    }
    
    // Additional utility functions
    
    /**
     * @dev Get all items for a specific user
     * @param _user Address of the user
     * @return Array of item IDs owned by the user
     */
    function getUserItems(address _user) external view returns (uint256[] memory) {
        return userItems[_user];
    }
    
    /**
     * @dev Get details of a specific item
     * @param _itemId ID of the item
     * @return LostItem struct containing all item details
     */
    function getItemDetails(uint256 _itemId) external view returns (LostItem memory) {
        return lostItems[_itemId];
    }
    
    /**
     * @dev Get total number of items reported
     * @return Total count of items
     */
    function getTotalItems() external view returns (uint256) {
        return itemCounter;
    }
    
    /**
     * @dev Update platform fee (only owner)
     * @param _newFeePercent New fee percentage
     */
    function updatePlatformFee(uint256 _newFeePercent) external onlyOwner {
        require(_newFeePercent <= 10, "Fee cannot exceed 10%");
        platformFeePercent = _newFeePercent;
    }
    
    /**
     * @dev Emergency function to cancel item (only by owner or item owner)
     * @param _itemId ID of the item to cancel
     */
    function cancelItem(uint256 _itemId) external nonReentrant {
        LostItem storage item = lostItems[_itemId];
        
        require(
            msg.sender == item.owner || msg.sender == owner(), 
            "Only item owner or contract owner can cancel"
        );
        require(item.status == ItemStatus.Lost, "Can only cancel lost items");
        
        item.status = ItemStatus.Cancelled;
        item.isActive = false;
        
        // Refund bounty to item owner (minus small cancellation fee)
        uint256 cancellationFee = (item.bountyAmount * 2) / 100; // 2% cancellation fee
        uint256 refundAmount = item.bountyAmount - cancellationFee;
        
        payable(item.owner).transfer(refundAmount);
        payable(owner()).transfer(cancellationFee);
    }
}
