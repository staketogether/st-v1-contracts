// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import './IFees.sol';

/// @custom:security-contact security@staketogether.app
interface IStakeTogether {
  struct Config {
    uint256 blocksPerDay;
    uint256 depositLimit;
    uint256 maxDelegations;
    uint256 minDepositAmount;
    uint256 poolSize;
    uint256 validatorSize;
    uint256 withdrawalLimit;
    Feature feature;
  }

  struct Feature {
    bool AddPool;
    bool Deposit;
    bool Lock;
    bool WithdrawPool;
    bool WithdrawValidator;
  }

  enum DepositType {
    DonationPool,
    Pool
  }

  enum WithdrawType {
    Pool,
    Validator
  }

  event AddPool(address pool, bool listed, uint256 amount);
  event AddValidatorOracle(address indexed account);
  event BurnPoolShares(address indexed from, address indexed pool, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);
  event ClaimRewards(address indexed account, uint256 sharesAmount);
  event CreateValidator(
    address indexed creator,
    uint256 indexed amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );
  event DepositBase(
    address indexed to,
    address indexed pool,
    uint256 amount,
    uint256[4] shares,
    DepositType depositType,
    address referral
  );
  event DepositLimitReached(address indexed sender, uint256 amount);
  event Init(uint256 amount);
  event MintPoolShares(address indexed to, address indexed pool, uint256 sharesAmount);
  event MintRewards(
    address indexed to,
    address indexed pool,
    uint256 amount,
    uint256 sharesAmount,
    IFees.FeeType feeType,
    IFees.FeeRole feeRole
  );
  event MintShares(address indexed to, uint256 sharesAmount);
  event ReceiveEther(address indexed sender, uint amount);
  event RefundPool(address indexed sender, uint256 amount);
  event RemovePool(address pool);
  event RemoveValidator(address indexed account, uint256 epoch, bytes publicKey, uint256 receivedAmount);
  event RemoveValidatorOracle(address indexed account);
  event SetBeaconBalance(uint256 amount);
  event SetConfig(Config config);
  event SetRouter(address router);
  event SetStakeTogether(address stakeTogether);
  event SetValidatorSize(uint256 newValidatorSize);
  event SetWithdrawalsCredentials(bytes indexed withdrawalCredentials);
  event TransferDelegationShares(address indexed from, address indexed to, uint256 sharesAmount);
  event TransferPoolDelegationShares(
    address indexed from,
    address indexed to,
    address indexed pool,
    uint256 sharesAmount
  );
  event TransferPoolShares(
    address indexed account,
    address indexed fromPool,
    address indexed toPool,
    uint256 sharesAmount
  );
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  event WithdrawBase(
    address indexed account,
    address pool,
    uint256 amount,
    uint256 shares,
    WithdrawType withdrawType
  );
  event WithdrawalsLimitReached(address indexed sender, uint256 amount);
}
