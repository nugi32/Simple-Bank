// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Owner/employe_assignment.sol";
import "../lib/regular.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../lib/TimeUtils.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title Conventional Bank-Style Loan Manager (ETH-based)
/// @notice Manages ETH-denominated loans with collateral, interest, penalties, and liquidation logic
contract LoanData is EmployeeAssignment, Initializable, ReentrancyGuardUpgradeable {
    
// ================================
// Section Headers
// ================================

// 1. Structs
// 2. State Variables  
// 3. Events
// 4. Custom Errors
// 5. Modifiers
// 6. Initialization
// 7. User Functions
// 8. Admin Functions
// 9. View Functions
// 10. Internal Functions


    // ================================
    // Structs
    // ================================
    
    /// @notice Structure representing a loan
    /// @dev Contains all relevant information about a loan
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
    
    /// @notice Array of all loans
    Loan[] public loans;
    
    /// @notice Monthly interest rate in percent (e.g., 2 for 2%)
    uint16 public monthlyInterestPercent;
    
    /// @notice Penalty percentage for missed payments
    uint16 public penaltyPercent;
    
    /// @notice Collateral ratio required for loans
    uint16 public collateralRatioPercent;
    
    /// @notice Maximum Non-Performing Loan percentage allowed
    uint16 public maxNPLPercent;
    
    /// @notice Total profits accumulated by the protocol
    uint public totalProfits;
    
    /// @notice Wallet address for management fees
    address payable internal managementWallet;
    
    /// @notice Address of the AdminLogic contract for delegated calls
    address internal AdminLogic;
    
    /// @notice Mapping of blacklisted addresses
    mapping(address => bool) public blacklist;
    
    /// @notice Mapping of strikes count per address
    mapping(address => uint) public strikes;
    
    /// @notice Storage gap for future variable additions (upgrade safety)
    uint256[50] private __gap;

    // ================================
    // Events
    // ================================
    
    event InitialAddress(address indexed managementWallet, address indexed AdminLogic);
    event LoanRequested(uint indexed loanId, address indexed borrower, uint principal, uint durationMonths, uint collateral);
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
    event AdminLogicChanged(address indexed oldContract, address indexed newContract);
    event LoanLiquidated(uint indexed loanId, address indexed borrower, uint collateralUsed, uint deficitCovered, uint profitFromCollateral);
    event StrikeAdded(address indexed borrower, uint strikes);
    event Blacklistedi(address indexed borrower);

    // ================================
    // Custom Errors
    // ================================
    
    error ZeroAddress();
    error InvalidLoanId(uint256 id);
    error Blacklisted(address user);
    error NotBlacklisted(address user);
    error NotBorrower();
    error LoanInactiveOrLiquidated();
    error InsufficientCollateral(uint256 required, uint256 provided);
    error ContractLiquidityInsufficient(uint256 required, uint256 available);
    error PaymentValueMismatch(uint256 expected, uint256 received);
    error InvalidPrincipal();
    error InvalidDuration();
    error NewLoansBlocked();
    error DelegateCallFailed(string fn);

    // ================================
    // Modifiers
    // ================================
    
    /// @notice Ensures the caller is not the zero address
    modifier callerZeroAddr() {
        zero_Address(msg.sender);
        _;
    }

    // ================================
    // Initialization
    // ================================
    
    /// @notice Initializes the contract with required addresses and default parameters
    /// @dev Called during contract deployment/upgrade
    /// @param _managementWallet Address for management fees
    /// @param _AdminLogic Address of AdminLogic contract for delegated calls
    function initialize(address payable _managementWallet, address _AdminLogic) public initializer {
        __ReentrancyGuard_init();
        
        if (_managementWallet == address(0)) revert ZeroAddress();
        
        managementWallet = _managementWallet;
        monthlyInterestPercent = 2;    // 2% per month
        penaltyPercent = 1;            // 1% penalty per missed month
        collateralRatioPercent = 50;   // 50% collateral relative to principal
        maxNPLPercent = 20;
        AdminLogic = _AdminLogic;

        emit InitialAddress(_managementWallet, _AdminLogic);
    }

    // ================================
    // Fallback Function
    // ================================
    
    /// @notice Allows the contract to receive ETH
    receive() external payable {}

    // =================================================
    // USER FUNCTIONS
    // =================================================

    /**
     * @notice Request a loan and deposit collateral (send collateral with the call)
     * @dev Creates a new loan request with specified principal and duration
     * @param principalInETH Loan amount in ETH
     * @param durationMonths Loan duration in months
     */
    function requestLoan(uint principalInETH, uint durationMonths)
        external
        payable
        notEmployes
        notOwner
        callerZeroAddr
    {
        if (blacklist[msg.sender]) revert Blacklisted(msg.sender);
        if (principalInETH == 0) revert InvalidPrincipal();
        if (durationMonths < 1) revert InvalidDuration();
        if (!loansAllowed()) revert NewLoansBlocked();

        uint principal = principalInETH * 1 ether;
        uint requiredCollateral = (principal * collateralRatioPercent) / 100;
        
        if (msg.value < requiredCollateral) {
            revert InsufficientCollateral(requiredCollateral, msg.value);
        }

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

    /**
     * @notice Pay monthly installment(s). Caller can pay for one or more months at once.
     * @dev Processes payment for specified number of months including penalties if applicable
     * @param loanId ID of the loan to make payment for
     * @param monthsToPay Number of months to pay
     */
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

        if (!ln.active || ln.liquidated) revert LoanInactiveOrLiquidated();
        if (msg.sender != ln.borrower) revert NotBorrower();
        if (monthsToPay == 0) revert InvalidDuration();
        if (ln.paidMonths + monthsToPay > ln.durationMonths) revert InvalidDuration();

        uint monthsSinceStart = _monthsSince(ln.startTimestamp, TimeUtils._now());
        if (ln.paidMonths >= ln.durationMonths) revert InvalidDuration();

        uint monthly = monthlyDue(loanId);

        // Calculate penalty for overdue months
        uint dueMonthIndex = ln.paidMonths;
        uint timeAllowedMonths = monthsSinceStart;
        uint penalty = 0;
        
        if (timeAllowedMonths > dueMonthIndex) {
            uint lateCount = timeAllowedMonths - dueMonthIndex;
            penalty = (monthly * penaltyPercent / 100) * lateCount;
        }

        uint totalPaymentNeeded = monthly + penalty;
        if (monthsToPay > 1) {
            totalPaymentNeeded += monthly * (monthsToPay - 1);
        }

        if (msg.value != totalPaymentNeeded) {
            revert PaymentValueMismatch(totalPaymentNeeded, msg.value);
        }

        // Process payments
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

        // If loan fully repaid, mark inactive and refund collateral
        if (ln.paidMonths >= ln.durationMonths || ln.remainingPrincipal == 0) {
            ln.active = false;
            uint coll = ln.collateral;
            ln.collateral = 0;
            if (coll > 0) {
                (bool ok, ) = payable(ln.borrower).call{value: coll}("");
                require(ok, "Collateral failed to send!");
            }
        }
    }

    /**
     * @notice Called to check loan status and auto-liquidate if conditions met
     * @dev Monitors loan status and triggers liquidation if criteria are met
     * @param loanId ID of the loan to check
     */
    function checkAndProcessLoan(uint loanId)
        external
        notEmployes
        notOwner
        callerZeroAddr
    {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        if (!ln.active || ln.liquidated) return;

        uint monthsPassed = _monthsSince(ln.startTimestamp, TimeUtils._now());
        uint expectedPaid = monthsPassed;
        
        if (expectedPaid > ln.durationMonths) {
            expectedPaid = ln.durationMonths;
        }

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

    // =================================================
    // ADMIN FUNCTIONS
    // =================================================

    // -----------------------------
    // Loan Approval & Management
    // -----------------------------

    /**
     * @notice Admin can reject a loan request (collateral returned)
     * @dev Rejects a pending loan and refunds collateral to borrower
     * @param loanId ID of the loan to reject
     */
    function rejectLoan(uint loanId) external 
        onlyEmployes 
        nonReentrant
        callerZeroAddr
    {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        if (ln.active || ln.liquidated) revert LoanInactiveOrLiquidated();

        uint coll = ln.collateral;
        ln.collateral = 0;
        (bool ok, ) = payable(ln.borrower).call{value: coll}("");
        require(ok, "Refund failed");

        ln.liquidated = true;
        emit LoanLiquidated(loanId, ln.borrower, coll, 0, 0);
    }

    /**
     * @notice Admin approves and disburses the loan
     * @dev Approves a pending loan and transfers principal to borrower
     * @param loanId ID of the loan to approve
     */
    function approveLoan(uint loanId) external
        onlyEmployes
        nonReentrant
        callerZeroAddr
    {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        if (ln.liquidated) revert LoanInactiveOrLiquidated();
        if (ln.active) revert LoanInactiveOrLiquidated();

        if (address(this).balance < ln.principal) {
            revert ContractLiquidityInsufficient(ln.principal, address(this).balance);
        }

        ln.startTimestamp = TimeUtils._now();
        ln.active = true;

        (bool ok, ) = payable(ln.borrower).call{value: ln.principal}("");
        require(ok, "Disburse failed");

        emit LoanApproved(loanId, ln.borrower, ln.startTimestamp);
        emit LoanDisbursed(loanId, ln.borrower, ln.principal);
    }

    /**
     * @notice Remove a user from the blacklist
     * @dev Removes an address from the blacklist allowing them to request loans
     * @param user Address to remove from blacklist
     */
    function unblacklist(address user) external 
        onlyEmployes
        callerZeroAddr
    {
        zero_Address(user);
        if (!blacklist[user]) revert NotBlacklisted(user);

        blacklist[user] = false;
        emit UnBlacklisted(user);
    }

    // -----------------------------
    // Rate Configuration
    // -----------------------------

    /**
     * @notice Set monthly interest percentage
     * @dev Delegates call to AdminLogic contract
     * @param p New monthly interest percentage
     */
    function setMonthlyInterestPercent(uint16 p) external
        onlyEmployes
        callerZeroAddr
    {
        _delegateTo(
            AdminLogic,
            abi.encodeWithSignature("MonthlyInterestPercent(uint16)", p), 
            "MonthlyInterestPercent"
        );
    }

    /**
     * @notice Set penalty percentage
     * @dev Delegates call to AdminLogic contract
     * @param p New penalty percentage
     */
    function setPenaltyPercent(uint16 p) external
        onlyEmployes
        callerZeroAddr
    {
        _delegateTo(
            AdminLogic,
            abi.encodeWithSignature("PenaltyPercent(uint16)", p), 
            "PenaltyPercent"
        );
    }

    /**
     * @notice Set collateral ratio percentage
     * @dev Delegates call to AdminLogic contract
     * @param p New collateral ratio percentage
     */
    function setCollateralRatioPercent(uint16 p) external
        onlyEmployes
        callerZeroAddr
    {
        _delegateTo(
            AdminLogic,
            abi.encodeWithSignature("CollateralRatioPercent(uint16)", p), 
            "CollateralRatioPercent"
        );
    }

    /**
     * @notice Set maximum NPL percentage
     * @dev Delegates call to AdminLogic contract
     * @param p New maximum NPL percentage
     */
    function setMaxNPLPercent(uint16 p) external
        onlyEmployes
        callerZeroAddr
    {
        _delegateTo(
            AdminLogic,
            abi.encodeWithSignature("MaxNPLPercent(uint16)", p), 
            "MaxNPLPercent"
        );
    }

    // -----------------------------
    // Profit Management
    // -----------------------------

    /**
     * @notice Set management wallet address
     * @dev Delegates call to AdminLogic contract
     * @param w New management wallet address
     */
    function setManagementWallet(address payable w) external
        onlyEmployes
        callerZeroAddr
    {
        _delegateTo(
            AdminLogic,
            abi.encodeWithSignature("ManagementWallet(address)", w), 
            "ManagementWallet"
        );
    }

    /**
     * @notice Take accumulated profits
     * @dev Delegates call to AdminLogic contract to transfer profits
     */
    function takeProfits() external 
        onlyEmployes 
        nonReentrant 
        callerZeroAddr
    {
        _delegateTo(
            AdminLogic,
            abi.encodeWithSignature("TP()"), 
            "TP"
        );
    }

    // -----------------------------
    // AdminLogic Configuration
    // -----------------------------

    /**
     * @notice Set the AdminLogic contract address
     * @dev Only owner can change the AdminLogic contract
     * @param _AdminLogic New AdminLogic contract address
     */
    function setLogicAdminContract(address _AdminLogic) external callerZeroAddr onlyOwner {
        if (_AdminLogic == address(0)) revert ZeroAddress();
        
        address oldContract = AdminLogic;
        address newContract = _AdminLogic;
        AdminLogic = _AdminLogic;
        
        emit AdminLogicChanged(oldContract, newContract);
    }

    // ================================
    // View Functions
    // ================================

    /**
     * @notice Get total number of loans
     * @return uint Total number of loans
     */
    function TotalLoan() external view
        onlyEmployes 
        callerZeroAddr
        returns (uint)
    {
        return loans.length;
    }

    /**
     * @notice Get detailed information about a loan
     * @param loanId ID of the loan to query
     * @return borrower Borrower address
     * @return principal Original principal amount
     * @return durationMonths Loan duration in months
     * @return startTimestamp Loan start timestamp
     * @return paidMonths Number of months paid
     * @return consecutiveMissed Consecutive missed payments
     * @return remainingPrincipal Remaining principal amount
     * @return collateral Collateral amount
     * @return liquidated Whether loan is liquidated
     * @return active Whether loan is active
     */
    function loanInfo(uint loanId)
        external
        view
        onlyEmployes
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
        _invalidId(loanId);
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

    // ================================
    // Internal Functions
    // ================================

    /**
     * @dev Execute delegate call to AdminLogic contract
     * @param target Target contract address
     * @param data Call data
     * @param fnName Function name for error reporting
     */
    function _delegateTo(
        address target,
        bytes memory data,
        string memory fnName
    ) internal {
        (bool ok, bytes memory res) = target.delegatecall(data);
        if (!ok) {
            if (res.length > 0) {
                assembly {
                    revert(add(res, 32), mload(res))
                }
            } else {
                revert DelegateCallFailed(fnName);
            }
        }
    }

    /**
     * @dev Validate loan ID
     * @param Id Loan ID to validate
     */
    function _invalidId(uint Id) internal view {
        if (Id >= loans.length) revert InvalidLoanId(Id);
    }

    /**
     * @dev Check if new loans are allowed based on NPL ratio
     * @return bool True if new loans are allowed
     */
    function loansAllowed() internal view returns (bool) {
        if (maxNPLPercent == 0) return true;
        return currentNPL() < maxNPLPercent;
    }

    /**
     * @dev Calculate monthly due amount for a loan
     * @param loanId ID of the loan
     * @return uint Monthly due amount
     */
    function monthlyDue(uint loanId) internal view returns (uint) {
        _invalidId(loanId);
        Loan storage ln = loans[loanId];
        if (ln.durationMonths == 0) revert InvalidDuration();

        uint principalPart = ln.principal / ln.durationMonths;
        uint interestPart = (ln.principal * monthlyInterestPercent) / 100;
        return principalPart + interestPart;
    }

    /**
     * @dev Calculate months between two timestamps
     * @param startTs Start timestamp
     * @param nowTs Current timestamp
     * @return uint Number of months passed
     */
    function _monthsSince(uint startTs, uint nowTs) internal pure returns (uint) {
        if (nowTs <= startTs) return 0;
        uint secondsPerMonth = 30 days;
        return (nowTs - startTs) / secondsPerMonth;
    }

    /**
     * @dev Calculate current Non-Performing Loan percentage
     * @return uint Current NPL percentage
     */
    function currentNPL() internal view returns (uint) {
        if (loans.length == 0) return 0;
        
        uint bad = 0;
        for (uint i = 0; i < loans.length; i++) {
            if (loans[i].liquidated) bad++;
        }
        
        return (bad * 100) / loans.length;
    }

    // ================================
    // Liquidation Functions
    // ================================

    /**
     * @dev Liquidate loan for consecutive missed payments
     * @param loanId ID of the loan to liquidate
     * @param monthsToCover Number of months to cover with liquidation
     */
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
        uint totalPenalty = (totalMonthlyDue * penaltyPercent) / 100;
        uint needed = totalMonthlyDue + totalPenalty;

        uint usedCollateral = 0;
        uint profitFromCollateral = 0;
        uint deficit = 0;

        if (ln.collateral >= needed) {
            usedCollateral = needed;

            uint interestPerMonth = (ln.principal * monthlyInterestPercent) / 100;
            uint totalInterest = interestPerMonth * toCover;
            totalProfits += totalInterest + totalPenalty;

            uint principalCovered = totalMonthlyDue - (interestPerMonth * toCover);
            if (principalCovered > ln.remainingPrincipal) principalCovered = ln.remainingPrincipal;
            ln.remainingPrincipal -= principalCovered;

            ln.collateral -= usedCollateral;
        } else {
            usedCollateral = ln.collateral;
            uint remaining = usedCollateral;

            // Cover principal portion
            uint principalPortion = (ln.principal / ln.durationMonths) * toCover;
            if (principalPortion > ln.remainingPrincipal) principalPortion = ln.remainingPrincipal;
            
            if (principalPortion > remaining) {
                ln.remainingPrincipal -= remaining;
                remaining = 0;
            } else {
                ln.remainingPrincipal -= principalPortion;
                remaining -= principalPortion;
            }

            // Cover interest and penalties
            uint interestPerMonth = (ln.principal * monthlyInterestPercent) / 100;
            uint totalInterest = interestPerMonth * toCover;
            uint toCoverInterestPenalties = totalInterest + totalPenalty;

            if (remaining >= toCoverInterestPenalties) {
                totalProfits += toCoverInterestPenalties;
                remaining -= toCoverInterestPenalties;
                profitFromCollateral += remaining;
            } else {
                totalProfits += remaining;
                remaining = 0;
            }

            ln.collateral = 0;
            deficit = needed > usedCollateral ? (needed - usedCollateral) : 0;
        }

        ln.paidMonths += toCover;
        if (ln.paidMonths > ln.durationMonths) ln.paidMonths = ln.durationMonths;
        ln.consecutiveMissed = 0;

        strikes[ln.borrower] += 1;
        emit StrikeAdded(ln.borrower, strikes[ln.borrower]);

        if (strikes[ln.borrower] >= 3) {
            blacklist[ln.borrower] = true;
            emit Blacklistedi(ln.borrower);
        }

        if (ln.paidMonths >= ln.durationMonths || ln.remainingPrincipal == 0) {
            ln.active = false;
            ln.liquidated = true;
        }

        emit LoanLiquidated(loanId, ln.borrower, usedCollateral, deficit, profitFromCollateral);
    }

    /**
     * @dev Final liquidation at loan maturity
     * @param loanId ID of the loan to liquidate
     */
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

            // Cover principal portion
            uint principalPortion = (ln.principal / ln.durationMonths) * monthsRemaining;
            if (principalPortion > ln.remainingPrincipal) principalPortion = ln.remainingPrincipal;
            
            if (remaining >= principalPortion) {
                remaining -= principalPortion;
                ln.remainingPrincipal -= principalPortion;
            } else {
                ln.remainingPrincipal -= remaining;
                remaining = 0;
            }

            // Cover interest and penalties
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
            emit Blacklistedi(ln.borrower);
        }

        emit LoanLiquidated(loanId, ln.borrower, usedCollateral, deficit, profitFromCollateral);
    }
}