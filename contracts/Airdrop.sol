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
  uint256 public maxBatchSize;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __Pausable_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);

    version = 1;
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  receive() external payable nonReentrant {
    emit ReceiveEther(msg.sender, msg.value);
  }

  /// @notice Transfers any extra amount of ETH in the contract to the StakeTogether fee address.
  /// @dev Only callable by the admin role.
  function transferExtraAmount() external whenNotPaused onlyRole(ADMIN_ROLE) {
    uint256 extraAmount = address(this).balance;
    require(extraAmount > 0, 'NO_EXTRA_AMOUNT');
    address stakeTogetherFee = stakeTogether.getFeeAddress(IStakeTogether.FeeRole.StakeTogether);
    payable(stakeTogetherFee).transfer(extraAmount);
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function setRouter(address _router) external onlyRole(ADMIN_ROLE) {
    require(_router != address(0), 'ROUTER_CONTRACT_ALREADY_SET');
    router = Router(payable(_router));
    emit SetRouter(_router);
  }

  function setMaxBatch(uint256 _batchSize) external onlyRole(ADMIN_ROLE) {
    maxBatchSize = _batchSize;
    emit SetMaxBatch(_batchSize);
  }

  /**************
   ** AIRDROPS **
   **************/

  function addMerkleRoot(uint256 _epoch, bytes32 merkleRoot) external nonReentrant {
    require(msg.sender == address(router), 'ONLY_ROUTER');
    require(merkleRoots[_epoch] == bytes32(0), 'MERKLE_ALREADY_SET_FOR_EPOCH');
    merkleRoots[_epoch] = merkleRoot;
    emit AddMerkleRoot(_epoch, merkleRoot);
  }

  function claim(
    uint256 _epoch,
    address _account,
    uint256 _sharesAmount,
    bytes32[] calldata merkleProof
  ) public nonReentrant whenNotPaused {
    require(merkleRoots[_epoch] != bytes32(0), 'EPOCH_NOT_FOUND');
    require(_account != address(0), 'ZERO_ADDR');
    require(_sharesAmount > 0, 'ZERO_SHARES_AMOUNT');
    if (isClaimed(_epoch, _account)) revert('ALREADY_CLAIMED');

    bytes32 leaf = keccak256(abi.encodePacked(_account, _sharesAmount));
    if (!MerkleProofUpgradeable.verify(merkleProof, merkleRoots[_epoch], leaf))
      revert('INVALID_MERKLE_PROOF');

    uint256 index = uint256(keccak256(abi.encodePacked(_epoch, _account)));
    uint256 claimedWordIndex = index / 256;
    uint256 claimedBitIndex = index % 256;
    claimBitMap[_epoch][claimedWordIndex] =
      claimBitMap[_epoch][claimedWordIndex] |
      (1 << claimedBitIndex);

    stakeTogether.claimRewards(_account, _sharesAmount);
    emit ClaimAirdrop(_epoch, _account, _sharesAmount);
  }

  function claimBatch(
    uint256[] calldata _epochs,
    address[] calldata _accounts,
    uint256[] calldata _sharesAmounts,
    bytes32[][] calldata merkleProofs
  ) external nonReentrant whenNotPaused {
    uint256 length = _epochs.length;
    require(length <= maxBatchSize, 'BATCH_SIZE_EXCEEDS_LIMIT');
    require(
      _accounts.length == length && _sharesAmounts.length == length && merkleProofs.length == length,
      'INVALID_ARRAYS_LENGTH'
    );

    uint256 totalAmount = 0;
    for (uint256 i = 0; i < length; i++) {
      claim(_epochs[i], _accounts[i], _sharesAmounts[i], merkleProofs[i]);
      totalAmount += _sharesAmounts[i];
    }

    emit ClaimBatch(msg.sender, length, totalAmount);
  }

  function isClaimed(uint256 _epoch, address _account) public view returns (bool) {
    uint256 index = uint256(keccak256(abi.encodePacked(_epoch, _account)));
    uint256 claimedWordIndex = index / 256;
    uint256 claimedBitIndex = index % 256;
    uint256 claimedWord = claimBitMap[_epoch][claimedWordIndex];
    uint256 mask = (1 << claimedBitIndex);
    return claimedWord & mask == mask;
  }
}
