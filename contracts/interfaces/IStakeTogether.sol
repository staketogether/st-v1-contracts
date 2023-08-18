// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IStakeTogether {
  struct Config {
    uint256 blocksPerDay;
    uint256 depositLimit;
    uint256 maxDelegations;
    uint256 minDepositAmount;
    uint256 minWithdrawAmount;
    uint256 poolSize;
    uint256 validatorSize;
    uint256 withdrawalLimit;
    Feature feature;
  }

  struct Delegation {
    address pool;
    uint256 shares;
  }

  struct Feature {
    bool AddPool;
    bool Deposit;
    bool WithdrawPool;
    bool WithdrawValidator;
  }

  struct Fee {
    uint256 value;
    FeeMath mathType;
    mapping(FeeRole => uint256) allocations;
  }

  enum DepositType {
    Donation,
    Pool
  }

  enum WithdrawType {
    Pool,
    Validator
  }

  enum FeeType {
    StakeEntry,
    StakeRewards,
    StakePool,
    StakeValidator
  }

  enum FeeMath {
    FIXED,
    PERCENTAGE
  }

  enum FeeRole {
    Airdrop,
    Operator,
    StakeTogether,
    Sender
  }

  event AddPool(address indexed pool, bool listed, uint256 amount);
  event AddValidatorOracle(address indexed account);
  event BurnShares(address indexed account, uint256 sharesAmount);
  event ClaimRewards(address indexed account, uint256 sharesAmount);
  event CreateValidator(
    address indexed creator,
    uint256 amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );
  event DepositBase(address indexed to, uint256 amount, DepositType depositType, address referral);
  event DepositLimitReached(address indexed sender, uint256 amount);
  event MintRewards(address indexed to, uint256 sharesAmount, FeeType feeType, FeeRole feeRole);
  event MintShares(address indexed to, uint256 sharesAmount);
  event NextValidatorOracle(uint256 index, address indexed account);
  event ReceiveEther(address indexed sender, uint amount);
  event RemovePool(address indexed pool);
  event RemoveValidator(address indexed account, uint256 epoch, bytes publicKey);
  event RemoveValidatorOracle(address indexed account);
  event SetBeaconBalance(uint256 amount);
  event SetConfig(Config config);
  event SetFee(FeeType indexed feeType, uint256 value, FeeMath mathType, uint256[] allocations);
  event SetFeeAddress(FeeRole indexed role, address indexed account);
  event SetRouter(address indexed router);
  event SetStakeTogether(address indexed stakeTogether);
  event SetValidatorSize(uint256 newValidatorSize);
  event SetWithdrawalsCredentials(bytes indexed withdrawalCredentials);
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  event UpdateDelegations(address indexed account, Delegation[] delegations);
  event WithdrawBase(address indexed account, uint256 amount, WithdrawType withdrawType);
  event WithdrawRefund(address indexed sender, uint256 amount);
  event WithdrawalsLimitReached(address indexed sender, uint256 amount);
}
