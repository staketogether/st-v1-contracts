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
  uint256 public version;

  StakeTogether public stakeTogether;
  Liquidity public liquidity;

  uint256 public maxDynamicFee;

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

  function setLiquidity(address _liquidity) external onlyRole(ADMIN_ROLE) {
    require(_liquidity != address(0));
    liquidity = Liquidity(payable(_liquidity));
    emit SetLiquidity(_liquidity);
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

  function setFee(
    FeeType _feeType,
    uint256 _value,
    FeeMathType _mathType,
    uint256[] calldata _allocations
  ) external onlyRole(ADMIN_ROLE) {
    require(_allocations.length == 8);

    fees[_feeType].value = _value;
    fees[_feeType].mathType = _mathType;

    uint256 sum = 0;
    for (uint256 i = 0; i < _allocations.length; i++) {
      uint256 allocation = _allocations[i];
      fees[_feeType].allocations[FeeRoles(i)] = allocation;
      sum += allocation;
    }

    require(sum == 1 ether);
    emit SetFee(_feeType, _value, _mathType, _allocations);
  }

  function getFee(
    FeeType _feeType
  ) public view returns (FeeType, uint256, FeeMathType, uint256[8] memory) {
    uint256[8] memory allocations;
    for (uint i = 0; i < 8; i++) {
      allocations[i] = fees[_feeType].allocations[FeeRoles(i)];
    }

    return (_feeType, fees[_feeType].value, fees[_feeType].mathType, allocations);
  }

  function getFees()
    public
    view
    returns (
      FeeType[] memory feeTypes,
      uint256[] memory feeValues,
      FeeMathType[] memory feeMathTypes,
      uint256[8][] memory allocations
    )
  {
    uint256 feeCount = 6;

    feeTypes = new FeeType[](feeCount);
    feeValues = new uint256[](feeCount);
    feeMathTypes = new FeeMathType[](feeCount);
    allocations = new uint256[8][](feeCount);

    for (uint256 i = 0; i < feeCount; i++) {
      (FeeType feeType, uint256 feeValue, FeeMathType feeMathType, uint256[8] memory allocation) = getFee(
        FeeType(i)
      );

      feeTypes[i] = feeType;
      feeValues[i] = feeValue;
      feeMathTypes[i] = feeMathType;
      allocations[i] = allocation;
    }

    return (feeTypes, feeValues, feeMathTypes, allocations);
  }

  function setMaxDynamicFee(uint256 _maxDynamicFee) external onlyRole(ADMIN_ROLE) {
    maxDynamicFee = _maxDynamicFee;
    emit SetMaxDynamicFee(_maxDynamicFee);
  }

  function _transferToStakeTogether() private {
    payable(stakeTogether).transfer(address(this).balance);
  }

  /*************
   * ESTIMATES *
   *************/

  function distributeFee(
    FeeType _feeType,
    uint256 _sharesAmount,
    bool _dynamicFee
  ) public view returns (uint256[8] memory shares, uint256[8] memory amounts) {
    FeeRoles[8] memory roles = getFeesRoles();
    address[8] memory feeAddresses = getFeeRolesAddresses();
    uint256[8] memory allocations;

    for (uint256 i = 0; i < feeAddresses.length - 1; i++) {
      require(feeAddresses[i] != address(0), 'ZERO_ADDRESS');
    }

    for (uint256 i = 0; i < allocations.length; i++) {
      allocations[i] = fees[_feeType].allocations[roles[i]];
    }

    uint256 feeValue = fees[_feeType].value;

    if (_dynamicFee && fees[_feeType].mathType == FeeMathType.PERCENTAGE) {
      feeValue = _calculateDynamicFee(feeValue);
    }

    uint256 feeShares = MathUpgradeable.mulDiv(_sharesAmount, feeValue, 1 ether);

    // Create a temporary variable to keep track of the total allocated shares
    uint256 totalAllocatedShares = 0;

    // Allocate shares for the first 7 roles
    for (uint256 i = 0; i < roles.length - 1; i++) {
      shares[i] = MathUpgradeable.mulDiv(feeShares, allocations[i], 1 ether);
      totalAllocatedShares += shares[i];
    }

    // Allocate the remaining shares to the last role
    shares[7] = _sharesAmount - totalAllocatedShares;

    // Calculate the amounts for each role
    for (uint256 i = 0; i < roles.length; i++) {
      amounts[i] = stakeTogether.pooledEthByShares(shares[i]);
    }

    return (shares, amounts);
  }

  function estimateFeePercentage(
    FeeType _feeType,
    uint256 _amount,
    bool _dynamicFee
  ) public view returns (uint256[8] memory shares, uint256[8] memory amounts) {
    require(fees[_feeType].mathType == FeeMathType.PERCENTAGE);
    uint256 sharesAmount = stakeTogether.sharesByPooledEth(_amount);
    return distributeFee(_feeType, sharesAmount, _dynamicFee);
  }

  function estimateFeeFixed(
    FeeType _feeType
  ) public view returns (uint256[8] memory shares, uint256[8] memory amounts) {
    require(fees[_feeType].mathType == FeeMathType.FIXED);
    return distributeFee(_feeType, fees[_feeType].value, false);
  }

  function _calculateDynamicFee(uint256 _baseFee) internal view returns (uint256) {
    uint256 totalPooledEtherStake = stakeTogether.totalPooledEther();
    uint256 totalPooledEtherLiquidity = liquidity.totalPooledEther();
    uint256 _fee;

    if (totalPooledEtherLiquidity == 0) {
      _fee = MathUpgradeable.mulDiv(_baseFee, 1 ether + maxDynamicFee, 1 ether);
    } else {
      uint256 ratio = MathUpgradeable.mulDiv(totalPooledEtherStake, 1 ether, totalPooledEtherLiquidity);

      if (ratio >= 1 ether) {
        _fee = MathUpgradeable.mulDiv(_baseFee, 1 ether + maxDynamicFee, 1 ether);
      } else {
        uint256 feeIncrease = MathUpgradeable.mulDiv(ratio, maxDynamicFee, 1 ether);
        _fee = MathUpgradeable.mulDiv(_baseFee, 1 ether + feeIncrease, 1 ether);
      }
    }

    return _fee;
  }
}
