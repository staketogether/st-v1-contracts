// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IFees {
  enum FeeType {
    StakeEntry,
    StakeRewards,
    StakePool,
    StakeValidator,
    LiquidityProvideEntry,
    LiquidityProvide
  }

  enum FeeMathType {
    FIXED,
    PERCENTAGE
  }

  enum FeeRoles {
    StakeAccounts,
    LockAccounts,
    Pools,
    Operators,
    Oracles,
    StakeTogether,
    LiquidityProviders,
    Sender
  }

  struct Fee {
    uint256 value;
    FeeMathType mathType;
    mapping(FeeRoles => uint256) allocations;
  }

  event FallbackEther(address indexed sender, uint256 amount);
  event ReceiveEther(address indexed sender, uint256 amount);
  event SetFeeAddress(FeeRoles indexed role, address indexed account);
  event SetFeeAllocation(FeeType indexed feeType, FeeRoles indexed role, uint256 allocation);
  event SetFeeValue(FeeType indexed feeType, uint256 amount);
  event SetLiquidityContract(address liquidityContract);
  event SetMaxFeeIncrease(uint256 maxFeeIncrease);
  event SetRouterContract(address routerContract);
  event SetStakeTogether(address stakeTogether);
}