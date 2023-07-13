// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IStakeTogether {
  event Bootstrap(address sender, uint256 balance);
  event RepayLoan(uint256 amount);

  /************
   ** SHARES **
   ************/

  event MintShares(address indexed to, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);

  /*****************
   ** LOCK SHARES **
   *****************/

  struct Lock {
    uint256 amount;
    uint256 unlockBlock;
    // Todo: unlockAmount
  }

  event SetMaxActiveLocks(uint256 amount);
  event SharesLocked(address indexed account, uint256 amount, uint256 unlockBlock);
  event SharesUnlocked(address indexed account, uint256 amount);

  /*****************
   ** POOLS SHARES **
   *****************/

  event MintPoolShares(address indexed to, address indexed pool, uint256 sharesAmount);
  event BurnPoolShares(address indexed from, address indexed pool, uint256 sharesAmount);
  event TransferPoolShares(
    address indexed from,
    address indexed to,
    address indexed pool,
    uint256 sharesAmount
  );
  event TransferDelegationShares(
    address indexed from,
    address indexed to,
    address indexed pool,
    uint256 sharesAmount
  );

  /*****************
   ** REWARDS **
   *****************/
  struct Reward {
    address recipient;
    uint256 shares;
    uint256 amount;
  }
  enum RewardType {
    Pools,
    Operators,
    StakeTogether
  }

  event SetBeaconBalance(uint256 amount);
  event MintRewards(uint256 epoch, address indexed to, uint256 sharesAmount, RewardType rewardType);
  event MintPenalty(uint256 epoch, uint256 amount);
  event ClaimPoolRewards(address indexed account, uint256 sharesAmount);

  event MintRewardsAccounts(address indexed sender, uint amount);
  event MintRewardsAccountsFallback(address indexed sender, uint amount);

  /*****************
   ** STAKE **
   *****************/

  event DepositBase(
    address indexed to,
    address indexed pool,
    uint256 amount,
    uint256 depositorShares,
    uint256 accountShares,
    uint256 poolsShares,
    uint256 operatorsShares,
    uint256 stakeTogetherShares
  );
  event DepositLimitReached(address indexed sender, uint256 amount);
  event DepositPool(address indexed account, uint256 amount, address delegated, address referral);
  event DepositDonationPool(
    address indexed donor,
    address indexed account,
    uint256 amount,
    address pool,
    address referral
  );

  event WithdrawalLimitReached(address indexed sender, uint256 amount);
  event WithdrawPool(address indexed account, uint256 amount, address pool);
  event WithdrawBorrow(address indexed account, uint256 amount, address pool);
  event WithdrawValidator(address indexed account, uint256 amount, address pool);

  event SetDepositLimit(uint256 newLimit);
  event SetWithdrawalLimit(uint256 newLimit);
  event SetAccountDepositLimit(uint256 newLimit);
  event SetMinDepositPoolAmount(uint256 amount);
  event SetPoolSize(uint256 amount);
  event SetBlocksInterval(uint256 blocksInterval);

  /*****************
   ** VALIDATORS **
   *****************/

  event SetWithdrawalCredentials(bytes withdrawalCredentials);

  event CreateValidator(
    address indexed creator,
    uint256 indexed amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );
}
