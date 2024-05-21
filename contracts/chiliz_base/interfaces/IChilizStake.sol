// SPDX-FileCopyrightText: 2024 Together Technology LTD <legal@staketogether.org>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

/// @title Interface for Chiliz Staking
/// @notice A contract that represent the validator withdrawal functionality
/// @custom:security-contact security@staketogether.org
interface IChilizStake {
  function stake(address _benifactor) external payable;
  function unstake(address _user, uint256 _tokenId) external;
  function claim(address _recipient) external;
}
