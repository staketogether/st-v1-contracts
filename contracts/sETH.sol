// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import './interfaces/IDepositContract.sol';
import './Distributor.sol';
import './Pool.sol';
import './WETH.sol';
import './LETH.sol';

/// @custom:security-contact security@staketogether.app
abstract contract SETH is AccessControl, ERC20, ERC20Permit, Pausable, ReentrancyGuard {
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  Distributor public distributorContract;
  Pool public poolContract;
  WETH public WETHContract;
  LETH public LETHContract;
  IDepositContract public depositContract;

  constructor() ERC20('ST Pool Ether', 'SETH') ERC20Permit('ST Pool Ether') {
    _bootstrap();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
  }

  modifier onlyDistributor() {
    require(msg.sender == address(distributorContract), 'ONLY_DISTRIBUTOR_CONTRACT');
    _;
  }

  event Bootstrap(address sender, uint256 balance);
  event MintShares(address indexed to, uint256 sharesAmount);
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);

  mapping(address => uint256) private shares;
  uint256 public totalShares = 0;
  mapping(address => mapping(address => uint256)) private allowances;

  function _bootstrap() internal {
    address stakeTogether = address(this);
    uint256 balance = stakeTogether.balance;

    require(balance > 0, 'NON_ZERO_VALUE');

    emit Bootstrap(msg.sender, balance);

    _mintShares(stakeTogether, balance);
    _mintPoolShares(stakeTogether, stakeTogether, balance);

    setStakeTogetherFeeAddress(msg.sender);
    setOperatorFeeAddress(msg.sender);
  }

  function contractBalance() public view returns (uint256) {
    return address(this).balance;
  }

  function totalSupply() public view override returns (uint256) {
    return totalPooledEther();
  }

  function balanceOf(address _account) public view override returns (uint256) {
    return pooledEthByShares(netSharesOf(_account));
  }

  function sharesOf(address _account) public view returns (uint256) {
    return shares[_account];
  }

  function netSharesOf(address _account) public view returns (uint256) {
    return shares[_account] - lockedShares[_account];
  }

  function getSharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
    return Math.mulDiv(_ethAmount, totalShares, totalPooledEther());
  }

  function pooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
    return Math.mulDiv(_sharesAmount, totalPooledEther(), totalShares);
  }

  function transfer(address _to, uint256 _amount) public override returns (bool) {
    _transfer(msg.sender, _to, _amount);
    return true;
  }

  function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
    _spendAllowance(_from, msg.sender, _amount);
    _transfer(_from, _to, _amount);

    return true;
  }

  function transferShares(address _to, uint256 _sharesAmount) public returns (uint256) {
    _transferShares(msg.sender, _to, _sharesAmount);
    uint256 tokensAmount = pooledEthByShares(_sharesAmount);
    return tokensAmount;
  }

  function transferSharesFrom(
    address _from,
    address _to,
    uint256 _sharesAmount
  ) external returns (uint256) {
    uint256 tokensAmount = pooledEthByShares(_sharesAmount);
    _spendAllowance(_from, msg.sender, tokensAmount);
    _transferShares(_from, _to, _sharesAmount);
    return tokensAmount;
  }

  function allowance(address _account, address _spender) public view override returns (uint256) {
    return allowances[_account][_spender];
  }

  function approve(address _spender, uint256 _amount) public override returns (bool) {
    _approve(msg.sender, _spender, _amount);
    return true;
  }

  function increaseAllowance(address _spender, uint256 _addedValue) public override returns (bool) {
    _approve(msg.sender, _spender, allowances[msg.sender][_spender] + _addedValue);
    return true;
  }

  function decreaseAllowance(address _spender, uint256 _subtractedValue) public override returns (bool) {
    uint256 currentAllowance = allowances[msg.sender][_spender];
    require(currentAllowance >= _subtractedValue, 'ALLOWANCE_BELOW_ZERO');
    _approve(msg.sender, _spender, currentAllowance - _subtractedValue);
    return true;
  }

  function totalPooledEther() public view virtual returns (uint256);

  function _approve(address _account, address _spender, uint256 _amount) internal override {
    require(_account != address(0), 'APPROVE_FROM_ZERO_ADDR');
    require(_spender != address(0), 'APPROVE_TO_ZERO_ADDR');

    allowances[_account][_spender] = _amount;
    emit Approval(_account, _spender, _amount);
  }

  function _mintShares(address _to, uint256 _sharesAmount) internal whenNotPaused {
    require(_to != address(0), 'MINT_TO_ZERO_ADDR');

    shares[_to] = shares[_to] + _sharesAmount;
    totalShares += _sharesAmount;

    emit MintShares(_to, _sharesAmount);
  }

  function _burnShares(address _account, uint256 _sharesAmount) internal whenNotPaused {
    require(_account != address(0), 'BURN_FROM_ZERO_ADDR');
    require(_sharesAmount <= netSharesOf(_account), 'BALANCE_EXCEEDED');

    shares[_account] = shares[_account] - _sharesAmount;
    totalShares -= _sharesAmount;

    emit BurnShares(_account, _sharesAmount);
  }

  function _transfer(address _from, address _to, uint256 _amount) internal override {
    uint256 _sharesToTransfer = getSharesByPooledEth(_amount);
    _transferShares(_from, _to, _sharesToTransfer);
    _transferDelegationShares(_from, _to, _sharesToTransfer);
    emit Transfer(_from, _to, _amount);
  }

  function _transferShares(address _from, address _to, uint256 _sharesAmount) internal whenNotPaused {
    require(_from != address(0), 'TRANSFER_FROM_ZERO_ADDR');
    require(_to != address(0), 'TRANSFER_TO_ZERO_ADDR');
    require(_to != address(this), 'TRANSFER_TO_SETH_CONTRACT');
    require(_sharesAmount <= netSharesOf(_from), 'BALANCE_EXCEEDED');

    shares[_from] = shares[_from] - _sharesAmount;
    shares[_to] = shares[_to] + _sharesAmount;

    emit TransferShares(_from, _to, _sharesAmount);
  }

  function _spendAllowance(address _account, address _spender, uint256 _amount) internal override {
    uint256 currentAllowance = allowances[_account][_spender];
    if (currentAllowance != ~uint256(0)) {
      require(currentAllowance >= _amount, 'ALLOWANCE_EXCEEDED');
      _approve(_account, _spender, currentAllowance - _amount);
    }
  }

  /*****************
   ** LOCK SHARES **
   *****************/

  modifier onlyLETH() {
    require(msg.sender == address(LETHContract), 'ONLY_LETH_CONTRACT');
    _;
  }

  event SetMaxActiveLocks(uint256 amount);
  event SharesLocked(address indexed account, uint256 amount, uint256 unlockBlock);
  event SharesUnlocked(address indexed account, uint256 amount);

  struct Lock {
    uint256 amount;
    uint256 unlockBlock;
  }

  mapping(address => Lock[]) public locked;
  mapping(address => uint256) public lockedShares;
  uint256 public totalLockedShares;
  uint256 public maxActiveLocks = 10;

  // Todo: require time lock
  function setMaxActiveLocks(uint256 _amount) external onlyRole(ADMIN_ROLE) {
    maxActiveLocks = _amount;
    emit SetMaxActiveLocks(_amount);
  }

  function lockedSharesOf(address _account) public view returns (uint256) {
    return lockedShares[_account];
  }

  function lockShares(
    uint256 _sharesAmount,
    uint256 _blocks
  ) external onlyLETH nonReentrant whenNotPaused {
    require(locked[msg.sender].length < maxActiveLocks, 'TOO_MANY_LOCKS');
    require(_sharesAmount <= shares[msg.sender], 'BALANCE_EXCEEDED');
    require(_blocks > 0, 'BLOCKS_MUST_BE_GREATER_THAN_ZERO');

    shares[msg.sender] -= _sharesAmount;
    lockedShares[msg.sender] += _sharesAmount;
    totalLockedShares += _sharesAmount;

    Lock memory newLock = Lock(_sharesAmount, block.number + _blocks);
    locked[msg.sender].push(newLock);

    emit SharesLocked(msg.sender, _sharesAmount, newLock.unlockBlock);
  }

  function unlockShares() external nonReentrant whenNotPaused {
    Lock[] storage locks = locked[msg.sender];
    require(locks.length > 0, 'NO_LOCKS_FOUND');

    for (uint256 i = 0; i < locks.length; i++) {
      if (locks[i].unlockBlock <= block.number) {
        uint256 amount = locks[i].amount;
        shares[msg.sender] += amount;
        lockedShares[msg.sender] -= amount;
        totalLockedShares -= amount;

        _removeLock(msg.sender, i);
        i--;

        emit SharesUnlocked(msg.sender, amount);
      }
    }
  }

  function unlockSpecificLock(uint256 _index) external nonReentrant whenNotPaused {
    Lock[] storage locks = locked[msg.sender];
    require(_index < locks.length, 'INVALID_INDEX');
    require(locks[_index].unlockBlock <= block.number, 'LOCK_NOT_EXPIRED');

    uint256 amount = locks[_index].amount;
    shares[msg.sender] += amount;
    lockedShares[msg.sender] -= amount;
    totalLockedShares -= amount;

    _removeLock(msg.sender, _index);

    emit SharesUnlocked(msg.sender, amount);
  }

  function _removeLock(address _account, uint256 _index) internal {
    Lock[] storage locks = locked[_account];
    require(_index < locks.length, 'INVALID_INDEX');

    locks[_index] = locks[locks.length - 1];
    locks.pop();
  }

  /*****************
   ** DELEGATIONS **
   *****************/

  mapping(address => uint256) private poolShares;
  uint256 public totalPoolShares = 0;
  mapping(address => mapping(address => uint256)) private delegationsShares;
  mapping(address => address[]) private delegates;
  mapping(address => mapping(address => bool)) private isDelegate;
  uint256 public maxDelegations = 64; // Todo: verify merkle tree

  event MintPoolShares(address indexed to, address indexed pool, uint256 sharesAmount);

  event TransferPoolShares(
    address indexed from,
    address indexed to,
    address indexed pool,
    uint256 sharesAmount
  );

  event BurnPoolShares(address indexed from, address indexed pool, uint256 sharesAmount);

  function poolSharesOf(address _account) public view returns (uint256) {
    return poolShares[_account];
  }

  function delegationSharesOf(address _account, address _pool) public view returns (uint256) {
    return delegationsShares[_account][_pool];
  }

  function transferPoolShares(address _to, address _pool, uint256 _sharesAmount) external {
    _transferPoolShares(msg.sender, _to, _pool, _sharesAmount);
  }

  function _mintPoolShares(address _to, address _pool, uint256 _sharesAmount) internal whenNotPaused {
    require(_to != address(0), 'MINT_TO_ZERO_ADDR');
    require(poolContract.isPool(_pool), 'ONLY_CAN_DELEGATE_TO_POOL');
    require(delegates[_to].length < maxDelegations, 'MAX_DELEGATIONS_REACHED');

    poolShares[_pool] += _sharesAmount;
    delegationsShares[_to][_pool] += _sharesAmount;
    totalPoolShares += _sharesAmount;

    if (!isDelegate[_to][_pool]) {
      delegates[_to].push(_pool);
      isDelegate[_to][_pool] = true;
    }

    emit MintPoolShares(_to, _pool, _sharesAmount);
  }

  function _burnPoolShares(address _from, address _pool, uint256 _sharesAmount) internal whenNotPaused {
    require(_from != address(0), 'BURN_FROM_ZERO_ADDR');
    require(poolContract.isPool(_pool), 'ONLY_CAN_BURN_FROM_POOL');

    poolShares[_pool] -= _sharesAmount;
    delegationsShares[_from][_pool] -= _sharesAmount;
    totalPoolShares -= _sharesAmount;

    if (delegationsShares[_from][_pool] == 0) {
      isDelegate[_from][_pool] = false;
      // Todo: revise, need to remove from delegates array
    }

    emit BurnPoolShares(_from, _pool, _sharesAmount);
  }

  function _transferDelegationShares(
    address _from,
    address _to,
    uint256 _sharesToTransfer
  ) internal whenNotPaused {
    require(_sharesToTransfer <= sharesOf(_from), 'TRANSFER_EXCEEDS_BALANCE');

    for (uint256 i = 0; i < delegates[_from].length; i++) {
      address pool = delegates[_from][i];
      uint256 delegationSharesToTransfer = Math.mulDiv(
        delegationSharesOf(_from, pool),
        _sharesToTransfer,
        sharesOf(_from)
      );

      delegationsShares[_from][pool] -= delegationSharesToTransfer;

      if (!isDelegate[_to][pool]) {
        require(delegates[_to].length < maxDelegations, 'MAX_DELEGATIONS_REACHED');
        delegates[_to].push(pool);
        isDelegate[_to][pool] = true;
      }

      delegationsShares[_to][pool] += delegationSharesToTransfer;

      if (delegationSharesOf(_from, pool) == 0) {
        isDelegate[_from][pool] = false;
      }

      emit TransferPoolShares(_from, _to, pool, delegationSharesToTransfer);
    }
  }

  function _transferPoolShares(
    address _account,
    address _from,
    address _to,
    uint256 _sharesAmount
  ) internal whenNotPaused {
    require(_from != address(0), 'TRANSFER_FROM_ZERO_ADDR');
    require(_to != address(0), 'TRANSFER_TO_ZERO_ADDR');
    require(_to != address(this), 'TRANSFER_TO_SETH_CONTRACT');
    require(poolContract.isPool(_to), 'ONLY_CAN_TRANSFER_TO_POOL');

    require(_sharesAmount <= delegationsShares[_account][_from], 'BALANCE_EXCEEDED');

    poolShares[_from] -= _sharesAmount;
    delegationsShares[_account][_from] -= _sharesAmount;

    poolShares[_to] += _sharesAmount;
    delegationsShares[_account][_to] += _sharesAmount;

    emit TransferPoolShares(_account, _from, _to, _sharesAmount);
  }

  /*****************
   ** ADDRESSES **
   *****************/

  address public poolFeeAddress;
  address public operatorFeeAddress;
  address public stakeTogetherFeeAddress;

  event SetPoolFeeAddress(address indexed to);
  event SetOperatorFeeAddress(address indexed to);
  event SetStakeTogetherFeeAddress(address indexed to);

  // Todo: Needs TimeLock
  function setPoolFeeAddress(address _to) public onlyRole(ADMIN_ROLE) {
    require(_to != address(0), 'NON_ZERO_ADDR');
    poolFeeAddress = _to;
    emit SetPoolFeeAddress(_to);
  }

  // Todo: Needs TimeLock
  function setOperatorFeeAddress(address _to) public onlyRole(ADMIN_ROLE) {
    require(_to != address(0), 'NON_ZERO_ADDR');
    operatorFeeAddress = _to;
    emit SetOperatorFeeAddress(_to);
  }

  // Todo: Needs TimeLock
  function setStakeTogetherFeeAddress(address _to) public onlyRole(ADMIN_ROLE) {
    require(_to != address(0), 'NON_ZERO_ADDR');
    stakeTogetherFeeAddress = _to;
    emit SetStakeTogetherFeeAddress(_to);
  }

  /*****************
   ** FEES **
   *****************/

  uint256 public basisPoints = 1 ether;

  uint256 public stakeTogetherFee = 0.03 ether;
  uint256 public operatorFee = 0.03 ether;
  uint256 public poolFee = 0.03 ether;
  uint256 public validatorFee = 0.001 ether;
  uint256 public addPoolFee = 1 ether;
  uint256 public entryFee = 0.003 ether;

  event SetStakeTogetherFee(uint256 fee);
  event SetPoolFee(uint256 fee);
  event SetOperatorFee(uint256 fee);
  event SetValidatorFee(uint256 fee);
  event SetAddPoolFee(uint256 fee);
  event SetEntryFee(uint256 fee);

  // Todo: Needs TimeLock
  function setStakeTogetherFee(uint256 _fee) external onlyRole(ADMIN_ROLE) {
    stakeTogetherFee = _fee;
    emit SetStakeTogetherFee(_fee);
  }

  // Todo: Needs TimeLock
  function setPoolFee(uint256 _fee) external onlyRole(ADMIN_ROLE) {
    poolFee = _fee;
    emit SetPoolFee(_fee);
  }

  // Todo: Needs TimeLock
  function setOperatorFee(uint256 _fee) external onlyRole(ADMIN_ROLE) {
    operatorFee = _fee;
    emit SetOperatorFee(_fee);
  }

  // Todo: Needs TimeLock
  function setValidatorFee(uint256 _fee) external onlyRole(ADMIN_ROLE) {
    validatorFee = _fee;
    emit SetValidatorFee(_fee);
  }

  // Todo: Needs TimeLock
  function setAddPoolFee(uint256 _fee) external onlyRole(ADMIN_ROLE) {
    addPoolFee = _fee;
    emit SetAddPoolFee(_fee);
  }

  // Todo: Needs TimeLock
  function setEntryFee(uint256 _fee) external onlyRole(ADMIN_ROLE) {
    addPoolFee = _fee;
    emit SetEntryFee(_fee);
  }

  /*****************
   ** REWARDS **
   *****************/

  struct Reward {
    address recipient;
    uint256 shares;
    uint256 amount;
  }

  enum RewardType {
    StakeTogether,
    Operator,
    Pool
  }

  uint256 public beaconBalance = 0;

  event MintRewards(uint256 epoch, address indexed to, uint256 sharesAmount, RewardType rewardType);
  event MintPenalty(uint256 epoch, uint256 amount);

  function mintRewards(
    uint256 _epoch,
    address _rewardAddress,
    uint256 _sharesAmount
  ) external payable nonReentrant onlyDistributor {
    _mintShares(_rewardAddress, _sharesAmount);
    _mintPoolShares(_rewardAddress, _rewardAddress, _sharesAmount);

    if (_rewardAddress == stakeTogetherFeeAddress) {
      emit MintRewards(_epoch, _rewardAddress, _sharesAmount, RewardType.StakeTogether);
    } else if (_rewardAddress == operatorFeeAddress) {
      emit MintRewards(_epoch, _rewardAddress, _sharesAmount, RewardType.Operator);
    } else {
      emit MintRewards(_epoch, _rewardAddress, _sharesAmount, RewardType.Pool);
    }
  }

  function mintPenalty(uint256 _blockNumber, uint256 _lossAmount) external nonReentrant onlyDistributor {
    beaconBalance -= _lossAmount;
    require(totalPooledEther() - _lossAmount > 0, 'NEGATIVE_TOTAL_POOLED_ETHER_BALANCE');
    emit MintPenalty(_blockNumber, _lossAmount);
  }
}
