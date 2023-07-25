// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol';

import './Liquidity.sol';
import './Router.sol';
import './StakeTogether.sol';

import './interfaces/IFees.sol';

/// @custom:security-contact security@staketogether.app
contract Fees is
  Initializable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuardUpgradeable,
  IFees
{
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  StakeTogether public stakeTogether;
  Liquidity public liquidityContract;

  uint256 public maxFeeIncrease;

  mapping(FeeRoles => address payable) public roleAddresses;
  mapping(FeeType => Fee) public fees;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __Pausable_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  receive() external payable nonReentrant {
    emit ReceiveEther(msg.sender, msg.value);
    _transferToStakeTogether();
  }

  fallback() external payable nonReentrant {
    emit FallbackEther(msg.sender, msg.value);
    _transferToStakeTogether();
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0));
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function setLiquidityContract(address _liquidityContract) external onlyRole(ADMIN_ROLE) {
    require(_liquidityContract != address(0));
    liquidityContract = Liquidity(payable(_liquidityContract));
    emit SetLiquidityContract(_liquidityContract);
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

  function getFeeRolesAddresses() public view returns (address[8] memory) {
    FeeRoles[8] memory roles = getFeesRoles();
    address[8] memory addresses;
    for (uint256 i = 0; i < roles.length; i++) {
      addresses[i] = getFeeAddress(roles[i]);
    }
    return addresses;
  }

  function setFeeValue(
    FeeType _feeType,
    uint256 _fee,
    FeeMathType _mathType
  ) external onlyRole(ADMIN_ROLE) {
    if (_mathType == FeeMathType.PERCENTAGE) {
      require(_fee <= 1 ether);
    }
    fees[_feeType].value = _fee;
    fees[_feeType].mathType = _mathType;
    emit SetFeeValue(_feeType, _fee);
  }

  function getFee(FeeType _feeType) public view returns (uint256, FeeMathType) {
    return (fees[_feeType].value, fees[_feeType].mathType);
  }

  function setFeeAllocation(
    FeeType _feeType,
    FeeRoles _role,
    uint256 _allocation
  ) external onlyRole(ADMIN_ROLE) {
    uint256 feeAmount = fees[_feeType].value;
    uint256 currentTotal = 0;
    uint256 allocationAmount;

    for (uint i = 0; i < 7; i++) {
      currentTotal += fees[_feeType].allocations[FeeRoles(i)];
    }

    if (fees[_feeType].mathType == FeeMathType.PERCENTAGE) {
      allocationAmount = _allocation;
      require(allocationAmount + currentTotal <= 1 ether);
    } else {
      allocationAmount = MathUpgradeable.mulDiv(feeAmount, _allocation, 1 ether);
      require(allocationAmount + currentTotal <= feeAmount);
    }

    fees[_feeType].allocations[_role] = _allocation;
    emit SetFeeAllocation(_feeType, _role, _allocation);
  }

  function getFeeAllocation(FeeType _feeType, FeeRoles _role) public view returns (uint256) {
    return fees[_feeType].allocations[_role];
  }

  function setMaxFeeIncrease(uint256 _maxFeeIncrease) external onlyRole(ADMIN_ROLE) {
    maxFeeIncrease = _maxFeeIncrease;
    emit SetMaxFeeIncrease(_maxFeeIncrease);
  }

  function _transferToStakeTogether() private {
    payable(stakeTogether).transfer(address(this).balance);
  }

  /*************
   * ESTIMATES *
   *************/

  function estimateFeePercentage(
    FeeType _feeType,
    uint256 _amount
  ) public view returns (uint256[8] memory shares, uint256[8] memory amounts) {
    uint256 sharesAmount = stakeTogether.sharesByPooledEth(_amount);
    return distributeFeePercentage(_feeType, sharesAmount, 0);
  }

  function distributeFeePercentage(
    FeeType _feeType,
    uint256 _sharesAmount,
    uint256 _dynamicFee
  ) public view returns (uint256[8] memory shares, uint256[8] memory amounts) {
    require(_dynamicFee <= fees[_feeType].value + maxFeeIncrease);
    require(fees[_feeType].mathType == FeeMathType.PERCENTAGE);

    FeeRoles[8] memory roles = getFeesRoles();

    uint256[8] memory allocations;

    for (uint256 i = 0; i < allocations.length - 1; i++) {
      allocations[i] = getFeeAllocation(_feeType, roles[i]);
    }
    require(_checkAllocationSum(allocations));

    address[8] memory feeAddresses = getFeeRolesAddresses();

    for (uint256 i = 0; i < feeAddresses.length - 1; i++) {
      require(feeAddresses[i] != address(0));
    }

    uint256 feeShares = MathUpgradeable.mulDiv(_sharesAmount, _dynamicFee, 1 ether);

    for (uint256 i = 0; i < roles.length - 1; i++) {
      shares[i] = MathUpgradeable.mulDiv(feeShares, getFeeAllocation(_feeType, roles[i]), 1 ether);
    }

    uint256 senderShares = _sharesAmount - feeShares;
    shares[7] = senderShares;

    for (uint256 i = 0; i < roles.length; i++) {
      amounts[i] = stakeTogether.pooledEthByShares(shares[i]);
    }

    return (shares, amounts);
  }

  function estimateDynamicFeePercentage(
    FeeType _feeType,
    uint256 _amount
  ) public view returns (uint256[8] memory shares, uint256[8] memory amounts) {
    uint256 totalPooledEtherStake = stakeTogether.totalPooledEther();
    uint256 totalPooledEtherLiquidity = liquidityContract.totalPooledEther();
    uint256 baseFee = fees[FeeType.LiquidityProvide].value;
    uint256 dynamicFee;

    if (totalPooledEtherLiquidity == 0) {
      dynamicFee = MathUpgradeable.mulDiv(baseFee, 1 ether + maxFeeIncrease, 1 ether);
    } else {
      uint256 ratio = MathUpgradeable.mulDiv(totalPooledEtherStake, 1 ether, totalPooledEtherLiquidity);

      if (ratio >= 1 ether) {
        dynamicFee = MathUpgradeable.mulDiv(baseFee, 1 ether + maxFeeIncrease, 1 ether);
      } else {
        uint256 feeIncrease = MathUpgradeable.mulDiv(ratio, maxFeeIncrease, 1 ether);
        dynamicFee = MathUpgradeable.mulDiv(baseFee, 1 ether + feeIncrease, 1 ether);
      }
    }

    uint256 sharesAmount = stakeTogether.sharesByPooledEth(_amount);
    return distributeFeePercentage(_feeType, sharesAmount, dynamicFee);
  }

  function estimateFeeFixed(FeeType _feeType) public view returns (uint256[8] memory amounts) {
    (uint256 feeAmount, FeeMathType mathType) = getFee(_feeType);
    require(mathType == FeeMathType.FIXED);

    address[8] memory feeAddresses = getFeeRolesAddresses();
    for (uint256 i = 0; i < feeAddresses.length; i++) {
      require(feeAddresses[i] != address(0));
    }

    FeeRoles[8] memory roles = getFeesRoles();

    for (uint256 i = 0; i < roles.length; i++) {
      amounts[i] = MathUpgradeable.mulDiv(feeAmount, getFeeAllocation(_feeType, roles[i]), 1 ether);
    }

    return amounts;
  }

  function _checkAllocationSum(uint256[8] memory allocations) internal pure returns (bool) {
    uint256 sum = 0;
    for (uint256 i = 0; i < allocations.length; i++) {
      sum += allocations[i];
    }
    return sum == 1 ether;
  }
}
