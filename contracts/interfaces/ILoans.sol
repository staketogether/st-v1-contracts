// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/// @custom:security-contact security@staketogether.app
interface ILoans is IERC20 {
  event ReceiveEther(address indexed sender, uint amount);
  event FallbackEther(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);

  /***********************
   ** LIQUIDITY **
   ***********************/

  event SetLiquidityFee(uint256 fee);
  event SetStakeTogetherLiquidityFee(uint256 fee);
  event SetPoolLiquidityFee(uint256 fee);
  event AddLiquidity(address indexed user, uint256 amount);
  event RemoveLiquidity(address indexed user, uint256 amount);
  event Borrow(address indexed user, uint256 amount);
  event RepayLoan(address indexed user, uint256 amount);
  event ReDeposit(address indexed user, uint256 amount);
  event ReDepositBatch(address indexed user, uint256[] amounts);
  event SetEnableBorrow(bool enable);

  /***********************
   ** ANTICIPATION **
   ***********************/

  event SetApr(uint256 epoch, uint256 apr);
  event SetMaxAnticipateFraction(uint256 fraction);
  event SetMaxAnticipationDays(uint256 anticipationDays);
  event SetAnticipationFeeRange(uint256 minFee, uint256 maxFee);
  event SetStakeTogetherAnticipateFee(uint256 fee);
  event SetPoolAnticipateFee(uint256 fee);
  event AnticipateRewards(
    address indexed user,
    uint256 anticipatedAmount,
    uint256 netAmount,
    uint256 fee
  );
  event SetEnableAnticipation(bool enable);

  /***************
   ** REDEPOSIT **
   ***************/

  event SetMaxBatchSize(uint256 size);
}
