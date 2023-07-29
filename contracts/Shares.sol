// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol';

import './Airdrop.sol';
import './Fees.sol';
import './Liquidity.sol';
import './Router.sol';
import './Validators.sol';
import './Withdrawals.sol';

import './interfaces/IFees.sol';
import './interfaces/IStakeTogether.sol';

/// @custom:security-contact security@staketogether.app
abstract contract Shares is
  Initializable,
  ERC20Upgradeable,
  ERC20BurnableUpgradeable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  ERC20PermitUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuardUpgradeable,
  IStakeTogether
{
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant POOL_MANAGER_ROLE = keccak256('POOL_MANAGER_ROLE');

  Router public router;
  Fees public fees;
  Airdrop public airdrop;
  Withdrawals public withdrawals;
  Liquidity public liquidity;
  Validators public validators;

  bytes public withdrawalCredentials;
  uint256 public beaconBalance;
  uint256 public liquidityBalance;
  Config public config;

  mapping(address => uint256) public shares;
  uint256 public totalShares;
  mapping(address => mapping(address => uint256)) private allowances;

  uint256 public totalLockedShares;
  mapping(address => mapping(uint256 => LockedShares)) public locks;
  mapping(address => uint256) public lockedShares;
  uint256 internal lockId;

  mapping(address => uint256) private poolShares;
  uint256 public totalPoolShares;
  mapping(address => mapping(address => uint256)) private delegationsShares;
  mapping(address => address[]) private delegates;
  mapping(address => mapping(address => bool)) private isDelegate;

  mapping(address => bool) internal pools;

  uint256 public lastResetBlock;
  uint256 public totalDeposited;
  uint256 public totalWithdrawn;

  function setBeaconBalance(uint256 _amount) external {
    require(msg.sender == address(validators));
    beaconBalance = _amount;
    emit SetBeaconBalance(_amount);
  }

  function setLiquidityBalance(uint256 _amount) external {
    require(msg.sender == address(liquidity));
    liquidityBalance = _amount;
    emit SetLiquidityBalance(_amount);
  }

  /************
   ** SHARES **
   ************/

  function totalPooledEther() public view virtual returns (uint256);

  function totalSupply() public view override returns (uint256) {
    return totalPooledEther();
  }

  function balanceOf(address _account) public view override returns (uint256) {
    return pooledEthByShares(netShares(_account));
  }

  function sharesByPooledEth(uint256 _amount) public view returns (uint256) {
    return MathUpgradeable.mulDiv(_amount, totalShares, totalPooledEther());
  }

  function pooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
    return
      MathUpgradeable.mulDiv(_sharesAmount, totalPooledEther(), totalShares, MathUpgradeable.Rounding.Up);
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
    require(currentAllowance >= _subtractedValue);
    _approve(msg.sender, _spender, currentAllowance - _subtractedValue);
    return true;
  }

  function _approve(address _account, address _spender, uint256 _amount) internal override {
    require(_account != address(0));
    require(_spender != address(0));

    allowances[_account][_spender] = _amount;
    emit Approval(_account, _spender, _amount);
  }

  function _mintShares(address _to, uint256 _sharesAmount) internal whenNotPaused {
    require(_to != address(0));

    shares[_to] = shares[_to] + _sharesAmount;
    totalShares += _sharesAmount;

    emit MintShares(_to, _sharesAmount);
  }

  function _burnShares(address _account, uint256 _sharesAmount) internal whenNotPaused {
    require(_account != address(0));
    require(_sharesAmount <= netShares(_account));

    shares[_account] = shares[_account] - _sharesAmount;
    totalShares -= _sharesAmount;

    emit BurnShares(_account, _sharesAmount);
  }

  function _transfer(address _from, address _to, uint256 _amount) internal override whenNotPaused {
    uint256 _sharesToTransfer = sharesByPooledEth(_amount);
    _transferShares(_from, _to, _sharesToTransfer);
    _transferDelegationShares(_from, _to, _sharesToTransfer);
    emit Transfer(_from, _to, _amount);
  }

  function _transferShares(address _from, address _to, uint256 _sharesAmount) internal whenNotPaused {
    require(_from != address(0));
    require(_to != address(0));
    require(_sharesAmount <= netShares(_from));
    shares[_from] = shares[_from] - _sharesAmount;
    shares[_to] = shares[_to] + _sharesAmount;
    emit TransferShares(_from, _to, _sharesAmount);
  }

  function _spendAllowance(address _account, address _spender, uint256 _amount) internal override {
    uint256 currentAllowance = allowances[_account][_spender];
    if (currentAllowance != ~uint256(0)) {
      require(currentAllowance >= _amount);
      _approve(_account, _spender, currentAllowance - _amount);
    }
  }

  /*****************
   ** LOCK SHARES **
   *****************/

  // Todo: put a integration with future anticipation contract

  function lockShares(uint256 _sharesAmount, uint256 _lockDays) external nonReentrant whenNotPaused {
    require(config.feature.Lock);
    require(_lockDays >= config.minLockDays && _lockDays <= config.maxLockDays);
    require(_sharesAmount <= shares[msg.sender]);

    uint256 newId = lockId;
    lockId += 1;

    locks[msg.sender][newId] = LockedShares({
      id: newId,
      amount: _sharesAmount,
      unlockTime: block.timestamp + (_lockDays * 1 days),
      lockDays: _lockDays
    });

    totalLockedShares += _sharesAmount;
    lockedShares[msg.sender] += _sharesAmount;

    emit LockShares(msg.sender, newId, _sharesAmount, _lockDays);
  }

  function unlockShares(uint256 _id) external nonReentrant whenNotPaused {
    LockedShares storage lockedShare = locks[msg.sender][_id];

    require(lockedShare.id != 0);
    require(lockedShare.unlockTime <= block.timestamp);

    totalLockedShares -= lockedShare.amount;
    lockedShares[msg.sender] -= lockedShare.amount;

    delete locks[msg.sender][_id];

    emit UnlockShares(msg.sender, _id, lockedShare.amount);
  }

  function netShares(address _account) public view returns (uint256) {
    return shares[_account] - lockedShares[_account];
  }

  /*****************
   ** POOLS SHARES **
   *****************/

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
    require(_to != address(0));
    require(pools[_pool]);
    require(_sharesAmount > 0);
    require(delegates[_to].length < config.maxDelegations);

    _incrementPoolShares(_to, _pool, _sharesAmount);
    _addDelegate(_to, _pool);

    emit MintPoolShares(_to, _pool, _sharesAmount);
  }

  function _burnPoolShares(address _to, address _pool, uint256 _sharesAmount) internal whenNotPaused {
    require(_to != address(0));
    require(pools[_pool]);
    require(delegationsShares[_to][_pool] >= _sharesAmount);
    require(_sharesAmount > 0);

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
  ) internal whenNotPaused {
    require(_account != address(0));
    require(_fromPool != address(0));
    require(pools[_toPool]);
    require(_sharesAmount <= delegationsShares[_account][_fromPool]);

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
    require(_from != address(0));
    require(_to != address(0));
    require(_sharesToTransfer <= netShares(_from));

    for (uint256 i = 0; i < delegates[_from].length; i++) {
      address pool = delegates[_from][i];
      uint256 delegationSharesToTransfer = MathUpgradeable.mulDiv(
        delegationSharesOf(_from, pool),
        _sharesToTransfer,
        netShares(_from)
      );

      delegationsShares[_from][pool] -= delegationSharesToTransfer;

      if (!isDelegate[_to][pool]) {
        require(delegates[_to].length < config.maxDelegations);
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
    require(_from != address(0));
    require(_to != address(0));
    require(pools[_pool]);
    require(_sharesAmount > 0);
    require(_sharesAmount <= delegationsShares[_from][_pool]);

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
      require(delegates[_to].length < config.maxDelegations);
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

  /***********
   ** POOLS **
   ***********/

  function addPool(address _pool, bool _listed) public payable nonReentrant {
    require(_pool != address(0));
    require(!pools[_pool]);
    if (!hasRole(POOL_MANAGER_ROLE, msg.sender)) {
      require(config.feature.AddPool);
      (uint256[8] memory _shares, ) = fees.estimateFeeFixed(IFees.FeeType.StakePool);
      IFees.FeeRoles[8] memory roles = fees.getFeesRoles();
      for (uint i = 0; i < roles.length - 1; i++) {
        _mintRewards(
          fees.getFeeAddress(roles[i]),
          fees.getFeeAddress(IFees.FeeRoles.StakeTogether),
          _shares[i]
        );
      }
    }
    pools[_pool] = true;
    emit AddPool(_pool, _listed);
  }

  function removePool(address _pool) external onlyRole(POOL_MANAGER_ROLE) {
    require(pools[_pool]);
    pools[_pool] = false;
    emit RemovePool(_pool);
  }

  /*****************
   ** REWARDS **
   *****************/

  function _mintRewards(address _address, address _pool, uint256 _sharesAmount) internal {
    _mintShares(_address, _sharesAmount);
    _mintPoolShares(_address, _pool, _sharesAmount);
    emit MintRewards(_address, _pool, _sharesAmount);
  }

  function mintRewards(address _address, address _pool, uint256 _sharesAmount) public payable {
    require(msg.sender == address(router) || msg.sender == address(liquidity));
    _mintRewards(_address, _pool, _sharesAmount);
  }

  function claimRewards(address _account, uint256 _sharesAmount) external whenNotPaused {
    require(msg.sender == address(airdrop));
    address stakeTogetherFee = fees.getFeeAddress(IFees.FeeRoles.StakeTogether);

    _transferShares(address(airdrop), _account, _sharesAmount);
    _transferPoolDelegationShares(stakeTogetherFee, _account, stakeTogetherFee, _sharesAmount);

    if (pools[_account]) {
      _transferPoolShares(_account, stakeTogetherFee, _account, _sharesAmount);
    }

    emit ClaimRewards(_account, _sharesAmount);
  }
}
