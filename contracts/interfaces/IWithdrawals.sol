// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IWithdrawals {
  event FallbackEther(address indexed sender, uint amount);
  event ReceiveEther(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);
  event Withdraw(address indexed user, uint256 amount);
}
