// SPDX-FileCopyrightText: 2023 Stake Together <info@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './CETH.sol';
import './Oracle.sol';
import './Validator.sol';

contract StakeTogether is Ownable, ReentrancyGuard, CETH {
  Oracle public immutable oracle;
  Validator public immutable validator;

  event Staked(address indexed account, uint256 amount);
  event Unstaked(address indexed account, uint256 amount);
  event BufferDeposited(address indexed account, uint256 amount);
  event BufferWithdrawn(address indexed account, uint256 amount);
  event Referral(address indexed account, address delegated, address indexed referral, uint256 amount);

  constructor(address _oracle, address _validator) payable {
    oracle = Oracle(_oracle);
    validator = Validator(_validator);
    _bootstrap();
  }

  /*****************
   ** STAKE **
   *****************/

  uint256 private immutable poolSize = 32 ether;
  uint256 private withdrawalsBuffer = 0;
  uint256 private minStakeAmount = 0.01 ether;

  uint256 private beaconBalance = 0;

  function stake(address _delegated, address referral) external payable nonReentrant whenNotPaused {
    require(_delegated != address(0), 'MINT_TO_ZERO_ADDR');
    require(_isCommunity(_delegated), 'Only can stake for Communities');
    require(msg.value > 0, 'Amount must be greater than 0');

    _mintShares(msg.sender, msg.value);
    _mintDelegatedShares(msg.sender, _delegated, msg.value);

    if (referral != address(0)) {
      emit Referral(msg.sender, _delegated, referral, msg.value);
    }

    emit Staked(msg.sender, msg.value);
  }

  function unstake(uint256 _amount, address _delegated) external nonReentrant whenNotPaused {
    require(_amount > 0, 'Amount must be greater than 0');
    require(_amount >= minStakeAmount, 'Amount must be greater or equal than minimum stake amount');
    require(_delegated != address(0), 'MINT_TO_ZERO_ADDR');
    require(_amount <= _getWithdrawalBalance(), 'Insufficient withdrawn balance');
    require(_delegationsOf(_delegated, msg.sender) > 0, 'No shares delegated to this address');

    uint256 userBalance = balanceOf(msg.sender);

    require(_amount <= userBalance, 'Unstake amount exceeds balance');

    uint256 sharesToBurn = (_amount * _sharesOf(msg.sender)) / userBalance;

    _burnShares(msg.sender, sharesToBurn);
    _burnDelegatedShares(msg.sender, _delegated, sharesToBurn);

    payable(msg.sender).transfer(_amount);

    emit Unstaked(msg.sender, _amount);
  }

  function depositBuffer() external payable onlyOwner nonReentrant whenNotPaused {
    require(msg.value > 0, 'Value sent must be greater than 0');
    withdrawalsBuffer += msg.value;

    emit BufferDeposited(msg.sender, msg.value);
  }

  function withdrawBuffer(uint256 amount) external onlyOwner nonReentrant whenNotPaused {
    require(amount > 0, 'Withdrawal amount must be greater than 0');
    require(withdrawalsBuffer > amount, 'Withdrawal amount exceeds buffer balance');

    withdrawalsBuffer -= amount;

    payable(owner()).transfer(amount);

    emit BufferWithdrawn(msg.sender, amount);
  }

  function getPoolSize() public pure returns (uint256) {
    return poolSize;
  }

  function getPoolBalance() public view returns (uint256) {
    return _getPoolBalance();
  }

  function getBufferBalance() public view returns (uint256) {
    return withdrawalsBuffer;
  }

  function getWithdrawalBalance() public view returns (uint256) {
    return _getWithdrawalBalance();
  }

  function setBeaconBalance(uint256 newBalance) external nonReentrant {
    require(msg.sender == address(oracle), 'Only oracle can call this function');

    uint256 lastBeaconBalance = beaconBalance;

    beaconBalance = newBalance;

    _distributeFee(beaconBalance, lastBeaconBalance);
  }

  function _getPoolBalance() internal view returns (uint256) {
    return address(this).balance - withdrawalsBuffer;
  }

  function _getTotalPooledEther() internal view override returns (uint256) {
    return (beaconBalance + address(this).balance) - withdrawalsBuffer;
  }

  function _getTotalEtherSupply() internal view returns (uint256) {
    return beaconBalance + address(this).balance + withdrawalsBuffer;
  }

  function _getWithdrawalBalance() internal view returns (uint256) {
    return address(this).balance + withdrawalsBuffer;
  }

  function _bootstrap() internal {
    address stakeTogether = address(this);
    uint256 balance = stakeTogether.balance;

    require(balance > 0, 'Contract balance must be greater than 0');

    _mintShares(stakeTogether, balance);
    _mintDelegatedShares(stakeTogether, stakeTogether, balance);
  }

  function setMinimumStakeAmount(uint256 amount) external onlyOwner {
    minStakeAmount = amount;
  }

  /*****************
   ** DELEGATION **
   *****************/

  function transfer(address _recipient, uint256 _amount) public override returns (bool) {
    _transfer(msg.sender, _recipient, _amount);
    return true;
  }

  function transferFrom(
    address _sender,
    address _recipient,
    uint256 _amount
  ) public override returns (bool) {
    _spendAllowance(_sender, msg.sender, _amount);
    _transfer(_sender, _recipient, _amount);

    return true;
  }

  /*****************
   ** VALIDATOR **
   *****************/

  function createValidator(
    bytes calldata pubkey,
    bytes calldata signature,
    bytes32 deposit_data_root
  ) external onlyOwner nonReentrant {
    require(_getPoolBalance() >= poolSize, 'Not enough ether on poolBalance to create validator');
    validator.createValidator{ value: poolSize }(pubkey, signature, deposit_data_root);
  }
}
