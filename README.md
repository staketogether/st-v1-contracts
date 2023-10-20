# Stake Together Smart Contracts

Welcome to the smart contracts of **Stake Together**. This is an Ethereum staking protocol designed especially for communities.

## 📜 License

The contracts are licensed under **BUSL-1.1**.

The interfaces are licensed under **GPL-3.0**.

## 📋 Table of Contents

- Protocol Overview
- Contract Summaries
- Environment Setup
- How to Run
- How to Test
- How to Deploy
- About

## Protocol Overview

The **Stake Together** protocol functions as a staking pool mechanism, allowing users to create and deposit ether into staking pools. Each deposit results in the issuance of an **stpETH** token as collateral.

When the total staked ether reaches 32 ETH, a validator oracle is triggered to create a validator. This ether is then transferred to the beacon chain.

Reports are generated daily by oracles and, once a consensus among them is reached, and after a certain delay, the report is executed. This can lead to various actions, including sending ETH to the **Stake Together** contract, the **Withdrawals** contract, and generating airdrop rewards in the **Airdrop** contract.

Users can request withdrawals, which are processed by the **Stake Together** contract or, in the absence of liquidity, can burn stpETH to generate stwETH.

## Contract Summaries

- **Stake Together**: Manages pools, deposits, withdrawals, and validator creation.
- **Router**: Receives reports from oracles, achieves consensus, and distributes ETH to associated contracts.
- **Withdrawals**: Manages the withdrawal of ETH from validators.
- **Airdrop**: Handles the payment of rewards and incentives via stpETH.

## Environment Setup

### Prerequisites

Before you start, make sure you have the following software installed on your system:

- **Node v18**
- **Hardhat**
- **Typescript**
- **Solidity**

## How to Run

Follow these steps to get ready for the **Stake Together** smart contracts:

1. **Duplicate Configuration File**:
   Make a copy of the `.env.example` file and rename it to `.env`.

2. **Update Environment Details**:
   Edit the `.env` file to include your details:

```env
ALCHEMY_GOERLI_API_KEY=YOUR_API_KEY_HERE
ETHERSCAN_API_KEY=YOUR_API_KEY_HERE
DEPLOYER_PRIVATE_KEY=YOUR_PRIVATE_KEY_HERE
```

3. **Install Dependencies**

   Navigate to the project directory in your terminal or command prompt and run:

```bash
npm install
```

4. **Compile contracts**

Execute the next command:

```bash
npm run compile
```

## How to Test

All tests are located in the `test` directory.

To execute the tests, simply run:

```bash
npm run test
```

All contracts have 100% test coverage. To verify the coverage, execute:

```bash
npm run coverage
```

## How to Deploy

To deploy on the Goerli testnet, ensure you have at least 1.1 ETH in your wallet and run:

```bash
npm run goerli:deploy
```

Thank you for being a part of the **Stake Together** community!
If you have feedback or questions, feel free to contribute or get in touch.

## About

**Website**: [staketogether.org](https://staketogether.org)

**Support on Discord**: [Join our server](https://discord.com/invite/w3keCscVsC)

**Follow us on Twitter**: [@0xStakeTogether](https://twitter.com/0xStakeTogether)
