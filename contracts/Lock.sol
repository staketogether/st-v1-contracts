// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';

/// @custom:security-contact security@staketogether.app
contract Lock is AccessControl, Pausable, ReentrancyGuard {
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  IERC20 public stakeTogether;
  mapping(address => uint256) public balances;
  mapping(address => uint256) public lockTime;

  mapping(address => uint256) public lockShares;
  uint256 public totalLockShares;

  uint256 public minDays;
  uint256 public maxDays;
  uint256 public incentiveFactor;

  event MintRewardsAccounts(address indexed sender, uint amount);
  event MintRewardsAccountsFallback(address indexed sender, uint amount);
  event LockToken(address indexed user, uint256 amount, uint256 lockDays);
  event UnlockToken(address indexed user, uint256 amount);
  event SetIncentiveFactor(uint256 amount);
  event SetMinDays(uint256 amount);
  event SetMaxDays(uint256 amount);

  constructor(address _stakeTogether, uint256 _minDays, uint256 _maxDays, uint256 _incentiveFactor) {
    stakeTogether = IERC20(_stakeTogether);
    minDays = _minDays;
    maxDays = _maxDays;
    incentiveFactor = _incentiveFactor;

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
  }

  function pause() external onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() external onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  receive() external payable nonReentrant {
    _transferToStakeTogether();
    emit MintRewardsAccounts(msg.sender, msg.value);
  }

  fallback() external payable nonReentrant {
    _transferToStakeTogether();
    emit MintRewardsAccountsFallback(msg.sender, msg.value);
  }

  function _transferToStakeTogether() private {
    payable(address(stakeTogether)).transfer(address(this).balance);
  }

  function lockToken(uint256 _amount, uint256 _days) external whenNotPaused nonReentrant {
    require(_days >= minDays && _days <= maxDays, 'INVALID_DAYS');
    uint256 newLockTime = block.timestamp + (_days * 1 days);
    require(newLockTime >= lockTime[msg.sender], 'CANNOT_REDUCE_LOCK_TIME');
    uint256 allowance = stakeTogether.allowance(msg.sender, address(this));
    require(allowance >= _amount, 'ALLOWANCE_NOT_ENOUGH');

    stakeTogether.transferFrom(msg.sender, address(this), _amount);
    balances[msg.sender] += _amount;
    lockTime[msg.sender] = newLockTime;

    uint256 shares = _amount * incentiveFactorOf(msg.sender);
    lockShares[msg.sender] += shares;
    totalLockShares += shares;

    emit LockToken(msg.sender, _amount, _days);
  }

  function unlockToken() external whenNotPaused nonReentrant {
    require(block.timestamp > lockTime[msg.sender], 'LOCK_TIME_NOT_PASSED');

    uint256 shares = balances[msg.sender] * incentiveFactorOf(msg.sender);

    require(lockShares[msg.sender] >= shares, 'LOCK_SHARES_NOT_ENOUGH');

    lockShares[msg.sender] -= shares;
    totalLockShares -= shares;

    uint256 amountToTransfer = balances[msg.sender];
    balances[msg.sender] = 0;
    stakeTogether.transfer(msg.sender, amountToTransfer);

    emit UnlockToken(msg.sender, amountToTransfer);
  }

  function incentiveFactorOf(address _account) public view returns (uint256) {
    if (block.timestamp < lockTime[_account]) {
      return 0;
    }

    uint256 timeLocked = (block.timestamp - lockTime[_account]) / 1 days;
    uint256 relativeLockTime = Math.max(minDays, Math.min(timeLocked, maxDays));
    return Math.mulDiv(relativeLockTime, incentiveFactor, maxDays);
  }

  function lockPercentage(address _account) public view returns (uint256) {
    if (totalLockShares == 0) {
      return 0;
    }
    return Math.mulDiv(lockShares[_account], 1 ether, totalLockShares);
  }

  function setIncentiveFactor(uint256 _incentiveFactor) external onlyRole(ADMIN_ROLE) {
    incentiveFactor = _incentiveFactor;
    emit SetIncentiveFactor(_incentiveFactor);
  }

  function setMinDays(uint256 _minDays) external onlyRole(ADMIN_ROLE) {
    require(_minDays <= maxDays, 'MIN_DAYS_GREATER_THAN_MAX_DAYS');
    require(_minDays > 0, 'INVALID_MIN_DAYS');
    minDays = _minDays;
    emit SetMinDays(_minDays);
  }

  function setMaxDays(uint256 _maxDays) external onlyRole(ADMIN_ROLE) {
    require(_maxDays >= minDays, 'MAX_DAYS_LOWER_THAN_MIN_DAYS');
    require(_maxDays > 0, 'INVALID_MAX_DAYS');
    maxDays = _maxDays;
    emit SetMaxDays(_maxDays);
  }
}
