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
    }

    modifier onlyRegistered() {
        require(users[msg.sender].isRegistered, "Not registered");
        _;
    }



//*****************************************************************************  USER  **********************************
    function register(string calldata name, uint8 age) public notEmployes caller_zero_Address notOwner{
        require(age > 17, "Too young !");
        require(age < 100, "Too old !");
        User storage u = users[msg.sender];
        require(!u.isRegistered, "Already registered");
        u.name = name;
        u.age = age;
        u.isRegistered = true;
        usercount++;
        emit User_registered(msg.sender, name, age);
    }

    function unregister() public onlyRegistered notEmployes caller_zero_Address notOwner{
        User storage u = users[msg.sender];
        uint refund = u.balance;
        u.balance = 0;
        u.isRegistered = false;
        usercount--;
        if (refund > 0) {
            (bool sent, ) = payable(msg.sender).call{value: refund}("");
            require(sent, "Refund failed");
        }
        emit User_unregistered(msg.sender, u.name, u.age);
    }

    function deposit() public payable virtual onlyRegistered notEmployes caller_zero_Address notOwner{
        regular.greater_than_0(msg.value);
        uint fee = (msg.value * depositFeePercent) / 100;
        uint netAmount = msg.value - fee;
        collectedFees += fee;
        users[msg.sender].balance += netAmount;
        emit User_deposit(msg.sender, netAmount);
    }

    function withdraw(uint amount) public virtual onlyRegistered notEmployes caller_zero_Address notOwner{
        regular.greater_than_0(amount);
        User storage u = users[msg.sender];
        require(u.balance >= amount, "Insufficient balance");
        u.balance -= amount;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdraw failed");
        emit User_withdraw(msg.sender, amount);
    }

    function transfer(address payable to, uint amount) public onlyRegistered notEmployes caller_zero_Address notOwner{
        regular.greater_than_0(amount);
        protectFromZeroAddress(to);
        require(users[to].isRegistered, "Not registered!");
        User storage sender = users[msg.sender];
        uint fee = (amount * transferFeePercent) / 100;
        sender.balance -= (amount + fee);
        collectedFees += fee;
        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");
        emit User_transfer(msg.sender, to, amount);
    }


//********************************************************************************  ADMIN  ************************************************
    function withdrawCollectedFees() public onlyemployes caller_zero_Address {
        uint amount = collectedFees;
        collectedFees = 0;
        (bool sent, ) = managementWallet.call{value: amount}("");
        require(sent, "Fee transfer failed");
    }

    function set_deposit_fee_percent(uint _newDepositFeePercent) public onlyemployes caller_zero_Address {
        require(_newDepositFeePercent <= 100, "Fee too high");
        depositFeePercent = _newDepositFeePercent;
    }

    function set_transfer_fee_percent(uint _newTransferFeePercent) public onlyemployes caller_zero_Address {
        require(_newTransferFeePercent <= 100, "Fee too high");
        transferFeePercent = _newTransferFeePercent;
    }

    function see_Contract_Balances() public view onlyemployes caller_zero_Address returns (uint) {
        return address(this).balance / 1 ether;
    }

    function totalUsers() public view onlyemployes caller_zero_Address returns (uint) {
        return usercount;
    }


