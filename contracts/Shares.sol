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
import './Router.sol';
import './Fees.sol';
import './Airdrop.sol';
import './Withdrawals.sol';
import './WithdrawalsLoan.sol';
import './Validators.sol';
import './RewardsLoan.sol';

/// @custom:security-contact security@staketogether.app
abstract contract Shares is AccessControl, Pausable, ReentrancyGuard, ERC20, ERC20Permit {
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant POOL_MANAGER_ROLE = keccak256('POOL_MANAGER_ROLE');

  Router public routerContract;
  Fees public feesContract;
  Airdrop public airdropContract;
  Withdrawals public withdrawalsContract;
  WithdrawalsLoan public withdrawalsLoanContract;
  Validators public validatorsContract;
  RewardsLoan public rewardsLoanContract;

  uint256 public beaconBalance = 0;
  uint256 public withdrawalsLoanBalance = 0;

  struct Lock {
    uint256 sharesAmount;
    uint256 debitSharesAmount;
    uint256 unlockBlock;
    address pool;
  }

  event SetBeaconBalance(uint256 amount);
  event SetWithdrawalsLoanBalance(uint256 amount);
  event MintShares(address indexed to, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  event SetMaxActiveLocks(uint256 amount);
  event LockSharesLoan(
    address indexed account,
    uint256 lockedSharesAmount,
    uint256 debitSharesAmount,
    uint256 unlockBlock,
    address pool
  );
  event SharesUnlocked(address indexed account, uint256 amount);
  event MintPoolShares(address indexed to, address indexed pool, uint256 sharesAmount);
  event BurnPoolShares(address indexed from, address indexed pool, uint256 sharesAmount);
  event TransferPoolShares(
    address indexed from,
    address indexed to,
    address indexed pool,
    uint256 sharesAmount
  );
  event TransferDelegationShares(
    address indexed from,
    address indexed to,
    address indexed pool,
    uint256 sharesAmount
  );
  event MintFeeShares(address indexed to, address indexed pool, uint256 sharesAmount);
  event MintPenalty(uint256 amount);
  event ClaimRewards(address indexed account, uint256 sharesAmount);
  event MintRewardsAccounts(address indexed sender, uint amount);
  event MintRewardsAccountsFallback(address indexed sender, uint amount);

  modifier onlyRouter() {
    require(msg.sender == address(routerContract), 'ONLY_DISTRIBUTOR_CONTRACT');
    _;
  }

  modifier onlyAirdrop() {
    require(msg.sender == address(airdropContract), 'ONLY_AIRDROP_CONTRACT');
    _;
  }

  modifier onlyWithdrawalsLoan() {
    require(msg.sender == address(withdrawalsLoanContract), 'ONLY_LOANS_CONTRACT');
    _;
  }

  modifier onlyValidators() {
    require(msg.sender == address(validatorsContract), 'ONLY_VALIDATORS_CONTRACT');
    _;
  }

  modifier onlyValidatorOracle() {
    require(validatorsContract.isValidatorOracle(msg.sender), 'ONLY_VALIDATOR_ORACLE');
    _;
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function setBeaconBalance(uint256 _amount) external onlyValidators {
    beaconBalance = _amount;
    emit SetBeaconBalance(_amount);
  }

  function setWithdrawalsLoanBalance(uint256 _amount) external onlyWithdrawalsLoan {
    withdrawalsLoanBalance = _amount;
    emit SetWithdrawalsLoanBalance(_amount);
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

  // @audit-issue | FM | review netSharesOf lock mechanism
  function balanceOf(address _account) public view override returns (uint256) {
    return pooledEthByShares(netSharesOf(_account));
  }

  function sharesOf(address _account) public view returns (uint256) {
    return shares[_account];
  }

  function netSharesOf(address _account) public view returns (uint256) {
    return shares[_account] - lockedShares[_account];
  }

  function sharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
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

  mapping(address => Lock[]) public locked;
  mapping(address => uint256) public lockedShares;
  uint256 public totalLockedShares;
  mapping(address => uint256) private debitShares;
  uint256 public totalDebitShares;
  uint256 public maxActiveLocks = 10;

  function setMaxActiveLocks(uint256 _amount) external onlyRole(ADMIN_ROLE) {
    maxActiveLocks = _amount;
    emit SetMaxActiveLocks(_amount);
  }

  function lockedSharesOf(address _account) public view returns (uint256) {
    return lockedShares[_account];
  }

  function debitSharesOf(address _account) public view returns (uint256) {
    return debitShares[_account];
  }

  function lockShares(
    address _account,
    uint256 _lockedSharesAmount,
    uint256 _debitSharesAmount,
    uint256 _unlockBlock,
    address _pool
  ) external onlyWithdrawalsLoan nonReentrant whenNotPaused {
    // Todo: wrong -> rewards loan
    require(locked[_account].length < maxActiveLocks, 'TOO_MANY_LOCKS');
    require(_lockedSharesAmount <= shares[_account], 'INSUFFICIENT_SHARES');
    // require(_debitSharesAmount <= _lockedSharesAmount[_account], 'INSUFFICIENT_LOCKED_SHARES');
    require(_unlockBlock > 0, 'INVALID_BLOCK_COUNT');
    shares[_account] -= _lockedSharesAmount;
    lockedShares[_account] += _lockedSharesAmount;
    debitShares[_account] += _debitSharesAmount;
    totalLockedShares += _lockedSharesAmount;
    totalDebitShares += _debitSharesAmount;
    Lock memory newLock = Lock(_lockedSharesAmount, _debitSharesAmount, _unlockBlock, _pool);
    locked[_account].push(newLock);
    // emit LockSharesLoan(_account, _lockedSharesAmount, newLock.unlockBlock);
  }

  /*****************
   ** POOLS SHARES **
   *****************/

  mapping(address => uint256) private poolShares;
  uint256 public totalPoolShares = 0;
  mapping(address => mapping(address => uint256)) private delegationsShares;
  mapping(address => address[]) private delegates;
  mapping(address => mapping(address => bool)) private isDelegate;
  uint256 public maxDelegations = 64; // Todo: verify merkle tree

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

    poolShares[_pool] += _sharesAmount;
    delegationsShares[_to][_pool] += _sharesAmount;
    totalPoolShares += _sharesAmount;

    if (!isDelegate[_to][_pool]) {
      delegates[_to].push(_pool);
      isDelegate[_to][_pool] = true;
    }

    emit MintPoolShares(_to, _pool, _sharesAmount);
  }

  function _burnPoolShares(address _to, address _pool, uint256 _sharesAmount) internal whenNotPaused {
    require(_to != address(0), 'BURN_to_ZERO_ADDR');
    require(isPool(_pool), 'ONLY_CAN_BURN_to_POOL');
    require(delegationsShares[_to][_pool] >= _sharesAmount, 'BURN_INVALID_AMOUNT');
    require(_sharesAmount > 0, 'BURN_INVALID_AMOUNT');

    poolShares[_pool] -= _sharesAmount;
    delegationsShares[_to][_pool] -= _sharesAmount;
    totalPoolShares -= _sharesAmount;

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
    require(_toPool != address(this), 'ST_ADDR');
    require(isPool(_toPool), 'ONLY_CAN_TRANSFER_TO_POOL');

    require(_sharesAmount <= delegationsShares[_account][_fromPool], 'BALANCE_EXCEEDED');

    poolShares[_fromPool] -= _sharesAmount;
    delegationsShares[_account][_fromPool] -= _sharesAmount;

    poolShares[_toPool] += _sharesAmount;
    delegationsShares[_account][_toPool] += _sharesAmount;

    emit TransferPoolShares(_account, _fromPool, _toPool, _sharesAmount);
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

      emit TransferDelegationShares(_from, _to, pool, delegationSharesToTransfer);
    }
  }

  /*****************
   ** REWARDS **
   *****************/

  function _mintFeeShares(address _address, address _pool, uint256 _sharesAmount) public payable {
    require(
      msg.sender == address(routerContract) || msg.sender == address(withdrawalsLoanContract),
      'ONLY_ROUTER_OR_WITHDRAWALS_LOANS_CONTRACT'
    );
    _mintShares(_address, _sharesAmount);
    _mintPoolShares(_address, _pool, _sharesAmount);
    emit MintFeeShares(_address, _pool, _sharesAmount);
  }

  function _mintPenalty(uint256 _lossAmount) external onlyRouter {
    beaconBalance -= _lossAmount;
    require(totalPooledEther() - _lossAmount > 0, 'NEGATIVE_TOTAL_POOLED_ETHER_BALANCE');
    emit MintPenalty(_lossAmount);
  }

  function _claimRewards(
    address _account,
    uint256 _sharesAmount
  ) external nonReentrant whenNotPaused onlyAirdrop {
    _transferShares(address(airdropContract), _account, _sharesAmount);
    _transferPoolShares(address(airdropContract), address(airdropContract), _account, _sharesAmount);
    emit ClaimRewards(_account, _sharesAmount);
  }

  function isPool(address _pool) public view virtual returns (bool);
}
