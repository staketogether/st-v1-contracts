// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface ILiquidity {
  struct Config {
    bool enableLiquidity;
    bool enableDeposit;
    uint256 depositLimit;
    uint256 withdrawalLimit;
    uint256 withdrawalLiquidityLimit;
    uint256 minDepositAmount;
    uint256 blocksInterval;
  }

  event BurnShares(address indexed account, uint256 sharesAmount);
  event DepositPool(address indexed user, uint256 amount);
  event MintRewardsWithdrawalLenders(address indexed sender, uint amount);
  event MintRewardsWithdrawalLendersFallback(address indexed sender, uint amount);
  event MintShares(address indexed to, uint256 sharesAmount);
  event SetConfig(Config config);
  event SetRouterContract(address routerContract);
  event SetStakeTogether(address stakeTogether);
  event SupplyLiquidity(address indexed user, uint256 amount);
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  event WithdrawLiquidity(address indexed user, uint256 amount);
  event WithdrawPool(address indexed user, uint256 amount);
}
