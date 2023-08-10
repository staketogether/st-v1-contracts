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
    require(currentAllowance >= _subtractedValue, 'ALLOWANCE_TOO_LOW');
    _approve(msg.sender, _spender, currentAllowance - _subtractedValue);
    return true;
  }

  function _approve(address _account, address _spender, uint256 _amount) internal override {
    require(_account != address(0), 'ZERO_ADDRESS');
    require(_spender != address(0), 'ZERO_ADDRESS');

    allowances[_account][_spender] = _amount;
    emit Approval(_account, _spender, _amount);
  }

  function _mintShares(address _to, uint256 _sharesAmount) internal whenNotPaused {
    require(_to != address(0), 'ZERO_ADDRESS');

    shares[_to] = shares[_to] + _sharesAmount;
    totalShares += _sharesAmount;

    emit MintShares(_to, _sharesAmount);
  }

  function _burnShares(address _account, uint256 _sharesAmount) internal whenNotPaused {
    require(_account != address(0), 'ZERO_ADDRESS');
    require(_sharesAmount <= shares[_account], 'BURN_AMOUNT_TOO_HIGH');

    shares[_account] = shares[_account] - _sharesAmount;
    totalShares -= _sharesAmount;

    emit BurnShares(_account, _sharesAmount);
  }

  function _transfer(address _from, address _to, uint256 _amount) internal override whenNotPaused {
    uint256 _sharesToTransfer = sharesByPooledEth(_amount);
    _transferShares(_from, _to, _sharesToTransfer);
    emit Transfer(_from, _to, _amount);
  }

  function _transferShares(address _from, address _to, uint256 _sharesAmount) internal whenNotPaused {
    require(_from != address(0), 'ZERO_ADDRESS');
    require(_to != address(0), 'ZERO_ADDRESS');
    require(_sharesAmount <= shares[_from], 'TRANSFER_AMOUNT_TOO_HIGH');
    shares[_from] = shares[_from] - _sharesAmount;
    shares[_to] = shares[_to] + _sharesAmount;
    emit TransferShares(_from, _to, _sharesAmount);
  }

  function _spendAllowance(address _account, address _spender, uint256 _amount) internal override {
    uint256 currentAllowance = allowances[_account][_spender];
    if (currentAllowance != ~uint256(0)) {
      require(currentAllowance >= _amount, 'ALLOWANCE_TOO_LOW');
      _approve(_account, _spender, currentAllowance - _amount);
    }
  }

  /*****************
   ** REWARDS **
   *****************/

  function _mintRewards(
    address _address,
    uint256 _amount,
    uint256 _sharesAmount,
    IFees.FeeType _feeType,
    IFees.FeeRole _feeRole
  ) internal {
    _mintShares(_address, _sharesAmount);
    emit MintRewards(_address, _amount, _sharesAmount, _feeType, _feeRole);
  }

  function mintRewards(
    address _address,
    uint256 _sharesAmount,
    IFees.FeeType _feeType,
    IFees.FeeRole _feeRole
  ) public payable {
    require(msg.sender == router, 'ONLY_ROUTER');
    _mintRewards(_address, msg.value, _sharesAmount, _feeType, _feeRole);
  }

  function claimRewards(address _account, uint256 _sharesAmount) external whenNotPaused {
    address airdropFee = fees.getFeeAddress(IFees.FeeRole.Airdrop);
    require(msg.sender == airdropFee, 'ONLY_AIRDROP');
    _transferShares(airdropFee, _account, _sharesAmount);
    emit ClaimRewards(_account, _sharesAmount);
  }
}
