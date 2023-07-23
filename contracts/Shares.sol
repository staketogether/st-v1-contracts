// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';

import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './Router.sol';
import './Fees.sol';
import './Airdrop.sol';
import './Withdrawals.sol';
import './Liquidity.sol';
import './Validators.sol';

/// @custom:security-contact security@staketogether.app
abstract contract Shares is
  Initializable,
  ERC20Upgradeable,
  ERC20BurnableUpgradeable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  ERC20PermitUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuard
{
  bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant POOL_MANAGER_ROLE = keccak256('POOL_MANAGER_ROLE');

  Router public routerContract;
  Fees public feesContract;
  Airdrop public airdropContract;
  Withdrawals public withdrawalsContract;
  Liquidity public liquidityContract;
  Validators public validatorsContract;

  uint256 public beaconBalance = 0;
  uint256 public liquidityBalance = 0;

  event SetBeaconBalance(uint256 amount);
  event SetLiquidityBalance(uint256 amount);
  event MintShares(address indexed to, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  event MintPoolShares(address indexed to, address indexed pool, uint256 sharesAmount);
  event BurnPoolShares(address indexed from, address indexed pool, uint256 sharesAmount);
  event TransferPoolShares(
    address indexed from,
    address indexed to,
    address indexed pool,
    uint256 sharesAmount
  );
  event TransferDelegationShares(address indexed from, address indexed to, uint256 sharesAmount);
  event TransferPoolDelegationShares(
    address indexed from,
    address indexed to,
    address indexed pool,
    uint256 sharesAmount
  );
  event MintRewards(address indexed to, address indexed pool, uint256 sharesAmount);
  event MintPenalty(uint256 amount);
  event ClaimRewards(address indexed account, uint256 sharesAmount);

  modifier onlyRouterContract() {
    require(msg.sender == address(routerContract), 'ONLY_ROUTER_CONTRACT');
    _;
  }

  modifier onlyAirdropContract() {
    require(msg.sender == address(airdropContract), 'ONLY_AIRDROP_CONTRACT');
    _;
  }

  modifier onlyLiquidityContract() {
    require(msg.sender == address(liquidityContract), 'ONLY_LIQUIDITY_CONTRACT');
    _;
  }

  modifier onlyValidatorsContract() {
    require(msg.sender == address(validatorsContract), 'ONLY_VALIDATORS_CONTRACT');
    _;
  }

  modifier onlyValidatorOracle() {
    require(validatorsContract.isValidatorOracle(msg.sender), 'ONLY_VALIDATOR_ORACLE');
    _;
  }

  modifier onlyRouterOrLiquidityContract() {
    require(
      msg.sender == address(routerContract) || msg.sender == address(liquidityContract),
      'ONLY_ROUTER_OR_LIQUIDITY_CONTRACT'
    );
    _;
  }

  function setBeaconBalance(uint256 _amount) external onlyValidatorsContract {
    beaconBalance = _amount;
    emit SetBeaconBalance(_amount);
  }

  function setLiquidityBalance(uint256 _amount) external onlyLiquidityContract {
    liquidityBalance = _amount;
    emit SetLiquidityBalance(_amount);
  }

  /************
   ** SHARES **
   ************/

  mapping(address => uint256) private shares;
  uint256 public totalShares = 0;
  mapping(address => mapping(address => uint256)) private allowances;

  function totalPooledEther() public view virtual returns (uint256);

  function totalSupply() public view override returns (uint256) {
    return totalPooledEther();
  }

  function balanceOf(address _account) public view override returns (uint256) {
    return pooledEthByShares(netSharesOf(_account));
  }

  function sharesOf(address _account) public view returns (uint256) {
    return shares[_account];
  }

  function sharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
    return Math.mulDiv(_ethAmount, totalShares, totalPooledEther());
  }

  function pooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
    return Math.mulDiv(_sharesAmount, totalPooledEther(), totalShares, Math.Rounding.Up);
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

  function _approve(address _account, address _spender, uint256 _amount) internal override {
    require(_account != address(0), 'APPROVE_FROM_ZERO_ADDR');
    require(_spender != address(0), 'APPROVE_TO_ZERO_ADDR');

    allowances[_account][_spender] = _amount;
    emit Approval(_account, _spender, _amount);
  }

  function _mintShares(address _to, uint256 _sharesAmount) internal {
    require(_to != address(0), 'MINT_TO_ZERO_ADDR');

    shares[_to] = shares[_to] + _sharesAmount;
    totalShares += _sharesAmount;

    emit MintShares(_to, _sharesAmount);
  }

  function _burnShares(address _account, uint256 _sharesAmount) internal {
    require(_account != address(0), 'BURN_FROM_ZERO_ADDR');
    require(_sharesAmount <= netSharesOf(_account), 'BALANCE_EXCEEDED');

    shares[_account] = shares[_account] - _sharesAmount;
    totalShares -= _sharesAmount;

    emit BurnShares(_account, _sharesAmount);
  }

  function _transfer(address _from, address _to, uint256 _amount) internal override {
    uint256 _sharesToTransfer = sharesByPooledEth(_amount);
    _transferShares(_from, _to, _sharesToTransfer);
    _transferDelegationShares(_from, _to, _sharesToTransfer);
    emit Transfer(_from, _to, _amount);
  }

  function _transferShares(address _from, address _to, uint256 _sharesAmount) internal {
    require(_from != address(0), 'TRANSFER_FROM_ZERO_ADDR');
    require(_to != address(0), 'TRANSFER_TO_ZERO_ADDR');
    require(_to != address(this), 'TRANSFER_TO_ST_CONTRACT');
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

  event LockShares(address indexed user, uint256 id, uint256 amount, uint256 lockDays);
  event UnlockShares(address indexed user, uint256 id, uint256 amount);
  event SetMinLockDays(uint256 minLockDays);
  event SetMaxLockDays(uint256 maxLockDays);

  struct LockedShares {
    uint256 id;
    uint256 amount;
    uint256 unlockTime;
    uint256 lockDays;
  }

  mapping(address => mapping(uint256 => LockedShares)) public lockedShares;
  mapping(address => uint256) public totalAccountLockedShares;
  mapping(address => uint256) public totalAccountLockedDays;
  uint256 public totalLockedShares = 0;

  uint256 private nextLockedSharesId = 1;
  uint256 public constant minLockDays = 30;
  uint256 public constant maxLockDays = 365;

  function lockShares(uint256 _sharesAmount, uint256 _lockDays) external nonReentrant whenNotPaused {
    require(_lockDays >= minLockDays && _lockDays <= maxLockDays, 'INVALID_LOCK_PERIOD');
    require(_sharesAmount <= shares[msg.sender], 'NOT_ENOUGH_SHARES');

    uint256 newId = nextLockedSharesId;
    nextLockedSharesId += 1;

    lockedShares[msg.sender][newId] = LockedShares({
      id: newId,
      amount: _sharesAmount,
      unlockTime: block.timestamp + (_lockDays * 1 days),
      lockDays: _lockDays
    });

    totalLockedShares += _sharesAmount;
    totalAccountLockedShares[msg.sender] += _sharesAmount;
    totalAccountLockedDays[msg.sender] += _sharesAmount * _lockDays;

    emit LockShares(msg.sender, newId, _sharesAmount, _lockDays);
  }

  function unlockShares(uint256 _id) external nonReentrant whenNotPaused {
    LockedShares storage lockedShare = lockedShares[msg.sender][_id];

    require(lockedShare.id != 0, 'LOCKED_SHARES_DOES_NOT_EXIST');
    require(lockedShare.unlockTime <= block.timestamp, 'SHARES_ARE_STILL_LOCKED');

    totalLockedShares -= lockedShare.amount;
    totalAccountLockedShares[msg.sender] -= lockedShare.amount;
    totalAccountLockedDays[msg.sender] -= lockedShare.amount * lockedShare.lockDays;

    delete lockedShares[msg.sender][_id];

    emit UnlockShares(msg.sender, _id, lockedShare.amount);
  }

  function incentiveFactorOf(address _account) public view returns (uint256, uint256) {
    if (totalAccountLockedShares[_account] > 0) {
      uint256 factor = Math.mulDiv(
        totalAccountLockedDays[_account],
        totalAccountLockedShares[_account],
        shares[_account]
      );
      uint256 percentage = Math.mulDiv(totalAccountLockedShares[_account], 1 ether, totalLockedShares);
      return (factor, percentage);
    } else {
      return (0, 0);
    }
  }

  function setMinLockDays(uint256 _minLockDays) external onlyRole(ADMIN_ROLE) {
    require(_minLockDays > 0, 'ZERO_MIN_LOCK_DAYS');
    require(_minLockDays <= maxLockDays, 'MIN_LOCK_DAYS_EXCEEDS_MAX_LOCK_DAYS');
    emit SetMinLockDays(_minLockDays);
  }

  function setMaxLockDays(uint256 _maxLockDays) external onlyRole(ADMIN_ROLE) {
    require(_maxLockDays > 0, 'ZERO_MAX_LOCK_DAYS');
    require(_maxLockDays >= minLockDays, 'MAX_LOCK_DAYS_BELOW_MIN_LOCK_DAYS');
    emit SetMaxLockDays(_maxLockDays);
  }

  function lockedSharesOf(address _account) public view returns (uint256) {
    return totalAccountLockedShares[_account];
  }

  function netSharesOf(address _account) public view returns (uint256) {
    return sharesOf(_account) - totalAccountLockedShares[_account];
  }

  /*****************
   ** POOLS SHARES **
   *****************/

  mapping(address => uint256) private poolShares;
  uint256 public totalPoolShares = 0;
  mapping(address => mapping(address => uint256)) private delegationsShares;
  mapping(address => address[]) private delegates;
  mapping(address => mapping(address => bool)) private isDelegate;
  uint256 public maxDelegations = 64;

  function isPool(address _pool) public view virtual returns (bool);

  function poolSharesOf(address _account) public view returns (uint256) {
    return poolShares[_account];
  }

  function delegationSharesOf(address _account, address _pool) public view returns (uint256) {
    return delegationsShares[_account][_pool];
  }

  function transferPoolShares(
    address _fromPool,
    address _toPool,
    uint256 _sharesAmount
  ) external nonReentrant whenNotPaused {
    _transferPoolShares(msg.sender, _fromPool, _toPool, _sharesAmount);
  }

  function _mintPoolShares(address _to, address _pool, uint256 _sharesAmount) internal whenNotPaused {
    require(_to != address(0), 'MINT_TO_ZERO_ADDR');
    require(isPool(_pool), 'ONLY_CAN_DELEGATE_TO_POOL');
    require(delegates[_to].length < maxDelegations, 'MAX_DELEGATIONS_REACHED');
    require(_sharesAmount > 0, 'MINT_INVALID_AMOUNT');

    _incrementPoolShares(_to, _pool, _sharesAmount);
    _addDelegate(_to, _pool);

    emit MintPoolShares(_to, _pool, _sharesAmount);
  }

  function _burnPoolShares(address _to, address _pool, uint256 _sharesAmount) internal whenNotPaused {
    require(_to != address(0), 'BURN_to_ZERO_ADDR');
    require(isPool(_pool), 'ONLY_CAN_BURN_to_POOL');
    require(delegationsShares[_to][_pool] >= _sharesAmount, 'BURN_INVALID_AMOUNT');
    require(_sharesAmount > 0, 'BURN_INVALID_AMOUNT');

    _decrementPoolShares(_to, _pool, _sharesAmount);

    if (delegationsShares[_to][_pool] == 0) {
      _removeDelegate(_to, _pool);
    }

    emit BurnPoolShares(_to, _pool, _sharesAmount);
  }

  function _transferPoolShares(
    address _account,
    address _fromPool,
    address _toPool,
    uint256 _sharesAmount
  ) internal {
    require(_account != address(0), 'ZERO_ADDR');
    require(_fromPool != address(0), 'ZERO_ADDR');
    require(_toPool != address(0), 'ZERO_ADDR');
    require(isPool(_toPool), 'ONLY_CAN_TRANSFER_TO_POOL');
    require(_sharesAmount <= delegationsShares[_account][_fromPool], 'BALANCE_EXCEEDED');

    _decrementPoolShares(_account, _fromPool, _sharesAmount);
    _removeDelegate(_account, _fromPool);

    _incrementPoolShares(_account, _toPool, _sharesAmount);
    _addDelegate(_account, _toPool);

    emit TransferPoolShares(_account, _fromPool, _toPool, _sharesAmount);
  }

  function _transferDelegationShares(
    address _from,
    address _to,
    uint256 _sharesToTransfer
  ) internal whenNotPaused {
    require(_from != address(0), 'TRANSFER_FROM_ZERO_ADDR');
    require(_to != address(0), 'TRANSFER_TO_ZERO_ADDR');
    require(_sharesToTransfer <= netSharesOf(_from), 'TRANSFER_EXCEEDS_BALANCE');

    for (uint256 i = 0; i < delegates[_from].length; i++) {
      address pool = delegates[_from][i];
      uint256 delegationSharesToTransfer = Math.mulDiv(
        delegationSharesOf(_from, pool),
        _sharesToTransfer,
        netSharesOf(_from)
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

      emit TransferDelegationShares(_from, _to, _sharesToTransfer);
    }
  }

  function _transferPoolDelegationShares(
    address _from,
    address _to,
    address _pool,
    uint256 _sharesAmount
  ) internal whenNotPaused {
    require(_from != address(0), 'TRANSFER_FROM_ZERO_ADDR');
    require(_to != address(0), 'TRANSFER_TO_ZERO_ADDR');
    require(isPool(_pool), 'INVALID_POOL');
    require(_sharesAmount > 0, 'INVALID_AMOUNT');
    require(_sharesAmount <= delegationsShares[_from][_pool], 'BALANCE_EXCEEDED');

    _decrementPoolShares(_from, _pool, _sharesAmount);
    _removeDelegate(_from, _pool);

    _incrementPoolShares(_to, _pool, _sharesAmount);
    _addDelegate(_to, _pool);

    emit TransferPoolDelegationShares(_from, _to, _pool, _sharesAmount);
  }

  function _incrementPoolShares(address _to, address _pool, uint256 _sharesAmount) internal {
    poolShares[_pool] += _sharesAmount;
    delegationsShares[_to][_pool] += _sharesAmount;
    totalPoolShares += _sharesAmount;
  }

  function _decrementPoolShares(address _to, address _pool, uint256 _sharesAmount) internal {
    poolShares[_pool] -= _sharesAmount;
    delegationsShares[_to][_pool] -= _sharesAmount;
    totalPoolShares -= _sharesAmount;
  }

  function _addDelegate(address _to, address _pool) internal {
    if (!isDelegate[_to][_pool]) {
      require(delegates[_to].length < maxDelegations, 'MAX_DELEGATIONS_REACHED');
      delegates[_to].push(_pool);
      isDelegate[_to][_pool] = true;
    }
  }

  function _removeDelegate(address _to, address _pool) internal {
    if (delegationsShares[_to][_pool] == 0) {
      isDelegate[_to][_pool] = false;

      for (uint i = 0; i < delegates[_to].length; i++) {
        if (delegates[_to][i] == _pool) {
          delegates[_to][i] = delegates[_to][delegates[_to].length - 1];
          delegates[_to].pop();
          break;
        }
      }
    }
  }

  /*****************
   ** REWARDS **
   *****************/

  function _mintRewards(address _address, address _pool, uint256 _sharesAmount) internal {
    _mintShares(_address, _sharesAmount);
    _mintPoolShares(_address, _pool, _sharesAmount);
    emit MintRewards(_address, _pool, _sharesAmount);
  }

  function mintRewards(
    address _address,
    address _pool,
    uint256 _sharesAmount
  ) public payable onlyRouterOrLiquidityContract {
    _mintRewards(_address, _pool, _sharesAmount);
  }

  function claimRewards(
    address _account,
    uint256 _sharesAmount,
    bool _isPool
  ) external nonReentrant whenNotPaused onlyAirdropContract {
    _transferShares(address(airdropContract), _account, _sharesAmount);
    _transferPoolDelegationShares(address(airdropContract), _account, address(this), _sharesAmount);

    if (_isPool) {
      _transferPoolShares(_account, address(this), _account, _sharesAmount);
    }

    emit ClaimRewards(_account, _sharesAmount);
  }

  function mintPenalty(uint256 _lossAmount) external onlyRouterContract {
    beaconBalance -= _lossAmount;
    require(totalPooledEther() - _lossAmount > 0, 'NEGATIVE_TOTAL_POOLED_ETHER_BALANCE');
    emit MintPenalty(_lossAmount);
  }
}
