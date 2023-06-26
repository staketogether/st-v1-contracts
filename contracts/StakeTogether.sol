// SPDX-FileCopyrightText: 2023 Stake Together Labs <info@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/utils/math/Math.sol';
import './SETH.sol';
import './interfaces/IDepositContract.sol';

/// @custom:security-contact security@staketogether.app
contract StakeTogether is SETH {
  IDepositContract public immutable depositContract;
  bytes public withdrawalCredentials;

  event EtherReceived(address indexed sender, uint amount);

  constructor(address _rewardsContract, address _depositContract) payable {
    rewardsContract = Rewards(payable(_rewardsContract));
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

  event DonationDepositPool(
    address indexed donor,
    address indexed account,
    uint256 amount,
    uint256 sharesAmount,
    address delegated,
    address referral
  );

  event WithdrawPool(address indexed account, uint256 amount, uint256 sharesAmount, address delegated);
  event SetWithdrawalCredentials(bytes withdrawalCredentials);
  event SetMinDepositPoolAmount(uint256 amount);
  event SetPoolSize(uint256 amount);
  event SetDepositLimit(uint256 newLimit);
  event SetWalletDepositLimit(uint256 newLimit);
  event SetWithdrawalLimit(uint256 newLimit);
  event SetBlocksInterval(uint256 blocksInterval);
  event DepositLimitReached(address indexed sender, uint256 amount);
  event WalletDepositLimitReached(address indexed sender, uint256 amount);
  event WithdrawalLimitReached(address indexed sender, uint256 amount);

  uint256 public poolSize = 32 ether;
  uint256 public minDepositAmount = 0.001 ether;
  uint256 public depositLimit = 1000 ether;
  uint256 public walletDepositLimit = 2 ether;
  uint256 public withdrawalLimit = 1000 ether;
  uint256 public blocksPerDay = 6500;
  uint256 public lastResetBlock;
  uint256 public totalDeposited;
  uint256 public totalWithdrawn;

  function depositBase(address _pool, address _referral, address _to, bool _isDonation) internal {
    require(isPool(_pool), 'NON_POOL_DELEGATE');
    require(msg.value > 0, 'ZERO_VALUE');
    require(msg.value >= minDepositAmount, 'NON_MIN_AMOUNT');

    if (walletDepositLimit > 0) {
      require(balanceOf(_to) + msg.value <= walletDepositLimit, 'WALLET_DEPOSIT_LIMIT_REACHED');
    }

    if (msg.value + totalDeposited > depositLimit) {
      emit DepositLimitReached(_to, msg.value);
      revert('DEPOSIT_LIMIT_REACHED');
    }

    uint256 sharesAmount = Math.mulDiv(msg.value, totalShares, totalPooledEther() - msg.value);

    if (_isDonation) {
      emit DonationDepositPool(msg.sender, _to, msg.value, sharesAmount, _pool, _referral);
    } else {
      emit DepositPool(_to, msg.value, sharesAmount, _pool, _referral);
    }

    _mintShares(_to, sharesAmount);
    _mintPoolShares(_to, _pool, sharesAmount);

    totalDeposited += msg.value;

    if (block.number > lastResetBlock + blocksPerDay) {
      totalDeposited = msg.value;
      totalWithdrawn = 0;
      lastResetBlock = block.number;
    }
  }

  function depositPool(
    address _delegated,
    address _referral
  ) external payable nonReentrant whenNotPaused {
    depositBase(_delegated, _referral, msg.sender, false);
  }

  function donationDepositPool(
    address _delegated,
    address _referral,
    address _to
  ) external payable nonReentrant whenNotPaused {
    depositBase(_delegated, _referral, _to, true);
  }

  function withdrawPool(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(_amount > 0, 'ZERO_VALUE');
    require(_pool != address(0), 'MINT_TO_ZERO_ADDR');
    require(_amount <= withdrawalsBalance(), 'NOT_ENOUGH_WITHDRAWALS_BALANCE');
    require(delegationSharesOf(msg.sender, _pool) > 0, 'NOT_DELEGATION_SHARES');

    if (_amount + totalWithdrawn > withdrawalLimit) {
      emit WithdrawalLimitReached(msg.sender, _amount);
      revert('WITHDRAWAL_LIMIT_REACHED');
    }

    uint256 userBalance = balanceOf(msg.sender);
    require(_amount <= userBalance, 'AMOUNT_EXCEEDS_BALANCE');

    uint256 sharesToBurn = Math.mulDiv(_amount, sharesOf(msg.sender), userBalance);

    emit WithdrawPool(msg.sender, _amount, sharesToBurn, _pool);

    _burnShares(msg.sender, sharesToBurn);
    _burnPoolShares(msg.sender, _pool, sharesToBurn);

    payable(msg.sender).transfer(_amount);

    totalWithdrawn += _amount;

    if (block.number > lastResetBlock + blocksPerDay) {
      totalDeposited = 0;
      totalWithdrawn = _amount;
      lastResetBlock = block.number;
    }
  }

  function setDepositLimit(uint256 _newLimit) external onlyOwner {
    depositLimit = _newLimit;
    emit SetDepositLimit(_newLimit);
  }

  function setWithdrawalLimit(uint256 _newLimit) external onlyOwner {
    withdrawalLimit = _newLimit;
    emit SetWithdrawalLimit(_newLimit);
  }

  function setWalletDepositLimit(uint256 _newLimit) external onlyOwner {
    walletDepositLimit = _newLimit;
    emit SetWalletDepositLimit(_newLimit);
  }

  function setBlocksInterval(uint256 _newBlocksInterval) external onlyOwner {
    blocksPerDay = _newBlocksInterval;
    emit SetBlocksInterval(_newBlocksInterval);
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

  function setPoolSize(uint256 _amount) external onlyOwner {
    require(_amount >= 32 ether, 'POOL_SIZE_TOO_LOW');
    poolSize = _amount;
    emit SetPoolSize(_amount);
  }

  function poolBalance() public view returns (uint256) {
    return contractBalance() - liquidityBufferBalance;
  }

  function totalPooledEther() public view override returns (uint256) {
    return (contractBalance() + beaconBalance) - liquidityBufferBalance;
  }

  function totalEtherSupply() public view returns (uint256) {
    return contractBalance() + beaconBalance + liquidityBufferBalance;
  }

  /*****************
   ** LIQUIDITY BUFFER **
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
    require(_amount <= liquidityBufferBalance, 'AMOUNT_EXCEEDS_BUFFER');

    liquidityBufferBalance -= _amount;

    payable(owner()).transfer(_amount);

    emit WithdrawLiquidityBuffer(msg.sender, _amount);
  }

  function withdrawalsBalance() public view returns (uint256) {
    return poolBalance() + liquidityBufferBalance;
  }

  /*****************
   ** VALIDATOR **
   *****************/

  mapping(bytes => bool) public validators;
  uint256 public totalValidators = 0;

  uint256 public validatorSize = 32 ether;

  modifier onlyValidatorModule() {
    require(msg.sender == validatorModuleAddress, 'ONLY_VALIDATOR_MODULE');
    _;
  }

  event CreateValidator(
    address indexed creator,
    uint256 indexed amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );
  event RemoveValidator(address indexed account, bytes publicKey);
  event SetValidatorSize(uint256 newValidatorSize);

  function setValidatorSize(uint256 _newSize) external onlyOwner {
    require(_newSize >= 32 ether, 'MINIMUM_VALIDATOR_SIZE');
    validatorSize = _newSize;
    emit SetValidatorSize(_newSize);
  }

  function createValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external onlyValidatorModule nonReentrant {
    require(poolBalance() >= poolSize + validatorFee, 'NOT_ENOUGH_POOL_BALANCE');
    require(!validators[_publicKey], 'PUBLIC_KEY_ALREADY_USED');

    depositContract.deposit{ value: validatorSize }(
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );

    validators[_publicKey] = true;
    totalValidators++;
    beaconBalance += validatorSize;

    payable(validatorFeeAddress).transfer(validatorFee);

    emit CreateValidator(
      msg.sender,
      poolSize,
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );
  }

  function removeValidator(bytes calldata _publicKey) external payable nonReentrant onlyRewardsContract {
    require(validators[_publicKey], 'PUBLIC_KEY_NOT_FOUND');

    validators[_publicKey] = false;
    totalValidators--;

    emit RemoveValidator(msg.sender, _publicKey);
  }

  function isValidator(bytes memory _publicKey) public view returns (bool) {
    return validators[_publicKey];
  }
}