//********************************************************************************************************************************************************************
//                                                                            LOAN
//********************************************************************************************************************************************************************

  function change_loan_contract_management_wallet(address payable new_wallet) public onlyemployes caller_zero_Address {
        managementWallet = new_wallet;
    }

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
    event ProfitTaken(address indexed to, uint amount);

    // ------------------------------
    // Helpers / View
    // ------------------------------
    function _now() internal view returns (uint) { return block.timestamp; }

    /// @dev monthly due for a loan (principal portion + interest portion) in wei for months that are still equal
    /// principal part per month uses integer division; last month may adjust when borrower pays final.
    function monthlyDue(uint loanId) public view notEmployes caller_zero_Address notOwner returns (uint) {
        Loan storage ln = loans[loanId];
        require(ln.durationMonths > 0, "invalid loan");
        uint principalPart = ln.principal / ln.durationMonths; // truncated
        uint interestPart = (ln.principal * monthlyInterestPercent) / 100; // interest calculated on original principal (fixed monthly)
        return principalPart + interestPart;
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
        require(loansAllowed(), "new loans blocked due to high NPL");

        uint principal = principalInETH * 1 ether;
        uint requiredCollateral = (principal * collateralRatioPercent) / 100;
        require(msg.value >= requiredCollateral, "insufficient collateral sent");

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

    /// @notice admin approves and disburses the loan (calls by owner or employees depending on your policy)
    /// @param loanId id returned from request
    function approveLoan(uint loanId) public onlyemployes caller_zero_Address {
        require(loanId < loans.length, "invalid loan id");
        Loan storage ln = loans[loanId];
        require(!ln.liquidated, "already liquidated");
        require(!ln.active, "already active");
        // ensure contract has liquidity to disburse principal
        require(address(this).balance >= ln.principal, "contract lacks disbursement liquidity");

        ln.startTimestamp = _now();
        ln.active = true;

        // disburse principal to borrower
        (bool ok, ) = payable(ln.borrower).call{value: ln.principal}("");
        require(ok, "disburse failed");

        emit LoanApproved(loanId, ln.borrower, ln.startTimestamp);
        emit LoanDisbursed(loanId, ln.borrower, ln.principal);
    }

    /// @notice admin can reject a loan request (collateral returned)
    function rejectLoan(uint loanId) public onlyemployes caller_zero_Address {
        require(loanId < loans.length, "invalid loan id");
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

    // ------------------------------
    // Monthly Payment Flow
    // ------------------------------

    /// @notice Pay monthly installment. Caller must send exact required net amount
    /// @param loanId loan id
    function payMonthly(uint loanId) public notEmployes caller_zero_Address notOwner payable {
        require(loanId < loans.length, "invalid loan id");
        Loan storage ln = loans[loanId];
        require(ln.active && !ln.liquidated, "loan not active or liquidated");
        require(msg.sender == ln.borrower, "only borrower");

        // compute which month is due: months since start (floor)
        uint monthsSinceStart = _monthsSince(ln.startTimestamp, _now());
        // borrower can pay next due month (monthsSinceStart may be >= paidMonths)
        require(ln.paidMonths < ln.durationMonths, "loan already fully paid");

        // monthly due calculated as: principal/month + fixed monthly interest (interest on original principal)
        uint monthly = monthlyDue(loanId);

        // if paying for a past-due month, penalties may apply (we accept paying only single monthly at a time)
        // compute how many months are overdue before this payment:
        uint dueMonthIndex = ln.paidMonths; // 0-based index of next unpaid month
        uint timeAllowedMonths = monthsSinceStart; // months that have passed
        // if paying late (timeAllowedMonths > dueMonthIndex), apply penalty per late month already counted
        uint penalty = 0;
        if (timeAllowedMonths > dueMonthIndex) {
            uint lateCount = timeAllowedMonths - dueMonthIndex;
            // penalty applied per missed/late month on the monthly due
            penalty = (monthly * penaltyPercent / 100) * lateCount;
        }

        uint expected = monthly + penalty;
        require(msg.value == expected, "msg.value mismatch monthly+penalty");

        // process payment:
        // 1) interest portion goes to profits immediately
        uint interestPart = (ln.principal * monthlyInterestPercent) / 100;
        uint principalPart = monthly - interestPart;

        // add interest and penalty to profits
        totalProfits += interestPart + penalty;

        // reduce remaining principal by principalPart (last month adjustment handled by remaining principal)
        if (principalPart > ln.remainingPrincipal) {
            // if rounding caused larger principalPart, cap
            principalPart = ln.remainingPrincipal;
        }
        ln.remainingPrincipal -= principalPart;

        // update paid months and reset consecutive missed
        ln.paidMonths += 1;
        ln.consecutiveMissed = 0;

        emit MonthlyPaymentMade(loanId, msg.sender, msg.value, ln.paidMonths);

        // If loan fully repaid, mark inactive
        if (ln.paidMonths >= ln.durationMonths || ln.remainingPrincipal == 0) {
            ln.active = false;
            // any remaining collateral should be returned to borrower automatically
            uint coll = ln.collateral;
            ln.collateral = 0;
            if (coll > 0) {
                (bool ok, ) = payable(ln.borrower).call{value: coll}("");
                // if refund fails (shouldn't normally), leave collateral as 0 and continue (we won't revert here)
                if (ok) {
                    // nothing extra
                } else {
                    // cannot revert, but ideally handle off-chain
                }
            }
        }
    }

    /// @dev helper to compute months since start (30 days per month used)
    function _monthsSince(uint startTs, uint nowTs) internal pure returns (uint) {
        if (nowTs <= startTs) return 0;
        // use 30 days as one month for simplicity
        uint secondsPerMonth = 30 days;
        return (nowTs - startTs) / secondsPerMonth;
    }

    // ------------------------------
    // Monitoring & Auto-Liquidation
    // ------------------------------

    /// @notice Called to check loan status and auto-liquidate if conditions met.
    /// Anyone can call to trigger checks; this is gas-paid by caller.
    function checkAndProcessLoan(uint loanId) public notEmployes caller_zero_Address notOwner {
        require(loanId < loans.length, "invalid loan id");
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

    /// @dev seize collateral to cover X months of due (principal+interest+penalty), prioritizing principal if collateral insufficient
    function _liquidateForConsecutiveMisses(uint loanId, uint monthsToCover) internal {
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

    // ------------------------------
    // Admin functions
    // ------------------------------
    function setMonthlyInterestPercent(uint p) public onlyemployes caller_zero_Address {
        monthlyInterestPercent = p;
    }

    function setPenaltyPercent(uint p) public onlyemployes caller_zero_Address {
        penaltyPercent = p;
    }

    function setCollateralRatioPercent(uint p) public onlyemployes caller_zero_Address {
        collateralRatioPercent = p;
    }

    function setMaxNPLPercent(uint p) public onlyemployes caller_zero_Address {
        maxNPLPercent = p;
    }

    function setManagementWallet(address payable w) public onlyemployes caller_zero_Address {
        managementWallet = w;
    }

    function unblacklist(address user) public onlyemployes caller_zero_Address {
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
    function loanCount() public view onlyemployes caller_zero_Address returns (uint) {
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
}
