// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IValidators {
  event ReceiveEther(address indexed sender, uint amount);
  event FallbackEther(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);

  /***********************
   ** VALIDATOR ORACLES **
   ***********************/
  event AddValidatorOracle(address indexed account);
  event RemoveValidatorOracle(address indexed account);

  /*****************
   ** VALIDATORS **
   *****************/
  event CreateValidator(
    address indexed creator,
    uint256 indexed amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );
  event RemoveValidator(address indexed account, uint256 epoch, bytes publicKey);
  event SetValidatorSize(uint256 newValidatorSize);
}
