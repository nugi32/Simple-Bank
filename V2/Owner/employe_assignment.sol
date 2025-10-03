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
    address internal owner;

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

    // ================================
    // Constructor
    // ================================

    /**
     * @notice Initializes the contract and sets the deployer as the owner
     */
    constructor() {
        owner = msg.sender;
    }

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

    /// @notice Ensures the caller is not the zero address
    function zero_Address(address x) internal pure {
        require(x != address(0), "EmployeeAssignment: zero address not allowed");
    }

    /// @notice Ensures that only employees with Admin role can call the function
    modifier onlyemployes () {
        require(employees[msg.sender]["Admin"], "EmployeeAssignment: caller is not an admin");
        _;
    }

    /// @notice Ensures that the caller is not an employee with Admin role
    modifier notEmployes() {
        require(!employees[msg.sender]["Admin"], "EmployeeAssignment: caller is an admin");
        _;
    }

    // ================================
    // External Functions
    // ================================

    /**
     * @notice Assigns a new employee with a specific role
     * @dev Only the owner can assign new employees
     * @param newEmployee Address of the employee to be assigned
     * @param role Role to assign to the employee
     */
    function assignNewEmployee(address newEmployee, string calldata role) external onlyOwner {
        require(keccak256(bytes(role)) == keccak256(bytes("Employe")), "EmployeeAssignment: invalid role");
        require(newEmployee != address(0), "EmployeeAssignment: employee cannot be zero address");
        require(!employees[newEmployee][role], "EmployeeAssignment: employee already has this role");
        
        employees[newEmployee][role] = true;
        employeeCount++;
        
        emit EmployeeAssigned(newEmployee, role);
    }

    /**
     * @notice Removes an employee's role
     * @dev Only the owner can remove employee roles
     * @param employee Address of the employee to remove the role from
     * @param role Role to remove from the employee
     */
    function removeEmployee(address employee, string calldata role) external onlyOwner {
        require(keccak256(bytes(role)) == keccak256(bytes("Employe")), "EmployeeAssignment: invalid role");
        require(employees[employee][role], "EmployeeAssignment: employee does not have this role");
        
        employees[employee][role] = false;
        employeeCount--;
        
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
}