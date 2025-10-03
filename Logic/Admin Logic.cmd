// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./InternalLogic.sol";

/// @title AdminLogic
/// @notice Admin-facing logic (approval, liquidation, parameter updates, profit management)
contract AdminLogic is InternalLogic {

    // -----------------------------
    // Events
    // -----------------------------
    event LoanApproved(uint indexed loanId, address indexed borrower, uint startTimestamp);
    event LoanDisbursed(uint indexed loanId, address indexed borrower, uint amount);
    event MonthlyPaymentMade(uint indexed loanId, address indexed payer, uint amount, uint monthIndex);
    event MonthMissed(uint indexed loanId, uint missedCount);
    event UnBlacklisted(address indexed borrower);

    event InterestRateChanged(uint oldValue, uint newValue);
    event PenaltyPercentChanged(uint oldValue, uint newValue);
    event CollateralRatioChanged(uint oldValue, uint newValue);
    event MaxNPLChanged(uint oldValue, uint newValue);
    event ManagementWalletChanged(address oldWallet, address newWallet);
    event ProfitTaken(address indexed to, uint amount);

//-----------------------------------------------------------------  APPROVALS  ----------------------------------

    /// @notice Admin can reject a loan request (collateral returned)
    function rejectLoan(uint loanId) external onlyemployes caller_zero_Address {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        require(!ln.active && !ln.liquidated, "cannot reject active/liquidated");

        uint coll = ln.collateral;
        ln.collateral = 0;
        (bool ok, ) = payable(ln.borrower).call{value: coll}("");
        require(ok, "refund failed");

        ln.liquidated = true;
        emit LoanLiquidated(loanId, ln.borrower, coll, 0, 0);
    }

    /// @notice Admin approves and disburses the loan
    function approveLoan(uint loanId) external onlyemployes caller_zero_Address {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        require(!ln.liquidated, "already liquidated");
        require(!ln.active, "already active");
        require(address(this).balance >= ln.principal, "contract lacks liquidity");

        ln.startTimestamp = _now();
        ln.active = true;

        (bool ok, ) = payable(ln.borrower).call{value: ln.principal}("");
        require(ok, "disburse failed");

        emit LoanApproved(loanId, ln.borrower, ln.startTimestamp);
        emit LoanDisbursed(loanId, ln.borrower, ln.principal);
    }

        /// @notice Remove a user from the blacklist
    function unblacklist(address user) external onlyemployes caller_zero_Address {
        require(user != address(0), "Cannot unblacklist zero address");
        require(blacklist[user], "Address is not blacklisted");

        blacklist[user] = false;
        emit UnBlacklisted(user);
    }

    //---------------------------------------------------------------  RATES  ------------------------------------

    /// @notice Set monthly interest percentage
    function setMonthlyInterestPercent(uint p) external onlyemployes caller_zero_Address {
        require(p <= 2000, "Interest too high: max 20%");
        require(p > 0, "Interest cannot be zero");

        uint oldValue = monthlyInterestPercent;
        monthlyInterestPercent = p;
        emit InterestRateChanged(oldValue, p);
    }

    /// @notice Set penalty percentage for late payments
    function setPenaltyPercent(uint p) external onlyemployes caller_zero_Address {
        require(p <= 5000, "Penalty too high: max 50%");
        require(p >= 100, "Penalty too low: min 1%");

        uint oldValue = penaltyPercent;
        penaltyPercent = p;
        emit PenaltyPercentChanged(oldValue, p);
    }

    /// @notice Set collateral ratio percentage
    function setCollateralRatioPercent(uint p) external onlyemployes caller_zero_Address {
        require(p >= 10000, "Collateral ratio too low: min 100%");
        require(p <= 30000, "Collateral ratio too high: max 300%");

        uint oldValue = collateralRatioPercent;
        collateralRatioPercent = p;
        emit CollateralRatioChanged(oldValue, p);
    }

    /// @notice Set maximum Non-Performing Loan percentage
    function setMaxNPLPercent(uint p) external onlyemployes caller_zero_Address {
        require(p <= 5000, "NPL limit too high: max 50%");

        uint oldValue = maxNPLPercent;
        maxNPLPercent = p;
        emit MaxNPLChanged(oldValue, p);
    }

//--------------------------------------------------------------------------  PROFIT  ---------------------------------
    
    /// @notice Set management wallet address for profit distribution
    function setManagementWallet(address payable w) external onlyemployes caller_zero_Address {
        require(w != address(0), "Cannot set zero address");
        require(w != address(this), "Cannot set contract itself");

        address oldWallet = managementWallet;
        managementWallet = w;
        emit ManagementWalletChanged(oldWallet, w);
    }

    /// @notice Transfer accumulated profits to management wallet
    function takeProfits() external onlyemployes caller_zero_Address {
        uint amount = totalProfits;
        require(amount > 0, "no profits");

        totalProfits = 0;
        (bool ok, ) = managementWallet.call{value: amount}("");
        require(ok, "transfer failed");

        emit ProfitTaken(managementWallet, amount);
    }


//----------------------------------------------------  UTILITIES  ---------------------------------


    /// @dev Current Non-Performing Loan percent (internal view, no access modifiers)
    /// @return percent NPL as integer (0..100)
    function currentNPL() internal view returns (uint) {
        if (loans.length == 0) return 0;
        uint bad = 0;
        for (uint i = 0; i < loans.length; i++) {
            if (loans[i].liquidated) bad++;
        }
        return (bad * 100) / loans.length;
    }
  

    function TotalLoan() external view onlyemployes caller_zero_Address returns (uint) {
        return loans.length;
    }

    function loanInfo(uint loanId)
        external
        view
        onlyemployes
        caller_zero_Address
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
        )
    {
        Loan storage ln = loans[loanId];
        return (
            ln.borrower,
            ln.principal,
            ln.durationMonths,
            ln.startTimestamp,
            ln.paidMonths,
            ln.consecutiveMissed,
            ln.remainingPrincipal,
            ln.collateral,
            ln.liquidated,
            ln.active
        );
    }
}