// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @title StakeTogether Interface
/// @notice This interface defines the essential structures and functions for the StakeTogether protocol.
/// @custom:security-contact security@staketogether.app
interface IStakeTogether {
  /// @notice Configuration for the StakeTogether protocol.
  struct Config {
    uint256 blocksPerDay; /// Number of blocks per day.
    uint256 depositLimit; /// Maximum amount of deposit.
    uint256 maxDelegations; /// Maximum number of delegations.
    uint256 minDepositAmount; /// Minimum amount to deposit.
    uint256 minWithdrawAmount; /// Minimum amount to withdraw.
    uint256 poolSize; /// Size of the pool.
    uint256 validatorSize; /// Size of the validator.
    uint256 withdrawalLimit; /// Maximum amount of withdrawal.
    Feature feature; /// Additional features configuration.
  }

  /// @notice Represents a delegation, including the pool address and shares.
  struct Delegation {
    address pool; /// Address of the delegated pool.
    uint256 shares; /// Number of shares in the delegation.
  }

  /// @notice Toggleable features for the protocol.
  struct Feature {
    bool AddPool; /// Enable/disable pool addition.
    bool Deposit; /// Enable/disable deposits.
    bool WithdrawPool; /// Enable/disable pool withdrawals.
    bool WithdrawValidator; /// Enable/disable validator withdrawals.
  }

  /// @notice Represents the fee structure.
  struct Fee {
    uint256 value; /// Value of the fee.
    FeeMath mathType; /// Type of calculation for the fee (Fixed or Percentage).
    mapping(FeeRole => uint256) allocations; /// Allocation of fees among different roles.
  }

  /// @notice Types of deposits available.
  enum DepositType {
    Donation, /// Donation type deposit.
    Pool /// Pool type deposit.
  }

  /// @notice Types of withdrawals available.
  enum WithdrawType {
    Pool, /// Pool type withdrawal.
    Validator /// Validator type withdrawal.
  }

  /// @notice Types of fees within the protocol.
  enum FeeType {
    StakeEntry, /// Fee for entering a stake.
    StakeRewards, /// Fee for staking rewards.
    StakePool, /// Fee for pool staking.
    StakeValidator /// Fee for validator staking.
  }

  /// @notice Types of mathematics used in fee calculation.
  enum FeeMath {
    FIXED, /// Fixed value fee.
    PERCENTAGE /// Percentage value fee.
  }

  /// @notice Different roles that are used in fee allocation
  enum FeeRole {
    Airdrop, /// Role for distributing airdrops
    Operator, /// Role for managing various functionalities
    StakeTogether, /// Role for handling internal responsibilities within StakeTogether
    Sender /// Role representing the sender of a transaction
  }

  /// @notice Emitted when a pool is added
  /// @param pool The address of the pool
  /// @param listed Whether the pool is listed
  /// @param amount The amount associated with the pool
  event AddPool(address indexed pool, bool listed, uint256 amount);

  /// @notice Emitted when a validator oracle is added
  /// @param account The address of the account
  event AddValidatorOracle(address indexed account);

  /// @notice Emitted when shares are burned
  /// @param account The address of the account
  /// @param sharesAmount The amount of shares burned
  event BurnShares(address indexed account, uint256 sharesAmount);

  /// @notice Emitted when a validator is created
  /// @param creator The address of the creator
  /// @param amount The amount for the validator
  /// @param externalKey The external key of the validator
  /// @param withdrawalCredentials The withdrawal credentials
  /// @param signature The signature
  /// @param depositDataRoot The deposit data root
  event CreateValidator(
    address indexed creator,
    uint256 amount,
    bytes externalKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );

  /// @notice Emitted when a base deposit is made
  /// @param to The address to deposit to
  /// @param amount The deposit amount
  /// @param depositType The type of deposit (Donation, Pool)
  /// @param referral The address of the referral
  event DepositBase(address indexed to, uint256 amount, DepositType depositType, address referral);

