// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./InternalLogic.sol";

/// @title UserLogic
/// @notice User-facing logic (loan requests, payments, monitoring) separated from internal logic
contract UserLogic is InternalLogic {

    // -----------------------------
    // Events
    // -----------------------------
    event LoanRequested(uint indexed loanId, address indexed borrower, uint principal, uint durationMonths, uint collateral);
    event LoanApproved(uint indexed loanId, address indexed borrower, uint startTimestamp);
    event LoanDisbursed(uint indexed loanId, address indexed borrower, uint amount);
    event MonthlyPaymentMade(uint indexed loanId, address indexed payer, uint amount, uint monthIndex);
    event MonthMissed(uint indexed loanId, uint missedCount);
    event UnBlacklisted(address indexed borrower);

    // -----------------------------
    // User / External functions
    // -----------------------------

    /// @notice Request a loan and deposit collateral (send collateral with the call)
    /// @param principalInETH principal requested in whole ETH
    /// @param durationMonths number of months for repayment
    function requestLoan(uint principalInETH, uint durationMonths)
        external
        payable
        notEmployes
        caller_zero_Address
        notOwner
    {
        require(!blacklist[msg.sender], "blacklisted");
        require(principalInETH > 0, "invalid principal");
        require(durationMonths >= 1, "duration must be >= 1 month");
        require(loansAllowed(), "new loans blocked");

        uint principal = principalInETH * 1 ether;
        uint requiredCollateral = (principal * collateralRatioPercent) / 100;
        require(msg.value >= requiredCollateral, "insufficient collateral");

        Loan memory ln = Loan({
            borrower: msg.sender,
            principal: principal,
            durationMonths: durationMonths,
            startTimestamp: 0,
            paidMonths: 0,
            consecutiveMissed: 0,
            remainingPrincipal: principal,
            collateral: msg.value,
            liquidated: false,
            active: false
        });

        loans.push(ln);
        uint id = loans.length - 1;
        emit LoanRequested(id, msg.sender, principal, durationMonths, msg.value);
    }

    /// @notice Pay monthly installment(s). Caller can pay for one or more months at once.
    /// @param loanId loan id
    /// @param monthsToPay number of months to pay (must be at least 1)
    function payMonthly(uint loanId, uint monthsToPay)
        external
        payable
        notEmployes
        caller_zero_Address
        notOwner
    {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        require(ln.active && !ln.liquidated, "loan not active or liquidated");
        require(msg.sender == ln.borrower, "only borrower");
        require(monthsToPay > 0, "must pay at least one month");
        require(ln.paidMonths + monthsToPay <= ln.durationMonths, "exceeds remaining months");

        uint monthsSinceStart = _monthsSince(ln.startTimestamp, _now());
        require(ln.paidMonths < ln.durationMonths, "loan already fully paid");

        uint monthly = monthlyDue(loanId);

        // calculate penalty for overdue months (if any)
        uint dueMonthIndex = ln.paidMonths; // 0-based index of next unpaid month
        uint timeAllowedMonths = monthsSinceStart; // months that have passed
        uint penalty = 0;
        if (timeAllowedMonths > dueMonthIndex) {
            uint lateCount = timeAllowedMonths - dueMonthIndex;
            // penalty applied per missed/late month on the monthly due
            penalty = (monthly * penaltyPercent / 100) * lateCount;
        }

        uint totalPaymentNeeded = monthly + penalty;
        if (monthsToPay > 1) {
            totalPaymentNeeded += monthly * (monthsToPay - 1);
        }

        require(msg.value == totalPaymentNeeded, "msg.value mismatch total payment needed");

        // process payments
        for (uint i = 0; i < monthsToPay; i++) {
            uint currentMonthlyPayment = (i == 0) ? (monthly + penalty) : monthly;

            uint interestPart = (ln.principal * monthlyInterestPercent) / 100;
            uint principalPart = monthly - interestPart;

            if (i == 0) {
                totalProfits += interestPart + penalty;
            } else {
                totalProfits += interestPart;
            }

            if (principalPart > ln.remainingPrincipal) {
                principalPart = ln.remainingPrincipal;
            }
            ln.remainingPrincipal -= principalPart;

            ln.paidMonths += 1;

            if (ln.paidMonths >= ln.durationMonths || ln.remainingPrincipal == 0) {
                break;
            }
        }

        ln.consecutiveMissed = 0;

        emit MonthlyPaymentMade(loanId, msg.sender, msg.value, ln.paidMonths);

        // if loan fully repaid, mark inactive and refund collateral
        if (ln.paidMonths >= ln.durationMonths || ln.remainingPrincipal == 0) {
            ln.active = false;
            uint coll = ln.collateral;
            ln.collateral = 0;
            if (coll > 0) {
                (bool ok, ) = payable(ln.borrower).call{value: coll}("");
                // do not revert on refund failure
                if (!ok) {
                    // optional: emit event for failed refund (not implemented here)
                }
            }
        }
    }

    /// @notice Called to check loan status and auto-liquidate if conditions met.
    /// Anyone can call to trigger checks; this is gas-paid by caller.
    /// @param loanId id of the loan to check
    function checkAndProcessLoan(uint loanId)
        external
        notEmployes
        caller_zero_Address
        notOwner
    {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        if (!ln.active || ln.liquidated) return;

        uint monthsPassed = _monthsSince(ln.startTimestamp, _now());

        uint expectedPaid = monthsPassed;
        if (expectedPaid > ln.durationMonths) expectedPaid = ln.durationMonths;

        if (expectedPaid > ln.paidMonths) {
            uint missed = expectedPaid - ln.paidMonths;
            ln.consecutiveMissed += missed;
            emit MonthMissed(loanId, ln.consecutiveMissed);
        }

        if (ln.consecutiveMissed >= 3) {
            _liquidateForConsecutiveMisses(loanId, 3);
        }

        if (monthsPassed >= ln.durationMonths && ln.paidMonths < ln.durationMonths && !ln.liquidated) {
            _finalLiquidation(loanId);
        }
    }

}
