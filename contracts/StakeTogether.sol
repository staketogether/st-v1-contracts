// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import './SETH.sol';
import './Rewards.sol';
import './interfaces/IDepositContract.sol';

contract StakeTogether is SETH {
  Rewards public immutable stOracle;
  IDepositContract public immutable depositContract;
  bytes public withdrawalCredentials;

  event EtherReceived(address indexed sender, uint amount);

  constructor(address _stOracle, address _depositContract) payable {
    stOracle = Rewards(_stOracle);
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
  event SetPoolSize(uint256 amount);
  event SetDepositLimit(uint256 newLimit);
  event SetWithdrawalLimit(uint256 newLimit);
  event SetBlocksInterval(uint256 blocksInterval);
  event DepositLimitReached(address indexed sender, uint256 amount);
  event WithdrawalLimitReached(address indexed sender, uint256 amount);

  uint256 public poolSize = 32 ether;
  uint256 public minDepositAmount = 0.001 ether;
  uint256 public depositLimit = 1000 ether;
  uint256 public withdrawalLimit = 1000 ether;
  uint256 public blocksPerDay = 6500;
  uint256 public lastResetBlock;
  uint256 public totalDeposited;
  uint256 public totalWithdrawn;

  function depositPool(
    address _delegated,
    address _referral
  ) external payable nonReentrant whenNotPaused {
    require(isPool(_delegated), 'NON_POOL_DELEGATE');
    require(msg.value > 0, 'ZERO_VALUE');
    require(msg.value >= minDepositAmount, 'NON_MIN_AMOUNT');
    if (msg.value + totalDeposited > depositLimit) {
      emit DepositLimitReached(msg.sender, msg.value);
      revert('DEPOSIT_LIMIT_REACHED');
    }

    uint256 sharesAmount = (msg.value * totalShares) / (totalPooledEther() - msg.value);

    emit DepositPool(msg.sender, msg.value, sharesAmount, _delegated, _referral);

    _mintShares(msg.sender, sharesAmount);
    _mintPoolShares(msg.sender, _delegated, sharesAmount);

    totalDeposited += msg.value;

    if (block.number > lastResetBlock + blocksPerDay) {
      totalDeposited = msg.value;
      totalWithdrawn = 0;
      lastResetBlock = block.number;
    }
  }

  function withdrawPool(uint256 _amount, address _delegated) external nonReentrant whenNotPaused {
    require(_amount > 0, 'ZERO_VALUE');
    require(_delegated != address(0), 'MINT_TO_ZERO_ADDR');
    require(_amount <= withdrawalsBalance(), 'NOT_ENOUGH_WITHDRAWALS_BALANCE');
    require(delegationSharesOf(msg.sender, _delegated) > 0, 'NOT_DELEGATION_SHARES');

    if (_amount + totalWithdrawn > withdrawalLimit) {
      emit WithdrawalLimitReached(msg.sender, _amount);
      revert('WITHDRAWAL_LIMIT_REACHED');
    }

    uint256 userBalance = balanceOf(msg.sender);
    require(_amount <= userBalance, 'AMOUNT_EXCEEDS_BALANCE');

    uint256 sharesToBurn = (_amount * sharesOf(msg.sender)) / userBalance;

    emit WithdrawPool(msg.sender, _amount, sharesToBurn, _delegated);

    _burnShares(msg.sender, sharesToBurn);
    _burnPoolShares(msg.sender, _delegated, sharesToBurn);

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
    return (contractBalance() + transientBalance + beaconBalance) - liquidityBufferBalance;
  }

  function totalEtherSupply() public view returns (uint256) {
    return contractBalance() + transientBalance + beaconBalance + liquidityBufferBalance;
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

  function createValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external onlyValidatorModule nonReentrant {
    require(poolBalance() >= poolSize, 'NOT_ENOUGH_POOL_BALANCE');

    depositContract.deposit{ value: 32 ether }(
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

  function getValidators() public view returns (string[] memory) {
    string[] memory publicKeys = new string[](validators.length);

    for (uint i = 0; i < validators.length; i++) {
      publicKeys[i] = string(validators[i]);
    }

    return publicKeys;
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
