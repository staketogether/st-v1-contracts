// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/// @custom:security-contact security@staketogether.app
interface IWithdrawals is IERC20 {
  event ReceiveEther(address indexed sender, uint amount);
  event FallbackEther(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);

  receive() external payable;

  fallback() external payable;

  function pause() external;

  function unpause() external;

  function setStakeTogether(address _stakeTogether) external;

  /**************
   ** WITHDRAW **
   **************/

  event Withdraw(address indexed user, uint256 amount);

  function mint(address _to, uint256 _amount) external;

  function withdraw(uint256 _amount) external;

  function isWithdrawReady(uint256 _amount) external view returns (bool);
}
