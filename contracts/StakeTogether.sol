// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;
import './SETH.sol';

/// @custom:security-contact security@staketogether.app
contract StakeTogether is SETH {
  event EtherReceived(address indexed sender, uint amount);

  constructor(
    address _distributorContract,
    address _poolContract,
    address _WETHContract,
    address _LETHContract,
    address _depositContract
  ) payable {
    distributorContract = Distributor(payable(_distributorContract));
    poolContract = Pool(payable(_poolContract));
    WETHContract = WETH(payable(_WETHContract));
    LETHContract = LETH(payable(_LETHContract));
    depositContract = IDepositContract(_depositContract);
  }

  receive() external payable {
    emit EtherReceived(msg.sender, msg.value);
    _repayLoan();
  }

  fallback() external payable {
    emit EtherReceived(msg.sender, msg.value);
    _repayLoan();
  }

  /*****************
   ** STAKE **
   *****************/

  event DepositPool(address indexed account, uint256 amount, address delegated, address referral);
  event DepositDonationPool(
    address indexed donor,
    address indexed account,
    uint256 amount,
    address pool,
    address referral
  );

  event WithdrawPool(address indexed account, uint256 amount, address pool);
  event WithdrawBorrow(address indexed account, uint256 amount, address pool);
  event WithdrawValidator(address indexed account, uint256 amount, address pool);

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

  function _depositBase(address _pool, address _to) internal {
    require(poolContract.isPool(_pool), 'NON_POOL_DELEGATE');
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

    _mintShares(_to, sharesAmount);
    _mintPoolShares(_to, _pool, sharesAmount);

    totalDeposited += msg.value;

    if (block.number > lastResetBlock + blocksPerDay) {
      totalDeposited = msg.value;
      totalWithdrawn = 0;
      lastResetBlock = block.number;
    }

    _repayLoan();
  }

  function depositPool(address _pool, address _referral) external payable nonReentrant whenNotPaused {
    _depositBase(_pool, msg.sender);
    emit DepositPool(msg.sender, msg.value, _pool, _referral);
  }

  function depositDonationPool(
    address _pool,
    address _referral,
    address _to
  ) external payable nonReentrant whenNotPaused {
    _depositBase(_pool, _to);
    emit DepositDonationPool(msg.sender, _to, msg.value, _pool, _referral);
  }

  function _withdrawBase(uint256 _amount, address _pool) internal whenNotPaused {
    require(_amount > 0, 'ZERO_VALUE');
    require(_pool != address(0), 'MINT_TO_ZERO_ADDR');
    require(delegationSharesOf(msg.sender, _pool) > 0, 'NOT_DELEGATION_SHARES');

    if (_amount + totalWithdrawn > withdrawalLimit) {
      emit WithdrawalLimitReached(msg.sender, _amount);
      revert('WITHDRAWAL_LIMIT_REACHED');
    }

    uint256 userBalance = balanceOf(msg.sender);
    require(_amount <= userBalance, 'AMOUNT_EXCEEDS_BALANCE');

    uint256 sharesToBurn = Math.mulDiv(_amount, sharesOf(msg.sender), userBalance);

    _burnShares(msg.sender, sharesToBurn);
    _burnPoolShares(msg.sender, _pool, sharesToBurn);

    totalWithdrawn += _amount;

    if (block.number > lastResetBlock + blocksPerDay) {
      totalDeposited = 0;
      totalWithdrawn = _amount;
      lastResetBlock = block.number;
    }
  }

  function withdrawPool(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(_amount <= poolBalance(), 'NOT_ENOUGH_POOL_BALANCE');
    emit WithdrawPool(msg.sender, _amount, _pool);
    _withdrawBase(_amount, _pool);
    payable(msg.sender).transfer(_amount);
  }

  function withdrawBorrow(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(_amount <= address(LETHContract).balance, 'NOT_ENOUGH_BORROW_BALANCE');
    emit WithdrawBorrow(msg.sender, _amount, _pool);
    _withdrawBase(_amount, _pool);
    poolSize += _amount;
    LETHContract.borrow(_amount, _pool);
    payable(msg.sender).transfer(_amount);
  }

  function withdrawValidator(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    // Todo: check borrow conditional rule
    require(_amount <= beaconBalance, 'NOT_ENOUGH_BEACON_BALANCE');
    emit WithdrawValidator(msg.sender, _amount, _pool);
    _withdrawBase(_amount, _pool);
    beaconBalance -= _amount;
    WETHContract.mint(msg.sender, _amount);
  }

  function setDepositLimit(uint256 _newLimit) external onlyRole(ADMIN_ROLE) {
    depositLimit = _newLimit;
    emit SetDepositLimit(_newLimit);
  }

  function setWithdrawalLimit(uint256 _newLimit) external onlyRole(ADMIN_ROLE) {
    withdrawalLimit = _newLimit;
    emit SetWithdrawalLimit(_newLimit);
  }

  function setWalletDepositLimit(uint256 _newLimit) external onlyRole(ADMIN_ROLE) {
    walletDepositLimit = _newLimit;
    emit SetWalletDepositLimit(_newLimit);
  }

  function setBlocksInterval(uint256 _newBlocksInterval) external onlyRole(ADMIN_ROLE) {
    blocksPerDay = _newBlocksInterval;
    emit SetBlocksInterval(_newBlocksInterval);
  }

  function setMinDepositPoolAmount(uint256 _amount) external onlyRole(ADMIN_ROLE) {
    minDepositAmount = _amount;
    emit SetMinDepositPoolAmount(_amount);
  }

  function setPoolSize(uint256 _amount) external onlyRole(ADMIN_ROLE) {
    require(_amount >= validatorSize + address(LETHContract).balance, 'POOL_SIZE_TOO_LOW');
    poolSize = _amount;
    emit SetPoolSize(_amount);
  }

  function poolBalance() public view returns (uint256) {
    return contractBalance();
  }

  function totalPooledEther() public view override returns (uint256) {
    return contractBalance() + beaconBalance;
  }

  function _repayLoan() internal {
    if (LETHContract.balanceOf(address(this)) > 0) {
      uint256 loanAmount = 0;
      if (LETHContract.balanceOf(address(this)) >= msg.value) {
        loanAmount = msg.value;
      } else {
        loanAmount = LETHContract.balanceOf(address(this));
      }
      LETHContract.repayLoan{ value: loanAmount }();
      poolSize -= loanAmount;
    }
  }

  /***********************
   ** VALIDATOR ORACLES **
   ***********************/

  address[] public validatorOracles;
  uint256 public currentOracleIndex;

  modifier onlyValidatorOracle() {
    require(hasRole(ORACLE_VALIDATOR_ROLE, msg.sender), 'MISSING_ORACLE_VALIDATOR_ROLE');
    require(msg.sender == validatorOracles[currentOracleIndex], 'NOT_CURRENT_VALIDATOR_ORACLE');
    _;
  }

  event AddValidatorOracle(address indexed account);
  event RemoveValidatorOracle(address indexed account);

  function addValidatorOracle(address _oracleAddress) external onlyRole(ORACLE_VALIDATOR_MANAGER_ROLE) {
    _grantRole(ORACLE_VALIDATOR_ROLE, _oracleAddress);
    validatorOracles.push(_oracleAddress);
    emit AddValidatorOracle(_oracleAddress);
  }

  function removeValidatorOracle(
    address _oracleAddress
  ) external onlyRole(ORACLE_VALIDATOR_MANAGER_ROLE) {
    _revokeRole(ORACLE_VALIDATOR_ROLE, _oracleAddress);
    for (uint256 i = 0; i < validatorOracles.length; i++) {
      if (validatorOracles[i] == _oracleAddress) {
        validatorOracles[i] = validatorOracles[validatorOracles.length - 1];
        validatorOracles.pop();
        break;
      }
    }
    emit RemoveValidatorOracle(_oracleAddress);
  }

  function forceNextValidatorOracle() external onlyRole(ORACLE_VALIDATOR_SENTINEL_ROLE) {
    require(
      hasRole(ORACLE_VALIDATOR_SENTINEL_ROLE, msg.sender) ||
        hasRole(ORACLE_VALIDATOR_MANAGER_ROLE, msg.sender),
      'MISSING_SENDER_ROLE'
    );
    require(validatorOracles.length > 0, 'NO_VALIDATOR_ORACLE');
    _nextValidatorOracle();
  }

  function currentValidatorOracle() external view returns (address) {
    return validatorOracles[currentOracleIndex];
  }

  function _nextValidatorOracle() internal {
    require(validatorOracles.length > 1, 'NOT_ENOUGH_ORACLES');
    currentOracleIndex = (currentOracleIndex + 1) % validatorOracles.length;
  }

  /*****************
   ** VALIDATORS **
   *****************/

  bytes public withdrawalCredentials;

  event CreateValidator(
    address indexed creator,
    uint256 indexed amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );
  event RemoveValidator(address indexed account, uint256 epoch, bytes publicKey);
  event SetValidatorSize(uint256 newValidatorSize);
  event SetWithdrawalCredentials(bytes withdrawalCredentials);

  mapping(bytes => bool) public validators;
  uint256 public totalValidators = 0;
  uint256 public validatorSize = 32 ether;

  function setWithdrawalCredentials(bytes memory _withdrawalCredentials) external onlyRole(ADMIN_ROLE) {
    require(withdrawalCredentials.length == 0, 'WITHDRAWAL_CREDENTIALS_ALREADY_SET');
    withdrawalCredentials = _withdrawalCredentials;
    emit SetWithdrawalCredentials(_withdrawalCredentials);
  }

  function createValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external nonReentrant onlyValidatorOracle {
    require(poolBalance() >= poolSize + validatorFee, 'NOT_ENOUGH_POOL_BALANCE');
    require(!validators[_publicKey], 'PUBLIC_KEY_ALREADY_USED');

    validators[_publicKey] = true;
    totalValidators++;
    beaconBalance += validatorSize;

    depositContract.deposit{ value: validatorSize }(
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );

    _nextValidatorOracle();

    emit CreateValidator(
      msg.sender,
      validatorSize,
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );

    payable(stakeTogetherFeeAddress).transfer(validatorFee);
  }

  function removeValidator(
    uint256 _epoch,
    bytes calldata _publicKey
  ) external payable nonReentrant onlyDistributor {
    require(validators[_publicKey], 'PUBLIC_KEY_NOT_FOUND');

    validators[_publicKey] = false;
    totalValidators--;

    emit RemoveValidator(msg.sender, _epoch, _publicKey);
  }

  function setValidatorSize(uint256 _newSize) external onlyRole(ADMIN_ROLE) {
    require(_newSize >= 32 ether, 'MINIMUM_VALIDATOR_SIZE');
    validatorSize = _newSize;
    emit SetValidatorSize(_newSize);
  }

  function isValidator(bytes memory _publicKey) public view returns (bool) {
    return validators[_publicKey];
  }
}
