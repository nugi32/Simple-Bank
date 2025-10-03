// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AddressUtils
/// @notice Utility library for address safety checks and ownership validation
library AddressUtils {
    /// @notice Reverts if address is zero (address(0))
    /// @param self Address to check
    function   protectFromZeroAddress(address self) internal pure {
        require(self != address(0), "ERR: zero address");
    }

    /// @notice Reverts if caller is not the owner
    /// @dev Uses msg.sender directly, suitable for modifiers
    /// @param owner Address that must match msg.sender
    function requireIsOwner(address owner) internal view {
        require(msg.sender == owner, "AddressUtils: caller is not the owner");
    }

    /// @notice Reverts if caller is the owner
    /// @dev Uses msg.sender directly, suitable for modifiers
    /// @param owner Address of the owner
    function requireIsNotOwner(address owner) internal view {
        require(msg.sender != owner, "AddressUtils: owner cannot do this action");
    }
}
