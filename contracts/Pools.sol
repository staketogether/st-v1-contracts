// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import './interfaces/IPools.sol';
import './Router.sol';
import './StakeTogether.sol';

/// @custom:security-contact security@staketogether.app
contract Pools is IPools, AccessControl, Pausable, ReentrancyGuard {
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant POOL_MANAGER_ROLE = keccak256('POOL_MANAGER_ROLE');

  StakeTogether public stakeTogether;
  Router public distribution;

  constructor() payable {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(POOL_MANAGER_ROLE, msg.sender);
  }

  modifier onlyRouter() {
    require(msg.sender == address(distribution), 'ONLY_DISTRIBUTOR_CONTRACT');
    _;
  }

  receive() external payable {
    _transferToStakeTogether();
    emit ReceiveEther(msg.sender, msg.value);
  }

  fallback() external payable {
    _transferToStakeTogether();
    emit FallbackEther(msg.sender, msg.value);
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function setRouter(address _distributor) external onlyRole(ADMIN_ROLE) {
    require(_distributor != address(0), 'DISTRIBUTOR_ALREADY_SET');
    distribution = Router(payable(_distributor));
    emit SetRouter(_distributor);
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function _transferToStakeTogether() private {
    payable(address(stakeTogether)).transfer(address(this).balance);
  }

  /***********************
   ** POOLS **
   ***********************/

  uint256 public maxPools = 100000;
  uint256 public poolCount = 0;
  mapping(address => bool) private pools;

  bool public permissionLessAddPool = false;

  function setMaxPools(uint256 _maxPools) external onlyRole(ADMIN_ROLE) {
    require(_maxPools >= poolCount, 'INVALID_MAX_POOLS');
    maxPools = _maxPools;
    emit SetMaxPools(_maxPools);
  }

  function setPermissionLessAddPool(bool _permissionLessAddPool) external onlyRole(ADMIN_ROLE) {
    permissionLessAddPool = _permissionLessAddPool;
    emit SetPermissionLessAddPool(_permissionLessAddPool);
  }

  function addPool(address _pool) external payable nonReentrant {
    require(_pool != address(0), 'ZERO_ADDR');
    require(_pool != address(this), 'POOL_CANNOT_BE_THIS');
    require(_pool != address(stakeTogether), 'POOL_CANNOT_BE_STAKE_TOGETHER');
    require(_pool != address(distribution), 'POOL_CANNOT_BE_DISTRIBUTOR');
    require(!isPool(_pool), 'POOL_ALREADY_ADDED');
    require(poolCount < maxPools, 'MAX_POOLS_REACHED');

    pools[_pool] = true;
    poolCount += 1;
    emit AddPool(_pool);

    if (permissionLessAddPool) {
      if (!hasRole(POOL_MANAGER_ROLE, msg.sender)) {
        require(msg.value == stakeTogether.addPoolFee(), 'INVALID_FEE_AMOUNT');
        payable(stakeTogether.stakeTogetherFeeAddress()).transfer(stakeTogether.addPoolFee());
      }
    } else {
      require(hasRole(POOL_MANAGER_ROLE, msg.sender), 'ONLY_POOL_MANAGER');
    }
  }

  function removePool(address _pool) external onlyRole(POOL_MANAGER_ROLE) {
    require(isPool(_pool), 'POOL_NOT_FOUND');

    pools[_pool] = false;
    poolCount -= 1;
    emit RemovePool(_pool);
  }

  function isPool(address _pool) public view returns (bool) {
    return pools[_pool];
  }

  /***********************
   ** REWARDS **
   ***********************/

  mapping(uint256 => bytes32) public rewardsMerkleRoots;
  mapping(uint256 => mapping(uint256 => uint256)) private claimedBitMap;
  uint256 public maxBatchSize = 100;

  function addRewardsMerkleRoot(uint256 _epoch, bytes32 merkleRoot) external onlyRouter {
    require(rewardsMerkleRoots[_epoch] == bytes32(0), 'MERKLE_ALREADY_SET_FOR_EPOCH');
    rewardsMerkleRoots[_epoch] = merkleRoot;
    emit AddRewardsMerkleRoot(_epoch, merkleRoot);
  }

  function claimPoolRewards(
    uint256 _epoch,
    address _account,
    uint256 _sharesAmount,
    bytes32[] calldata merkleProof
  ) public nonReentrant whenNotPaused {
    require(rewardsMerkleRoots[_epoch] != bytes32(0), 'EPOCH_NOT_FOUND');
    require(_account != address(0), 'INVALID_ADDRESS');
    require(_sharesAmount > 0, 'ZERO_SHARES_AMOUNT');
    if (isRewardsClaimed(_epoch, _account)) revert('ALREADY_CLAIMED');

    bytes32 leaf = keccak256(abi.encodePacked(_account, _sharesAmount));
    if (!MerkleProof.verify(merkleProof, rewardsMerkleRoots[_epoch], leaf))
      revert('INVALID_MERKLE_PROOF');

    _setRewardsClaimed(_epoch, _account);
    stakeTogether.claimPoolRewards(_account, _sharesAmount);
    emit ClaimPoolRewards(_epoch, _account, _sharesAmount);
  }

  function claimPoolRewardsBatch(
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
      claimPoolRewards(_epochs[i], _accounts[i], _sharesAmounts[i], merkleProofs[i]);
      totalAmount += _sharesAmounts[i];
    }

    emit ClaimPoolRewardsBatch(msg.sender, length, totalAmount);
  }

  function setMaxBatchSize(uint256 _maxBatchSize) external onlyRole(ADMIN_ROLE) {
    maxBatchSize = _maxBatchSize;
    emit SetMaxBatchSize(_maxBatchSize);
  }

  function isRewardsClaimed(uint256 _epoch, address _account) public view returns (bool) {
    uint256 index = uint256(keccak256(abi.encodePacked(_epoch, _account)));
    uint256 claimedWordIndex = index / 256;
    uint256 claimedBitIndex = index % 256;
    uint256 claimedWord = claimedBitMap[_epoch][claimedWordIndex];
    uint256 mask = (1 << claimedBitIndex);
    return claimedWord & mask == mask;
  }

  function _setRewardsClaimed(uint256 _epoch, address _account) private {
    uint256 index = uint256(keccak256(abi.encodePacked(_epoch, _account)));
    uint256 claimedWordIndex = index / 256;
    uint256 claimedBitIndex = index % 256;
    claimedBitMap[_epoch][claimedWordIndex] =
      claimedBitMap[_epoch][claimedWordIndex] |
      (1 << claimedBitIndex);
  }
}
