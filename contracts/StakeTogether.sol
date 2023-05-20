// SPDX-FileCopyrightText: 2023 Stake Together <info@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import './CETH.sol';
import './STOracle.sol';
import './STValidator.sol';

contract StakeTogether is CETH {
  STOracle public immutable stOracle;
  STValidator public immutable stValidator;

  constructor(address _stOracle, address _stValidator) payable {
    stOracle = STOracle(_stOracle);
    stValidator = STValidator(_stValidator);
    _bootstrap();
  }

  function _bootstrap() internal {
    address stakeTogether = address(this);
    uint256 balance = stakeTogether.balance;

    require(balance > 0, 'NON_ZERO_VALUE');

    _mintShares(stakeTogether, balance);
    _mintDelegatedShares(stakeTogether, stakeTogether, balance);
  }

  /*****************
   ** STAKE **
   *****************/

  event Staked(address indexed account, uint256 amount);
  event Unstaked(address indexed account, uint256 amount);
  event Referral(address indexed account, address delegated, address indexed referral, uint256 amount);

  uint256 public immutable poolSize = 32 ether;
  uint256 public minAmount = 0.001 ether;

  function stake(address _delegated, address referral) external payable nonReentrant whenNotPaused {
    require(_isCommunity(_delegated), 'NON_COMMUNITY_DELEGATE');
    require(msg.value > 0, 'ZERO_VALUE');
    require(msg.value >= minAmount, 'NON_MIN_AMOUNT');

    // uint256 sharesAmount = getSharesByPooledEth(msg.value);
    uint256 sharesAmount = msg.value;

    _mintShares(msg.sender, sharesAmount);
    _mintDelegatedShares(msg.sender, _delegated, sharesAmount);

    emit Staked(msg.sender, msg.value);

    if (referral != address(0)) {
      emit Referral(msg.sender, _delegated, referral, msg.value);
    }
  }

  function unstake(uint256 _amount, address _delegated) external nonReentrant whenNotPaused {
    require(_amount > 0, 'ZERO_VALUE');
    require(_delegated != address(0), 'MINT_TO_ZERO_ADDR');
    require(_amount <= getWithdrawalsBalance(), 'NOT_ENOUGHT_CONTRACT_BALANCE');
    require(delegationSharesOf(_delegated, msg.sender) > 0, 'NOT_DELEGATED_SHARES');

    uint256 userBalance = balanceOf(msg.sender);

    require(_amount <= userBalance, 'AMOUNT_EXCEEDS_BALANCE');

    uint256 sharesToBurn = (_amount * _sharesOf(msg.sender)) / userBalance;

    _burnShares(msg.sender, sharesToBurn);
    _burnDelegatedShares(msg.sender, _delegated, sharesToBurn);

    payable(msg.sender).transfer(_amount);

    emit Unstaked(msg.sender, _amount);
  }

  function setMinimumStakeAmount(uint256 amount) external onlyOwner {
    minAmount = amount;
  }

  function getPoolBalance() public view returns (uint256) {
    return _getPoolBalance();
  }

  function _getPoolBalance() internal view returns (uint256) {
    return address(this).balance - withdrawalsBuffer;
  }

  function _getTotalPooledEther() internal view override returns (uint256) {
    return (clBalance + address(this).balance) - withdrawalsBuffer;
  }

  function _getTotalEtherSupply() internal view returns (uint256) {
    return clBalance + address(this).balance + withdrawalsBuffer;
  }

  /*****************
   ** WITHDRAWALS **
   *****************/

  event BufferDeposited(address indexed account, uint256 amount);
  event BufferWithdrawn(address indexed account, uint256 amount);

  uint256 public withdrawalsBuffer = 0;

  function depositBuffer() external payable onlyOwner nonReentrant whenNotPaused {
    require(msg.value > 0, 'ZERO_VALUE');
    withdrawalsBuffer += msg.value;

    emit BufferDeposited(msg.sender, msg.value);
  }

  function withdrawBuffer(uint256 amount) external onlyOwner nonReentrant whenNotPaused {
    require(amount > 0, 'ZERO_VALUE');
    require(withdrawalsBuffer > amount, 'AMOUNT_EXCEEDS_BUFFER');

    withdrawalsBuffer -= amount;

    payable(owner()).transfer(amount);

    emit BufferWithdrawn(msg.sender, amount);
  }

  function getWithdrawalsBalance() public view returns (uint256) {
    return address(this).balance + withdrawalsBuffer;
  }

  /*****************
   ** REWARDS **
   *****************/

  function setClBalance(uint256 _balance) external override nonReentrant {
    require(msg.sender == address(stOracle), 'ONLY_ST_ORACLE');

    uint256 preClBalance = clBalance;
    clBalance = _balance;

    _processRewards(preClBalance, clBalance);
  }

  /*****************
   ** VALIDATOR **
   *****************/

  function createValidator(
    bytes calldata pubkey,
    bytes calldata signature,
    bytes32 deposit_data_root
  ) external onlyOwner nonReentrant {
    require(_getPoolBalance() >= poolSize, 'NOT_ENOUGH_POOL_BALANCE');
    stValidator.createValidator{ value: poolSize }(pubkey, signature, deposit_data_root);
  }
}
