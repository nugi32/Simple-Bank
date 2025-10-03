// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IManagementAssignment
/// @notice Interface for Management Assignment contract
/// @dev Declares events and functions without implementation
interface IManagementAssignment {
    // ----------------------------- Events -----------------------------

    /// @notice Emitted when a new employee is assigned
    /// @param new_employes_assign The address of the newly assigned employee
    event new_employes_assign(address indexed new_employes_assign);

    /// @notice Emitted when an employee is removed
    /// @param removedmanagement The address of the removed employee
    event employe_Removed(address indexed removedmanagement);

    // ----------------------------- Functions -----------------------------

    /// @notice Assign a new employee (management member)
    /// @param new_employes The address of the new employee
    function assign_new_management(address new_employes) external;

    /// @notice Remove an employee from the management list by ID
    /// @param employeId The index of the employee to remove
    function reAssign_management(uint employeId) external;

    /// @notice Returns the full list of assigned employees
    /// @return Array of employee addresses
    function see_all_assigned_employes() external view returns (address[] memory);
}
