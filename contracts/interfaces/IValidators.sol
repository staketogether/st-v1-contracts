// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IValidators {
  event AddValidatorOracle(address indexed account);
  event CreateValidator(
    address indexed creator,
    uint256 indexed amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );
  event FallbackEther(address indexed sender, uint amount);
  event ReceiveEther(address indexed sender, uint amount);
  event RemoveValidator(address indexed account, uint256 epoch, bytes publicKey);
  event RemoveValidatorOracle(address indexed account);
  event SetRouterContract(address routerContract);
  event SetStakeTogether(address stakeTogether);
  event SetValidatorSize(uint256 newValidatorSize);
}
