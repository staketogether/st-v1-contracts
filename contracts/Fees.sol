// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol';

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
  uint256 public version;

  StakeTogether public stakeTogether;

  mapping(FeeRole => address payable) public roleAddresses;
  mapping(FeeType => Fee) public fees;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __Pausable_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);

    version = 1;
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

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0));
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function getFeesRoles() public pure returns (FeeRole[4] memory) {
    FeeRole[4] memory roles = [FeeRole.Airdrop, FeeRole.Operator, FeeRole.StakeTogether, FeeRole.Sender];
    return roles;
  }

  function setFeeAddress(FeeRole _role, address payable _address) external onlyRole(ADMIN_ROLE) {
    roleAddresses[_role] = _address;
    emit SetFeeAddress(_role, _address);
  }

  function getFeeAddress(FeeRole _role) public view returns (address) {
    return roleAddresses[_role];
  }

  function getFeeRolesAddresses() public view returns (address[4] memory) {
    FeeRole[4] memory roles = getFeesRoles();
    address[4] memory addresses;
    for (uint256 i = 0; i < roles.length; i++) {
      addresses[i] = getFeeAddress(roles[i]);
    }
    return addresses;
  }

  function setFee(
    FeeType _feeType,
    uint256 _value,
    FeeMath _mathType,
    uint256[] calldata _allocations
  ) external onlyRole(ADMIN_ROLE) {
    require(_allocations.length == 4);

    fees[_feeType].value = _value;
    fees[_feeType].mathType = _mathType;

    uint256 sum = 0;
    for (uint256 i = 0; i < _allocations.length; i++) {
      uint256 allocation = _allocations[i];
      fees[_feeType].allocations[FeeRole(i)] = allocation;
      sum += allocation;
    }

    require(sum == 1 ether);
    emit SetFee(_feeType, _value, _mathType, _allocations);
  }

  function getFee(FeeType _feeType) public view returns (FeeType, uint256, FeeMath, uint256[4] memory) {
    uint256[4] memory allocations;
    for (uint i = 0; i < allocations.length; i++) {
      allocations[i] = fees[_feeType].allocations[FeeRole(i)];
    }

    return (_feeType, fees[_feeType].value, fees[_feeType].mathType, allocations);
  }

  function getFees()
    public
    view
    returns (
      FeeType[] memory feeTypes,
      uint256[] memory feeValues,
      FeeMath[] memory feeMathTypes,
      uint256[4][] memory allocations
    )
  {
    uint256 feeCount = 4;

    feeTypes = new FeeType[](feeCount);
    feeValues = new uint256[](feeCount);
    feeMathTypes = new FeeMath[](feeCount);
    allocations = new uint256[4][](feeCount);

    for (uint256 i = 0; i < feeCount; i++) {
      (FeeType feeType, uint256 feeValue, FeeMath feeMathType, uint256[4] memory allocation) = getFee(
        FeeType(i)
      );

      feeTypes[i] = feeType;
      feeValues[i] = feeValue;
      feeMathTypes[i] = feeMathType;
      allocations[i] = allocation;
    }

    return (feeTypes, feeValues, feeMathTypes, allocations);
  }

  function _transferToStakeTogether() private {
    payable(stakeTogether).transfer(address(this).balance);
  }

  /*************
   * ESTIMATES *
   *************/

  function distributeFee(
    FeeType _feeType,
    uint256 _sharesAmount
  ) public view returns (uint256[4] memory shares, uint256[4] memory amounts) {
    FeeRole[4] memory roles = getFeesRoles();
    address[4] memory feeAddresses = getFeeRolesAddresses();
    uint256[4] memory allocations;

    for (uint256 i = 0; i < feeAddresses.length - 1; i++) {
      require(feeAddresses[i] != address(0), 'ZERO_ADDRESS');
    }

    for (uint256 i = 0; i < allocations.length; i++) {
      allocations[i] = fees[_feeType].allocations[roles[i]];
    }

    uint256 feeValue = fees[_feeType].value;

    uint256 feeShares = MathUpgradeable.mulDiv(_sharesAmount, feeValue, 1 ether);

    uint256 totalAllocatedShares = 0;

    for (uint256 i = 0; i < roles.length - 1; i++) {
      shares[i] = MathUpgradeable.mulDiv(feeShares, allocations[i], 1 ether);
      totalAllocatedShares += shares[i];
    }

    shares[3] = _sharesAmount - totalAllocatedShares;

    for (uint256 i = 0; i < roles.length; i++) {
      amounts[i] = stakeTogether.pooledEthByShares(shares[i]);
    }

    return (shares, amounts);
  }

  function estimateFeePercentage(
    FeeType _feeType,
    uint256 _amount
  ) public view returns (uint256[4] memory shares, uint256[4] memory amounts) {
    require(fees[_feeType].mathType == FeeMath.PERCENTAGE);
    uint256 sharesAmount = stakeTogether.sharesByPooledEth(_amount);
    return distributeFee(_feeType, sharesAmount);
  }

  function estimateFeeFixed(
    FeeType _feeType
  ) public view returns (uint256[4] memory shares, uint256[4] memory amounts) {
    require(fees[_feeType].mathType == FeeMath.FIXED);
    return distributeFee(_feeType, fees[_feeType].value);
  }
}
