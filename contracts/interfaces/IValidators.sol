// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IValidators {
  event ReceiveEther(address indexed sender, uint amount);
  event FallbackEther(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);

  receive() external payable;

  fallback() external payable;

  function pause() external;

  function unpause() external;

  /***********************
   ** VALIDATOR ORACLES **
   ***********************/

  event AddValidatorOracle(address indexed account);
  event RemoveValidatorOracle(address indexed account);

  function addValidatorOracle(address _oracleAddress) external;

  function removeValidatorOracle(address _oracleAddress) external;

  function forceNextValidatorOracle() external;

  function currentValidatorOracle() external view returns (address);

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
  event SetWithdrawalCredentials(bytes withdrawalCredentials);

  function setWithdrawalCredentials(bytes memory _withdrawalCredentials) external;

  function createValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external;

  function removeValidator(uint256 _epoch, bytes calldata _publicKey) external payable;

  function setValidatorSize(uint256 _newSize) external;

  function validatorSize() external view returns (uint256);

  function isValidator(bytes memory _publicKey) external view returns (bool);
}
