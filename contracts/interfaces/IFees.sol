// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IFees {
  enum FeeType {
    StakeEntry, // (st - depositBase)
    StakeRewards, //  (router - executeReport)
    StakePool, // (st - addPool)
    StakeValidator, // (validator -> createValidator)
    LiquidityProvideEntry, // (liquidity - depositBase)
    LiquidityProvide // (liquidity - withdrawLiquidity)
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

  struct Fee {
    uint256 value;
    FeeMath mathType;
    mapping(FeeRole => uint256) allocations;
  }

  event ReceiveEther(address indexed sender, uint256 amount);
  event SetFeeAddress(FeeRole indexed role, address indexed account);
  event SetFee(FeeType indexed feeType, uint256 value, FeeMath indexed mathType, uint256[] allocations);
  event SetLiquidity(address liquidityContract);
  event SetMaxDynamicFee(uint256 maxDynamicFee);
  event SetRouter(address router);
  event SetStakeTogether(address stakeTogether);
}
