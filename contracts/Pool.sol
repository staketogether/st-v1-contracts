// SPDX-FileCopyrightText: 2023 Stake Together Labs <info@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;
import './StakeTogether.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import { IPool } from './interfaces/IPool.sol';

/// @custom:security-contact security@staketogether.app
contract Pool is Ownable, Pausable, ReentrancyGuard, IPool {
  StakeTogether public stakeTogether;
  Distributor public distribution;

  constructor(StakeTogether _stakeTogether, Distributor _distributor) payable {
    stakeTogether = StakeTogether(payable(_stakeTogether));
    distribution = Distributor(payable(_distributor));
  }

  modifier onlyDistributor() {
    require(msg.sender == address(distribution), 'ONLY_DISTRIBUTOR_CONTRACT');
    _;
  }

  receive() external payable {
    _transferToStakeTogether();
    emit EtherReceived(msg.sender, msg.value);
  }

  fallback() external payable {
    _transferToStakeTogether();
    emit EtherReceived(msg.sender, msg.value);
  }

  function _transferToStakeTogether() private {
    payable(address(stakeTogether)).transfer(address(this).balance);
  }

  /***********************
   ** POOLS **
   ***********************/

  event AddPool(address account);
  event RemovePool(address account);
  event SetMaxPools(uint256 maxPools);
  event SetAddPoolFee(uint256 addPoolFee);
  event SetPoolManager(address poolManager);
  event SetPermissionLessAddPool(bool permissionLessAddPool);

  uint256 public maxPools = 100000;
  uint256 public poolCount = 0;
  mapping(address => bool) private pools;
  uint256 public addPoolFee = 1 ether;
  bool public permissionLessAddPool = false;
  address public poolManager;

  function setMaxPools(uint256 _maxPools) external onlyOwner {
    require(_maxPools >= poolCount, 'INVALID_MAX_POOLS');
    maxPools = _maxPools;
    emit SetMaxPools(_maxPools);
  }

  function setAddPoolFee(uint256 _addPoolFee) external onlyOwner {
    addPoolFee = _addPoolFee;
    emit SetPoolFee(_addPoolFee);
  }

  function setPoolManager(address _poolManager) external onlyOwner {
    require(_poolManager != address(0), 'ZERO_ADDR');
    poolManager = _poolManager;
    emit SetPoolManager(_poolManager);
  }

  function setPermissionLessAddPool(bool _permissionLessAddPool) external onlyOwner {
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
      if (msg.sender != owner() && msg.sender != poolManager) {
        require(msg.value == addPoolFee, 'INVALID_FEE_AMOUNT');
        payable(stakeTogether.stakeTogetherFeeAddress()).transfer(addPoolFee);
      }
    } else {
      require(msg.sender == owner() || msg.sender == poolManager, 'NOT_AUTHORIZED');
    }
  }

  function removePool(address _pool) external {
    require(isPool(_pool), 'POOL_NOT_FOUND');
    require(msg.sender == owner() || msg.sender == poolManager, 'NOT_AUTHORIZED');

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

  event ClaimRewardsBatch(address indexed claimer, uint256 numClaims, uint256 totalAmount);
  event SetMaxBatchSize(uint256 maxBatchSize);

  mapping(uint256 => bytes32) public rewardsMerkleRoots;
  mapping(uint256 => mapping(uint256 => uint256)) private claimedBitMap;
  uint256 public maxBatchSize = 100;

  function addRewardsMerkleRoot(uint256 _epoch, bytes32 merkleRoot) external onlyDistributor {
    require(rewardsMerkleRoots[_epoch] == bytes32(0), 'MERKLE_ALREADY_SET_FOR_EPOCH');
    rewardsMerkleRoots[_epoch] = merkleRoot;
    emit AddRewardsMerkleRoot(_epoch, merkleRoot);
  }

  function removeRewardsMerkleRoot(uint256 _epoch) external onlyOwner {
    require(rewardsMerkleRoots[_epoch] != bytes32(0), 'MERKLE_NOT_SET_FOR_EPOCH');
    rewardsMerkleRoots[_epoch] = bytes32(0);
    emit RemoveRewardsMerkleRoot(_epoch);
  }

  function claimRewards(
    uint256 _epoch,
    uint256 _index,
    address _account,
    uint256 _sharesAmount,
    bytes32[] calldata merkleProof
  ) public nonReentrant whenNotPaused {
    require(rewardsMerkleRoots[_epoch] != bytes32(0), 'EPOCH_NOT_FOUND');
    require(_account != address(0), 'INVALID_ADDRESS');
    require(_sharesAmount > 0, 'ZERO_SHARES_AMOUNT');
    if (isRewardsClaimed(_epoch, _index)) revert('ALREADY_CLAIMED');

    bytes32 leaf = keccak256(abi.encodePacked(_index, _account, _sharesAmount));
    if (!MerkleProof.verify(merkleProof, rewardsMerkleRoots[_epoch], leaf))
      revert('INVALID_MERKLE_PROOF');

    _setRewardsClaimed(_epoch, _index);

    stakeTogether.mintRewards(_account, _sharesAmount);

    emit ClaimRewards(_epoch, _index, _account, _sharesAmount);
  }

  function claimRewardsBatch(
    uint256[] calldata _epochs,
    uint256[] calldata _indices,
    address[] calldata _accounts,
    uint256[] calldata _sharesAmounts,
    bytes32[][] calldata merkleProofs
  ) external nonReentrant whenNotPaused {
    uint256 length = _epochs.length;
    require(length <= maxBatchSize, 'BATCH_SIZE_EXCEEDS_LIMIT');
    require(
      _indices.length == length &&
        _accounts.length == length &&
        _sharesAmounts.length == length &&
        merkleProofs.length == length,
      'INVALID_ARRAYS_LENGTH'
    );

    uint256 totalAmount = 0;
    for (uint256 i = 0; i < length; i++) {
      claimRewards(_epochs[i], _indices[i], _accounts[i], _sharesAmounts[i], merkleProofs[i]);
      totalAmount += _sharesAmounts[i];
    }

    emit ClaimRewardsBatch(msg.sender, length, totalAmount);
  }

  function setMaxBatchSize(uint256 _maxBatchSize) external onlyOwner {
    maxBatchSize = _maxBatchSize;
    emit SetMaxBatchSize(_maxBatchSize);
  }

  function isRewardsClaimed(uint256 _epoch, uint256 _index) public view returns (bool) {
    uint256 claimedWordIndex = _index / 256;
    uint256 claimedBitIndex = _index % 256;
    uint256 claimedWord = claimedBitMap[_epoch][claimedWordIndex];
    uint256 mask = (1 << claimedBitIndex);
    return claimedWord & mask == mask;
  }

  function _setRewardsClaimed(uint256 _epoch, uint256 _index) private {
    uint256 claimedWordIndex = _index / 256;
    uint256 claimedBitIndex = _index % 256;
    claimedBitMap[_epoch][claimedWordIndex] =
      claimedBitMap[_epoch][claimedWordIndex] |
      (1 << claimedBitIndex);
  }
}
