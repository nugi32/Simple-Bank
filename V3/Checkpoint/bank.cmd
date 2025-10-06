// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Interface/Ibank.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../Owner/employe_assignment.sol";
import "../lib/regular.sol";

/**
 * @title Abstract Banking System
 * @author nugi
 * @notice Provides core banking features including user registration, deposits, withdrawals, and transfers
 * @dev This contract is abstract and must be extended to implement additional banking features
 *      Inherits access control from employe_assignment and security from ReentrancyGuard
 */
abstract contract bank is ReentrancyGuard, EmployeeAssignment{

    /**
     * @notice User profile structure containing personal information and account balance
     * @param name User's full name
     * @param age User's age (must be between 18-99)
     * @param isRegistered Whether the user has completed registration
     * @param balance User's account balance in wei
     */
    struct user {
        string name;
        uint8 age;
        bool isRegistered;
        uint balance; // internal balance in wei
    }

    /// @notice Maps user addresses to their profile and balance information
    mapping(address => user) internal users;

    /// @notice Total number of registered users
    uint internal usercount;

    /// @notice Wallet address that receives all collected fees
    address payable internal managementWallet;

    /// @notice Total accumulated fees awaiting withdrawal
    uint internal collectedFees;

    /// @notice Percentage fee charged on transfers (1 = 1%)
    uint internal transferFeePercent;

    /// @notice Percentage fee charged on deposits (1 = 1%)
    uint internal depositFeePercent;

    /**
     * @notice Emitted when management wallet address is set or changed
     * @param managementWallet Address of the management wallet
     */
    event managementWallet_address(address indexed managementWallet);

    /**
     * @notice Emitted when a new user registers with the bank
     * @param user Address of the newly registered user
     * @param name User's registered name
     * @param age User's registered age
     */
    event User_registered(address indexed user, string indexed name, uint8 indexed age);

    /**
     * @notice Emitted when a user unregisters from the bank
     * @param user Address of the unregistered user
     * @param name User's name at time of unregistration
     * @param age User's age at time of unregistration
     */
    event User_unregistered(address indexed user, string indexed name, uint8 indexed age);

    /**
     * @notice Emitted when a user deposits funds
     * @param user Address of the depositing user
     * @param netAmount Amount deposited after fees
     */
    event User_deposit(address indexed user, uint indexed netAmount);

    /**
     * @notice Emitted when a user withdraws funds
     * @param user Address of the withdrawing user
     * @param amount Amount withdrawn
     */
    event User_withdraw(address indexed user, uint indexed amount);

    /**
     * @notice Emitted when a user transfers funds to another user
     * @param user Address of the sender
     * @param to Address of the recipient
     * @param amount Amount transferred
     */
    event User_transfer(address indexed user, address indexed to, uint indexed amount);

    /**
     * @notice Emitted when profits are withdrawn to the management wallet
     * @param amount Amount of profits withdrawn
     */
    event profit_withdraw(uint indexed amount);

    /**
     * @notice Emitted when deposit fee percentage is changed
     * @param oldFee Previous fee percentage
     * @param newFee New fee percentage
     */
    event deposit_fee_changed(uint indexed oldFee, uint indexed newFee);

    /**
     * @notice Emitted when transfer fee percentage is changed
     * @param oldFee Previous fee percentage
     * @param newFee New fee percentage
     */
    event transfer_fee_changed(uint indexed oldFee, uint indexed newFee);

    /**
     * @notice Restricts function access to registered users only
     */
    modifier onlyRegistered() {
        require(users[msg.sender].isRegistered, "Not registered");
        _;
    }

    /**
     * @notice Initializes the bank contract with a management wallet for fee collection
     * @param _management_Wallet Address that will receive collected fees
     * @dev Sets initial fee percentages to 1%
     */
    constructor(address payable _management_Wallet) {
        require(_management_Wallet != address(0), "Err: input correct management wallet addrs!");
        managementWallet = _management_Wallet;
        transferFeePercent = 1;
        depositFeePercent = 1;
        emit managementWallet_address(managementWallet);
    }

    /**
     * @notice Allows a new user to register with the bank
     * @param name User's full name
     * @param age User's age (must be between 18-99)
     * @dev Increases usercount upon successful registration
     */
    function register(string calldata name, uint8 age) 
        external 
        notEmployes  
        notOwner
    {
        caller_zero_Address(msg.sender);
        require(age > 17, "Too young!");
        require(age < 100, "Too old!");
        user storage u = users[msg.sender];
        require(!u.isRegistered, "Already registered");
        
        u.name = name;
        u.age = age;
        u.isRegistered = true;
        usercount++;
        
        emit User_registered(msg.sender, name, age);
    }

    /**
     * @notice Allows a registered user to close their account and withdraw remaining funds
     * @dev Refunds any remaining balance to the user's address
     */
    function unregister() 
        external 
        onlyRegistered 
        notEmployes  
        notOwner 
        nonReentrant
    {
        caller_zero_Address(msg.sender);
        user storage u = users[msg.sender];
        uint refund = u.balance;
        
        // Update state before external call
        u.balance = 0;
        u.isRegistered = false;
        usercount--;
        
        // Process refund if balance exists
        if (refund > 0) {
            (bool sent, ) = payable(msg.sender).call{value: refund}("");
            require(sent, "Refund failed");
        }
        
        emit User_unregistered(msg.sender, u.name, u.age);
    }

    /**
     * @notice Allows a user to deposit ETH into their bank account
     * @dev A deposit fee is deducted from the deposited amount
     */
    function deposit() 
        external 
        payable 
        onlyRegistered 
        notEmployes  
        notOwner
    {
        caller_zero_Address(msg.sender);
        regular.greater_than_0(msg.value);
        
        uint fee = (msg.value * depositFeePercent) / 100;
        uint netAmount = msg.value - fee;
        
        collectedFees += fee;
        users[msg.sender].balance += netAmount;
        
        emit User_deposit(msg.sender, netAmount);
    }

    /**
     * @notice Allows a user to withdraw ETH from their bank account
     * @param amount Amount to withdraw in wei
     * @dev Checks for sufficient balance before processing withdrawal
     */
    function withdraw(uint amount) 
        external 
        onlyRegistered 
        notEmployes 
        notOwner 
        nonReentrant
    {
        caller_zero_Address(msg.sender);
        regular.greater_than_0(amount);
        
        user storage u = users[msg.sender];
        require(u.balance >= amount, "Insufficient balance");
        
        // Update state before external call
        u.balance -= amount;
        
        // Process withdrawal
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdraw failed");
        
        emit User_withdraw(msg.sender, amount);
    }

    /**
     * @notice Transfers funds from sender to another registered user
     * @param to The address of the recipient
     * @param amount The amount to transfer in wei
     * @dev A transfer fee is deducted from the sender's balance
     */
    function transfer(address payable to, uint amount) 
        external
        onlyRegistered 
        notEmployes  
        notOwner 
        nonReentrant
    {
        // Validate inputs
        caller_zero_Address(msg.sender);
        caller_zero_Address(to);
        regular.greater_than_0(amount);
        require(users[to].isRegistered, "Recipient not registered");
        require(to != msg.sender, "Cannot transfer to self");
        
        // Calculate fee
        uint fee = (amount * transferFeePercent) / 100;
        uint totalDeduction = amount + fee;
        
        // Check sufficient balance
        user storage sender = users[msg.sender];
        require(sender.balance >= totalDeduction, "Insufficient balance for amount + fee");
        
        // Update state before external interactions
        sender.balance -= totalDeduction;
        collectedFees += fee;
        
        // Send ETH
        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");
        
        // Emit event
        emit User_transfer(msg.sender, to, amount);
    }

    /**
     * @notice Allows a user to check their current account balance
     * @return User's current balance in wei
     */
    function seeMyBalance() 
        external 
        view 
        onlyRegistered 
        notEmployes 
        notOwner 
        returns (uint) 
    {
        caller_zero_Address(msg.sender);
        return users[msg.sender].balance;
    }



//==============================================  ADMIN AREA  ========================================================
    /**
     * @notice Allows authorized employees to withdraw collected fees to the management wallet
     * @dev Resets collectedFees to zero after successful withdrawal
     */
    function withdrawCollectedFees() 
        external 
        onlyemployes  
        nonReentrant
    {
        caller_zero_Address(msg.sender);
        uint amount = collectedFees;
        
        // Update state before external call
        collectedFees = 0;
        
        // Process transfer
        (bool sent, ) = managementWallet.call{value: amount}("");
        require(sent, "Fee transfer failed");
        
        emit profit_withdraw(amount);
    }

    /**
     * @notice Sets the deposit fee percentage
     * @param _newDepositFeePercent New deposit fee percentage (1 = 1%)
     * @dev Maximum fee is capped at 100%
     */
    function set_deposit_fee_percent(uint _newDepositFeePercent) 
        external 
        onlyemployes 
    {
        caller_zero_Address(msg.sender);
        require(_newDepositFeePercent <= 100, "Fee too high");
        
        uint oldFee = depositFeePercent;
        depositFeePercent = _newDepositFeePercent;
        
        emit deposit_fee_changed(oldFee, _newDepositFeePercent);
    }

    /**
     * @notice Sets the transfer fee percentage
     * @param _newTransferFeePercent New transfer fee percentage (1 = 1%)
     * @dev Maximum fee is capped at 100%
     */
    function set_transfer_fee_percent(uint _newTransferFeePercent) 
        external 
        onlyemployes 
    {
        caller_zero_Address(msg.sender);
        require(_newTransferFeePercent <= 100, "Fee too high");
        
        uint oldFee = transferFeePercent;
        transferFeePercent = _newTransferFeePercent;
        
        emit transfer_fee_changed(oldFee, _newTransferFeePercent);
    }

    /**
     * @notice Returns the contract's current ETH balance in whole ether
     * @return Contract balance in ether (not wei)
     */
    function see_Contract_Balances() 
        external 
        view 
        onlyemployes 
        returns (uint) 
    {
        caller_zero_Address(msg.sender);
        return address(this).balance / 1 ether;
    }

    /**
     * @notice Returns the total number of registered users
     * @return Count of registered users
     */
    function totalUsers() 
        external 
        view 
        onlyemployes 
        returns (uint) 
    {
        caller_zero_Address(msg.sender);
        return usercount;
    }
}