  /// @notice Emitted when the deposit limit is reached
  /// @param sender The address of the sender
  /// @param amount The amount deposited
  event DepositLimitReached(address indexed sender, uint256 amount);

  /// @notice Emitted when rewards are minted
  /// @param to The address to mint to
  /// @param sharesAmount The amount of shares minted
  /// @param feeType The type of fee (e.g., StakeEntry, StakeRewards)
  /// @param feeRole The role associated with the fee
  event MintFeeShares(address indexed to, uint256 sharesAmount, FeeType feeType, FeeRole feeRole);

  /// @notice Emitted when shares are minted
  /// @param to The address to mint to
  /// @param sharesAmount The amount of shares minted
  event MintShares(address indexed to, uint256 sharesAmount);

  /// @notice Emitted when the next validator oracle is set
  /// @param index The index of the oracle
  /// @param account The address of the account
  event NextValidatorOracle(uint256 index, address indexed account);

  /// @notice Emitted when Ether is received
  /// @param sender The address of the sender
  /// @param amount The amount of Ether received
  event ReceiveEther(address indexed sender, uint amount);

  /// @notice Emitted when a pool is removed
  /// @param pool The address of the pool
  event RemovePool(address indexed pool);

  /// @notice Emitted when a validator is removed
  /// @param account The address of the account
  /// @param epoch The epoch associated with the removal
  /// @param externalKey The external key of the validator
  event RemoveValidator(address indexed account, uint256 epoch, bytes externalKey);

  /// @notice Emitted when a validator oracle is removed
  /// @param account The address of the account
  event RemoveValidatorOracle(address indexed account);

  /// @notice Emitted when the beacon balance is set
  /// @param amount The amount set for the beacon balance
  event SetBeaconBalance(uint256 amount);

  /// @notice Emitted when the configuration is set
  /// @param config The configuration struct
  event SetConfig(Config config);

  /// @notice Emitted when a fee is set
  /// @param feeType The type of fee being set
  /// @param value The value of the fee
  /// @param mathType The mathematical type of the fee
  /// @param allocations The allocations for the fee
  event SetFee(FeeType indexed feeType, uint256 value, FeeMath mathType, uint256[] allocations);

  /// @notice Emitted when a fee address is set
  /// @param role The role associated with the fee
  /// @param account The address of the account
  event SetFeeAddress(FeeRole indexed role, address indexed account);

  /// @notice Emitted when the router is set
  /// @param router The address of the router
  event SetRouter(address indexed router);

  /// @notice Emitted when the StakeTogether address is set
  /// @param stakeTogether The address of StakeTogether
  event SetStakeTogether(address indexed stakeTogether);

  /// @notice Emitted when the validator size is set
  /// @param newValidatorSize The new size for the validator
  event SetValidatorSize(uint256 newValidatorSize);

  /// @notice Emitted when the withdrawal credentials are set
  /// @param withdrawalCredentials The withdrawal credentials bytes
  event SetWithdrawalsCredentials(bytes indexed withdrawalCredentials);

  /// @notice Emitted when shares are transferred
  /// @param from The address transferring from
  /// @param to The address transferring to
  /// @param sharesAmount The amount of shares transferred
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);

  /// @notice Emitted when delegations are updated
  /// @param account The address of the account
  /// @param delegations The delegation array
  event UpdateDelegations(address indexed account, Delegation[] delegations);

  /// @notice Emitted when a base withdrawal is made
  /// @param account The address withdrawing
  /// @param amount The withdrawal amount
  /// @param withdrawType The type of withdrawal
  event WithdrawBase(address indexed account, uint256 amount, WithdrawType withdrawType);

  /// @notice Emitted when a refund withdrawal is made
  /// @param sender The address of the sender
  /// @param amount The amount of the refund
  event WithdrawRefund(address indexed sender, uint256 amount);

  /// @notice Emitted when the withdrawal limit is reached
  /// @param sender The address of the sender
  /// @param amount The amount withdrawn
  event WithdrawalsLimitReached(address indexed sender, uint256 amount);
}
