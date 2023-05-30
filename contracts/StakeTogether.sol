// SPDX-FileCopyrightText: 2023 Stake Together <info@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import './CETH.sol';
import './STOracle.sol';
import './interfaces/IDepositContract.sol';

contract StakeTogether is CETH {
  STOracle public immutable stOracle;
  IDepositContract public immutable depositContract;
  bytes public withdrawalCredentials;

  event EtherReceived(address indexed sender, uint amount);

  constructor(address _stOracle, address _depositContract) payable {
    stOracle = STOracle(_stOracle);
    depositContract = IDepositContract(_depositContract);
  }

  receive() external payable {
    emit EtherReceived(msg.sender, msg.value);
  }

  fallback() external payable {
    emit EtherReceived(msg.sender, msg.value);
  }

  /*****************
   ** STAKE **
   *****************/

  event DepositPool(
    address indexed account,
    uint256 amount,
    uint256 sharesAmount,
    address delegated,
    address referral
  );

  event WithdrawPool(address indexed account, uint256 amount, uint256 sharesAmount, address delegated);

  event SetWithdrawalCredentials(bytes withdrawalCredentials);
  event SetMinDepositPoolAmount(uint256 amount);

  uint256 public immutable poolSize = 32 ether;
  uint256 public minDepositAmount = 0.000000000000000001 ether;

  function depositPool(
    address _delegated,
    address _referral
  ) external payable nonReentrant whenNotPaused {
    require(_isCommunity(_delegated), 'NON_COMMUNITY_DELEGATE');
    require(msg.value > 0, 'ZERO_VALUE');
    require(msg.value >= minDepositAmount, 'NON_MIN_AMOUNT');

    uint256 sharesAmount = (msg.value * totalShares) / (totalPooledEther() - msg.value);

    _mintShares(msg.sender, sharesAmount);
    _mintDelegatedShares(msg.sender, _delegated, sharesAmount);

    emit DepositPool(msg.sender, msg.value, sharesAmount, _delegated, _referral);
  }

  function withdrawPool(uint256 _amount, address _delegated) external nonReentrant whenNotPaused {
    require(_amount > 0, 'ZERO_VALUE');
    require(_delegated != address(0), 'MINT_TO_ZERO_ADDR');
    require(_amount <= withdrawalsBalance(), 'NOT_ENOUGH_WITHDRAWALS_BALANCE');
    require(delegationSharesOf(msg.sender, _delegated) > 0, 'NOT_DELEGATION_SHARES');

    uint256 userBalance = balanceOf(msg.sender);

    require(_amount <= userBalance, 'AMOUNT_EXCEEDS_BALANCE');

    uint256 sharesToBurn = (_amount * sharesOf(msg.sender)) / userBalance;

    _burnShares(msg.sender, sharesToBurn);
    _burnDelegatedShares(msg.sender, _delegated, sharesToBurn);

    emit WithdrawPool(msg.sender, _amount, sharesToBurn, _delegated);

    payable(msg.sender).transfer(_amount);
  }

  function setWithdrawalCredentials(bytes memory _withdrawalCredentials) external onlyOwner {
    require(withdrawalCredentials.length == 0, 'WITHDRAWAL_CREDENTIALS_ALREADY_SET');
    withdrawalCredentials = _withdrawalCredentials;
    emit SetWithdrawalCredentials(_withdrawalCredentials);
  }

  function setMinDepositPoolAmount(uint256 _amount) external onlyOwner {
    minDepositAmount = _amount;
    emit SetMinDepositPoolAmount(_amount);
  }

  function poolBalance() public view returns (uint256) {
    return contractBalance() - liquidityBufferBalance - poolBufferBalance;
  }

  function poolBalanceWithBuffer() public view returns (uint256) {
    return poolBalance() + poolBufferBalance;
  }

  function totalPooledEther() public view override returns (uint256) {
    return
      (contractBalance() + transientBalance + beaconBalance) - liquidityBufferBalance - poolBufferBalance;
  }

  function totalEtherSupply() public view returns (uint256) {
    return
      contractBalance() + transientBalance + beaconBalance + liquidityBufferBalance + poolBufferBalance;
  }

  /*****************
   ** WITHDRAWALS **
   *****************/

  event DepositLiquidityBuffer(address indexed account, uint256 amount);
  event WithdrawLiquidityBuffer(address indexed account, uint256 amount);

  uint256 public liquidityBufferBalance = 0;

  function depositLiquidityBuffer() external payable onlyOwner nonReentrant whenNotPaused {
    require(msg.value > 0, 'ZERO_VALUE');
    liquidityBufferBalance += msg.value;

    emit DepositLiquidityBuffer(msg.sender, msg.value);
  }

  function withdrawLiquidityBuffer(uint256 _amount) external onlyOwner nonReentrant whenNotPaused {
    require(_amount > 0, 'ZERO_VALUE');
    require(liquidityBufferBalance > _amount, 'AMOUNT_EXCEEDS_BUFFER');

    liquidityBufferBalance -= _amount;

    payable(owner()).transfer(_amount);

    emit WithdrawLiquidityBuffer(msg.sender, _amount);
  }

  function withdrawalsBalance() public view returns (uint256) {
    return poolBalance() + liquidityBufferBalance;
  }

  /*****************
   ** Pool Buffer **
   *****************/

  event DepositPoolBuffer(address indexed account, uint256 amount);
  event WithdrawPoolBuffer(address indexed account, uint256 amount);

  uint256 public poolBufferBalance = 0;

  function depositPoolBuffer() external payable onlyOwner nonReentrant whenNotPaused {
    require(msg.value > 0, 'ZERO_VALUE');
    poolBufferBalance += msg.value;

    emit DepositPoolBuffer(msg.sender, msg.value);
  }

  function withdrawPoolBuffer(uint256 _amount) external onlyOwner nonReentrant whenNotPaused {
    require(_amount > 0, 'ZERO_VALUE');
    require(poolBufferBalance > _amount, 'AMOUNT_EXCEEDS_BUFFER');

    poolBufferBalance -= _amount;

    payable(owner()).transfer(_amount);

    emit WithdrawPoolBuffer(msg.sender, _amount);
  }

  /*****************
   ** REWARDS **
   *****************/

  event SetTransientBalance(uint256 amount);
  event SetBeaconBalance(uint256 amount);

  function setTransientBalance(uint256 _transientBalance) external override nonReentrant {
    require(msg.sender == address(stOracle), 'ONLY_ST_ORACLE');

    transientBalance = _transientBalance;

    emit SetTransientBalance(_transientBalance);
  }

  function setBeaconBalance(uint256 _beaconBalance) external override nonReentrant {
    require(msg.sender == address(stOracle), 'ONLY_ST_ORACLE');

    uint256 preClBalance = beaconBalance;
    beaconBalance = _beaconBalance;

    _processRewards(preClBalance, _beaconBalance);

    emit SetBeaconBalance(_beaconBalance);
  }

  /*****************
   ** VALIDATOR **
   *****************/

  bytes[] private validators;
  uint256 public totalValidators = 0;

  event CreateValidator(
    address indexed creator,
    uint256 indexed amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );

  function createValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external onlyOwner nonReentrant {
    require(poolBalanceWithBuffer() >= poolSize, 'NOT_ENOUGH_POOL_BALANCE');

    depositContract.deposit{ value: poolSize }(
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );

    validators.push(_publicKey);
    totalValidators++;
    transientBalance += poolSize;

    emit CreateValidator(
      msg.sender,
      poolSize,
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );
  }

  function getValidators() public view returns (bytes[] memory) {
    return validators;
  }

  function isValidator(bytes memory publicKey) public view returns (bool) {
    for (uint256 i = 0; i < validators.length; i++) {
      if (keccak256(validators[i]) == keccak256(publicKey)) {
        return true;
      }
    }
    return false;
  }
}
