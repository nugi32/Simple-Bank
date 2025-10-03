// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Conventional Bank-Style Loan Manager (ETH-based)
/// @notice Manages ETH-denominated loans with collateral, interest, penalties, and liquidation logic
/// @dev 
/// - Loans are stored in an array of {Loan} structs
/// - Each loan tracks borrower info, repayment status, collateral, and liquidation state
/// - Parameters such as interest rate, penalties, and collateral ratio are set at the protocol level
import "../Owner/employe_assignment.sol";
import "../lib/regular.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../lib/now.sol";


contract LoanData
 is EmployeeAssignment 
 ,ReentrancyGuard
{
    // ================================
    // Structs
    // ================================

    /// @notice Represents a loan agreement
    struct Loan {
        address borrower;          // Borrower's wallet address
        uint principal;            // Principal amount (wei)
        uint durationMonths;       // Loan duration in months
        uint startTimestamp;       // Timestamp when loan was approved (0 = not approved)
        uint paidMonths;           // Number of successfully paid months
        uint consecutiveMissed;    // Count of consecutive missed months
        uint remainingPrincipal;   // Remaining unpaid principal (wei)
        uint collateral;           // Collateral deposited at loan request (wei)
        bool liquidated;           // True if loan has been liquidated
        bool active;               // True if loan is active (approved and disbursed)
    }

    // ================================
    // State Variables
    // ================================

    /// @notice Array of all loans
    Loan[] public loans;

    // ----------------
    // Protocol Parameters
    // ----------------
    /// @notice Monthly interest rate (in %). Example: 2 = 2% per month
    uint public monthlyInterestPercent;

    /// @notice Penalty percentage applied on overdue payments. Example: 1 = 1%
    uint public penaltyPercent;

    /// @notice Required collateral percentage relative to principal. Example: 50 = 50%
    uint public collateralRatioPercent;

    /// @notice Maximum Non-Performing Loan (NPL) percentage allowed before liquidation. Example: 20 = 20%
    uint public maxNPLPercent;

    // ----------------
    // Bookkeeping
    // ----------------
    /// @notice Accumulated profits from interest & penalties (in wei)
    uint public totalProfits;

    address payable internal managementWallet;

    /// @notice Tracks blacklisted borrowers
    mapping(address => bool) public blacklist;

    /// @notice Tracks number of times a borrower has been liquidated
    mapping(address => uint) public strikes;

    // ================================
    // Fallback / ETH Reception
    // ================================

    /// @notice Allows the contract to receive ETH
    receive() external payable {}


event managementWallet_address(address indexed managementWallet);
constructor(address payable _managementWallet) {
        require(_managementWallet != address(0), "Err: zero addr!");
        managementWallet = _managementWallet;

        monthlyInterestPercent = 2;    // 2% / month
        penaltyPercent = 1;            // 1% penalty per missed month on monthly due
        collateralRatioPercent = 50;   // 50% collateral relative to principal
        maxNPLPercent = 20; 

        emit managementWallet_address(_managementWallet);
    }

    modifier callerZeroAddr() {
        zero_Address(msg.sender);
        _;
    }
    // =================================================  USERS  ====================================================

     // -----------------------------
    // Events
    // -----------------------------
    event LoanRequested(uint indexed loanId, address indexed borrower, uint principal, uint durationMonths, uint collateral);

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
        notOwner
        callerZeroAddr
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
        notOwner
        nonReentrant
        callerZeroAddr
    {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        require(ln.active && !ln.liquidated, "loan not active or liquidated");
        require(msg.sender == ln.borrower, "only borrower");
        require(monthsToPay > 0, "must pay at least one month");
        require(ln.paidMonths + monthsToPay <= ln.durationMonths, "exceeds remaining months");

        uint monthsSinceStart = _monthsSince(ln.startTimestamp, now._now());
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
            require(currentMonthlyPayment == 0, "");
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
                require(ok, "Colateral failed to send !");
            }
        }
    }

    /// @notice Called to check loan status and auto-liquidate if conditions met.
    /// Anyone can call to trigger checks; this is gas-paid by caller.
    /// @param loanId id of the loan to check
    function checkAndProcessLoan(uint loanId)
        external
        notEmployes
        notOwner
        callerZeroAddr
    {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        if (!ln.active || ln.liquidated) return;

        uint monthsPassed = _monthsSince(ln.startTimestamp, now._now());

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

//======================================================================================  ADMIN  ==========================================


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
    function rejectLoan(uint loanId) external 
    onlyemployes 
    nonReentrant
    callerZeroAddr
    {
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
    function approveLoan(uint loanId) external
    onlyemployes
    nonReentrant
    callerZeroAddr
    {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        require(!ln.liquidated, "already liquidated");
        require(!ln.active, "already active");
        require(address(this).balance >= ln.principal, "contract lacks liquidity");

        ln.startTimestamp = now._now();
        ln.active = true;

        (bool ok, ) = payable(ln.borrower).call{value: ln.principal}("");
        require(ok, "disburse failed");

        emit LoanApproved(loanId, ln.borrower, ln.startTimestamp);
        emit LoanDisbursed(loanId, ln.borrower, ln.principal);
    }

        /// @notice Remove a user from the blacklist
    function unblacklist(address user) external 
    onlyemployes
    callerZeroAddr
    {
        zero_Address(user);
        require(blacklist[user], "Address is not blacklisted");

        blacklist[user] = false;
        emit UnBlacklisted(user);
    }

    //---------------------------------------------------------------  RATES  ------------------------------------

    /// @notice Set monthly interest percentage
    function setMonthlyInterestPercent(uint p) external
    onlyemployes
    callerZeroAddr
    {
        require(p <= 2000, "Interest too high: max 20%");
        require(p > 0, "Interest cannot be zero");

        uint oldValue = monthlyInterestPercent;
        monthlyInterestPercent = p;
        emit InterestRateChanged(oldValue, p);
    }

    /// @notice Set penalty percentage for late payments
    function setPenaltyPercent(uint p) external
    onlyemployes
    callerZeroAddr
    {
        require(p <= 5000, "Penalty too high: max 50%");
        require(p > 0, "Penalty too low");

        uint oldValue = penaltyPercent;
        penaltyPercent = p;
        emit PenaltyPercentChanged(oldValue, p);
    }

    /// @notice Set collateral ratio percentage
    function setCollateralRatioPercent(uint p) external
    onlyemployes
    callerZeroAddr
    {
        require(p > 0, "Collateral ratio too low");
        require(p <= 3000, "Collateral ratio too high: max 300%");

        uint oldValue = collateralRatioPercent;
        collateralRatioPercent = p;
        emit CollateralRatioChanged(oldValue, p);
    }

    /// @notice Set maximum Non-Performing Loan percentage
    function setMaxNPLPercent(uint p) external
    onlyemployes
    callerZeroAddr
    {
        require(p <= 5000, "NPL limit too high: max 50%");

        uint oldValue = maxNPLPercent;
        maxNPLPercent = p;
        emit MaxNPLChanged(oldValue, p);
    }

//--------------------------------------------------------------------------  PROFIT  ---------------------------------
    
    /// @notice Set management wallet address for profit distribution
    function setManagementWallet(address payable w) external
    onlyemployes
    callerZeroAddr
    {
        require(w != address(0), "Cannot set zero address");
        require(w != address(this), "Cannot set contract itself");

        address oldWallet = managementWallet;
        managementWallet = w;
        emit ManagementWalletChanged(oldWallet, w);
    }

    /// @notice Transfer accumulated profits to management wallet
    function takeProfits() external 
    onlyemployes 
    nonReentrant 
    callerZeroAddr
    {
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
  

    function TotalLoan() external view
    onlyemployes 
    callerZeroAddr
    returns (uint) {
        return loans.length;
    }

    function loanInfo(uint loanId)
        external
        view
        onlyemployes
        callerZeroAddr
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

//============================================================  INTERNAL LOGIC  ==================================================================================

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
