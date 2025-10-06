// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Bank Interface
 * @author nugi
 * @notice Interface defining the core banking functionality
 * @dev This interface captures all external functions of the abank contract
 */
interface Ibank {
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
     * @notice Allows a new user to register with the bank
     * @param name User's full name
     * @param age User's age (must be between 18-99)
     */
    function register(string calldata name, uint8 age) external;

    /**
     * @notice Allows a registered user to close their account and withdraw remaining funds
     */
    function unregister() external;

    /**
     * @notice Allows a user to deposit ETH into their bank account
     */
    function deposit() external payable;

    /**
     * @notice Allows a user to withdraw ETH from their bank account
     * @param amount Amount to withdraw in wei
     */
    function withdraw(uint amount) external;

    /**
     * @notice Transfers funds from sender to another registered user
     * @param to The address of the recipient
     * @param amount The amount to transfer in wei
     */
    function transfer(address payable to, uint amount) external;

    /**
     * @notice Allows a user to check their current account balance
     * @return User's current balance in wei
     */
    function seeMyBalance() external view returns (uint);

    /**
     * @notice Allows authorized employees to withdraw collected fees to the management wallet
     */
    function withdrawCollectedFees() external;

    /**
     * @notice Sets the deposit fee percentage
     * @param _newDepositFeePercent New deposit fee percentage (1 = 1%)
     */
    function set_deposit_fee_percent(uint _newDepositFeePercent) external;

    /**
     * @notice Sets the transfer fee percentage
     * @param _newTransferFeePercent New transfer fee percentage (1 = 1%)
     */
    function set_transfer_fee_percent(uint _newTransferFeePercent) external;

    /**
     * @notice Returns the contract's current ETH balance in whole ether
     * @return Contract balance in ether (not wei)
     */
    function see_Contract_Balances() external view returns (uint);

    /**
     * @notice Returns the total number of registered users
     * @return Count of registered users
     */
    function totalUsers() external view returns (uint);
}