// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface ILoans {
  event ReceiveEther(address indexed sender, uint amount);
  event FallbackEther(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);

  receive() external payable;

  fallback() external payable;

  function pause() external;

  function unpause() external;

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

  function setStakeTogether(address _stakeTogether) external;

  function setLiquidityFee(uint256 _fee) external;

  function setStakeTogetherLiquidityFee(uint256 _fee) external;

  function setPoolLiquidityFee(uint256 _fee) external;

  function setEnableBorrow(bool _enable) external;

  function addLiquidity() external payable;

  function removeLiquidity(uint256 _amount) external;

  function borrow(uint256 _amount, address _pool) external;

  function repayLoan() external payable;

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

  function setApr(uint256 _epoch, uint256 _apr) external;

  function setMaxAnticipateFraction(uint256 _fraction) external;

  function setMaxAnticipationDays(uint256 _days) external;

  function setAnticipationFeeRange(uint256 _minFee, uint256 _maxFee) external;

  function setStakeTogetherAnticipateFee(uint256 _fee) external;

  function setPoolAnticipateFee(uint256 _fee) external;

  function setEnableAnticipation(bool _enable) external;

  function estimateMaxAnticipation(uint256 _amount, uint256 _days) external view returns (uint256);

  function estimateAnticipationFee(uint256 _amount, uint256 _days) external view returns (uint256);

  function estimateNetAnticipatedAmount(uint256 _amount, uint256 _days) external view returns (uint256);

  function anticipateRewards(uint256 _amount, address _pool, uint256 _days) external;

  /***************
   ** REDEPOSIT **
   ***************/

  event SetMaxBatchSize(uint256 size);

  function setMaxBatchSize(uint256 _size) external;

  function reDeposit(uint256 _amount, address _pool, address _referral) external;

  function reDepositBatch(
    uint256[] memory _amounts,
    address[] memory _pools,
    address[] memory _referrals
  ) external;
}
