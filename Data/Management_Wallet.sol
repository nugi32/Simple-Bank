// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Owner/AccesControl.sol";
import "../lib/regular.sol";

/// @title Management Wallet
/// @notice Handles fund storage and controlled transfers between the loan contract and the owner wallet
/// @dev Inherits ownership & employee access control from `employe_assignment`
///@notice this is deployed contract for admind and not data storage only
contract manajement_wallet is AccesControl {

    /// @notice Address of the loan contract that receives allocated funds
    address payable internal loan_contract;

    /// @notice Initializes the management wallet with the linked loan contract
    /// @param _loan_contract Address of the loan contract
    constructor(address payable _loan_contract) {
        loan_contract = _loan_contract;
    }
modifier caller_zero_Address() {
    zero_Address(msg.sender);
    _;
}
    // ================================
    // ------------- TRANSFERS -------------
    // ================================

    /// @notice Transfer ETH from this wallet to the loan contract
    /// @dev Only callable by employees. Validates amount > 0 and sufficient balance before sending.
    /// @param amount Amount in wei to transfer
    function transfer_to_loan_contract(uint amount) 
        external 
        onlyEmployes 
        caller_zero_Address 
    {
        regular.greater_than_0(amount);
        require(address(this).balance >= amount, "insufficient balance");

        (bool success, ) = loan_contract.call{value: amount}("");
        require(success, "transfer to loan contract failed");
    }

    /// @notice Change the linked loan contract address
    /// @param new_loan_contract New loan contract address
    function change_loan_contract(address payable new_loan_contract) 
        external  
        onlyEmployes 
        caller_zero_Address 
    {
         zero_Address(new_loan_contract);
        loan_contract = new_loan_contract;
    }

    // ================================
    // ------------- VIEW FUNCTIONS -------------
    // ================================

    /// @notice Returns the current contract balance in ETH
    /// @dev Access restricted to employees
    /// @return balances Current balance expressed in whole ETH
    function see_contract_balances() 
        external 
        view 
        onlyEmployes 
        caller_zero_Address 
        returns (uint balances) 
    {
        balances = address(this).balance / 1 ether;
    }

    // ================================
    // ------------- RECEIVE ETH -------------
    // ================================

    /// @notice Fallback function to accept plain ETH transfers
    fallback() external payable {}

    /// @notice Receive function to accept ETH sent via `.send()` or `.transfer()`
    receive() external payable {}
}
