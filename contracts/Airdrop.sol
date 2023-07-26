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

  StakeTogether public stakeTogether;
  Router public router;

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
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  modifier onlyRouter() {
    require(msg.sender == address(router), 'ONLY_ROUTER');
    _;
  }

  receive() external payable nonReentrant {
    emit ReceiveEther(msg.sender, msg.value);
    _transferToStakeTogether();
  }

  fallback() external payable nonReentrant {
    emit FallbackEther(msg.sender, msg.value);
    _transferToStakeTogether();
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function setRouter(address _router) external onlyRole(ADMIN_ROLE) {
    require(_router != address(0), 'ROUTER_ALREADY_SET');
    router = Router(payable(_router));
    emit SetRouter(_router);
  }

  function _transferToStakeTogether() private {
    payable(address(stakeTogether)).transfer(address(this).balance);
  }

  /**************
   ** AIRDROPS **
   **************/

  mapping(Fees.FeeRoles => mapping(uint256 => bytes32)) public airdropsMerkleRoots;
  mapping(Fees.FeeRoles => mapping(uint256 => mapping(uint256 => uint256))) private claimedBitMap;
  uint256 public maxBatchSize;

  function addAirdropMerkleRoot(
    Fees.FeeRoles _role,
    uint256 _epoch,
    bytes32 merkleRoot
  ) external onlyRouter {
    require(airdropsMerkleRoots[_role][_epoch] == bytes32(0), 'MERKLE_ALREADY_SET_FOR_EPOCH');
    airdropsMerkleRoots[_role][_epoch] = merkleRoot;
    emit AddAirdropMerkleRoot(_role, _epoch, merkleRoot);
  }

  function claimAirdrop(
    Fees.FeeRoles _role,
    uint256 _epoch,
    address _account,
    uint256 _sharesAmount,
    bytes32[] calldata merkleProof
  ) public nonReentrant whenNotPaused {
    require(airdropsMerkleRoots[_role][_epoch] != bytes32(0), 'EPOCH_NOT_FOUND');
    require(_account != address(0), 'ZERO_ADDR');
    require(_sharesAmount > 0, 'ZERO_SHARES_AMOUNT');
    if (isAirdropClaimed(_role, _epoch, _account)) revert('ALREADY_CLAIMED');

    bytes32 leaf = keccak256(abi.encodePacked(_account, _sharesAmount));
    if (!MerkleProofUpgradeable.verify(merkleProof, airdropsMerkleRoots[_role][_epoch], leaf))
      revert('INVALID_MERKLE_PROOF');

    _setAirdropClaimed(_role, _epoch, _account);

    stakeTogether.claimRewards(_account, _sharesAmount, _role);
    emit ClaimAirdrop(_role, _epoch, _account, _sharesAmount);
  }

  function claimAirdropBatch(
    Fees.FeeRoles _role,
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
      claimAirdrop(_role, _epochs[i], _accounts[i], _sharesAmounts[i], merkleProofs[i]);
      totalAmount += _sharesAmounts[i];
    }

    emit ClaimAirdropBatch(msg.sender, _role, length, totalAmount);
  }

  function setMaxBatchSize(uint256 _maxBatchSize) external onlyRole(ADMIN_ROLE) {
    maxBatchSize = _maxBatchSize;
    emit SetMaxBatchSize(_maxBatchSize);
  }

  function isAirdropClaimed(
    Fees.FeeRoles _role,
    uint256 _epoch,
    address _account
  ) public view returns (bool) {
    uint256 index = uint256(keccak256(abi.encodePacked(_role, _epoch, _account)));
    uint256 claimedWordIndex = index / 256;
    uint256 claimedBitIndex = index % 256;
    uint256 claimedWord = claimedBitMap[_role][_epoch][claimedWordIndex];
    uint256 mask = (1 << claimedBitIndex);
    return claimedWord & mask == mask;
  }

  function _setAirdropClaimed(Fees.FeeRoles _role, uint256 _epoch, address _account) private {
    uint256 index = uint256(keccak256(abi.encodePacked(_role, _epoch, _account)));
    uint256 claimedWordIndex = index / 256;
    uint256 claimedBitIndex = index % 256;
    claimedBitMap[_role][_epoch][claimedWordIndex] =
      claimedBitMap[_role][_epoch][claimedWordIndex] |
      (1 << claimedBitIndex);
  }
}
