// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IPools {
  event ReceiveEther(address indexed sender, uint amount);
  event FallbackEther(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);
  event SetRouter(address router);

  function setStakeTogether(address _stakeTogether) external;

  function setRouter(address _distributor) external;

  function pause() external;

  function unpause() external;

  /***********************
   ** POOLS **
   ***********************/

  event AddPool(address account);
  event RemovePool(address account);
  event SetMaxPools(uint256 maxPools);
  event SetPermissionLessAddPool(bool permissionLessAddPool);

  function setMaxPools(uint256 _maxPools) external;

  function setPermissionLessAddPool(bool _permissionLessAddPool) external;

  function addPool(address _pool) external payable;

  function removePool(address _pool) external;

  function isPool(address _pool) external view returns (bool);

  /***********************
   ** REWARDS **
   ***********************/

  event AddRewardsMerkleRoot(uint256 indexed epoch, bytes32 merkleRoot);
  event ClaimPoolRewards(uint256 indexed _epoch, address indexed _account, uint256 sharesAmount);
  event ClaimPoolRewardsBatch(address indexed claimer, uint256 numClaims, uint256 totalAmount);
  event SetMaxBatchSize(uint256 maxBatchSize);

  function addRewardsMerkleRoot(uint256 _epoch, bytes32 merkleRoot) external;

  function claimPoolRewards(
    uint256 _epoch,
    address _account,
    uint256 _sharesAmount,
    bytes32[] calldata merkleProof
  ) external;

  function claimPoolRewardsBatch(
    uint256[] calldata _epochs,
    address[] calldata _accounts,
    uint256[] calldata _sharesAmounts,
    bytes32[][] calldata merkleProofs
  ) external;

  function setMaxBatchSize(uint256 _maxBatchSize) external;

  function isRewardsClaimed(uint256 _epoch, address _account) external view returns (bool);
}
