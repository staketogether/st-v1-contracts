// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.org>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title StakeTogetherWrapper Interface
/// @notice This interface defines the essential structures and functions for the StakeTogetherWrapper.
/// @custom:security-contact security@staketogether.org
interface IStakeTogetherWrapper {
  /// @notice Thrown if the listed in anti-fraud.
  error ListedInAntiFraud();

  /// @notice This error is thrown when there is no extra amount of ETH available to transfer.
  error NoExtraAmountAvailable();

  /// @notice This error is thrown when trying to set the stakeTogether address that has already been set.
  error StakeTogetherAlreadySet();

  /// @notice Thrown if the address trying to make a claim is the zero address.
  error ZeroAddress();

  /// @notice Thrown if the amount of stpETH amount is zero.
  error ZeroStpETHAmount();

  /// @notice Thrown if the amount of wstpETH amount is zero.
  error ZeroWstpETHAmount();

  /// @notice Emitted when Ether is received
  /// @param amount The amount of Ether received
  event ReceiveEther(uint256 amount);

  /// @notice Emitted when the StakeTogether address is set
  /// @param stakeTogether The address of the StakeTogether contract
  event SetStakeTogether(address stakeTogether);

  /// @notice Emitted when stpETH is wrapped into wstpETH.
  /// @param user The address of the user who wrapped the stpETH.
  /// @param stpETHAmount The amount of stpETH that was wrapped.
  /// @param wstpETHAmount The amount of wstpETH that was minted as a result.
  event Wrapped(address indexed user, uint256 stpETHAmount, uint256 wstpETHAmount);

  /// @notice Emitted when wstpETH is unwrapped into stpETH.
  /// @param user The address of the user who unwrapped the wstpETH.
  /// @param wstpETHAmount The amount of wstpETH that was unwrapped.
  /// @param stpETHAmount The amount of stpETH that was received as a result.
  event Unwrapped(address indexed user, uint256 wstpETHAmount, uint256 stpETHAmount);

  /// @notice Transfers any extra amount of ETH in the contract to the StakeTogether fee address.
  /// @dev Only callable by the admin role. Requires that extra amount exists in the contract.
  function transferExtraAmount() external;

  /// @notice Sets the StakeTogether contract address.
  /// @param _stakeTogether The address of the new StakeTogether contract.
  /// @dev Only callable by the admin role.
  function setStakeTogether(address _stakeTogether) external;

  /// @notice Wraps the given amount of stpETH into wstpETH.
  /// @dev Reverts if the sender is on the anti-fraud list, or if the _stpETH amount is zero.
  /// @param _stpETH The amount of stpETH to wrap.
  /// @return The amount of wstpETH minted.
  function wrap(uint256 _stpETH) external returns (uint256);

  /// @notice Unwraps the given amount of wstpETH into stpETH.
  /// @dev Reverts if the sender is on the anti-fraud list, or if the _wstpETH amount is zero.
  /// @param _wstpETH The amount of wstpETH to unwrap.
  /// @return The amount of stpETH received.
  function unwrap(uint256 _wstpETH) external returns (uint256);

  /// @notice Calculates the current exchange rate of stpETH per wstpETH.
  /// @dev Returns zero if the total supply of wstpETH is zero.
  /// @return The current rate of stpETH per wstpETH.
  function stpEthPerWstpETH() external view returns (uint256);

  /// @notice Calculates the current exchange rate of wstpETH per stpETH.
  /// @dev Returns zero if the balance of stpETH is zero.
  /// @return The current rate of wstpETH per stpETH.
  function wstpETHPerStpETH() external view returns (uint256);
}
