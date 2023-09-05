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
    uint256 percentage; /// Number of percentage in the delegation.
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
    ProcessStakeRewards, /// Fee for staking rewards.
    StakePool, /// Fee for pool staking.
    ProcessStakeValidator /// Fee for validator staking.
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
  /// @param publicKey The public key of the validator
  /// @param withdrawalCredentials The withdrawal credentials
  /// @param signature The signature
  /// @param depositDataRoot The deposit data root
  event CreateValidator(
    address indexed creator,
    uint256 amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );

  /// @notice Emitted when a base deposit is made
  /// @param to The address to deposit to
  /// @param amount The deposit amount
  /// @param depositType The type of deposit (Donation, Pool)
  /// @param pool The address of the pool
  /// @param referral The address of the referral
  event DepositBase(
    address indexed to,
    uint256 amount,
    DepositType depositType,
    address pool,
    address referral
  );

  /// @notice Emitted when the deposit limit is reached
  /// @param sender The address of the sender
  /// @param amount The amount deposited
  event DepositLimitReached(address indexed sender, uint256 amount);

  /// @notice Emitted when rewards are minted
  /// @param to The address to mint to
  /// @param sharesAmount The amount of shares minted
  /// @param feeType The type of fee (e.g., StakeEntry, ProcessStakeRewards)
  /// @param feeRole The role associated with the fee
  event MintFeeShares(
    address indexed to,
    uint256 sharesAmount,
    FeeType indexed feeType,
    FeeRole indexed feeRole
  );

  /// @notice Emitted when shares are minted
  /// @param to The address to mint to
  /// @param sharesAmount The amount of shares minted
  event MintShares(address indexed to, uint256 sharesAmount);

  /// @notice Emitted when the next validator oracle is set
  /// @param index The index of the oracle
  /// @param account The address of the account
  event NextValidatorOracle(uint256 index, address indexed account);

  /// @dev This event emits when rewards are processed for staking, indicating the amount and the number of shares.
  /// @param amount The total amount of rewards that have been processed for staking.
  /// @param sharesAmount The total number of shares associated with the processed staking rewards.
  event ProcessStakeRewards(uint256 amount, uint256 sharesAmount);

  /// @dev This event emits when a validator's stake has been processed.
  /// @param account The address of the account whose stake as a validator has been processed.
  /// @param amount The amount the account staked that has been processed.
  event ProcessStakeValidator(address indexed account, uint256 amount);

  /// @notice Emitted when Ether is received
  /// @param amount The amount of Ether received
  event ReceiveEther(uint256 amount);

  /// @notice Emitted when a pool is removed
  /// @param pool The address of the pool
  event RemovePool(address indexed pool);

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
  /// @param allocations The allocations for the fee
  event SetFee(FeeType indexed feeType, uint256 value, uint256[] allocations);

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

  /// @notice Emitted when the withdraw balance is set
  /// @param amount The amount set for the withdraw balance
  event SetWithdrawBalance(uint256 amount);

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
  /// @param pool The address of the pool
  event WithdrawBase(address indexed account, uint256 amount, WithdrawType withdrawType, address pool);

  /// @notice Emitted when the withdrawal limit is reached
  /// @param sender The address of the sender
  /// @param amount The amount withdrawn
  event WithdrawalsLimitReached(address indexed sender, uint256 amount);

  /// @notice Stake Together Pool Initialization
  /// @param _router The address of the router.
  /// @param _withdrawals The address of the withdrawals contract.
  /// @param _depositContract The address of the deposit contract.
  /// @param _withdrawalCredentials The bytes for withdrawal credentials.
  function initialize(
    address _router,
    address _withdrawals,
    address _depositContract,
    bytes memory _withdrawalCredentials
  ) external;

  /// @notice Pauses the contract, preventing certain actions.
  /// @dev Only callable by the admin role.
  function pause() external;

  /// @notice Unpauses the contract, allowing actions to resume.
  /// @dev Only callable by the admin role.
  function unpause() external;

  /// @notice Receive function to accept incoming ETH transfers.
  receive() external payable;

  /// @notice Sets the configuration for the Stake Together Protocol.
  /// @dev Only callable by the admin role.
  /// @param _config Configuration settings to be applied.
  function setConfig(Config memory _config) external;

  /// @notice Returns the total supply of the pool (contract balance + beacon balance).
  /// @return Total supply value.
  function totalSupply() external view returns (uint256);

  /// @notice Calculates the shares amount by wei.
  /// @param _account The address of the account.
  /// @return Balance value of the given account.
  function balanceOf(address _account) external view returns (uint256);

  /// @notice Calculates the wei amount by shares.
  /// @param _sharesAmount Amount of shares.
  /// @return Equivalent amount in wei.
  function weiByShares(uint256 _sharesAmount) external view returns (uint256);

  /// @notice Calculates the shares amount by wei.
  /// @param _amount Amount in wei.
  /// @return Equivalent amount in shares.
  function sharesByWei(uint256 _amount) external view returns (uint256);

  /// @notice Transfers an amount of wei to the specified address.
  /// @param _to The address to transfer to.
  /// @param _amount The amount to be transferred.
  /// @return True if the transfer was successful.
  function transfer(address _to, uint256 _amount) external returns (bool);

  /// @notice Transfers tokens from one address to another using an allowance mechanism.
  /// @param _from Address to transfer from.
  /// @param _to Address to transfer to.
  /// @param _amount Amount of tokens to transfer.
  /// @return A boolean value indicating whether the operation succeeded.
  function transferFrom(address _from, address _to, uint256 _amount) external returns (bool);

  /// @notice Transfers a number of shares to the specified address.
  /// @param _to The address to transfer to.
  /// @param _sharesAmount The number of shares to be transferred.
  /// @return Equivalent amount in wei.
  function transferShares(address _to, uint256 _sharesAmount) external returns (uint256);

  /// @notice Returns the remaining number of tokens that an spender is allowed to spend on behalf of a token owner.
  /// @param _account Address of the token owner.
  /// @param _spender Address of the spender.
  /// @return A uint256 value representing the remaining number of tokens available for the spender.
  function allowance(address _account, address _spender) external view returns (uint256);

  /// @notice Sets the amount `_amount` as allowance of `_spender` over the caller's tokens.
  /// @param _spender Address of the spender.
  /// @param _amount Amount of allowance to be set.
  /// @return A boolean value indicating whether the operation succeeded.
  function approve(address _spender, uint256 _amount) external returns (bool);

  /// @notice Increases the allowance granted to `_spender` by the caller.
  /// @param _spender Address of the spender.
  /// @param _addedValue The additional amount to increase the allowance by.
  /// @return A boolean value indicating whether the operation succeeded.
  function increaseAllowance(address _spender, uint256 _addedValue) external returns (bool);

  /// @notice Decreases the allowance granted to `_spender` by the caller.
  /// @param _spender Address of the spender.
  /// @param _subtractedValue The amount to subtract from the allowance.
  /// @return A boolean value indicating whether the operation succeeded.
  function decreaseAllowance(address _spender, uint256 _subtractedValue) external returns (bool);

  /// @notice Deposits into the pool with specific delegations.
  /// @param _pool the address of the pool.
  /// @param _referral The referral address.
  function depositPool(address _pool, address _referral) external payable;

  /// @notice Deposits a donation to the specified address.
  /// @param _to The address to deposit to.
  /// @param _pool the address of the pool.
  /// @param _referral The referral address.
  function depositDonation(address _to, address _pool, address _referral) external payable;

  /// @notice Withdraws from the pool with specific delegations and transfers the funds to the sender.
  /// @param _amount The amount to withdraw.
  /// @param _pool the address of the pool.
  function withdrawPool(uint256 _amount, address _pool) external;

  /// @notice Withdraws from the validators with specific delegations and mints tokens to the sender.
  /// @param _amount The amount to withdraw.
  /// @param _pool the address of the pool.
  function withdrawValidator(uint256 _amount, address _pool) external;

  /// @notice Adds a permissionless pool with a specified address and listing status if feature enabled.
  /// @param _pool The address of the pool to add.
  /// @param _listed The listing status of the pool.
  function addPool(address _pool, bool _listed) external payable;

  /// @notice Removes a pool by its address.
  /// @param _pool The address of the pool to remove.
  function removePool(address _pool) external;

  /// @notice Updates delegations for the sender's address.
  /// @param _delegations The array of delegations to update.
  function updateDelegations(Delegation[] memory _delegations) external;

  /// @notice Adds a new validator oracle by its address.
  /// @param _account The address of the validator oracle to add.
  function addValidatorOracle(address _account) external;

  /// @notice Removes a validator oracle by its address.
  /// @param _account The address of the validator oracle to remove.
  function removeValidatorOracle(address _account) external;

  /// @notice Checks if an address is a validator oracle.
  /// @param _account The address to check.
  /// @return True if the address is a validator oracle, false otherwise.
  function isValidatorOracle(address _account) external view returns (bool);

  /// @notice Forces the selection of the next validator oracle.
  function forceNextValidatorOracle() external;

  /****************
   ** VALIDATORS **
   ****************/

  /// @notice Sets the beacon balance to the specified amount.
  /// @param _amount The amount to set as the beacon balance.
  /// @dev Only the router address can call this function.
  function setBeaconBalance(uint256 _amount) external payable;

  /// @notice Sets the pending withdraw balance to the specified amount.
  /// @param _amount The amount to set as the pending withdraw balance.
  /// @dev Only the router address can call this function.
  function setWithdrawBalance(uint256 _amount) external payable;

  /// @notice Creates a new validator with the given parameters.
  /// @param _publicKey The public key of the validator.
  /// @param _signature The signature of the validator.
  /// @param _depositDataRoot The deposit data root for the validator.
  /// @dev Only a valid validator oracle can call this function.
  function createValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external;

  /// @notice Function to claim rewards by transferring shares, accessible only by the airdrop fee address.
  /// @param _account Address to transfer the claimed rewards to.
  /// @param _sharesAmount Amount of shares to claim as rewards.
  function claimAirdrop(address _account, uint256 _sharesAmount) external;

  /// @notice Returns an array of fee roles.
  /// @return roles An array of FeeRole.
  function getFeesRoles() external pure returns (FeeRole[4] memory);

  /// @notice Sets the fee address for a given role.
  /// @param _role The role for which the address will be set.
  /// @param _address The address to set.
  /// @dev Only an admin can call this function.
  function setFeeAddress(FeeRole _role, address payable _address) external;

  /// @notice Gets the fee address for a given role.
  /// @param _role The role for which the address will be retrieved.
  /// @return The address associated with the given role.
  function getFeeAddress(FeeRole _role) external view returns (address);

  /// @notice Sets the fee for a given fee type.
  /// @param _feeType The type of fee to set.
  /// @param _value The value of the fee.
  /// @param _allocations The allocations for the fee.
  /// @dev Only an admin can call this function.
  function setFee(FeeType _feeType, uint256 _value, uint256[] calldata _allocations) external;

  /// @notice Process staking rewards and distributes the rewards based on shares.
  /// @param _sharesAmount The amount of shares related to the staking rewards.
  /// @dev Requires the caller to be the router contract.
  function processStakeRewards(uint256 _sharesAmount) external payable;
}
