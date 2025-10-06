// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AdminLogic
/// @notice Contains administrative functions and configuration for loan protocol parameters,
///         including interest rates, penalties, collateral ratios, profit management, and wallet settings.
/// @dev This contract is designed to be called via delegatecall from a main loan contract,
///      so it does not maintain its own storage context for loans or parameters.
contract AdminLogic {
    // ================================
    // Structs
    // ================================

    /// @notice Represents the basic structure of a loan.
    struct Loan {
        address borrower;
        uint principal;
        uint durationMonths;
        uint startTimestamp;
        uint paidMonths;
        uint consecutiveMissed;
        uint remainingPrincipal;
        uint collateral;
        bool liquidated;
        bool active;
    }

    // ================================
    // State Variables
    // ================================

    /// @notice Array storing all loans.
    Loan[] public loans;

    /// @notice Protocol configuration parameters.
    uint16 public monthlyInterestPercent;     // e.g., 1000 = 10.00%
    uint16 public penaltyPercent;             // penalty applied on missed payments
    uint16 public collateralRatioPercent;     // minimum collateral ratio required
    uint16 public maxNPLPercent;              // maximum allowed non-performing loan ratio

    /// @notice Total accumulated profits within the protocol.
    uint public totalProfits;

    /// @notice Wallet where management fees and profits are sent.
    address payable internal managementWallet;

    // ================================
    // Custom Errors
    // ================================

    error ZeroAddress();
    error InterestTooHigh(uint16 provided);
    error InterestZero();
    error PenaltyTooHigh(uint16 provided);
    error PenaltyZero();
    error CollateralRatioTooLow();
    error CollateralRatioTooHigh(uint16 provided);
    error NPLTooHigh(uint16 provided);
    error NoProfitToWithdraw();

    // ================================
    // Events
    // ================================

    event InterestRateChanged(uint oldValue, uint newValue);
    event PenaltyPercentChanged(uint oldValue, uint newValue);
    event CollateralRatioChanged(uint oldValue, uint newValue);
    event MaxNPLChanged(uint oldValue, uint newValue);
    event ManagementWalletChanged(address oldWallet, address newWallet);
    event ProfitTaken(address indexed to, uint amount);

    // ================================
    // Administrative Functions
    // ================================

    /**
     * @notice Sets the monthly interest rate percentage.
     * @param p New interest rate in basis points (e.g., 1000 = 10.00%).
     * @dev Reverts if the interest is zero or above 20.00% (2000 bps).
     */
    function MonthlyInterestPercent(uint16 p) external {
        if (p > 2000) revert InterestTooHigh(p);
        if (p == 0) revert InterestZero();

        uint oldValue = monthlyInterestPercent;
        monthlyInterestPercent = p;
        emit InterestRateChanged(oldValue, p);
    }

    /**
     * @notice Sets the penalty percentage for missed payments.
     * @param p New penalty percentage in basis points.
     * @dev Reverts if the penalty is zero or above 50.00% (5000 bps).
     */
    function PenaltyPercent(uint16 p) external {
        if (p > 5000) revert PenaltyTooHigh(p);
        if (p == 0) revert PenaltyZero();

        uint oldValue = penaltyPercent;
        penaltyPercent = p;
        emit PenaltyPercentChanged(oldValue, p);
    }

    /**
     * @notice Sets the required collateral ratio.
     * @param p New collateral ratio in basis points.
     * @dev Reverts if p == 0 or above 30.00% (3000 bps).
     */
    function CollateralRatioPercent(uint16 p) external {
        if (p == 0) revert CollateralRatioTooLow();
        if (p > 3000) revert CollateralRatioTooHigh(p);

        uint oldValue = collateralRatioPercent;
        collateralRatioPercent = p;
        emit CollateralRatioChanged(oldValue, p);
    }

    /**
     * @notice Sets the maximum Non-Performing Loan (NPL) ratio.
     * @param p New maximum NPL ratio in basis points.
     * @dev Reverts if p is above 50.00% (5000 bps).
     */
    function MaxNPLPercent(uint16 p) external {
        if (p > 5000) revert NPLTooHigh(p);

        uint oldValue = maxNPLPercent;
        maxNPLPercent = p;
        emit MaxNPLChanged(oldValue, p);
    }

    // ================================
    // Profit & Wallet Management
    // ================================

    /**
     * @notice Sets the management wallet where protocol profits will be transferred.
     * @param w The new management wallet address.
     * @dev Reverts if w is the zero address or this contract's own address.
     */
    function ManagementWallet(address payable w) external {
        if (w == address(0)) revert ZeroAddress();
        if (w == address(this)) revert ZeroAddress();

        address oldWallet = managementWallet;
        managementWallet = w;
        emit ManagementWalletChanged(oldWallet, w);
    }

    /**
     * @notice Transfers all accumulated protocol profits to the management wallet.
     * @dev Reverts if no profit is available or transfer fails.
     */
    function TP() external {
        uint amount = totalProfits;
        if (amount == 0) revert NoProfitToWithdraw();

        totalProfits = 0;
        (bool ok, ) = managementWallet.call{value: amount}("");
        require(ok, "transfer failed");

        emit ProfitTaken(managementWallet, amount);
    }
}
