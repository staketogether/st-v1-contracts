// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import './StakeTogether.sol';
import './Router.sol';

/// @custom:security-contact security@staketogether.app
contract Fees is AccessControl, Pausable, ReentrancyGuard {
  StakeTogether public stakeTogether;
  Router public routerContract;
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  enum FeeType {
    Swap,
    StakeEntry,
    StakeRewards,
    StakePool,
    StakeValidator,
    LiquidityProvideEntry,
    LiquidityProvide
  }

  enum FeeMathType {
    FIXED,
    PERCENTAGE
  }

  enum FeeRoles {
    StakeAccounts,
    LockAccounts,
    Pools,
    Operators,
    Oracles,
    StakeTogether,
    LiquidityProviders,
    Sender
  }

  struct Fee {
    uint256 value;
    FeeMathType mathType;
    mapping(FeeRoles => uint256) allocations;
  }

  mapping(FeeRoles => address payable) public roleAddresses;
  mapping(FeeType => Fee) public fees;
  uint256 public apr;
  uint256 public blocksPerYear = 2102400;
  uint256 public riskMargin; // 80%
  uint256 public minAnticipationDays = 30;
  uint256 public maxAnticipationDays = 365;
  uint256 public maxAnticipationFeeReduction; // 50%

  event SetTotalFee(FeeType indexed feeType, uint256 total);
  event SetFeeAllocation(FeeType indexed feeType, FeeRoles indexed role, uint256 allocation);
  event SetRouter(address routerContract);
  event ReceiveEther(address indexed sender, uint256 amount);
  event FallbackEther(address indexed sender, uint256 amount);
  event SetStakeTogether(address stakeTogether);
  event SetFeeAddress(FeeRoles indexed role, address indexed account);
  event SetApr(uint256 apr);

  event SetRiskMargin(uint256 riskMargin);
  event SetBlocksPerYear(uint256 blocksPerYear);
  event SetMinAnticipationDays(uint256 minAnticipationDays);
  event SetMaxAnticipationDays(uint256 maxAnticipationDays);

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

  modifier onlyRouter() {
    require(msg.sender == address(routerContract), 'ONLY_ROUTER_CONTRACT');
    _;
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function setRouter(address _routerContract) external onlyRole(ADMIN_ROLE) {
    require(_routerContract != address(0), 'ROUTER_CONTRACT_ALREADY_SET');
    routerContract = Router(payable(_routerContract));
    emit SetRouter(_routerContract);
  }

  function getFeesRoles() public pure returns (FeeRoles[8] memory) {
    FeeRoles[8] memory roles = [
      FeeRoles.StakeAccounts,
      FeeRoles.LockAccounts,
      FeeRoles.Pools,
      FeeRoles.Operators,
      FeeRoles.Oracles,
      FeeRoles.StakeTogether,
      FeeRoles.LiquidityProviders,
      FeeRoles.Sender
    ];
    return roles;
  }

  function setFeeAddress(FeeRoles _role, address payable _address) external onlyRole(ADMIN_ROLE) {
    roleAddresses[_role] = _address;
    emit SetFeeAddress(_role, _address);
  }

  function getFeeAddress(FeeRoles _role) public view returns (address) {
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
    FeeRoles _role,
    uint256 _allocation
  ) external onlyRole(ADMIN_ROLE) {
    uint256 currentTotal = fees[_feeType].value;
    require(_allocation <= currentTotal, 'FEE_ALLOCATION_EXCEEDS_TOTAL');
    fees[_feeType].allocations[_role] = _allocation;
    emit SetFeeAllocation(_feeType, _role, _allocation);
  }

  function getFeeAllocation(FeeType _feeType, FeeRoles _role) public view returns (uint256) {
    return fees[_feeType].allocations[_role];
  }

  function setApr(uint256 _apr) external onlyRouter {
    apr = _apr;
    emit SetApr(_apr);
  }

  function setRiskMargin(uint256 _riskMargin) external onlyRole(ADMIN_ROLE) {
    riskMargin = _riskMargin;
    emit SetRiskMargin(_riskMargin);
  }

  function setBlocksPerYear(uint256 _blocksPerYear) external onlyRole(ADMIN_ROLE) {
    blocksPerYear = _blocksPerYear;
    emit SetBlocksPerYear(_blocksPerYear);
  }

  function setMinAnticipationDays(uint256 _minAnticipationDays) external onlyRole(ADMIN_ROLE) {
    minAnticipationDays = _minAnticipationDays;
    emit SetMinAnticipationDays(_minAnticipationDays);
  }

  function setMaxAnticipationDays(uint256 _maxAnticipationDays) external onlyRole(ADMIN_ROLE) {
    maxAnticipationDays = _maxAnticipationDays;
    emit SetMaxAnticipationDays(_maxAnticipationDays);
  }

  function _transferToStakeTogether() private nonReentrant {
    payable(stakeTogether).transfer(address(this).balance);
  }

  /*************
   * ESTIMATES *
   *************/

  function estimateFeePercentage(
    FeeType _feeType,
    uint256 _amount
  ) public view returns (uint256[8] memory shares, uint256[8] memory amounts) {
    (uint256 fee, FeeMathType mathType) = getFee(_feeType);
    require(mathType == FeeMathType.PERCENTAGE, 'FEE_NOT_PERCENTAGE');

    // Todo: Allocation always should sum 1 ether

    uint256 sharesAmount = Math.mulDiv(
      _amount,
      stakeTogether.totalShares(),
      stakeTogether.totalPooledEther() - _amount
    );

    uint256 feeShares = Math.mulDiv(sharesAmount, fee, 1 ether);

    FeeRoles[8] memory roles = getFeesRoles();

    for (uint256 i = 0; i < roles.length - 1; i++) {
      shares[i] = Math.mulDiv(feeShares, getFeeAllocation(_feeType, roles[i]), 1 ether);
    }

    uint256 senderShares = sharesAmount - feeShares;
    shares[7] = senderShares;

    for (uint256 i = 0; i < roles.length; i++) {
      amounts[i] = stakeTogether.pooledEthByShares(shares[i]);
    }

    return (shares, amounts);
  }

  function estimateFeeFixed(FeeType _feeType) public view returns (uint256[8] memory amounts) {
    (uint256 feeAmount, FeeMathType mathType) = getFee(_feeType);
    require(mathType == FeeMathType.FIXED, 'FEE_NOT_FIXED');

    FeeRoles[8] memory roles = getFeesRoles();

    for (uint256 i = 0; i < roles.length; i++) {
      amounts[i] = Math.mulDiv(feeAmount, getFeeAllocation(_feeType, roles[i]), 1 ether);
    }

    return amounts;
  }
}
