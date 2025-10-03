// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Data/Bank.sol";
import "../Owner/employe_assignment.sol";
import "../lib/regular.sol";
import "../Data/Loan.sol";

/// @title InternalLogic
/// @notice Shared internal helpers and liquidation logic used by User/Admin contracts
contract InternalLogic is BankData, employe_assignment, LoanData {

address payable LoanContract;

    // -----------------------------
    // Events
    // -----------------------------
    event LoanLiquidated(uint indexed loanId, address indexed borrower, uint collateralUsed, uint deficitCovered, uint profitFromCollateral);
    event StrikeAdded(address indexed borrower, uint strikes);
    event Blacklisted(address indexed borrower);
    // -----------------------------
    // Internal helpers
    // -----------------------------

    /// @dev Validate loan id exists
    function _invalidId(uint Id) internal view {
        require(Id < loans.length, "invalid Id");
    }

    /// @dev Current block timestamp (wrapper for easier testing/mocking)
    function _now() internal view returns (uint) { return block.timestamp; }

    /// @notice Whether new loans are allowed based on configured NPL threshold
    /// @dev Uses internal `currentNPL()` which does not enforce access control so it can be used from other internals
    function loansAllowed() internal view returns (bool) {
        if (maxNPLPercent == 0) return true; // 0 means no limit
        return currentNPL() < maxNPLPercent;
    }


    /// @dev Monthly due calculated as fixed interest on original principal + equal principal installment
    function monthlyDue(uint loanId) internal view returns (uint) {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        require(ln.durationMonths > 0, "invalid loan");
        uint principalPart = ln.principal / ln.durationMonths; // truncated
        uint interestPart = (ln.principal * monthlyInterestPercent) / 100; // interest calculated on original principal (fixed monthly)
        return principalPart + interestPart;
    }

    /// @dev helper to compute months since start (30 days per month used)
    function _monthsSince(uint startTs, uint nowTs) internal pure returns (uint) {
        if (nowTs <= startTs) return 0;
        // use 30 days as one month for simplicity
        uint secondsPerMonth = 30 days;
        return (nowTs - startTs) / secondsPerMonth;
    }

    // -----------------------------
    // Liquidation logic
    // -----------------------------

    /// @dev Seize collateral to cover X months of due (principal+interest+penalty)
    /// Prioritizes principal coverage when collateral is insufficient
    function _liquidateForConsecutiveMisses(uint loanId, uint monthsToCover) internal {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        if (ln.liquidated || !ln.active) return;

        uint toCover = monthsToCover;
        if (ln.paidMonths + toCover > ln.durationMonths) {
            toCover = ln.durationMonths - ln.paidMonths;
        }
        if (toCover == 0) return;

        uint monthly = monthlyDue(loanId);
        uint totalMonthlyDue = monthly * toCover;
        uint totalPenalty = (totalMonthlyDue * penaltyPercent) / 100; // simplified single penalty calc
        uint needed = totalMonthlyDue + totalPenalty;

        uint usedCollateral = 0;
        uint profitFromCollateral = 0;
        uint deficit = 0;

        if (ln.collateral >= needed) {
            // collateral fully covers dues + penalty
            usedCollateral = needed;

            // interest portion per month
            uint interestPerMonth = (ln.principal * monthlyInterestPercent) / 100;
            uint totalInterest = interestPerMonth * toCover;
            totalProfits += totalInterest + totalPenalty;

            // principal covered:
            uint principalCovered = totalMonthlyDue - (interestPerMonth * toCover);
            if (principalCovered > ln.remainingPrincipal) principalCovered = ln.remainingPrincipal;
            ln.remainingPrincipal -= principalCovered;

            ln.collateral -= usedCollateral;
            profitFromCollateral = 0;
            deficit = 0;
        } else {
            // collateral insufficient: priority -> cover principal as much as possible, then interest+penalty
            usedCollateral = ln.collateral;
            uint remaining = usedCollateral;

            // attempt to cover principal outstanding first
            uint principalOutstanding = ln.remainingPrincipal;
            uint principalToCover = principalOutstanding;
            if (principalToCover > remaining) {
                // cover partially principal
                uint covered = remaining;
                ln.remainingPrincipal -= covered;
                remaining = 0;
            } else {
                // cover principal portion for the toCover months
                uint principalPortion = (ln.principal / ln.durationMonths) * toCover;
                if (principalPortion > ln.remainingPrincipal) principalPortion = ln.remainingPrincipal;
                if (principalPortion > remaining) {
                    ln.remainingPrincipal -= remaining;
                    remaining = 0;
                } else {
                    ln.remainingPrincipal -= principalPortion;
                    remaining -= principalPortion;
                }
            }

            // after principal coverage attempt, use remaining collateral to cover interest & penalties
            uint interestPerMonth = (ln.principal * monthlyInterestPercent) / 100;
            uint totalInterest = interestPerMonth * toCover;
            uint toCoverInterestPenalties = totalInterest + ((monthly * toCover * penaltyPercent) / 100);

            if (remaining >= toCoverInterestPenalties) {
                // cover interest + penalties fully
                totalProfits += toCoverInterestPenalties;
                remaining -= toCoverInterestPenalties;
                profitFromCollateral += remaining; // small leftover counts as profit
            } else {
                // partial cover
                totalProfits += remaining;
                remaining = 0;
                // leftover uncovered -> considered deficit (bank loss)
            }

            // collateral consumed fully
            ln.collateral = 0;
            deficit = needed > usedCollateral ? (needed - usedCollateral) : 0;
        }

        // mark that some months are considered "handled" by liquidation: increase paidMonths as principal covered
        ln.paidMonths += toCover;
        if (ln.paidMonths > ln.durationMonths) ln.paidMonths = ln.durationMonths;

        // reset consecutive missed after liquidation action
        ln.consecutiveMissed = 0;

        // add strike
        strikes[ln.borrower] += 1;
        emit StrikeAdded(ln.borrower, strikes[ln.borrower]);

        // if strikes reach 3, blacklist
        if (strikes[ln.borrower] >= 3) {
            blacklist[ln.borrower] = true;
            emit Blacklisted(ln.borrower);
        }

        // if loan fully covered by liquidation, mark inactive
        if (ln.paidMonths >= ln.durationMonths || ln.remainingPrincipal == 0) {
            ln.active = false;
            ln.liquidated = true;
        }

        emit LoanLiquidated(loanId, ln.borrower, usedCollateral, deficit, profitFromCollateral);
    }

    /// @dev Final liquidation at end of term to recover outstanding principal+interest+penalty
    function _finalLiquidation(uint loanId) internal {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        if (ln.liquidated) return;

        uint monthsRemaining = (ln.durationMonths > ln.paidMonths) ? (ln.durationMonths - ln.paidMonths) : 0;
        uint monthly = monthlyDue(loanId);
        uint totalMonthlyDue = monthly * monthsRemaining;
        uint totalPenalty = (totalMonthlyDue * penaltyPercent) / 100;
        uint totalNeeded = totalMonthlyDue + totalPenalty;

        uint usedCollateral = 0;
        uint deficit = 0;
        uint profitFromCollateral = 0;

        if (ln.collateral >= totalNeeded) {
            usedCollateral = totalNeeded;

            uint interestPerMonth = (ln.principal * monthlyInterestPercent) / 100;
            uint totalInterest = interestPerMonth * monthsRemaining;
            totalProfits += totalInterest + totalPenalty;

            uint principalCovered = totalMonthlyDue - (interestPerMonth * monthsRemaining);
            if (principalCovered > ln.remainingPrincipal) principalCovered = ln.remainingPrincipal;
            ln.remainingPrincipal -= principalCovered;

            ln.collateral -= usedCollateral;
        } else {
            usedCollateral = ln.collateral;
            uint remaining = usedCollateral;

            uint principalPortion = (ln.principal / ln.durationMonths) * monthsRemaining;
            if (principalPortion > ln.remainingPrincipal) principalPortion = ln.remainingPrincipal;
            if (remaining >= principalPortion) {
                remaining -= principalPortion;
                ln.remainingPrincipal -= principalPortion;
            } else {
                ln.remainingPrincipal -= remaining;
                remaining = 0;
            }

            uint interestPerMonth = (ln.principal * monthlyInterestPercent) / 100;
            uint totalInterest = interestPerMonth * monthsRemaining;
            uint toCoverInterestPenalty = totalInterest + totalPenalty;

            if (remaining >= toCoverInterestPenalty) {
                totalProfits += toCoverInterestPenalty;
                remaining -= toCoverInterestPenalty;
                profitFromCollateral += remaining;
            } else {
                totalProfits += remaining;
                remaining = 0;
            }

            ln.collateral = 0;
            deficit = totalNeeded > usedCollateral ? (totalNeeded - usedCollateral) : 0;
        }

        ln.liquidated = true;
        ln.active = false;
        strikes[ln.borrower] += 1;
        emit StrikeAdded(ln.borrower, strikes[ln.borrower]);
        if (strikes[ln.borrower] >= 3) {
            blacklist[ln.borrower] = true;
            emit Blacklisted(ln.borrower);
        }

        emit LoanLiquidated(loanId, ln.borrower, usedCollateral, deficit, profitFromCollateral);
    }
}
