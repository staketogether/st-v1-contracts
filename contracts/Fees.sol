// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import './interfaces/IFees.sol';
import './StakeTogether.sol';

/// @custom:security-contact security@staketogether.app
contract Fees is IFees, AccessControl, Pausable {
  StakeTogether public stakeTogether;
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  Fee[8] private _fees;
  mapping(FeeAddressType => address) public feeAddresses;
  mapping(FeeType => mapping(address => uint256)) private _allocations;

  uint256 public dayStart = 30;
  uint256 public dayEnd = 365;
  uint256 public proportionStart = 100;
  uint256 public proportionEnd = 60;

  constructor() {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
  }

  receive() external payable {
    _transferToStakeTogether();
    emit ReceiveEther(msg.sender, msg.value);
  }

  fallback() external payable {
    _transferToStakeTogether();
    emit FallbackEther(msg.sender, msg.value);
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

  function setTotalFee(
    FeeType _feeType,
    uint256 _total,
    FeeValueType _valueType
  ) external onlyRole(ADMIN_ROLE) {
    if (_valueType == FeeValueType.PERCENTAGE) {
      require(_total <= 1 ether, 'TOTAL_FEE_EXCEEDS_100_PERCENT');
    }
    _fees[uint256(_feeType)].total = _total;
    _fees[uint256(_feeType)].valueType = _valueType;
    emit SetTotalFee(_feeType, _total);
  }

  function getTotalFee(FeeType _feeType) public view returns (uint256) {
    return _fees[uint256(_feeType)].total;
  }

  function setFeeAddress(FeeAddressType _addressType, address _address) external onlyRole(ADMIN_ROLE) {
    feeAddresses[_addressType] = _address;
    emit SetFeeAddress(_addressType, _address);
  }

  function getFeeAddress(FeeAddressType _addressType) external view returns (address) {
    return feeAddresses[_addressType];
  }

  function setFeeAllocation(
    FeeType _feeType,
    FeeAddressType _addressType,
    uint256 _allocation
  ) external onlyRole(ADMIN_ROLE) {
    address feeAddress = feeAddresses[_addressType];
    uint256 currentTotal = _fees[uint256(_feeType)].total;
    require(_allocation <= currentTotal, 'FEE_ALLOCATION_EXCEEDS_TOTAL');
    _allocations[_feeType][feeAddress] = _allocation;
    emit SetFeeAllocation(_feeType, feeAddress, _allocation);
  }

  function getFeeAllocation(FeeType _feeType, address _address) public view returns (uint256) {
    return _allocations[_feeType][_address];
  }

  function setRangeAndProportion(
    uint256 _dayStart,
    uint256 _dayEnd,
    uint256 _proportionStart,
    uint256 _proportionEnd
  ) public onlyRole(ADMIN_ROLE) {
    dayStart = _dayStart;
    dayEnd = _dayEnd;
    proportionStart = _proportionStart;
    proportionEnd = _proportionEnd;
    emit SetRangeAndProportion(_dayStart, _dayEnd, _proportionStart, _proportionEnd);
  }

  // Todo: rename
  function calculateFee(uint256 _days) public view returns (uint256) {
    require(_days >= dayStart && _days <= dayEnd, 'DAYS_OUT_OF_RANGE');
    uint256 range = dayEnd - dayStart;
    uint256 proportionRange = proportionStart - proportionEnd;
    uint256 daysOverStart = _days - dayStart;
    return proportionStart - ((daysOverStart * proportionRange) / range);
  }

  function _transferToStakeTogether() private {
    payable(stakeTogether).transfer(address(this).balance);
  }

  /*******************
   ** ESTIMATE FEES **
   *******************/

  function estimateFeePercentage(
    FeeType _feeType,
    uint256 _amount,
    bool _includeDepositor
  ) external view returns (uint256[] memory, uint256[] memory) {
    uint256 sharesLength = _includeDepositor ? 5 : 4;

    uint256[] memory shares = new uint256[](sharesLength);
    uint256[] memory amounts = new uint256[](sharesLength);

    uint256 sharesAmount = Math.mulDiv(
      _amount,
      stakeTogether.totalShares(),
      stakeTogether.totalPooledEther() - _amount
    );

    uint256 feePercentage = getTotalFee(_feeType);

    Fee memory fee = _fees[uint256(_feeType)];
    require(fee.valueType == FeeValueType.PERCENTAGE, 'FEE_NOT_PERCENTAGE');

    uint256 feeShares = Math.mulDiv(sharesAmount, feePercentage, 1 ether);

    shares[0] = Math.mulDiv(
      feeShares,
      getFeeAllocation(_feeType, feeAddresses[FeeAddressType.Pools]),
      1 ether
    );
    shares[1] = Math.mulDiv(
      feeShares,
      getFeeAllocation(_feeType, feeAddresses[FeeAddressType.Operators]),
      1 ether
    );
    shares[2] = Math.mulDiv(
      feeShares,
      getFeeAllocation(_feeType, feeAddresses[FeeAddressType.StakeTogether]),
      1 ether
    );
    shares[3] = Math.mulDiv(
      feeShares,
      getFeeAllocation(_feeType, feeAddresses[FeeAddressType.Accounts]),
      1 ether
    );

    amounts[0] = stakeTogether.pooledEthByShares(shares[0]);
    amounts[1] = stakeTogether.pooledEthByShares(shares[1]);
    amounts[2] = stakeTogether.pooledEthByShares(shares[2]);
    amounts[3] = stakeTogether.pooledEthByShares(shares[3]);

    if (_includeDepositor) {
      shares[4] = sharesAmount - feeShares;
      amounts[4] = stakeTogether.pooledEthByShares(shares[4]);
    }

    return (shares, amounts);
  }
}
