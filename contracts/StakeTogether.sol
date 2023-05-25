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
    uint256 shares,
    address delegated,
    address referral
  );

  event WithdrawPool(address indexed account, uint256 amount, uint256 shares, address delegated);

  event SetWithdrawalCredentials(bytes withdrawalCredentials);
  event SetMinDepositPoolAmount(uint256 amount);

  uint256 public immutable poolSize = 32 ether;
  uint256 public minAmount = 0.000000000000000001 ether;

  function depositPool(
    address _delegated,
    address _referral
  ) external payable nonReentrant whenNotPaused {
    require(_isCommunity(_delegated), 'NON_COMMUNITY_DELEGATE');
    require(msg.value > 0, 'ZERO_VALUE');
    require(msg.value >= minAmount, 'NON_MIN_AMOUNT');

    uint256 sharesAmount = (msg.value * totalShares) / (getTotalPooledEther() - msg.value);

    _mintShares(msg.sender, sharesAmount);
    _mintDelegatedShares(msg.sender, _delegated, sharesAmount);

    emit DepositPool(msg.sender, msg.value, sharesAmount, _delegated, _referral);
  }

  function withdrawPool(uint256 _amount, address _delegated) external nonReentrant whenNotPaused {
    require(_amount > 0, 'ZERO_VALUE');
    require(_delegated != address(0), 'MINT_TO_ZERO_ADDR');
    require(_amount <= getWithdrawalsBalance(), 'NOT_ENOUGH_CONTRACT_BALANCE');
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
    minAmount = _amount;
    emit SetMinDepositPoolAmount(_amount);
  }

  function getBalance() public view returns (uint) {
    return address(this).balance;
  }

  function getPoolBalance() public view returns (uint256) {
    return address(this).balance - withdrawalsBalance;
  }

  function getTotalPooledEther() public view override returns (uint256) {
    // Todo: Implement Transient Balance
    return (clBalance + address(this).balance) - withdrawalsBalance;
  }

  function getTotalEtherSupply() public view returns (uint256) {
    return clBalance + address(this).balance + withdrawalsBalance;
  }

  /*****************
   ** WITHDRAWALS **
   *****************/

  event DepositBuffer(address indexed account, uint256 amount);
  event WithdrawBuffer(address indexed account, uint256 amount);

  uint256 public withdrawalsBalance = 0;

  function depositBuffer() external payable onlyOwner nonReentrant whenNotPaused {
    require(msg.value > 0, 'ZERO_VALUE');
    withdrawalsBalance += msg.value;

    emit DepositBuffer(msg.sender, msg.value);
  }

  function withdrawBuffer(uint256 _amount) external onlyOwner nonReentrant whenNotPaused {
    require(_amount > 0, 'ZERO_VALUE');
    require(withdrawalsBalance > _amount, 'AMOUNT_EXCEEDS_BUFFER');

    withdrawalsBalance -= _amount;

    payable(owner()).transfer(_amount);

    emit WithdrawBuffer(msg.sender, _amount);
  }

  function getWithdrawalsBalance() public view returns (uint256) {
    return address(this).balance + withdrawalsBalance;
  }

  /*****************
   ** REWARDS **
   *****************/

  event SetConsensusLayerBalance(uint256 amount);

  function setClBalance(uint256 _balance) external override nonReentrant {
    require(msg.sender == address(stOracle), 'ONLY_ST_ORACLE');

    uint256 preClBalance = clBalance;
    clBalance = _balance;

    _processRewards(preClBalance, clBalance);

    emit SetConsensusLayerBalance(clBalance);
  }

  /*****************
   ** VALIDATOR **
   *****************/

  bytes[] public validators;

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
    require(getPoolBalance() >= poolSize, 'NOT_ENOUGH_POOL_BALANCE');

    depositContract.deposit{ value: poolSize }(
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );

    validators.push(_publicKey);

    emit CreateValidator(
      msg.sender,
      poolSize,
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );
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
