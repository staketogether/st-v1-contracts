// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IPools {
  event ReceiveEther(address indexed sender, uint amount);
  event FallbackEther(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);
  event SetRouter(address router);

  /***********************
   ** POOLS **
   ***********************/

  event AddPool(address account);
  event RemovePool(address account);
  event SetMaxPools(uint256 maxPools);
  event SetPermissionLessAddPool(bool permissionLessAddPool);

  /***********************
   ** REWARDS **
   ***********************/

  event AddRewardsMerkleRoot(uint256 indexed epoch, bytes32 merkleRoot);
  event ClaimPoolRewards(uint256 indexed _epoch, address indexed _account, uint256 sharesAmount);
  event ClaimPoolRewardsBatch(address indexed claimer, uint256 numClaims, uint256 totalAmount);
  event SetMaxBatchSize(uint256 maxBatchSize);
}
