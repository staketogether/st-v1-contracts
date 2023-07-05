// SPDX-FileCopyrightText: 2023 Stake Together Labs <info@staketogether.app>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

/// @title Pool Contract Interface
/// @notice Interface for a contract that manage pools and allows to claim a shares.
/// @dev The pool interface implement shares distribution via merkle proofs.
interface IPool {
  /// @dev This event is emitted whenever the contract receives Ether from a sender.
  /// @param sender The address of the sender.
  /// @param amount The amount of Ether received.
  event EtherReceived(address indexed sender, uint amount);

  /// @dev This event is triggered whenever a new merkle root is added.
  /// @param epoch The epoch for which the new merkle root is added.
  /// @param merkleRoot The new merkle root that has been added.
  event AddRewardsMerkleRoot(uint256 indexed epoch, bytes32 merkleRoot);

  /// @dev This event is triggered whenever a merkle root is removed.
  /// @param epoch The epoch for which the merkle root is removed.
  event RemoveRewardsMerkleRoot(uint256 indexed epoch);

  /// @notice Allows a certain amount of shares to be claimed by an address, provided a valid merkle proof.
  /// @dev This function will revert if the provided inputs are invalid.
  /// @param epoch The epoch of the account that is claiming.
  /// @param index The index of the account that is claiming.
  /// @param account The address of the account that is claiming.
  /// @param sharesAmount The amount of shares to be claimed.
  /// @param merkleProof The merkle proof that proves the claim is valid.
  function claimRewards(
    uint256 epoch,
    uint256 index,
    address account,
    uint256 sharesAmount,
    bytes32[] calldata merkleProof
  ) external;

  /**
   * @notice Claims rewards in batch for multiple epochs and accounts.
   * @dev This function allows multiple rewards to be claimed in a single transaction.
   * @param _epochs An array of epochs for which the rewards will be claimed.
   * @param _indices An array of indices corresponding to the accounts for which rewards will be claimed.
   * @param _accounts An array of addresses representing the accounts that will claim rewards.
   * @param _sharesAmounts An array of amounts of shares to be claimed for each account.
   * @param merkleProofs An array of merkle proofs corresponding to each epoch and account.
   */
  function claimRewardsBatch(
    uint256[] calldata _epochs,
    uint256[] calldata _indices,
    address[] calldata _accounts,
    uint256[] calldata _sharesAmounts,
    bytes32[][] calldata merkleProofs
  ) external;

  /// @notice Checks if a certain claim has been made.
  /// @param epoch The epoch to check.
  /// @param index The index of the account for which to check.
  /// @return A boolean indicating whether the claim has been made.
  function isRewardsClaimed(uint256 epoch, uint256 index) external view returns (bool);

  /// @dev This event is triggered whenever a call to claimRewards function is successful.
  /// @param epoch The epoch of the account that has claimed.
  /// @param index The index of the account that has claimed.
  /// @param account The address of the account that has claimed.
  /// @param sharesAmount The amount of shares that were claimed.
  event ClaimRewards(uint256 indexed epoch, uint256 index, address indexed account, uint256 sharesAmount);
}
