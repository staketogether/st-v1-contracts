// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import './StakeTogether.sol';

/// @custom:security-contact security@staketogether.app
contract Fees is AccessControl, Pausable, ReentrancyGuard {
  StakeTogether public stakeTogether;
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  enum FeeType {
    EntryStake,
    EntryLoan,
    Rewards,
    Borrow,
    Anticipate,
    RefundAnticipate,
    Validator,
    AddPool
  }

  enum FeeMathType {
    FIXED,
    PERCENTAGE
  }

  enum Roles {
    Pools,
    Operators,
    StakeTogether,
    Accounts,
    Lenders,
    Sender
  }

  struct Fee {
    uint256 value;
    FeeMathType mathType;
    mapping(Roles => uint256) allocations;
  }

  mapping(Roles => address payable) public roleAddresses;
  mapping(FeeType => Fee) public fees;

  event SetTotalFee(FeeType indexed feeType, uint256 total);
  event SetFeeAllocation(FeeType indexed feeType, Roles indexed role, uint256 allocation);
  event ReceiveEther(address indexed sender, uint256 amount);
  event FallbackEther(address indexed sender, uint256 amount);
  event SetStakeTogether(address stakeTogether);
  event SetFeeAddress(Roles indexed role, address indexed account);

  constructor() {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
  }

  receive() external payable whenNotPaused {
    emit ReceiveEther(msg.sender, msg.value);
    _transferToStakeTogether();
  }

  fallback() external payable whenNotPaused {
    emit FallbackEther(msg.sender, msg.value);
    _transferToStakeTogether();
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function setFeeAddress(Roles _role, address payable _address) external onlyRole(ADMIN_ROLE) {
    roleAddresses[_role] = _address;
    emit SetFeeAddress(_role, _address);
  }

  function getFeeAddress(Roles _role) public view returns (address) {
    return roleAddresses[_role];
  }

  function setFee(FeeType _feeType, uint256 _fee, FeeMathType _mathType) external onlyRole(ADMIN_ROLE) {
    if (_mathType == FeeMathType.PERCENTAGE) {
      require(_fee <= 1 ether, 'TOTAL_FEE_EXCEEDS_100_PERCENT');
    }
    fees[_feeType].value = _fee;
    fees[_feeType].mathType = _mathType;
    emit SetTotalFee(_feeType, _fee);
  }

  function getFee(FeeType _feeType) public view returns (uint256, FeeMathType) {
    return (fees[_feeType].value, fees[_feeType].mathType);
  }

  function setFeeAllocation(
    FeeType _feeType,
    Roles _role,
    uint256 _allocation
  ) external onlyRole(ADMIN_ROLE) {
    uint256 currentTotal = fees[_feeType].value;
    require(_allocation <= currentTotal, 'FEE_ALLOCATION_EXCEEDS_TOTAL');
    fees[_feeType].allocations[_role] = _allocation;
    emit SetFeeAllocation(_feeType, _role, _allocation);
  }

  function getFeeAllocation(FeeType _feeType, Roles _role) public view returns (uint256) {
    return fees[_feeType].allocations[_role];
  }

  function estimateFeePercentage(
    FeeType _feeType,
    uint256 _amount
  ) external view returns (uint256[6] memory shares, uint256[6] memory amounts) {
    (uint256 fee, FeeMathType mathType) = getFee(_feeType);
    require(mathType == FeeMathType.PERCENTAGE, 'FEE_NOT_PERCENTAGE');

    uint256 sharesAmount = Math.mulDiv(
      _amount,
      stakeTogether.totalShares(),
      stakeTogether.totalPooledEther() - _amount
    );

    uint256 feeShares = Math.mulDiv(sharesAmount, fee, 1 ether);

    Roles[6] memory roles = [
      Roles.Pools,
      Roles.Operators,
      Roles.StakeTogether,
      Roles.Accounts,
      Roles.Lenders,
      Roles.Sender
    ];

    for (uint256 i = 0; i < roles.length - 1; i++) {
      shares[i] = Math.mulDiv(feeShares, getFeeAllocation(_feeType, roles[i]), 1 ether);
      amounts[i] = stakeTogether.pooledEthByShares(shares[i]);
    }

    uint256 senderShares = sharesAmount - feeShares;
    shares[5] = senderShares;
    amounts[5] = stakeTogether.pooledEthByShares(senderShares);

    return (shares, amounts);
  }

  function estimateFeeFixed(FeeType _feeType) external view returns (uint256[6] memory amounts) {
    (uint256 feeAmount, FeeMathType mathType) = getFee(_feeType);
    require(mathType == FeeMathType.FIXED, 'FEE_NOT_FIXED');

    Roles[6] memory roles = [
      Roles.Pools,
      Roles.Operators,
      Roles.StakeTogether,
      Roles.Accounts,
      Roles.Lenders,
      Roles.Sender
    ];

    for (uint256 i = 0; i < roles.length; i++) {
      amounts[i] = Math.mulDiv(feeAmount, getFeeAllocation(_feeType, roles[i]), 1 ether);
    }

    return amounts;
  }

  function _transferToStakeTogether() private nonReentrant {
    payable(stakeTogether).transfer(address(this).balance);
  }
}
