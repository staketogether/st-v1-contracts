// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IFees {
  enum FeeType {
    Entry,
    Rewards,
    Borrow,
    Anticipate,
    RefundAnticipate,
    Validator,
    AddPool
  }

  enum FeeAddressType {
    Pools,
    Operators,
    StakeTogether,
    Accounts,
    Lenders
  }

  enum FeeValueType {
    FIXED,
    PERCENTAGE
  }

  struct Fee {
    uint256 total;
    FeeValueType valueType;
  }

  event SetTotalFee(FeeType indexed feeType, uint256 total);

  event SetFeeAddress(FeeAddressType indexed addressType, address indexed _address);

  event SetFeeAllocation(FeeType indexed feeType, address indexed _address, uint256 allocation);

  event ReceiveEther(address indexed sender, uint256 amount);

  event FallbackEther(address indexed sender, uint256 amount);

  event SetStakeTogether(address stakeTogether);

  event SetRangeAndProportion(
    uint256 _dayStart,
    uint256 _dayEnd,
    uint256 _proportionStart,
    uint256 _proportionEnd
  );
}
