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

  mapping(uint256 => bytes32) public airdropsMerkleRoots;
  mapping(uint256 => mapping(uint256 => uint256)) private claimedBitMap;
  uint256 public maxBatchSize;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __Pausable_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

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
    _transferToStakeTogether();
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

  function _transferToStakeTogether() private {
    payable(address(stakeTogether)).transfer(address(this).balance);
  }

  /**************
   ** AIRDROPS **
   **************/

  function addAirdropMerkleRoot(uint256 _epoch, bytes32 merkleRoot) external {
    require(msg.sender == address(router), 'ONLY_ROUTER');
    require(airdropsMerkleRoots[_epoch] == bytes32(0), 'MERKLE_ALREADY_SET_FOR_EPOCH');
    airdropsMerkleRoots[_epoch] = merkleRoot;
    emit AddAirdropMerkleRoot(_epoch, merkleRoot);
  }

  function claimAirdrop(
    uint256 _epoch,
    address _account,
    uint256 _sharesAmount,
    bytes32[] calldata merkleProof
  ) public nonReentrant whenNotPaused {
    require(airdropsMerkleRoots[_epoch] != bytes32(0), 'EPOCH_NOT_FOUND');
    require(_account != address(0), 'ZERO_ADDR');
    require(_sharesAmount > 0, 'ZERO_SHARES_AMOUNT');
    if (isAirdropClaimed(_epoch, _account)) revert('ALREADY_CLAIMED');

    bytes32 leaf = keccak256(abi.encodePacked(_account, _sharesAmount));
    if (!MerkleProofUpgradeable.verify(merkleProof, airdropsMerkleRoots[_epoch], leaf))
      revert('INVALID_MERKLE_PROOF');

    _setAirdropClaimed(_epoch, _account);

    stakeTogether.claimRewards(_account, _sharesAmount);
    emit ClaimAirdrop(_epoch, _account, _sharesAmount);
  }

  function claimAirdropBatch(
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
      claimAirdrop(_epochs[i], _accounts[i], _sharesAmounts[i], merkleProofs[i]);
      totalAmount += _sharesAmounts[i];
    }

    emit ClaimAirdropBatch(msg.sender, length, totalAmount);
  }

  function setMaxBatchSize(uint256 _maxBatchSize) external onlyRole(ADMIN_ROLE) {
    maxBatchSize = _maxBatchSize;
    emit SetMaxBatchSize(_maxBatchSize);
  }

  function isAirdropClaimed(uint256 _epoch, address _account) public view returns (bool) {
    uint256 index = uint256(keccak256(abi.encodePacked(_epoch, _account)));
    uint256 claimedWordIndex = index / 256;
    uint256 claimedBitIndex = index % 256;
    uint256 claimedWord = claimedBitMap[_epoch][claimedWordIndex];
    uint256 mask = (1 << claimedBitIndex);
    return claimedWord & mask == mask;
  }

  function _setAirdropClaimed(uint256 _epoch, address _account) private {
    uint256 index = uint256(keccak256(abi.encodePacked(_epoch, _account)));
    uint256 claimedWordIndex = index / 256;
    uint256 claimedBitIndex = index % 256;
    claimedBitMap[_epoch][claimedWordIndex] =
      claimedBitMap[_epoch][claimedWordIndex] |
      (1 << claimedBitIndex);
  }
}
