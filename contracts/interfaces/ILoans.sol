// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface ILoans {
  event MintRewardsAccounts(address indexed sender, uint amount);
  event MintRewardsAccountsFallback(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);
  /************
   ** SHARES **
   ************/
  event MintShares(address indexed to, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  /***********************
   ** LIQUIDITY **
   ***********************/
  event SetEnableBorrow(bool enable);
  event AddLiquidity(address indexed user, uint256 amount);
  event RemoveLiquidity(address indexed user, uint256 amount);

  event Borrow(address indexed user, uint256 amount);

  event RepayLoan(address indexed user, uint256 amount);

  /***********************
   ** ANTICIPATION **
   ***********************/
  event SetEnableAnticipation(bool enable);
  event SetApr(uint256 epoch, uint256 apr);

  event AnticipateRewards(
    address indexed user,
    uint256 anticipatedAmount,
    uint256 netAmount,
    uint256 fee
  );

  /***************
   ** REDEPOSIT **
   ***************/
  event SetMaxBatchSize(uint256 size);

  event ReDeposit(address indexed user, uint256 amount);
  event ReDepositBatch(address indexed user, uint256[] amounts);
}
