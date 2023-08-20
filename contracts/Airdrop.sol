// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol';

import './Router.sol';
import './StakeTogether.sol';

import './interfaces/IAirdrop.sol';

/// @title Airdrop Contract for StakeTogether Protocol
/// @notice This contract manages the Airdrop functionality for the StakeTogether protocol, providing methods to set and claim rewards.
/// @custom:security-contact security@staketogether.app
contract Airdrop is
  Initializable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuardUpgradeable,
  IAirdrop
{
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  uint256 public version;

  StakeTogether public stakeTogether;
  Router public router;

  mapping(uint256 => bytes32) public merkleRoots;
  mapping(uint256 => mapping(uint256 => uint256)) private claimBitMap;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes the contract with initial settings.
  function initialize() external initializer {
    __Pausable_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);

    version = 1;
  }

  /// @notice Pauses all contract functionalities.
  /// @dev Only callable by the admin role.
  function pause() external onlyRole(ADMIN_ROLE) {
    _pause();
  }

  /// @notice Unpauses all contract functionalities.
  /// @dev Only callable by the admin role.
  function unpause() external onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  /// @notice Internal function to authorize an upgrade.
  /// @dev Only callable by the upgrader role.
  /// @param _newImplementation Address of the new contract implementation.
  function _authorizeUpgrade(address _newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  /// @notice Transfers any extra amount of ETH in the contract to the StakeTogether fee address.
  /// @dev Only callable by the admin role.
  receive() external payable nonReentrant {
    emit ReceiveEther(msg.sender, msg.value);
  }

  /// @notice Transfers any extra amount of ETH in the contract to the StakeTogether fee address.
  /// @dev Only callable by the admin role.
  function transferExtraAmount() external whenNotPaused nonReentrant onlyRole(ADMIN_ROLE) {
    uint256 extraAmount = address(this).balance;
    require(extraAmount > 0, 'NO_EXTRA_AMOUNT');
    address stakeTogetherFee = stakeTogether.getFeeAddress(IStakeTogether.FeeRole.StakeTogether);
    payable(stakeTogetherFee).transfer(extraAmount);
  }

  /// @notice Sets the StakeTogether contract address.
  /// @param _stakeTogether The address of the StakeTogether contract.
  /// @dev Only callable by the admin role.
  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  /// @notice Sets the Router contract address.
  /// @param _router The address of the router.
  /// @dev Only callable by the admin role.
  function setRouter(address _router) external onlyRole(ADMIN_ROLE) {
    require(_router != address(0), 'ROUTER_CONTRACT_ALREADY_SET');
    router = Router(payable(_router));
    emit SetRouter(_router);
  }

  /**************
   ** AIRDROPS **
   **************/

  /// @notice Adds a new Merkle root for a given epoch.
  /// @param _epoch The epoch number.
  /// @param merkleRoot The Merkle root.
  /// @dev Only callable by the router.
  function addMerkleRoot(uint256 _epoch, bytes32 merkleRoot) external nonReentrant whenNotPaused {
    require(msg.sender == address(router), 'ONLY_ROUTER');
    require(merkleRoots[_epoch] == bytes32(0), 'MERKLE_ALREADY_SET_FOR_EPOCH');
    merkleRoots[_epoch] = merkleRoot;
    emit AddMerkleRoot(_epoch, merkleRoot);
  }

  /// @notice Claims a reward for a specific epoch.
  /// @param _epoch The epoch number.
  /// @param _index The index in the Merkle tree.
  /// @param _account The address claiming the reward.
  /// @param _sharesAmount The amount of shares to claim.
  /// @param merkleProof The Merkle proof required to claim the reward.
  /// @dev Verifies the Merkle proof and transfers the reward shares.
  function claim(
    uint256 _epoch,
    uint256 _index,
    address _account,
    uint256 _sharesAmount,
    bytes32[] calldata merkleProof
  ) external nonReentrant whenNotPaused {
    require(!isClaimed(_epoch, _index), 'ALREADY_CLAIMED');
    require(merkleRoots[_epoch] != bytes32(0), 'MERKLE_ROOT_NOT_SET');
    require(_account != address(0), 'ZERO_ADDRESS');
    require(_sharesAmount > 0, 'ZERO_AMOUNT');

    bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(_index, _account, _sharesAmount))));
    require(MerkleProofUpgradeable.verify(merkleProof, merkleRoots[_epoch], leaf), 'INVALID_PROOF');

    _setClaimed(_epoch, _index);

    stakeTogether.claimAirdropRewards(_account, _sharesAmount);

    emit Claim(_epoch, _index, _account, _sharesAmount, merkleProof);
  }

  /// @notice Marks a reward as claimed for a specific index and epoch.
  /// @param _epoch The epoch number.
  /// @param _index The index in the Merkle tree.
  /// @dev This function is private and is used internally to update the claim status.
  function _setClaimed(uint256 _epoch, uint256 _index) private {
    uint256 claimedWordIndex = _index / 256;
    uint256 claimedBitIndex = _index % 256;
    claimBitMap[_epoch][claimedWordIndex] =
      claimBitMap[_epoch][claimedWordIndex] |
      (1 << claimedBitIndex);
  }

  /// @notice Checks if a reward has been claimed for a specific index and epoch.
  /// @param _epoch The epoch number.
  /// @param _index The index in the Merkle tree.
  /// @return Returns true if the reward has been claimed, false otherwise.
  function isClaimed(uint256 _epoch, uint256 _index) public view returns (bool) {
    uint256 claimedWordIndex = _index / 256;
    uint256 claimedBitIndex = _index % 256;
    uint256 claimedWord = claimBitMap[_epoch][claimedWordIndex];
    uint256 mask = (1 << claimedBitIndex);
    return claimedWord & mask == mask;
  }
}
