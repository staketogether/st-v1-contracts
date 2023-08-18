// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IAirdrop {
  event AddMerkleRoot(uint256 indexed epoch, bytes32 merkleRoot);
  event Claim(
    uint256 indexed epoch,
    uint256 index,
    address indexed account,
    uint256 sharesAmount,
    bytes32[] merkleProof
  );
  event ClaimBatch(address indexed claimer, uint256 numClaims, uint256 totalAmount);
  event ReceiveEther(address indexed sender, uint amount);
  event SetRouter(address router);
  event SetStakeTogether(address stakeTogether);
}
