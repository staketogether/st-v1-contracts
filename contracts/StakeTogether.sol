// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol';

import './Withdrawals.sol';

import './interfaces/IStakeTogether.sol';
import './interfaces/IDepositContract.sol';

/// @custom:security-contact security@staketogether.app
/// @title StakeTogether Pool Contract
/// @notice The StakeTogether contract is the primary entry point for interaction with the StakeTogether protocol.
/// It provides functionalities for staking, withdrawals, fee management, and interactions with pools and validators.
contract StakeTogether is
  Initializable,
  ERC20Upgradeable,
  ERC20BurnableUpgradeable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  ERC20PermitUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuardUpgradeable,
  IStakeTogether
{
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE'); /// Role for managing upgrades.
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE'); /// Role for administration.
  bytes32 public constant POOL_MANAGER_ROLE = keccak256('POOL_MANAGER_ROLE'); /// Role for managing pools.
  bytes32 public constant VALIDATOR_ORACLE_ROLE = keccak256('VALIDATOR_ORACLE_ROLE'); /// Role for managing validator oracles.
  bytes32 public constant VALIDATOR_ORACLE_MANAGER_ROLE = keccak256('VALIDATOR_ORACLE_MANAGER_ROLE'); /// Role for managing validator oracle managers.
  bytes32 public constant VALIDATOR_ORACLE_SENTINEL_ROLE = keccak256('VALIDATOR_ORACLE_SENTINEL_ROLE'); /// Role for sentinel functionality in validator oracle management.

  uint256 public version; /// Contract version.

  address public router; /// Address of the contract router.
  Withdrawals public withdrawals; /// Withdrawals contract instance.
  IDepositContract public depositContract; /// Deposit contract interface.

  bytes public withdrawalCredentials; /// Credentials for withdrawals.
  uint256 public beaconBalance; /// Beacon balance (includes transient Beacon balance on router).
  Config public config; /// Configuration settings for the protocol.

  mapping(address => uint256) public shares; /// Mapping of addresses to their shares.
  uint256 public totalShares; /// Total number of shares.
  mapping(address => mapping(address => uint256)) private allowances; /// Allowances mapping.

  uint256 public lastResetBlock; /// Block number of the last reset.
  uint256 public totalDeposited; /// Total amount deposited.
  uint256 public totalWithdrawn; /// Total amount withdrawn.

  mapping(address => bool) public pools; /// Mapping of pool addresses.

  address[] private validatorsOracle; /// List of validator oracles.
  mapping(address => uint256) private validatorsOracleIndices; /// Mapping of validator oracle indices.
  uint256 public currentOracleIndex; /// Current index of the oracle.

  mapping(bytes => bool) public validators; /// Mapping of validators.
  uint256 public totalValidators; /// Total number of validators.

  mapping(FeeRole => address payable) private feesRole; /// Mapping of fee roles to addresses.
  mapping(FeeType => Fee) private fees; /// Mapping of fee types to fee details.

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Stake Together Pool Initialization
  /// @param _router The address of the router.
  /// @param _withdrawals The address of the withdrawals contract.
  /// @param _depositContract The address of the deposit contract.
  /// @param _withdrawalCredentials The bytes for withdrawal credentials.
  function initialize(
    address _router,
    address _withdrawals,
    address _depositContract,
    bytes memory _withdrawalCredentials
  ) public initializer {
    __ERC20_init('Stake Together Pool', 'stpETH');
    __ERC20Burnable_init();
    __Pausable_init();
    __AccessControl_init();
    __ERC20Permit_init('Stake Together Pool');
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);
    _grantRole(POOL_MANAGER_ROLE, msg.sender);

    version = 1;

    router = _router;
    withdrawals = Withdrawals(payable(_withdrawals));
    depositContract = IDepositContract(_depositContract);
    withdrawalCredentials = _withdrawalCredentials;

    totalShares = 0;
    totalValidators = 0;
    beaconBalance = 0;
    currentOracleIndex = 0;

    _mintShares(address(this), 1 ether);
  }

  /// @notice Pauses the contract, preventing certain actions.
  /// @dev Only callable by the admin role.
  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  /// @notice Unpauses the contract, allowing actions to resume.
  /// @dev Only callable by the admin role.
  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  /// @notice Internal function to authorize an upgrade.
  /// @dev Only callable by the upgrader role.
  /// @param _newImplementation Address of the new contract implementation.
  function _authorizeUpgrade(address _newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  /// @notice Receive function to accept incoming ETH transfers.
  /// @dev Non-reentrant to prevent re-entrancy attacks.
  receive() external payable nonReentrant {
    emit ReceiveEther(msg.sender, msg.value);
  }

  /************
   ** CONFIG **
   ************/

  /// @notice Sets the configuration for the Stake Together Protocol.
  /// @dev Only callable by the admin role.
  /// @param _config Configuration settings to be applied.
  function setConfig(Config memory _config) public onlyRole(ADMIN_ROLE) {
    require(_config.poolSize >= config.validatorSize, 'IS');
    config = _config;
    emit SetConfig(_config);
  }

  /************
   ** SHARES **
   ************/

  /// @notice Returns the total supply of the pool (contract balance + beacon balance).
  /// @return Total supply value.
  function totalSupply() public view override returns (uint256) {
    return address(this).balance + beaconBalance;
  }

  ///  @notice Calculates the shares amount by wei.
  /// @param _account The address of the account.
  /// @return Balance value of the given account.
  function balanceOf(address _account) public view override returns (uint256) {
    return weiByShares(shares[_account]);
  }

  /// @notice Calculates the wei amount by shares.
  /// @param _sharesAmount Amount of shares.
  /// @return Equivalent amount in wei.
  function weiByShares(uint256 _sharesAmount) public view returns (uint256) {
    return MathUpgradeable.mulDiv(_sharesAmount, totalSupply(), totalShares, MathUpgradeable.Rounding.Up);
  }

  /// @notice Calculates the shares amount by wei.
  /// @param _amount Amount in wei.
  /// @return Equivalent amount in shares.
  function sharesByWei(uint256 _amount) public view returns (uint256) {
    return MathUpgradeable.mulDiv(_amount, totalShares, totalSupply());
  }

  /// @notice Transfers an amount of wei to the specified address.
  /// @param _to The address to transfer to.
  /// @param _amount The amount to be transferred.
  /// @return True if the transfer was successful.
  function transfer(address _to, uint256 _amount) public override returns (bool) {
    _transfer(msg.sender, _to, _amount);
    return true;
  }

  /// @notice Transfers an amount of wei from one address to another.
  /// @param _from The address to transfer from.
  /// @param _to The address to transfer to.
  /// @param _amount The amount to be transferred.
  function _transfer(address _from, address _to, uint256 _amount) internal override {
    uint256 _sharesToTransfer = sharesByWei(_amount);
    _transferShares(_from, _to, _sharesToTransfer);
    emit Transfer(_from, _to, _amount);
  }

  /// @notice Transfers a number of shares to the specified address.
  /// @param _to The address to transfer to.
  /// @param _sharesAmount The number of shares to be transferred.
  /// @return Equivalent amount in wei.
  function transferShares(address _to, uint256 _sharesAmount) public returns (uint256) {
    _transferShares(msg.sender, _to, _sharesAmount);
    return weiByShares(_sharesAmount);
  }

  /// @notice Internal function to handle the transfer of shares.
  /// @param _from The address to transfer from.
  /// @param _to The address to transfer to.
  /// @param _sharesAmount The number of shares to be transferred.
  function _transferShares(address _from, address _to, uint256 _sharesAmount) private whenNotPaused {
    require(_from != address(0), 'ZA');
    require(_to != address(0), 'ZA');
    require(_sharesAmount <= shares[_from], 'IS');
    shares[_from] -= _sharesAmount;
    shares[_to] += _sharesAmount;
    emit TransferShares(_from, _to, _sharesAmount);
  }

  /// @notice Transfers tokens from one address to another using an allowance mechanism.
  /// @param _from Address to transfer from.
  /// @param _to Address to transfer to.
  /// @param _amount Amount of tokens to transfer.
  /// @return A boolean value indicating whether the operation succeeded.
  function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
    _spendAllowance(_from, msg.sender, _amount);
    _transfer(_from, _to, _amount);
    return true;
  }

  /// @notice Returns the remaining number of tokens that an spender is allowed to spend on behalf of a token owner.
  /// @param _account Address of the token owner.
  /// @param _spender Address of the spender.
  /// @return A uint256 value representing the remaining number of tokens available for the spender.
  function allowance(address _account, address _spender) public view override returns (uint256) {
    return allowances[_account][_spender];
  }

  /// @notice Sets the amount `_amount` as allowance of `_spender` over the caller's tokens.
  /// @param _spender Address of the spender.
  /// @param _amount Amount of allowance to be set.
  /// @return A boolean value indicating whether the operation succeeded.
  function approve(address _spender, uint256 _amount) public override returns (bool) {
    _approve(msg.sender, _spender, _amount);
    return true;
  }

  /// @notice Internal function to set the approval amount for a given spender and owner.
  /// @param _account Address of the token owner.
  /// @param _spender Address of the spender.
  /// @param _amount Amount of allowance to be set.
  function _approve(address _account, address _spender, uint256 _amount) internal override {
    require(_account != address(0), 'ZA');
    require(_spender != address(0), 'ZA');
    allowances[_account][_spender] = _amount;
    emit Approval(_account, _spender, _amount);
  }

  /// @notice Increases the allowance granted to `_spender` by the caller.
  /// @param _spender Address of the spender.
  /// @param _addedValue The additional amount to increase the allowance by.
  /// @return A boolean value indicating whether the operation succeeded.
  function increaseAllowance(address _spender, uint256 _addedValue) public override returns (bool) {
    _approve(msg.sender, _spender, allowances[msg.sender][_spender] + _addedValue);
    return true;
  }

  /// @notice Decreases the allowance granted to `_spender` by the caller.
  /// @param _spender Address of the spender.
  /// @param _subtractedValue The amount to subtract from the allowance.
  /// @return A boolean value indicating whether the operation succeeded.
  function decreaseAllowance(address _spender, uint256 _subtractedValue) public override returns (bool) {
    uint256 currentAllowance = allowances[msg.sender][_spender];
    require(currentAllowance >= _subtractedValue, 'IA');
    _approve(msg.sender, _spender, currentAllowance - _subtractedValue);
    return true;
  }

  /// @notice Internal function to deduct the allowance for a given spender, if any.
  /// @param _account Address of the token owner.
  /// @param _spender Address of the spender.
  /// @param _amount Amount to be deducted from the allowance.
  function _spendAllowance(address _account, address _spender, uint256 _amount) internal override {
    uint256 currentAllowance = allowances[_account][_spender];
    if (currentAllowance != ~uint256(0)) {
      require(currentAllowance >= _amount, 'IA');
      _approve(_account, _spender, currentAllowance - _amount);
    }
  }

  /// @notice Internal function to mint shares to a given address.
  /// @param _to Address to mint shares to.
  /// @param _sharesAmount Amount of shares to mint.
  function _mintShares(address _to, uint256 _sharesAmount) private whenNotPaused {
    require(_to != address(0), 'ZA');
    shares[_to] += _sharesAmount;
    totalShares += _sharesAmount;
    emit MintShares(_to, _sharesAmount);
  }

  /// @notice Internal function to burn shares from a given address.
  /// @param _account Address to burn shares from.
  /// @param _sharesAmount Amount of shares to burn.
  function _burnShares(address _account, uint256 _sharesAmount) private whenNotPaused {
    require(_account != address(0), 'ZA');
    require(_sharesAmount <= shares[_account], 'IS');
    shares[_account] -= _sharesAmount;
    totalShares -= _sharesAmount;
    emit BurnShares(_account, _sharesAmount);
  }

  /*************
   ** REWARDS **
   *************/

  /// @notice Internal function to mint rewards as shares to a given address.
  /// @param _address Address to mint rewards to.
  /// @param _sharesAmount Amount of reward shares to mint.
  /// @param _feeType Type of fee associated with the minting.
  /// @param _feeRole Role of the fee within the system.
  function _mintRewards(
    address _address,
    uint256 _sharesAmount,
    FeeType _feeType,
    FeeRole _feeRole
  ) private {
    _mintShares(_address, _sharesAmount);
    emit MintRewards(_address, _sharesAmount, _feeType, _feeRole);
  }

  /// @notice Function to mint rewards to a given address, accessible only by the router.
  /// @param _address Address to mint rewards to.
  /// @param _sharesAmount Amount of reward shares to mint.
  /// @param _feeType Type of fee associated with the minting.
  /// @param _feeRole Role of the fee within the system.
  function mintRewards(
    address _address,
    uint256 _sharesAmount,
    FeeType _feeType,
    FeeRole _feeRole
  ) public payable nonReentrant {
    require(msg.sender == router, 'OR');
    _mintRewards(_address, _sharesAmount, _feeType, _feeRole);
  }

  /// @notice Function to claim rewards by transferring shares, accessible only by the airdrop fee address.
  /// @param _account Address to transfer the claimed rewards to.
  /// @param _sharesAmount Amount of shares to claim as rewards.
  function claimRewards(address _account, uint256 _sharesAmount) external nonReentrant whenNotPaused {
    address airdropFee = getFeeAddress(FeeRole.Airdrop);
    require(msg.sender == airdropFee, 'OA');
    _transferShares(airdropFee, _account, _sharesAmount);
    emit ClaimRewards(_account, _sharesAmount);
  }

  /***********
   ** STAKE **
   ***********/

  function _depositBase(address _to, DepositType _depositType, address _referral) private {
    require(config.feature.Deposit, 'FD');
    require(msg.value >= config.minDepositAmount, 'MD');

    _resetLimits();

    if (msg.value + totalDeposited > config.depositLimit) {
      emit DepositLimitReached(_to, msg.value);
      revert('DLR');
    }

    uint256 sharesAmount = MathUpgradeable.mulDiv(msg.value, totalShares, totalSupply() - msg.value);

    (uint256[4] memory _shares, ) = _estimaFee(FeeType.StakeEntry, sharesAmount);

    FeeRole[4] memory roles = getFeesRoles();
    for (uint i = 0; i < roles.length; i++) {
      if (_shares[i] > 0) {
        if (roles[i] == FeeRole.Sender) {
          _mintShares(_to, _shares[i]);
        } else {
          _mintRewards(getFeeAddress(roles[i]), _shares[i], FeeType.StakeEntry, roles[i]);
        }
      }
    }

    totalDeposited += msg.value;
    emit DepositBase(_to, msg.value, _depositType, _referral);
  }

  function depositPool(
    Delegation[] memory _delegations,
    address _referral
  ) external payable nonReentrant whenNotPaused {
    _depositBase(msg.sender, DepositType.Pool, _referral);
    _updateDelegations(msg.sender, _delegations);
  }

  function depositDonation(address _to, address _referral) external payable nonReentrant whenNotPaused {
    _depositBase(_to, DepositType.Donation, _referral);
  }

  function _withdrawBase(uint256 _amount, WithdrawType _withdrawType) private {
    require(_amount > 0, 'ZA');
    require(_amount <= balanceOf(msg.sender), 'IAB');
    require(_amount >= config.minWithdrawAmount, 'MW');

    _resetLimits();

    if (_amount + totalWithdrawn > config.withdrawalLimit) {
      emit WithdrawalsLimitReached(msg.sender, _amount);
      revert('WLR');
    }

    uint256 sharesToBurn = MathUpgradeable.mulDiv(_amount, shares[msg.sender], balanceOf(msg.sender));
    _burnShares(msg.sender, sharesToBurn);

    totalWithdrawn += _amount;
    emit WithdrawBase(msg.sender, _amount, _withdrawType);
  }

  function withdrawPool(
    uint256 _amount,
    Delegation[] memory _delegations
  ) external nonReentrant whenNotPaused {
    require(config.feature.WithdrawPool, 'FD');
    require(_amount <= address(this).balance, 'IB');
    _withdrawBase(_amount, WithdrawType.Pool);
    _updateDelegations(msg.sender, _delegations);
    payable(msg.sender).transfer(_amount);
  }

  function withdrawValidator(
    uint256 _amount,
    Delegation[] memory _delegations
  ) external nonReentrant whenNotPaused {
    require(config.feature.WithdrawValidator, 'FD');
    require(_amount <= beaconBalance, 'IB');
    _withdrawBase(_amount, WithdrawType.Validator);
    _updateDelegations(msg.sender, _delegations);
    _setBeaconBalance(beaconBalance - _amount);
    withdrawals.mint(msg.sender, _amount);
  }

  function withdrawRefund() external payable {
    require(msg.sender == router, 'OR');
    _setBeaconBalance(beaconBalance - msg.value);
    emit WithdrawRefund(msg.sender, msg.value);
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

  function addPool(address _pool, bool _listed) external payable nonReentrant {
    require(_pool != address(0), 'ZA');
    require(!pools[_pool], 'PE');
    if (!hasRole(POOL_MANAGER_ROLE, msg.sender)) {
      require(config.feature.AddPool, 'FD');
      (uint256[4] memory _shares, ) = estimateFeeFixed(FeeType.StakePool);
      FeeRole[4] memory roles = getFeesRoles();
      for (uint i = 0; i < roles.length - 1; i++) {
        _mintRewards(getFeeAddress(roles[i]), _shares[i], FeeType.StakePool, roles[i]);
      }
    }
    pools[_pool] = true;
    emit AddPool(_pool, _listed, msg.value);
  }

  function removePool(address _pool) external onlyRole(POOL_MANAGER_ROLE) {
    require(pools[_pool], 'PNF');
    pools[_pool] = false;
    emit RemovePool(_pool);
  }

  function updateDelegations(Delegation[] memory _delegations) external {
    _updateDelegations(msg.sender, _delegations);
  }

  function _updateDelegations(address _account, Delegation[] memory _delegations) private {
    _validateDelegations(_account, _delegations);
    emit UpdateDelegations(_account, _delegations);
  }

  function _validateDelegations(address _account, Delegation[] memory _delegations) private view {
    if (shares[_account] > 0) {
      require(_delegations.length <= config.maxDelegations, 'MD');
      uint256 delegationShares = 0;
      for (uint i = 0; i < _delegations.length; i++) {
        require(pools[_delegations[i].pool], 'PNF');
        delegationShares += _delegations[i].shares;
      }
      require(delegationShares == shares[_account], 'IS');
    }
  }

  /***********************
   ** VALIDATORS ORACLE **
   ***********************/

  function addValidatorOracle(address _account) external onlyRole(VALIDATOR_ORACLE_MANAGER_ROLE) {
    _grantRole(VALIDATOR_ORACLE_ROLE, _account);
    validatorsOracle.push(_account);
    validatorsOracleIndices[_account] = validatorsOracle.length;
    emit AddValidatorOracle(_account);
  }

  function removeValidatorOracle(address _account) external onlyRole(VALIDATOR_ORACLE_MANAGER_ROLE) {
    require(validatorsOracleIndices[_account] > 0, 'NF');

    uint256 index = validatorsOracleIndices[_account] - 1;

    if (index < validatorsOracle.length - 1) {
      address lastAddress = validatorsOracle[validatorsOracle.length - 1];
      validatorsOracle[index] = lastAddress;
      validatorsOracleIndices[lastAddress] = index + 1;
    }

    validatorsOracle.pop();

    delete validatorsOracleIndices[_account];
    _revokeRole(VALIDATOR_ORACLE_ROLE, _account);
    emit RemoveValidatorOracle(_account);
  }

  function isValidatorOracle(address _account) public view returns (bool) {
    return hasRole(VALIDATOR_ORACLE_ROLE, _account) && validatorsOracleIndices[_account] > 0;
  }

  function forceNextValidatorOracle() external {
    require(
      hasRole(VALIDATOR_ORACLE_SENTINEL_ROLE, msg.sender) ||
        hasRole(VALIDATOR_ORACLE_MANAGER_ROLE, msg.sender),
      'NA'
    );
    _nextValidatorOracle();
  }

  function _nextValidatorOracle() private {
    currentOracleIndex = (currentOracleIndex + 1) % validatorsOracle.length;
    emit NextValidatorOracle(currentOracleIndex, validatorsOracle[currentOracleIndex]);
  }

  /****************
   ** VALIDATORS **
   ****************/

  function setBeaconBalance(uint256 _amount) external {
    require(msg.sender == address(router), 'OR');
    _setBeaconBalance(_amount);
  }

  function _setBeaconBalance(uint256 _amount) private {
    beaconBalance = _amount;
    emit SetBeaconBalance(_amount);
  }

  function createValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external nonReentrant whenNotPaused {
    require(isValidatorOracle(msg.sender), 'OV');
    require(address(this).balance >= config.poolSize, 'NBP');
    require(!validators[_publicKey], 'VE');
    (uint256[4] memory _shares, ) = estimateFeeFixed(FeeType.StakeValidator);
    FeeRole[4] memory roles = getFeesRoles();
    for (uint i = 0; i < _shares.length - 1; i++) {
      if (_shares[i] > 0) {
        _mintRewards(getFeeAddress(roles[i]), _shares[i], FeeType.StakeValidator, roles[i]);
      }
    }
    _setBeaconBalance(beaconBalance + config.validatorSize);
    validators[_publicKey] = true;
    totalValidators++;
    _nextValidatorOracle();
    depositContract.deposit{ value: config.validatorSize }(
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );
    emit CreateValidator(
      msg.sender,
      config.validatorSize,
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );
  }

  function removeValidator(uint256 _epoch, bytes calldata _publicKey) external {
    require(msg.sender == address(router), 'OR');
    require(validators[_publicKey], 'NF');
    validators[_publicKey] = false;
    totalValidators--;
    emit RemoveValidator(msg.sender, _epoch, _publicKey);
  }

  /*****************
   **    FEES     **
   *****************/

  function getFeesRoles() public pure returns (FeeRole[4] memory) {
    FeeRole[4] memory roles = [FeeRole.Airdrop, FeeRole.Operator, FeeRole.StakeTogether, FeeRole.Sender];
    return roles;
  }

  function setFeeAddress(FeeRole _role, address payable _address) external onlyRole(ADMIN_ROLE) {
    feesRole[_role] = _address;
    emit SetFeeAddress(_role, _address);
  }

  function getFeeAddress(FeeRole _role) public view returns (address) {
    return feesRole[_role];
  }

  function setFee(
    FeeType _feeType,
    uint256 _value,
    FeeMath _mathType,
    uint256[] calldata _allocations
  ) external onlyRole(ADMIN_ROLE) {
    require(_allocations.length == 4, 'IL');

    uint256 sum = 0;
    for (uint256 i = 0; i < _allocations.length; i++) {
      fees[_feeType].allocations[FeeRole(i)] = _allocations[i];
      sum += _allocations[i];
    }

    require(sum == 1 ether, 'SI');

    fees[_feeType].value = _value;
    fees[_feeType].mathType = _mathType;

    emit SetFee(_feeType, _value, _mathType, _allocations);
  }

  /*******************
   ** ESTIMATE FEES **
   *******************/

  function estimateFeePercentage(
    FeeType _feeType,
    uint256 _amount
  ) public view returns (uint256[4] memory _shares, uint256[4] memory _amounts) {
    require(fees[_feeType].mathType == FeeMath.PERCENTAGE);
    uint256 sharesAmount = sharesByWei(_amount);
    return _estimaFee(_feeType, sharesAmount);
  }

  function estimateFeeFixed(
    FeeType _feeType
  ) public view returns (uint256[4] memory _shares, uint256[4] memory _amounts) {
    require(fees[_feeType].mathType == FeeMath.FIXED);
    return _estimaFee(_feeType, fees[_feeType].value);
  }

  function _estimaFee(
    FeeType _feeType,
    uint256 _sharesAmount
  ) private view returns (uint256[4] memory _shares, uint256[4] memory _amounts) {
    FeeRole[4] memory roles = getFeesRoles();

    uint256 feeValue = fees[_feeType].value;
    uint256 feeShares = MathUpgradeable.mulDiv(_sharesAmount, feeValue, 1 ether);
    uint256 totalAllocatedShares = 0;

    for (uint256 i = 0; i < roles.length - 1; i++) {
      uint256 allocation = fees[_feeType].allocations[roles[i]];
      _shares[i] = MathUpgradeable.mulDiv(feeShares, allocation, 1 ether);
      totalAllocatedShares += _shares[i];
    }

    _shares[3] = _sharesAmount - totalAllocatedShares;

    for (uint256 i = 0; i < roles.length; i++) {
      _amounts[i] = weiByShares(_shares[i]);
    }

    return (_shares, _amounts);
  }
}
