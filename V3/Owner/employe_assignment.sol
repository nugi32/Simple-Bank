// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Interface/Iemploye_assignment.sol";

/// @title Employee Assignment and Management Contract
/// @notice Provides role-based access control with an owner and assigned employees
/// @dev Abstract contract that can be inherited by other contracts to enforce employee-only actions
abstract contract EmployeeAssignment {
    
    // ================================
    // State Variables
    // ================================
    
    /// @notice Address of the contract owner
    address internal owner = msg.sender;
    
    /// @notice Total number of employees currently assigned
    uint public employeeCount;
    
    /// @notice Mapping to track employee roles (address => role => hasRole)
    mapping(address => mapping(string => bool)) internal employees;
    
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
    // Modifiers
    // ================================
    
    /// @notice Ensures that only the contract owner can call the function
    modifier onlyOwner() {
        require(msg.sender == owner, "EmployeeAssignment: caller is not the owner");
        _;
    }
    
    /// @notice Ensures that the caller is not the owner
    modifier notOwner() {
        require(msg.sender != owner, "EmployeeAssignment: caller is the owner");
        _;
    }
    
    /// @notice Ensures that only employees with Admin role can call the function
    modifier onlyEmployes() {
        require(employees[msg.sender]["Admin"], "EmployeeAssignment: caller is not an admin");
        _;
    }
    
    /// @notice Ensures that the caller is not an employee with Admin role
    modifier notEmployes() {
        require(!employees[msg.sender]["Admin"], "EmployeeAssignment: caller is an admin");
        _;
    }
    
    // ================================
    // Internal Functions
    // ================================
    
    /**
     * @notice Validates that an address is not the zero address
     * @dev Internal helper function for address validation
     * @param x Address to validate
     */
    function zero_Address(address x) internal pure {
        require(x != address(0), "EmployeeAssignment: zero address not allowed");
    }
    
    // ================================
    // External Functions
    // ================================
    
    /**
     * @notice Assigns a new employee with a specific role
     * @dev Only the owner can assign new employees. Validates role and address.
     * @param newEmployee Address of the employee to be assigned
     * @param role Role to assign to the employee
     */
    function assignNewEmployee(address newEmployee, string calldata role) external onlyOwner {
        // Validate that the role is "Employe"
        require(keccak256(bytes(role)) == keccak256(bytes("Employe")), "EmployeeAssignment: invalid role");
        
        // Validate that employee address is not zero
        require(newEmployee != address(0), "EmployeeAssignment: employee cannot be zero address");
        
        // Validate that employee doesn't already have this role
        require(!employees[newEmployee][role], "EmployeeAssignment: employee already has this role");
        
        // Assign the role to the employee
        employees[newEmployee][role] = true;
        employeeCount++;
        
        // Emit assignment event
        emit EmployeeAssigned(newEmployee, role);
    }
    
    /**
     * @notice Removes an employee's role
     * @dev Only the owner can remove employee roles. Validates role and current assignment.
     * @param employee Address of the employee to remove the role from
     * @param role Role to remove from the employee
     */
    function removeEmployee(address employee, string calldata role) external onlyOwner {
        // Validate that the role is "Employe"
        require(keccak256(bytes(role)) == keccak256(bytes("Employe")), "EmployeeAssignment: invalid role");
        
        // Validate that employee currently has this role
        require(employees[employee][role], "EmployeeAssignment: employee does not have this role");
        
        // Remove the role from the employee
        employees[employee][role] = false;
        employeeCount--;
        
        // Emit removal event
        emit EmployeeRemoved(employee, role);
    }
    
    /**
     * @notice Checks if an address has a specific role
     * @param account Address to check
     * @param role Role to check for
     * @return bool True if the account has the specified role
     */
    function hasRole(address account, string calldata role) external view returns (bool) {
        return employees[account][role];
    }
    
    /**
     * @notice Transfers ownership to a new address
     * @dev Only the current owner can call this function. Validates the new owner address.
     * @param newOwner Address of the new owner
     */
    function changeOwner(address newOwner) external onlyOwner {
        // Validate that new owner address is not zero
        zero_Address(newOwner);
        
        // Validate that current sender address is not zero
        zero_Address(msg.sender);
        
        // Store current owner for event emission
        address oldOwner = owner;
        
        // Transfer ownership
        owner = newOwner;
        
        // Emit ownership change event
        emit OwnerChanged(oldOwner, newOwner);
    }
}