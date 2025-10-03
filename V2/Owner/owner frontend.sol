// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./employe_assignment.sol";

/**
 * @title Owner Address
 * @notice Manages contract ownership and employee assignment
 * @dev 
 * - Inherits {employe_assignment}
 * - Uses {AddressUtils} for zero address checks
 */
contract owner_address is EmployeeAssignment {

    // ================================
    // State Variables
    // ================================

    /// @notice The current owner of the contract
    address private _owner;

    // ================================
    // Events
    // ================================

    /**
     * @notice Emitted when the contract ownership is changed
     * @param old_owner The previous owner address
     * @param new_owner The new owner address
     */
    event owner_changed(address indexed old_owner, address indexed new_owner);

    // ================================
    // Constructor
    // ================================

    /**
     * @notice Initializes the contract and sets the deployer as the initial owner
     */
    constructor() {
        _owner = msg.sender;
    }

    // ================================
    // Modifiers
    // ================================
    // (Modifiers inherited from parent contracts, no custom modifier here)

    // ================================
    // Owner Functions
    // ================================

    /**
     * @notice Transfers ownership of the contract to a new address
     * @dev 
     * - Only callable by the current owner
     * - New owner address must not be zero
     *
     * Emits a {owner_changed} event
     *
     * @param new_owner The address of the new owner
     */
    function change_owner(address new_owner) 
        public 
        virtual 
        onlyOwner   
    {
        caller_zero_Address(msg.sender);
        caller_zero_Address(new_owner);

        address old = _owner;
        _owner = new_owner;

        emit owner_changed(old, new_owner);
    }

    /**
     * @notice Returns the current owner address
     * @dev Callable by anyone, but protected against zero caller (via modifier)
     * @return The current owner address
     */
    function see_owner() 
        public 
        virtual 
        view  
        returns (address) 
    {
        caller_zero_Address(msg.sender);
        return _owner;
    }

}
