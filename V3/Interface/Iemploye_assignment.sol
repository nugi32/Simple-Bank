// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Employee Assignment Interface
/// @notice Interface for role-based access control with owner and employee management
/// @dev Provides function definitions for employee role management and ownership control
interface IEmployeeAssignment {
    
    // ================================
    // Events
    // ================================
    
    /// @notice Emitted when a new employee is assigned
    /// @param employee The address of the newly assigned employee
    /// @param role The role assigned to the employee
    event EmployeeAssigned(address indexed employee, string role);
    
    /// @notice Emitted when an employee is removed
    /// @param employee The address of the removed employee
    /// @param role The role that was removed
    event EmployeeRemoved(address indexed employee, string role);
    
    /// @notice Emitted when the contract owner is changed
    /// @param oldOwner The address of the previous owner
    /// @param newOwner The address of the new owner
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    
    // ================================
    // State Variables Getters
    // ================================
    
    /// @notice Get total number of employees currently assigned
    /// @return uint Total employee count
    function employeeCount() external view returns (uint);
    
    // ================================
    // Employee Management Functions
    // ================================
    
    /**
     * @notice Assigns a new employee with a specific role
     * @dev Only the owner can assign new employees
     * @param newEmployee Address of the employee to be assigned
     * @param role Role to assign to the employee
     */
    function assignNewEmployee(address newEmployee, string calldata role) external;
    
    /**
     * @notice Removes an employee's role
     * @dev Only the owner can remove employee roles
     * @param employee Address of the employee to remove the role from
     * @param role Role to remove from the employee
     */
    function removeEmployee(address employee, string calldata role) external;
    
    /**
     * @notice Checks if an address has a specific role
     * @param account Address to check
     * @param role Role to check for
     * @return bool True if the account has the specified role
     */
    function hasRole(address account, string calldata role) external view returns (bool);
    
    // ================================
    // Ownership Management Functions
    // ================================
    
    /**
     * @notice Transfers ownership to a new address
     * @dev Only the current owner can call this function
     * @param newOwner Address of the new owner
     */
    function changeOwner(address newOwner) external;
}