function _now() internal view returns (uint);

function monthlyDue(uint loanId) public view virtual returns (uint);

function currentNPL() public view returns (uint);****************************

function loansAllowed() public view virtual returns (bool);

receive() external payable;

function fundContract() external virtual payable;

function requestLoan(uint principalInETH, uint durationMonths) external virtual payable;

function approveLoan(uint loanId) external virtual;

function rejectLoan(uint loanId) external virtual;

function payMonthly(uint loanId) external virtual payable;

function _monthsSince(uint startTs, uint nowTs) internal pure returns (uint);

function checkAndProcessLoan(uint loanId) public virtual;

function _liquidateForConsecutiveMisses(uint loanId, uint monthsToCover) internal;

function _finalLiquidation(uint loanId) internal;

function setMonthlyInterestPercent(uint p) external virtual;

function setPenaltyPercent(uint p) external virtual;

function setCollateralRatioPercent(uint p) external virtual;

function setMaxNPLPercent(uint p) external virtual;

function setManagementWallet(address payable w) external virtual;

function unblacklist(address user) external virtual;

function takeProfits() external virtual;

function loanCount() public view virtual returns (uint);

function loanInfo(uint loanId) public view virtual returns (
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
