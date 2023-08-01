// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import './IFees.sol';

/// @custom:security-contact security@staketogether.app
interface IStakeTogether {
  struct Config {
    uint256 poolSize;
    uint256 minDepositAmount;
    uint256 minLockDays;
    uint256 maxLockDays;
    uint256 depositLimit;
    uint256 withdrawalLimit;
    uint256 blocksPerDay;
    uint256 maxDelegations;
    Feature feature;
  }

  struct Feature {
    bool AddPool;
    bool Deposit;
    bool Lock;
    bool WithdrawPool;
    bool WithdrawLiquidity;
    bool WithdrawValidator;
  }

  struct LockedShares {
    uint256 id;
    uint256 amount;
    uint256 unlockTime;
    uint256 lockDays;
  }

  enum DepositType {
    DonationPool,
    Pool
  }

  enum WithdrawType {
    Pool,
    Liquidity,
    Validator
  }

  event AddPool(address pool, bool listed);
  event BurnPoolShares(address indexed from, address indexed pool, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);
  event ClaimRewards(address indexed account, uint256 sharesAmount);
  event DepositBase(
    address indexed to,
    address indexed pool,
    uint256 amount,
    uint256[4] shares,
    DepositType depositType,
    address referral
  );
  event DepositLimitReached(address indexed sender, uint256 amount);
  event LockShares(address indexed user, uint256 id, uint256 amount, uint256 lockDays);
  event MintPoolShares(address indexed to, address indexed pool, uint256 sharesAmount);
  event MintRewards(
    address indexed to,
    address indexed pool,
    uint256 sharesAmount,
    IFees.FeeType feeType,
    IFees.FeeRole feeRole
  );
  event MintShares(address indexed to, uint256 sharesAmount);
  event ReceiveEther(address indexed sender, uint amount);
  event RefundPool(address indexed sender, uint256 amount);
  event RemovePool(address pool);
  event SetBeaconBalance(uint256 amount);
  event SetConfig(Config config);
  event SetLiquidityBalance(uint256 amount);
  event SetWithdrawalsCredentials(bytes indexed withdrawalCredentials);
  event SupplyLiquidity(uint256 amount);
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
  event UnlockShares(address indexed user, uint256 id, uint256 amount);
  event WithdrawBase(
    address indexed account,
    address pool,
    uint256 amount,
    uint256 shares,
    WithdrawType withdrawType
  );
  event WithdrawalsLimitReached(address indexed sender, uint256 amount);
}
