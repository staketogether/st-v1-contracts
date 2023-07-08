// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;
import './sETH.sol';

/// @custom:security-contact security@staketogether.app
contract StakeTogether is sETH {
  event EtherReceived(address indexed sender, uint amount);

  constructor(
    address _distributorContract,
    address _poolContract,
    address _wETHContract,
    address _lETHContract,
    address _depositContract
  ) payable {
    distributorContract = Distributor(payable(_distributorContract));
    poolContract = Pool(payable(_poolContract));
    wETHContract = wETH(payable(_wETHContract));
    lETHContract = lETH(payable(_lETHContract));
    depositContract = IDepositContract(_depositContract);
  }

  receive() external payable {
    _repayLoan();
    emit EtherReceived(msg.sender, msg.value);
  }

  fallback() external payable {
    _repayLoan();
    emit EtherReceived(msg.sender, msg.value);
  }

  /*****************
   ** STAKE BUFFER **
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
  event WithdrawValidator(address indexed account, uint256 amount, address pool);
  event WithdrawBorrow(address indexed account, uint256 amount, address pool);

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

    _repayLoan();

    if (block.number > lastResetBlock + blocksPerDay) {
      totalDeposited = msg.value;
      totalWithdrawn = 0;
      lastResetBlock = block.number;
    }
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
    _withdrawBase(_amount, _pool);
    payable(msg.sender).transfer(_amount);
    emit WithdrawPool(msg.sender, _amount, _pool);
  }

  function withdrawValidator(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(_amount <= beaconBalance, 'NOT_ENOUGH_BEACON_BALANCE');
    _withdrawBase(_amount, _pool);
    beaconBalance -= _amount;
    wETHContract.mint(msg.sender, _amount);
    emit WithdrawValidator(msg.sender, _amount, _pool);
  }

  function withdrawBorrow(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(_amount <= address(lETHContract).balance, 'NOT_ENOUGH_BORROW_BALANCE');
    _withdrawBase(_amount, _pool);
    poolSize += _amount;
    emit WithdrawBorrow(msg.sender, _amount, _pool);
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

  // Todo: dynamic change pool size with wETH
  function setPoolSize(uint256 _amount) external onlyRole(ADMIN_ROLE) {
    require(_amount >= validatorSize + address(lETHContract).balance, 'POOL_SIZE_TOO_LOW');
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
    if (lETHContract.balanceOf(address(this)) > 0) {
      uint256 loanAmount = 0;
      if (lETHContract.balanceOf(address(this)) >= msg.value) {
        loanAmount = msg.value;
      } else {
        loanAmount = lETHContract.balanceOf(address(this));
      }
      lETHContract.repayLoan{ value: loanAmount }();
      poolSize -= loanAmount;
    }
  }

  /***********************
   ** VALIDATOR ORACLES **
   ***********************/

  // modifier onlyValidatorOracle() {
  //   require(isOracle(msg.sender), 'ONLY_ORACLES');
  //   _;
  // }

  // event AddValidatorOracle(address oracle);
  // event RemoveValidatorOracle(address oracle);

  // mapping(address => bool) private validatorOracles;
  // mapping(uint256 => bool) private validatorOraclesIndex;
  // uint256 totalValidatorOracles = 0;
  // uint256 public validatorOracleOrder = 0;

  // function isOracle(address _oracle) public view returns (bool) {
  //   return validatorOracles[_oracle];
  // }

  // function addValidatorOracle(address oracle) external onlyOwner {
  //   require(!isOracle(oracle), 'ORACLE_EXISTS');
  //   validatorOracles[oracle] = true;
  //   validatorOraclesIndex[totalValidatorOracles] = true;
  //   totalValidatorOracles += 1;
  //   emit AddValidatorOracle(oracle);
  // }

  // function removeValidatorOracle(address oracle) external onlyOwner {
  //   require(isOracle(oracle), 'ORACLE_NOT_EXISTS');
  //   validatorOracles[oracle] = false;
  //   validatorOraclesIndex[totalValidatorOracles] = false;
  //   totalValidatorOracles -= 1;
  //   emit RemoveValidatorOracle(oracle);
  // }

  // function getValidatorByOrder() public view returns (address) {
  //   return validatorOracles[validatorOracleOrder];
  // }

  // function forceNewValidatorOrder() external onlyOwner {
  //   validatorOracleOrder += 1;

  //   if (validatorOracleOrder >= totalValidatorOracles) {
  //     validatorOracleOrder = 0;
  //   }
  // }

  // Todo Add BlockList

  /*****************
   ** VALIDATORS **
   *****************/

  // Todo: exit sequence with wETH

  bytes public withdrawalCredentials;

  event SetStakeTogether(address stakeTogether);
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
  ) external nonReentrant {
    require(poolBalance() >= poolSize + validatorFee, 'NOT_ENOUGH_POOL_BALANCE');
    require(!validators[_publicKey], 'PUBLIC_KEY_ALREADY_USED');
    // require(msg.sender == getValidatorByOrder(), 'NOT_VALIDATOR_ORACLE');

    validators[_publicKey] = true;
    totalValidators++;
    beaconBalance += validatorSize;

    // validatorOracleOrder += 1;

    // if (validatorOracleOrder >= totalValidatorOracles) {
    //   validatorOracleOrder = 0;
    // }

    depositContract.deposit{ value: validatorSize }(
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );

    payable(stakeTogetherFeeAddress).transfer(validatorFee);

    emit CreateValidator(
      msg.sender,
      validatorSize,
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );
  }

  function removeValidator(uint256 _epoch, bytes calldata _publicKey) external payable nonReentrant {
    require(msg.sender == address(distributorContract), 'ONLY_DISTRIBUTOR_CONTRACT');
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
