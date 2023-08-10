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
    totalPoolShares = 0;
  }

  function initializeShares() external payable onlyRole(ADMIN_ROLE) {
    require(totalShares == 0);
    address stakeTogetherFee = fees.getFeeAddress(IFees.FeeRole.StakeTogether);
    addPool(stakeTogetherFee, false);
    _mintShares(address(this), msg.value);
    _mintPoolShares(address(this), stakeTogetherFee, msg.value);
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
    require(_config.poolSize >= config.validatorSize);
    config = _config;
    emit SetConfig(_config);
  }

  /*****************
   ** STAKE **
   *****************/

  function _depositBase(address _to, address _pool, DepositType _depositType, address referral) internal {
    require(config.feature.Deposit);
    require(_to != address(0));
    require(pools[_pool]);
    require(msg.value >= config.minDepositAmount);

    _resetLimits();

    if (msg.value + totalDeposited > config.depositLimit) {
      emit DepositLimitReached(_to, msg.value);
      revert();
    }

    uint256 sharesAmount = MathUpgradeable.mulDiv(msg.value, totalShares, totalPooledEther() - msg.value);

    (uint256[4] memory _shares, ) = fees.distributeFee(IFees.FeeType.StakeEntry, sharesAmount);

    IFees.FeeRole[4] memory roles = fees.getFeesRoles();
    for (uint i = 0; i < roles.length; i++) {
      if (_shares[i] > 0) {
        if (roles[i] == IFees.FeeRole.Sender) {
          _mintShares(_to, _shares[i]);
          _mintPoolShares(_to, _pool, _shares[i]);
        } else {
          _mintRewards(
            fees.getFeeAddress(roles[i]),
            fees.getFeeAddress(IFees.FeeRole.StakeTogether),
            0,
            _shares[i],
            IFees.FeeType.StakeEntry,
            roles[i]
          );
        }
      }
    }

    totalDeposited += msg.value;
    emit DepositBase(_to, _pool, msg.value, _shares, _depositType, referral);
  }

  function depositPool(address _pool, address _referral) external payable nonReentrant whenNotPaused {
    _depositBase(msg.sender, _pool, DepositType.Pool, _referral);
  }

  function depositDonationPool(
    address _to,
    address _pool,
    address _referral
  ) external payable nonReentrant whenNotPaused {
    _depositBase(_to, _pool, DepositType.DonationPool, _referral);
  }

  function _withdrawBase(uint256 _amount, address _pool, WithdrawType _withdrawType) internal {
    require(_amount > 0);
    require(_amount <= balanceOf(msg.sender));
    require(pools[_pool]);
    require(delegationSharesOf(msg.sender, _pool) > 0);

    _resetLimits();

    if (_amount + totalWithdrawn > config.withdrawalLimit) {
      emit WithdrawalsLimitReached(msg.sender, _amount);
      revert();
    }

    uint256 sharesToBurn = MathUpgradeable.mulDiv(_amount, shares[msg.sender], balanceOf(msg.sender));

    totalWithdrawn += _amount;

    _burnShares(msg.sender, sharesToBurn);
    _burnPoolShares(msg.sender, _pool, sharesToBurn);

    emit WithdrawBase(msg.sender, _pool, _amount, sharesToBurn, _withdrawType);
  }

  function withdrawPool(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(config.feature.WithdrawPool);
    require(_amount <= address(this).balance);
    _withdrawBase(_amount, _pool, WithdrawType.Pool);
    payable(msg.sender).transfer(_amount);
  }

  function withdrawValidator(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(config.feature.WithdrawValidator);
    require(_amount <= beaconBalance);
    beaconBalance -= _amount;
    _withdrawBase(_amount, _pool, WithdrawType.Validator);
    withdrawals.mint(msg.sender, _amount);
  }

  function refundPool() external payable {
    require(msg.sender == router);
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
        hasRole(ORACLE_VALIDATOR_MANAGER_ROLE, msg.sender)
    );
    require(validatorOracles.length > 0);
    _nextValidatorOracle();
  }

  function isValidatorOracle(address _oracleAddress) public view returns (bool) {
    return
      hasRole(ORACLE_VALIDATOR_ROLE, _oracleAddress) &&
      validatorOracles[currentOracleIndex] == _oracleAddress;
  }

  function _nextValidatorOracle() internal {
    require(validatorOracles.length > 1);
    currentOracleIndex = (currentOracleIndex + 1) % validatorOracles.length;
  }

  /*****************
   ** VALIDATORS **
   *****************/

  function setBeaconBalance(uint256 _amount) external {
    require(msg.sender == address(router));
    beaconBalance = _amount;
    emit SetBeaconBalance(_amount);
  }

  function createValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external nonReentrant whenNotPaused {
    require(isValidatorOracle(msg.sender));
    require(address(this).balance >= config.validatorSize);
    require(!validators[_publicKey]);

    validators[_publicKey] = true;
    totalValidators++;

    (uint256[4] memory _shares, ) = fees.estimateFeeFixed(IFees.FeeType.StakeValidator);

    IFees.FeeRole[4] memory roles = fees.getFeesRoles();

    for (uint i = 0; i < _shares.length - 1; i++) {
      if (_shares[i] > 0) {
        _mintRewards(
          fees.getFeeAddress(roles[i]),
          fees.getFeeAddress(IFees.FeeRole.StakeTogether),
          0,
          _shares[i],
          IFees.FeeType.StakeValidator,
          roles[i]
        );
      }
    }

    beaconBalance += validatorSize;

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
    require(msg.sender == address(router));
    require(validators[_publicKey]);

    validators[_publicKey] = false;
    totalValidators--;

    emit RemoveValidator(msg.sender, _epoch, _publicKey, msg.value);
  }
}
