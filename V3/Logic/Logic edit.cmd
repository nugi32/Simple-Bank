// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Data/Abank.sol";
import "../Owner/employe_assignment.sol";
import "../lib/regular.sol";
import "../Data/Aloan.sol";

contract Logicv1 is abank
, employe_assignment
, ConventionalLoanManager
{

//*******************************************************************  EVENT  ****************************************
event managementWallet_address(address indexed managementWallet);
event User_registered(address indexed user,string indexed  name, uint8 indexed age);
event User_unregistered(address indexed user, string indexed name, uint8 indexed age);
event User_deposit(address indexed user, uint indexed netAmount);
event User_withdraw(address indexed , uint indexed amount);
event User_transfer(address indexed user, address indexed to, uint indexed amount);
//**********************************************************************  LOGIC  *************************************
    constructor(address payable _managementWallet) {
        require(_managementWallet != address(0), "Err: zero addr!");
        managementWallet = _managementWallet;

        depositFeePercent = 1;
        monthlyInterestPercent = 2;    // 2% / month
        penaltyPercent = 1;            // 1% penalty per missed month on monthly due
        collateralRatioPercent = 50;   // 50% collateral relative to principal
        maxNPLPercent = 20; 

        emit managementWallet_address(_managementWallet);
    }*

//********************************************************************************************************************************************************************
//                                                                            LOAN
//********************************************************************************************************************************************************************

    // events
    event LoanRequested(uint indexed loanId, address indexed borrower, uint principal, uint durationMonths, uint collateral);
    event LoanApproved(uint indexed loanId, address indexed borrower, uint startTimestamp);
    event LoanDisbursed(uint indexed loanId, address indexed borrower, uint amount);
    event MonthlyPaymentMade(uint indexed loanId, address indexed payer, uint amount, uint monthIndex);
    event MonthMissed(uint indexed loanId, uint missedCount);
    event LoanLiquidated(uint indexed loanId, address indexed borrower, uint collateralUsed, uint deficitCovered, uint profitFromCollateral);
    event StrikeAdded(address indexed borrower, uint strikes);
    event Blacklisted(address indexed borrower);
    event UnBlacklisted(address indexed borrower);

    // ------------------------------
    // Loan Request / Approval
    // ------------------------------

    /// @notice request a loan and deposit collateral (send collateral with the call)
    /// @param principalInETH principal requested in whole ETH
    /// @param durationMonths number of months for repayment
    function requestLoan(uint principalInETH, uint durationMonths) public notEmployes caller_zero_Address notOwner payable {
        require(!blacklist[msg.sender], "blacklisted");
        require(principalInETH > 0, "invalid principal");
        require(durationMonths >= 1, "duration must be >= 1 month");
        require(loansAllowed(), "new loans blocked");

        uint principal = principalInETH * 1 ether;
        uint requiredCollateral = (principal * collateralRatioPercent) / 100;
        require(msg.value >= requiredCollateral, "insufficient collateral");

        // store loan request (not yet approved)
        Loan memory ln;
        ln.borrower = msg.sender;
        ln.principal = principal;
        ln.durationMonths = durationMonths;
        ln.startTimestamp = 0; // not yet approved
        ln.paidMonths = 0;
        ln.consecutiveMissed = 0;
        ln.remainingPrincipal = principal;
        ln.collateral = msg.value;
        ln.liquidated = false;
        ln.active = false;

        loans.push(ln);
        uint id = loans.length - 1;
        emit LoanRequested(id, msg.sender, principal, durationMonths, msg.value);
    }

    // ------------------------------
    // Monthly Payment Flow
    // ------------------------------




/// @notice Pay monthly installment(s). Caller can pay for one or more months at once.
/// @param loanId loan id
/// @param monthsToPay number of months to pay (must be at least 1)
function payMonthly(uint loanId, uint monthsToPay) public notEmployes caller_zero_Address notOwner payable {
    _invalidId(loanId);
    Loan storage ln = loans[loanId];
    require(ln.active && !ln.liquidated, "loan not active or liquidated");
    require(msg.sender == ln.borrower, "only borrower");
    require(monthsToPay > 0, "must pay at least one month");
    
    // Check if there are enough months left to pay
    require(ln.paidMonths + monthsToPay <= ln.durationMonths, "exceeds remaining months");

    // compute which month is due: months since start (floor)
    uint monthsSinceStart = _monthsSince(ln.startTimestamp, _now());
    // borrower can pay next due month (monthsSinceStart may be >= paidMonths)
    require(ln.paidMonths < ln.durationMonths, "loan already fully paid");

    // Calculate total payment needed
    uint totalPaymentNeeded = 0;
    uint monthly = monthlyDue(loanId);
    
    // Calculate penalty for overdue months (if any)
    uint dueMonthIndex = ln.paidMonths; // 0-based index of next unpaid month
    uint timeAllowedMonths = monthsSinceStart; // months that have passed
    uint penalty = 0;
    
    if (timeAllowedMonths > dueMonthIndex) {
        uint lateCount = timeAllowedMonths - dueMonthIndex;
        // penalty applied per missed/late month on the monthly due
        penalty = (monthly * penaltyPercent / 100) * lateCount;
    }
    
    // First month includes penalty
    totalPaymentNeeded = monthly + penalty;
    
    // Add payment for additional months (no penalty for future months)
    if (monthsToPay > 1) {
        totalPaymentNeeded += monthly * (monthsToPay - 1);
    }
    
    require(msg.value == totalPaymentNeeded, "msg.value mismatch total payment needed");

    // Process payments for each month
    for (uint i = 0; i < monthsToPay; i++) {
        // For the first month, include penalty
        uint currentMonthlyPayment = (i == 0) ? (monthly + penalty) : monthly;
        
        // Calculate interest and principal parts
        uint interestPart = (ln.principal * monthlyInterestPercent) / 100;
        uint principalPart = monthly - interestPart;
        
        // Add interest and penalty to profits
        if (i == 0) {
            totalProfits += interestPart + penalty;
        } else {
            totalProfits += interestPart;
        }
        
        // Reduce remaining principal
        if (principalPart > ln.remainingPrincipal) {
            principalPart = ln.remainingPrincipal;
        }
        ln.remainingPrincipal -= principalPart;
        
        // Update paid months
        ln.paidMonths += 1;
        
        // If loan is fully paid, break the loop
        if (ln.paidMonths >= ln.durationMonths || ln.remainingPrincipal == 0) {
            break;
        }
    }
    
    // Reset consecutive missed
    ln.consecutiveMissed = 0;
    
    emit MonthlyPaymentMade(loanId, msg.sender, msg.value, ln.paidMonths);
    
    // If loan fully repaid, mark inactive
    if (ln.paidMonths >= ln.durationMonths || ln.remainingPrincipal == 0) {
        ln.active = false;
        // Return any remaining collateral to borrower
        uint coll = ln.collateral;
        ln.collateral = 0;
        if (coll > 0) {
            (bool ok, ) = payable(ln.borrower).call{value: coll}("");
            // if refund fails, we continue without reverting
        }
    }
}

    // ------------------------------
    // Monitoring & Auto-Liquidation
    // ------------------------------

    /// @notice Called to check loan status and auto-liquidate if conditions met.
    /// Anyone can call to trigger checks; this is gas-paid by caller.
    function checkAndProcessLoan(uint loanId) public notEmployes caller_zero_Address notOwner {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        if (!ln.active || ln.liquidated) return;

        // calculate months since start
        uint monthsPassed = _monthsSince(ln.startTimestamp, _now());

        // count how many payments are expected so far and how many paid
        uint expectedPaid = monthsPassed;
        if (expectedPaid > ln.durationMonths) expectedPaid = ln.durationMonths;

        // missed payments = expectedPaid - paidMonths
        if (expectedPaid > ln.paidMonths) {
            uint missed = expectedPaid - ln.paidMonths;
            // for each missed month increment consecutiveMissed
            ln.consecutiveMissed += missed;
            emit MonthMissed(loanId, ln.consecutiveMissed);
        }

        // If consecutive missed >= 3 -> perform partial liquidation for those months (seize collateral for up to missed months)
        if (ln.consecutiveMissed >= 3) {
            _liquidateForConsecutiveMisses(loanId, 3);
        }

        // If loan duration fully passed and not fully repaid -> final liquidation
        if (monthsPassed >= ln.durationMonths && ln.paidMonths < ln.durationMonths && !ln.liquidated) {
            // finalize liquidation to recover remaining principal + interest + penalty
            _finalLiquidation(loanId);
        }
    }

     /// @dev monthly due for a loan (principal portion + interest portion) in wei for months that are still equal
    /// principal part per month uses integer division; last month may adjust when borrower pays final.
    function monthlyDue(uint loanId) public view notEmployes caller_zero_Address notOwner returns (uint) {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        require(ln.durationMonths > 0, "invalid loan");
        uint principalPart = ln.principal / ln.durationMonths; // truncated
        uint interestPart = (ln.principal * monthlyInterestPercent) / 100; // interest calculated on original principal (fixed monthly)
        return principalPart + interestPart;
    }
 


//*************************************************************  ADMIN  *********************************************
 /// @notice admin can reject a loan request (collateral returned)
    function rejectLoan(uint loanId) public onlyemployes caller_zero_Address {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        require(!ln.active && !ln.liquidated, "cannot reject active/liquidated");
        // return collateral to borrower
        uint coll = ln.collateral;
        ln.collateral = 0;
        (bool ok, ) = payable(ln.borrower).call{value: coll}("");
        require(ok, "refund failed");
        ln.liquidated = true; // mark to prevent re-use
        emit LoanLiquidated(loanId, ln.borrower, coll, 0, 0);
    }

    /// @notice admin approves and disburses the loan (calls by owner or employees depending on your policy)
    /// @param loanId id returned from request
    function approveLoan(uint loanId) public onlyemployes caller_zero_Address {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        require(!ln.liquidated, "already liquidated");
        require(!ln.active, "already active");
        // ensure contract has liquidity to disburse principal
        require(address(this).balance >= ln.principal, "contract lacks liquidity");

        ln.startTimestamp = _now();
        ln.active = true;

        // disburse principal to borrower
        (bool ok, ) = payable(ln.borrower).call{value: ln.principal}("");
        require(ok, "disburse failed");

        emit LoanApproved(loanId, ln.borrower, ln.startTimestamp);
        emit LoanDisbursed(loanId, ln.borrower, ln.principal);
    }


      function change_loan_contract_management_wallet(address payable new_wallet) public onlyemployes caller_zero_Address {
        managementWallet = new_wallet;
    }

    /// @notice current NPL percent: liquidated loans / total loans * 100
    function currentNPL() public view onlyemployes caller_zero_Address returns (uint) {
        if (loans.length == 0) return 0;
        uint bad = 0;
        for (uint i = 0; i < loans.length; i++) {
            if (loans[i].liquidated) bad++;
        }
        return (bad * 100) / loans.length;
    }

    /// @notice whether new loans are allowed based on NPL
    function loansAllowed() public view onlyemployes caller_zero_Address returns (bool) {
        if (maxNPLPercent == 0) return true; // 0 means no limit
        return currentNPL() < maxNPLPercent;
    }

// Events for parameter changes
event InterestRateChanged(uint oldValue, uint newValue);
event PenaltyPercentChanged(uint oldValue, uint newValue);
event CollateralRatioChanged(uint oldValue, uint newValue);
event MaxNPLChanged(uint oldValue, uint newValue);
event ManagementWalletChanged(address oldWallet, address newWallet);
event ProfitTaken(address indexed to, uint amount);
   /**
 * @notice Set monthly interest percentage
 * @dev Includes safety checks for reasonable values
 * @param p New monthly interest percentage (in basis points, e.g. 100 = 1%)
 */
function setMonthlyInterestPercent(uint p) public onlyemployes caller_zero_Address {
    require(p <= 2000, "Interest too high: max 20%");
    require(p > 0, "Interest cannot be zero");
    
    // Optional: Log the change
    uint oldValue = monthlyInterestPercent;
    monthlyInterestPercent = p;
    emit InterestRateChanged(oldValue, p);
}

/**
 * @notice Set penalty percentage for late payments
 * @dev Includes safety checks for reasonable values
 * @param p New penalty percentage
 */
function setPenaltyPercent(uint p) public onlyemployes caller_zero_Address {
    require(p <= 5000, "Penalty too high: max 50%");
    require(p >= 100, "Penalty too low: min 1%");
    
    uint oldValue = penaltyPercent;
    penaltyPercent = p;
    emit PenaltyPercentChanged(oldValue, p);
}

/**
 * @notice Set collateral ratio percentage
 * @dev Includes safety checks for reasonable values
 * @param p New collateral ratio percentage
 */
function setCollateralRatioPercent(uint p) public onlyemployes caller_zero_Address {
    require(p >= 10000, "Collateral ratio too low: min 100%");
    require(p <= 30000, "Collateral ratio too high: max 300%");
    
    uint oldValue = collateralRatioPercent;
    collateralRatioPercent = p;
    emit CollateralRatioChanged(oldValue, p);
}

/**
 * @notice Set maximum Non-Performing Loan percentage
 * @dev Includes safety checks for reasonable values
 * @param p New maximum NPL percentage
 */
function setMaxNPLPercent(uint p) public onlyemployes caller_zero_Address {
    require(p <= 5000, "NPL limit too high: max 50%");
    
    uint oldValue = maxNPLPercent;
    maxNPLPercent = p;
    emit MaxNPLChanged(oldValue, p);
}

/**
 * @notice Set management wallet address for profit distribution
 * @dev Includes safety checks for valid address
 * @param w New management wallet address
 */
function setManagementWallet(address payable w) public onlyemployes caller_zero_Address {
    require(w != address(0), "Cannot set zero address");
    require(w != address(this), "Cannot set contract itself");
    
    address oldWallet = managementWallet;
    managementWallet = w;
    emit ManagementWalletChanged(oldWallet, w);
}

/**
 * @notice Remove a user from the blacklist
 * @dev Checks if user is actually blacklisted before removing
 * @param user Address to remove from blacklist
 */
function unblacklist(address user) public onlyemployes caller_zero_Address {
    require(user != address(0), "Cannot unblacklist zero address");
    require(blacklist[user], "Address is not blacklisted");
    
    blacklist[user] = false;
    emit UnBlacklisted(user);
}
    // take profits to management wallet
    function takeProfits() public onlyemployes caller_zero_Address {
        uint amount = totalProfits;
        require(amount > 0, "no profits");
        totalProfits = 0;
        (bool ok, ) = managementWallet.call{value: amount}("");
        require(ok, "transfer failed");
        emit ProfitTaken(managementWallet, amount);
    }

    // ------------------------------
    // Utilities & Getters
    // ------------------------------
    function TotalLoan() public view onlyemployes caller_zero_Address returns (uint) {
        return loans.length;
    }

    function loanInfo(uint loanId) public view onlyemployes caller_zero_Address returns (
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
    ) {
        Loan storage ln = loans[loanId];
        borrower = ln.borrower;
        principal = ln.principal;
        durationMonths = ln.durationMonths;
        startTimestamp = ln.startTimestamp;
        paidMonths = ln.paidMonths;
        consecutiveMissed = ln.consecutiveMissed;
        remainingPrincipal = ln.remainingPrincipal;
        collateral = ln.collateral;
        liquidated = ln.liquidated;
        active = ln.active;
    }



//********************************************  INTERNAL  ********************************

function _invalidId(uint Id) internal view {
    require(Id < loans.length, "invalid Id");
}

/// @dev helper to compute months since start (30 days per month used)
    function _monthsSince(uint startTs, uint nowTs) internal pure returns (uint) {
        if (nowTs <= startTs) return 0;
        // use 30 days as one month for simplicity
        uint secondsPerMonth = 30 days;
        return (nowTs - startTs) / secondsPerMonth;
    }

   function _now() internal view returns (uint) { return block.timestamp; }

 /// @dev seize collateral to cover X months of due (principal+interest+penalty), prioritizing principal if collateral insufficient
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
            // split: interest+penalty -> profit, principal -> reduce remainingPrincipal
            // interest portion per month:
            uint interestPerMonth = (ln.principal * monthlyInterestPercent) / 100;
            uint totalInterest = interestPerMonth * toCover;
            totalProfits += totalInterest + totalPenalty;

            // principal covered:
            uint principalCovered = totalMonthlyDue - (interestPerMonth * toCover);
            if (principalCovered > ln.remainingPrincipal) principalCovered = ln.remainingPrincipal;
            ln.remainingPrincipal -= principalCovered;

            ln.collateral -= usedCollateral;
            // any leftover in collateral remains stored on loan (could be used later)
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
                // cover all principal needed for this period
                // we need to determine how much principal portion would be part of the toCover months:
                // approximate principal portion: principal/month * toCover
                uint principalPortion = (ln.principal / ln.durationMonths) * toCover;
                if (principalPortion > ln.remainingPrincipal) principalPortion = ln.remainingPrincipal;
                if (principalPortion > remaining) {
                    // partial cover
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
                // no extra profit
            }

            // collateral consumed fully
            ln.collateral = 0;
            deficit = needed > usedCollateral ? (needed - usedCollateral) : 0;
        }

        // mark that some months are considered "handled" by liquidation: increase paidMonths as principal covered
        // We'll consider those months as paid if principal for those months covered.
        // For simplicity, treat toCover months as resolved (we may cap by remainingPrincipal).
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

    /// @dev final liquidation at end of term to recover outstanding principal+interest+penalty
    function _finalLiquidation(uint loanId) internal {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        if (ln.liquidated) return;

        // compute outstanding total due (remaining principal + remaining interest estimate + penalties)
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
            // interest/penalty -> profits
            uint interestPerMonth = (ln.principal * monthlyInterestPercent) / 100;
            uint totalInterest = interestPerMonth * monthsRemaining;
            totalProfits += totalInterest + totalPenalty;

            // principal covered:
            uint principalCovered = totalMonthlyDue - (interestPerMonth * monthsRemaining);
            if (principalCovered > ln.remainingPrincipal) principalCovered = ln.remainingPrincipal;
            ln.remainingPrincipal -= principalCovered;

            ln.collateral -= usedCollateral;
        } else {
            usedCollateral = ln.collateral;
            // apply same priority logic: principal first, then interest/penalty, leftover profit
            uint remaining = usedCollateral;
            // attempt to cover principal
            uint principalPortion = (ln.principal / ln.durationMonths) * monthsRemaining;
            if (principalPortion > ln.remainingPrincipal) principalPortion = ln.remainingPrincipal;
            if (remaining >= principalPortion) {
                remaining -= principalPortion;
                ln.remainingPrincipal -= principalPortion;
            } else {
                ln.remainingPrincipal -= remaining;
                remaining = 0;
            }
            // cover interest+penalty with remaining
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

        // mark loan as liquidated
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
