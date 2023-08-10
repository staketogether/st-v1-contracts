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

import './Fees.sol';
import './Withdrawals.sol';

import './interfaces/IFees.sol';
import './interfaces/IStakeTogether.sol';
import './interfaces/IDepositContract.sol';

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
  bytes32 public constant ORACLE_VALIDATOR_ROLE = keccak256('ORACLE_VALIDATOR_ROLE');
  bytes32 public constant ORACLE_VALIDATOR_MANAGER_ROLE = keccak256('ORACLE_VALIDATOR_MANAGER_ROLE');
  bytes32 public constant ORACLE_VALIDATOR_SENTINEL_ROLE = keccak256('ORACLE_VALIDATOR_SENTINEL_ROLE');

  uint256 public version;

  address public router;
  Fees public fees;
  Withdrawals public withdrawals;
  IDepositContract public deposit;

  bytes public withdrawalCredentials;
  uint256 public beaconBalance;
  Config public config;

  mapping(address => uint256) public shares;
  uint256 public totalShares;
  mapping(address => mapping(address => uint256)) private allowances;

  mapping(address => uint256) public poolShares;
  uint256 public totalPoolShares;
  mapping(address => mapping(address => uint256)) public delegationShares;
  mapping(address => address[]) public delegates;
  mapping(address => mapping(address => bool)) public isDelegate;

  uint256 public lastResetBlock;
  uint256 public totalDeposited;
  uint256 public totalWithdrawn;

  mapping(address => bool) internal pools;

  address[] public validatorOracles;
  uint256 public currentOracleIndex;

  mapping(bytes => bool) public validators;
  uint256 public totalValidators;
  uint256 public validatorSize;

  /************
   ** SHARES **
   ************/

  function totalPooledEther() public view virtual returns (uint256);

  function totalSupply() public view override returns (uint256) {
    return totalPooledEther();
  }

  function balanceOf(address _account) public view override returns (uint256) {
    return pooledEthByShares(shares[_account]);
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
    require(_sharesAmount <= shares[_account]);

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
    require(_sharesAmount <= shares[_from]);
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
   ** POOLS SHARES **
   *****************/

  function delegationSharesOf(address _account, address _pool) public view returns (uint256) {
    return delegationShares[_account][_pool];
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
    require(delegationShares[_to][_pool] >= _sharesAmount);
    require(_sharesAmount > 0);

    _decrementPoolShares(_to, _pool, _sharesAmount);

    if (delegationShares[_to][_pool] == 0) {
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
    require(_sharesAmount <= delegationSharesOf(_account, _fromPool));

    _decrementPoolShares(_account, _fromPool, _sharesAmount);
    _removeDelegate(_account, _fromPool);

    _incrementPoolShares(_account, _toPool, _sharesAmount);
    _addDelegate(_account, _toPool);

    emit TransferPoolShares(_account, _fromPool, _toPool, _sharesAmount);
  }

  function _transferDelegationShares(
    address _from,
    address _to,
    uint256 _sharesAmount
  ) internal whenNotPaused {
    require(_from != address(0));
    require(_to != address(0));
    require(_sharesAmount <= shares[_from]);

    for (uint256 i = 0; i < delegates[_from].length; i++) {
      address pool = delegates[_from][i];
      uint256 delegationSharesToTransfer = MathUpgradeable.mulDiv(
        delegationSharesOf(_from, pool),
        _sharesAmount,
        shares[_from]
      );

      delegationShares[_from][pool] -= delegationSharesToTransfer;

      if (!isDelegate[_to][pool]) {
        require(delegates[_to].length < config.maxDelegations);
        delegates[_to].push(pool);
        isDelegate[_to][pool] = true;
      }

      delegationShares[_to][pool] += delegationSharesToTransfer;

      if (delegationSharesOf(_from, pool) == 0) {
        isDelegate[_from][pool] = false;
      }

      emit TransferDelegationShares(_from, _to, _sharesAmount);
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
    require(_sharesAmount <= delegationSharesOf(_from, _pool));

    _decrementPoolShares(_from, _pool, _sharesAmount);
    _removeDelegate(_from, _pool);

    _incrementPoolShares(_to, _pool, _sharesAmount);
    _addDelegate(_to, _pool);

    emit TransferPoolDelegationShares(_from, _to, _pool, _sharesAmount);
  }

  function _incrementPoolShares(address _to, address _pool, uint256 _sharesAmount) internal {
    poolShares[_pool] += _sharesAmount;
    delegationShares[_to][_pool] += _sharesAmount;
    totalPoolShares += _sharesAmount;
  }

  function _decrementPoolShares(address _to, address _pool, uint256 _sharesAmount) internal {
    poolShares[_pool] -= _sharesAmount;
    delegationShares[_to][_pool] -= _sharesAmount;
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
    if (delegationSharesOf(_to, _pool) == 0) {
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

  function _mintRewards(
    address _address,
    address _pool,
    uint256 _amount,
    uint256 _sharesAmount,
    IFees.FeeType _feeType,
    IFees.FeeRole _feeRole
  ) internal {
    _mintShares(_address, _sharesAmount);
    _mintPoolShares(_address, _pool, _sharesAmount);
    emit MintRewards(_address, _pool, _amount, _sharesAmount, _feeType, _feeRole);
  }

  function mintRewards(
    address _address,
    address _pool,
    uint256 _sharesAmount,
    IFees.FeeType _feeType,
    IFees.FeeRole _feeRole
  ) public payable {
    require(msg.sender == router);
    _mintRewards(_address, _pool, msg.value, _sharesAmount, _feeType, _feeRole);
  }

  function claimRewards(address _account, uint256 _sharesAmount) external whenNotPaused {
    address airdropFee = fees.getFeeAddress(IFees.FeeRole.Airdrop);
    address stakeTogetherFee = fees.getFeeAddress(IFees.FeeRole.StakeTogether);

    require(msg.sender == airdropFee);

    _transferShares(airdropFee, _account, _sharesAmount);
    _transferPoolDelegationShares(airdropFee, _account, stakeTogetherFee, _sharesAmount);

    if (pools[_account]) {
      _transferPoolShares(_account, stakeTogetherFee, _account, _sharesAmount);
    }

    emit ClaimRewards(_account, _sharesAmount);
  }
}
