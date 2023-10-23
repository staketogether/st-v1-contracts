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
pnpm install
```

4. **Compile Contracts**

Execute the next command:

```bash
pnpm compile
```

## How to Test

All tests are located in the `test` directory.

To execute the tests, simply run:

```bash
pnpm test
```

All contracts have 100% test coverage. To verify the coverage, execute:

```bash
pnpm coverage
```

## How to Deploy

To deploy on the Goerli testnet, ensure you have at least 1.1 ETH in your wallet and run:

```bash
pnpm goerli:deploy
```

Thank you for being a part of the **Stake Together** community!
If you have feedback or questions, feel free to contribute or get in touch.

## Contract Summaries

- **StakeTogether**: Manages pools, deposits, withdrawals, and validator creation.
- **Router**: Receives reports from oracles, achieves consensus, and distributes ETH to associated contracts.
- **Withdrawals**: Manages the withdrawal of ETH from validators.
- **Airdrop**: Handles the payment of rewards and incentives via stpETH.
- **StakeTogetherWrapper**: Handles the conversion between stpETH (rebase token) and wstpETH (stable token)

## Main Features by Contract

### StakeTogether

- **addPool**: This function allows users to add a new staking pool to the system. It verifies that the pool address is not zero, the pool does not already exist, and that the sender has the appropriate permissions or pays the required fee if the feature is enabled. The pool's address, listing status, and whether it's a social pool are recorded and an event is emitted to log the addition of the new pool.

- **depositPool**: This function allows users to deposit a specified amount into a designated staking pool. It ensures the deposit feature is enabled, the total supply is not zero, the recipient is not listed in the anti-fraud list, and the deposit is above the minimum amount and within the deposit limit. The function also ensures that the selected pool exists. Upon successful validation, it processes the stake entry, updating the total deposited amount.

- **depositDonation**: This function allows users to deposit a donation to a specific address associated with a pool. It follows similar validation checks as the depositPool function, including feature enablement, total supply, anti-fraud list, and deposit limits. This function is specifically designed for donation-type deposits, making it distinct from regular pool deposits while still utilizing the core deposit functionality.

- **withdrawPool**: This function allows users to withdraw a specified amount from a staking pool. It checks if the withdraw pool feature is enabled and ensures that the withdrawal amount is available in the pool balance. The user must not be on the anti-fraud list, and the withdrawal amount should meet the specified conditions, including being non-zero, not exceeding the user's balance, and falling within the minimum and maximum limits. If all conditions are met, the amount is transferred to the user, and an equivalent amount of shares is burned from the user’s account.

- **withdrawValidator**: This functions allows users can withdraw a specific amount from the validators on the beacon chain using this function. It also checks if the feature is enabled and that the amount to be withdrawn is not available in the pool balance, ensuring the withdrawal is specifically from the validator. The function follows the same security and validation checks as withdrawPool. The withdrawn amount adds to the pending withdrawal balance, and the user is minted tokens equivalent to the withdrawal amount, effectively converting their stake in the validator into tokens.

- **addValidator**: This function facilitates the creation of a new validator on the beacon chain. It's designed to be invoked only by a validated oracle and under non-paused conditions to maintain system integrity. The process ensures specific conditions are met, such as the caller being an authorized validator oracle, the pool having sufficient balance, and the validator not already existing. Upon meeting these criteria, the validator is registered, and an associated beacon balance is set. An event is then emitted to log the validator's addition, and the deposit is made to the beacon chain. The process also involves transitioning to the next validator oracle and managing the staking validator fee. This structured, conditional approach ensures that validators are added seamlessly, securely, and in alignment with the system’s operational parameters.

### Router

- **submitReport**: This function in the contract is instrumental for oracles to submit data reports. Each submission is validated through a consensus mechanism, ensuring that a significant number of oracles concur on the reported data to establish its validity. This consensus is achieved when the submissions surpass a predetermined quorum, ensuring multiple validations and enhancing data integrity. A built-in circuit breaker mechanism is another crucial aspect of this function. Once a consensus is reached, the execution of the agreed report is not immediate. There's a deliberate delay introduced to allow stakeholders to review the consensus data. This delay acts as a safeguard, offering an opportunity to scrutinize, verify, and if necessary, intervene to prevent the execution of potentially erroneous or malicious data. This two-step verification - consensus reaching and execution delay - collectively fortifies the security and reliability of the data handling process within the contract.

- **executeReport**: This function is activated in the post-consensus phase of the StakeTogether platform, this function validates and executes an approved report after a consensus is reached and the circuit breaker delay passes. Initiated by an active report oracle, it ensures the consensus is unrevoked and unexecuted, and the circuit breaker delay is respected. It then executes the report, updating state variables and managing the removal of validators and integration of new Merkle roots. A key responsibility includes overseeing the precise distribution of profits and management of withdrawals according to the report's stipulations, adjusting the StakeTogether and withdrawals balances accordingly. In a nutshell, executeReport is a robust function adept at not only executing consensus reports but also managing the integrated outcomes with precision, ensuring a balanced ecosystem and the protection of stakeholders’ interests.

### Airdrop

- **addMerkleRoot**: This function is tasked with associating a Merkle root to a specific reporting block, a crucial step to identify and validate the wallets slated to receive an airdrop. Only accessible by the router contract, this function ensures that the Merkle root, which encapsulates the information of all eligible airdrop recipients, is securely and accurately recorded. Each Merkle root corresponds to a distinct reporting block, forming a reliable dataset for validating and processing airdrop claims efficiently and securely.

- **claim**: This function allows users to claim their airdrop rewards by providing the block number, Merkle tree index, address, share amount, and Merkle proof. It verifies the claim against anti-fraud lists, claim history, and the Merkle root. If validated, the user's claim status is updated, and the shares are transferred to their address

### Withdrawals

- **withdraw**: This function is integrated with the Router contract to facilitate a secure and efficient process for users to retrieve their staked ETH. Initially, the Router contract manages and processes the withdrawal of ETH, transferring the designated amount to the Withdrawals contract. This integrated step ensures that the required ETH is ready and available for users intending to withdraw. When calling the withdraw function, several checks are conducted; it verifies if the caller is not listed in the anti-fraud directory, confirms that the contract possesses sufficient ETH, and ascertains that users have an adequate balance of staked tokens to be burnt in exchange for the withdrawal. If all these conditions align, the staked tokens are burnt, and the equivalent ETH amount is directly transferred to the user’s wallet, completing the withdrawal procedure efficiently and securely.

### StakeTogetherWrapper

- **wrap**: This function enables users to convert their stpETH tokens into the wrapped version, wstpETH. It ensures that users aren't on an anti-fraud list and that they are attempting to wrap a non-zero amount of tokens. Upon these validations, the function calculates the equivalent number of wstpETH tokens, mints them to the user's account, and transfers the original stpETH tokens to the contract. This process is encapsulated in a single transaction, providing users with a seamless experience to easily switch between the two token types while ensuring security and integrity of the operation.

- **unwrap**: This function allows users to convert their wstpETH tokens back into stpETH. It first ensures that the user is not on an anti-fraud list and is trying to unwrap a non-zero amount of wstpETH. The function calculates the equivalent number of stpETH tokens based on the given wstpETH. It then burns the wstpETH tokens from the user's account and transfers the equivalent stpETH tokens back to the user. This conversion allows users to easily switch back from the wrapped token to the original token format while ensuring that the process is secure and the user is eligible to perform the conversion.

## About

**Website**: [staketogether.org](https://staketogether.org)

**Support on Discord**: [Join our server](https://discord.com/invite/w3keCscVsC)

**Follow us on Twitter**: [@0xStakeTogether](https://twitter.com/0xStakeTogether)
