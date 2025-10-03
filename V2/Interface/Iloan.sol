// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title LoanData Interface
/// @notice Defines the external interface for the LoanData contract
/// @dev Provides function signatures and events that can be used by other contracts
interface ILoanData {
    // ================================
    // Events
    // ================================

    /// @notice Emitted when a borrower requests a new loan
    event LoanRequested(uint indexed loanId, address indexed borrower, uint principal, uint durationMonths, uint collateral);

    /// @notice Emitted when an admin approves a loan
    event LoanApproved(uint indexed loanId, address indexed borrower, uint startTimestamp);

    /// @notice Emitted when the loan principal is disbursed to the borrower
    event LoanDisbursed(uint indexed loanId, address indexed borrower, uint amount);

    /// @notice Emitted when a borrower makes a monthly payment
    event MonthlyPaymentMade(uint indexed loanId, address indexed payer, uint amount, uint monthIndex);

    /// @notice Emitted when a borrower misses one or more months of payments
    event MonthMissed(uint indexed loanId, uint missedCount);

    /// @notice Emitted when a loan is liquidated
    event LoanLiquidated(uint indexed loanId, address indexed borrower, uint collateralUsed, uint deficitCovered, uint profitFromCollateral);

    /// @notice Emitted when a borrower is blacklisted
    event Blacklisted(address indexed borrower);

    /// @notice Emitted when a borrower is removed from the blacklist
    event UnBlacklisted(address indexed borrower);

    /// @notice Emitted when a borrower receives a strike
    event StrikeAdded(address indexed borrower, uint strikes);

    /// @notice Emitted when protocol parameters are updated
    event InterestRateChanged(uint oldValue, uint newValue);
    event PenaltyPercentChanged(uint oldValue, uint newValue);
    event CollateralRatioChanged(uint oldValue, uint newValue);
    event MaxNPLChanged(uint oldValue, uint newValue);
    event ManagementWalletChanged(address oldWallet, address newWallet);

    /// @notice Emitted when accumulated profits are withdrawn
    event ProfitTaken(address indexed to, uint amount);

    // ================================
    // User Functions
    // ================================

    /// @notice Request a new loan and deposit collateral
    /// @param principalInETH Principal amount requested (in whole ETH units)
    /// @param durationMonths Loan repayment duration in months
    function requestLoan(uint principalInETH, uint durationMonths) external payable;

    /// @notice Pay one or more monthly installments for a loan
    /// @param loanId ID of the loan
    /// @param monthsToPay Number of months to pay (must be at least 1)
    function payMonthly(uint loanId, uint monthsToPay) external payable;

    /// @notice Check the loan status and trigger liquidation if conditions are met
    /// @param loanId ID of the loan to check
    function checkAndProcessLoan(uint loanId) external;

    // ================================
    // Admin Functions
    // ================================

    /// @notice Reject a pending loan request and refund collateral
    /// @param loanId ID of the loan
    function rejectLoan(uint loanId) external;

    /// @notice Approve and disburse a pending loan
    /// @param loanId ID of the loan
    function approveLoan(uint loanId) external;

    /// @notice Remove a borrower from the blacklist
    /// @param user Address of the borrower to unblacklist
    function unblacklist(address user) external;

    /// @notice Update monthly interest percentage
    /// @param p New interest percentage
    function setMonthlyInterestPercent(uint p) external;

    /// @notice Update penalty percentage
    /// @param p New penalty percentage
    function setPenaltyPercent(uint p) external;

    /// @notice Update collateral ratio percentage
    /// @param p New collateral ratio percentage
    function setCollateralRatioPercent(uint p) external;

    /// @notice Update maximum NPL (Non-Performing Loan) percentage
    /// @param p New maximum NPL percentage
    function setMaxNPLPercent(uint p) external;

    /// @notice Update the management wallet address
    /// @param w New management wallet address
    function setManagementWallet(address payable w) external;

    /// @notice Withdraw accumulated profits to the management wallet
    function takeProfits() external;

    // ================================
    // View Functions
    // ================================

    /// @notice Get total number of loans created
    /// @return Total loan count
    function TotalLoan() external view returns (uint);

    /// @notice Get information about a loan
    /// @param loanId ID of the loan
    /// @return borrower Loan borrower address
    /// @return principal Loan principal amount in wei
    /// @return durationMonths Loan duration in months
    /// @return startTimestamp Timestamp when loan started
    /// @return paidMonths Number of months paid
    /// @return consecutiveMissed Number of consecutive missed months
    /// @return remainingPrincipal Remaining unpaid principal in wei
    /// @return collateral Collateral amount deposited in wei
    /// @return liquidated True if loan has been liquidated
    /// @return active True if loan is currently active
    function loanInfo(uint loanId)
        external
        view
        returns (
            address borrower,
            uint principal,
            uint durationMonths,
            uint startTimestamp,
            uint paidMonths,
            uint consecutiveMissed,
            uint remainingPrincipal,
            uint collateral,
            bool liquidated,
            bool active
        );
}
