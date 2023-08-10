// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;
import './Shares.sol';

/// @custom:security-contact security@staketogether.app
contract StakeTogether is Shares {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address _fees,
    address _router,
    address _withdrawals,
    address _deposit,
    bytes memory _withdrawalCredentials
  ) public initializer {
    __ERC20_init('Stake Together Pool', 'stpETH');
    __ERC20Burnable_init();
    __Pausable_init();
    __AccessControl_init();
    __ERC20Permit_init('Stake Together Pool');
    __UUPSUpgradeable_init();

    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);
    _grantRole(POOL_MANAGER_ROLE, msg.sender);

    version = 1;

    fees = Fees(payable(_fees));
    router = _router;
    withdrawals = Withdrawals(payable(_withdrawals));
    deposit = IDepositContract(_deposit);
    withdrawalCredentials = _withdrawalCredentials;

    beaconBalance = 0;

    totalShares = 0;
  }

  function initializeShares() external payable onlyRole(ADMIN_ROLE) {
    _mintShares(address(this), msg.value);
    emit Init(msg.value);
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  receive() external payable nonReentrant {
    emit ReceiveEther(msg.sender, msg.value);
  }

  /************
   ** CONFIG **
   ************/

  function setConfig(Config memory _config) public onlyRole(ADMIN_ROLE) {
    require(_config.poolSize >= config.validatorSize, 'POOL_SIZE_TOO_SMALL');
    config = _config;
    emit SetConfig(_config);
  }

  /*****************
   ** STAKE **
   *****************/

  function _depositBase(
    address _to,
    Delegation[] memory _delegations,
    DepositType _depositType,
    address referral
  ) internal {
    require(config.feature.Deposit, 'DEPOSIT_DISABLED');
    require(_to != address(0), 'ZERO_ADDRESS');
    require(msg.value >= config.minDepositAmount, 'MIN_DEPOSIT_AMOUNT');

    _resetLimits();

    if (msg.value + totalDeposited > config.depositLimit) {
      emit DepositLimitReached(_to, msg.value);
      revert();
    }

    if (_depositType == DepositType.DonationPool) {
      _validateDelegations(_to, _delegations);
    }

    uint256 sharesAmount = MathUpgradeable.mulDiv(msg.value, totalShares, totalPooledEther() - msg.value);

    (uint256[4] memory _shares, ) = fees.distributeFee(IFees.FeeType.StakeEntry, sharesAmount);

    IFees.FeeRole[4] memory roles = fees.getFeesRoles();
    for (uint i = 0; i < roles.length; i++) {
      if (_shares[i] > 0) {
        if (roles[i] == IFees.FeeRole.Sender) {
          _mintShares(_to, _shares[i]);
        } else {
          _mintRewards(fees.getFeeAddress(roles[i]), 0, _shares[i], IFees.FeeType.StakeEntry, roles[i]);
        }
      }
    }

    totalDeposited += msg.value;
    emit DepositBase(_to, _delegations, msg.value, _shares, _depositType, referral);
  }

  function depositPool(
    Delegation[] memory _delegations,
    address _referral
  ) external payable nonReentrant whenNotPaused {
    _depositBase(msg.sender, _delegations, DepositType.Pool, _referral);
  }

  function depositDonationPool(
    address _to,
    address _referral
  ) external payable nonReentrant whenNotPaused {
    Delegation[] memory delegations;
    _depositBase(_to, delegations, DepositType.DonationPool, _referral);
  }

  function _withdrawBase(
    uint256 _amount,
    Delegation[] memory _delegations,
    WithdrawType _withdrawType
  ) internal {
    require(_amount > 0, 'ZERO_AMOUNT');
    require(_amount <= balanceOf(msg.sender), 'INSUFFICIENT_BALANCE');

    _resetLimits();

    if (_amount + totalWithdrawn > config.withdrawalLimit) {
      emit WithdrawalsLimitReached(msg.sender, _amount);
      revert();
    }

    _validateDelegations(msg.sender, _delegations);

    uint256 sharesToBurn = MathUpgradeable.mulDiv(_amount, shares[msg.sender], balanceOf(msg.sender));

    totalWithdrawn += _amount;

    _burnShares(msg.sender, sharesToBurn);

    emit WithdrawBase(msg.sender, _delegations, _amount, sharesToBurn, _withdrawType);
  }

  function withdrawPool(
    uint256 _amount,
    Delegation[] memory _delegations
  ) external nonReentrant whenNotPaused {
    require(config.feature.WithdrawPool, 'WITHDRAW_DISABLED');
    require(_amount <= address(this).balance, 'INSUFFICIENT_POOL_BALANCE');
    _withdrawBase(_amount, _delegations, WithdrawType.Pool);
    payable(msg.sender).transfer(_amount);
  }

  function withdrawValidator(
    uint256 _amount,
    Delegation[] memory _delegations
  ) external nonReentrant whenNotPaused {
    require(config.feature.WithdrawValidator, 'WITHDRAW_DISABLED');
    require(_amount <= beaconBalance, 'INSUFFICIENT_BEACON_BALANCE');
    beaconBalance -= _amount;
    _withdrawBase(_amount, _delegations, WithdrawType.Validator);
    withdrawals.mint(msg.sender, _amount);
  }

  function refundPool() external payable {
    require(msg.sender == router, 'NOT_ROUTER');
    beaconBalance -= msg.value;
    emit RefundPool(msg.sender, msg.value);
  }

  function totalPooledEther() public view override returns (uint256) {
    return address(this).balance + beaconBalance;
  }

  function _resetLimits() private {
    if (block.number > lastResetBlock + config.blocksPerDay) {
      totalDeposited = 0;
      totalWithdrawn = 0;
      lastResetBlock = block.number;
    }
  }

  /***********
   ** POOLS **
   ***********/

  function addPool(address _pool, bool _listed) public payable nonReentrant {
    require(_pool != address(0), 'ZERO_ADDRESS');
    require(!pools[_pool], 'POOL_ALREADY_ADDED');
    if (!hasRole(POOL_MANAGER_ROLE, msg.sender)) {
      require(config.feature.AddPool, 'ADD_POOL_DISABLED');
      (uint256[4] memory _shares, ) = fees.estimateFeeFixed(IFees.FeeType.StakePool);
      IFees.FeeRole[4] memory roles = fees.getFeesRoles();
      for (uint i = 0; i < roles.length - 1; i++) {
        _mintRewards(
          fees.getFeeAddress(roles[i]),
          msg.value,
          _shares[i],
          IFees.FeeType.StakePool,
          roles[i]
        );
      }
    }
    pools[_pool] = true;
    emit AddPool(_pool, _listed, msg.value);
  }

  function removePool(address _pool) external onlyRole(POOL_MANAGER_ROLE) {
    require(pools[_pool], 'POOL_NOT_FOUND');
    pools[_pool] = false;
    emit RemovePool(_pool);
  }

  function updateDelegations(Delegation[] memory _delegations) external {
    _validateDelegations(msg.sender, _delegations);
    emit UpdateDelegations(msg.sender, _delegations);
  }

  function _validateDelegations(address _account, Delegation[] memory _delegations) internal view {
    uint256 totalDelegationsShares = 0;

    for (uint i = 0; i < _delegations.length; i++) {
      require(pools[_delegations[i].pool], 'POOL_NOT_FOUND');
      totalDelegationsShares += _delegations[i].shares;
    }

    require(totalDelegationsShares == shares[_account], 'INVALID_TOTAL_SHARES');
    require(_delegations.length <= config.maxDelegations, 'TO_MANY_DELEGATIONS');
  }

  /***********************
   ** VALIDATOR ORACLES **
   ***********************/

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
      'NOT_AUTHORIZED'
    );
    require(validatorOracles.length > 0, 'NO_VALIDATOR_ORACLES');
    _nextValidatorOracle();
  }

  function isValidatorOracle(address _oracleAddress) public view returns (bool) {
    return
      hasRole(ORACLE_VALIDATOR_ROLE, _oracleAddress) &&
      validatorOracles[currentOracleIndex] == _oracleAddress;
  }

  function _nextValidatorOracle() internal {
    require(validatorOracles.length > 1, 'NO_VALIDATOR_ORACLES');
    currentOracleIndex = (currentOracleIndex + 1) % validatorOracles.length;
  }

  /*****************
   ** VALIDATORS **
   *****************/

  function setBeaconBalance(uint256 _amount) external {
    require(msg.sender == address(router), 'NOT_ROUTER');
    beaconBalance = _amount;
    emit SetBeaconBalance(_amount);
  }

  function createValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external nonReentrant whenNotPaused {
    require(isValidatorOracle(msg.sender), 'NOT_VALIDATOR_ORACLE');
    require(address(this).balance >= config.validatorSize, 'INSUFFICIENT_POOL_BALANCE');
    require(!validators[_publicKey], 'VALIDATOR_ALREADY_CREATED');

    (uint256[4] memory _shares, ) = fees.estimateFeeFixed(IFees.FeeType.StakeValidator);

    IFees.FeeRole[4] memory roles = fees.getFeesRoles();

    for (uint i = 0; i < _shares.length - 1; i++) {
      if (_shares[i] > 0) {
        _mintRewards(fees.getFeeAddress(roles[i]), 0, _shares[i], IFees.FeeType.StakeValidator, roles[i]);
      }
    }

    beaconBalance += validatorSize;
    validators[_publicKey] = true;
    totalValidators++;

    _nextValidatorOracle();

    deposit.deposit{ value: validatorSize }(
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );

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
    require(msg.sender == address(router), 'NOT_ROUTER');
    require(validators[_publicKey], 'NOT_VALIDATOR');

    validators[_publicKey] = false;
    totalValidators--;

    emit RemoveValidator(msg.sender, _epoch, _publicKey, msg.value);
  }
}
