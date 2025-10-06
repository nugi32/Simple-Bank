# 🏦 Conventional Bank-Style Loan Manager (ETH-based)

A Solidity smart contract system that simulates a **traditional bank loan mechanism** using **ETH** as the base currency.  
It supports **collateralized loans**, **interest**, **penalties**, and **liquidation logic**, while being upgradeable and secure against common vulnerabilities.

## ✨ Features

- 💰 **ETH-Denominated Loans** — Borrow and repay in ETH.  
- 🧍 **Role-Based Access Control** — Custom `AccessControl` system to manage privileged roles.  
- 📊 **Interest & Penalty Management** — Configurable interest rates and penalties for late payments.  
- 🛡 **Collateralization** — Each loan requires collateral; automatic liquidation if collateral ratio falls below threshold.  
- 🔐 **Reentrancy Protection** — Uses OpenZeppelin’s `ReentrancyGuardUpgradeable`.  
- 🧠 **Upgradeable Architecture** — Built with `Initializable` for use in proxy patterns.  
- ⏱ **Time Utilities** — Helper library for time calculations in loan schedules.
