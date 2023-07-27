// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import './IFees.sol';

/// @custom:security-contact security@staketogether.app
interface IAirdrop {
  event AddAirdropMerkleRoot(IFees.FeeRoles indexed _role, uint256 indexed epoch, bytes32 merkleRoot);
  event AddMerkleRoots(
    uint256 indexed epoch,
    bytes32 poolsRoot,
    bytes32 operatorsRoot,
    bytes32 stakeRoot,
    bytes32 withdrawalsRoot,
    bytes32 rewardsRoot
  );
  event ClaimAirdrop(
    IFees.FeeRoles indexed role,
    uint256 indexed epoch,
    address indexed account,
    uint256 sharesAmount
  );
  event ClaimAirdropBatch(
    address indexed claimer,
    IFees.FeeRoles indexed role,
    uint256 numClaims,
    uint256 totalAmount
  );
  event ClaimRewards(uint256 indexed _epoch, address indexed _account, uint256 sharesAmount);
  event ClaimRewardsBatch(address indexed claimer, uint256 numClaims, uint256 totalAmount);
  event FallbackEther(address indexed sender, uint amount);
  event ReceiveEther(address indexed sender, uint amount);
  event SetMaxBatchSize(uint256 maxBatchSize);
  event SetRouter(address routerContract);
  event SetStakeTogether(address stakeTogether);
}
