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

  enum FeeValueType {
    FIXED,
    PERCENTAGE
  }

  struct Fee {
    uint256 value;
    FeeValueType valueType;
    mapping(string => uint256) allocations;
  }

  event SetTotalFee(FeeType indexed feeType, uint256 total);

  event SetFeeAllocation(FeeType indexed feeType, string indexed role, uint256 allocation);

  event ReceiveEther(address indexed sender, uint256 amount);

  event FallbackEther(address indexed sender, uint256 amount);

  event SetStakeTogether(address stakeTogether);

  event SetRangeAndProportion(
    uint256 _dayStart,
    uint256 _dayEnd,
    uint256 _proportionStart,
    uint256 _proportionEnd
  );

  function setFee(FeeType _feeType, uint256 _fee, FeeValueType _valueType) external;

  function getFee(FeeType _feeType) external view returns (uint256);

  function setFeeAllocation(FeeType _feeType, string calldata _role, uint256 _allocation) external;

  function getFeeAllocation(FeeType _feeType, string calldata _role) external view returns (uint256);

  function pause() external;

  function unpause() external;

  function setStakeTogether(address _stakeTogether) external;
}
