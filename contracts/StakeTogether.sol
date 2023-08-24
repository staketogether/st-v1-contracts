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

/// @title StakeTogether Pool Contract
/// @notice The StakeTogether contract is the primary entry point for interaction with the StakeTogether protocol.
/// It provides functionalities for staking, withdrawals, fee management, and interactions with pools and validators.
/// @custom:security-contact security@staketogether.app
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
  uint256 public withdrawBalance; /// Pending withdraw balance to be withdrawn from router.

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
    beaconBalance = 0;
    withdrawBalance = 0;
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
    emit ReceiveEther(msg.value);
  }

  /************
   ** CONFIG **
   ************/

  /// @notice Sets the configuration for the Stake Together Protocol.
  /// @dev Only callable by the admin role.
  /// @param _config Configuration settings to be applied.
  function setConfig(Config memory _config) public onlyRole(ADMIN_ROLE) {
    require(_config.poolSize >= config.validatorSize, 'IS'); // IS = Invalid Size
    config = _config;
    emit SetConfig(_config);
  }

  /************
   ** SHARES **
   ************/

  /// @notice Returns the total supply of the pool (contract balance + beacon balance).
  /// @return Total supply value.
  function totalSupply() public view override(ERC20Upgradeable, IStakeTogether) returns (uint256) {
    return address(this).balance + beaconBalance - withdrawBalance;
  }

  ///  @notice Calculates the shares amount by wei.
  /// @param _account The address of the account.
  /// @return Balance value of the given account.
  function balanceOf(
    address _account
  ) public view override(ERC20Upgradeable, IStakeTogether) returns (uint256) {
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
  function transfer(
    address _to,
    uint256 _amount
  ) public override(ERC20Upgradeable, IStakeTogether) returns (bool) {
    _transfer(msg.sender, _to, _amount);
    return true;
  }

  /// @notice Transfers tokens from one address to another using an allowance mechanism.
  /// @param _from Address to transfer from.
  /// @param _to Address to transfer to.
  /// @param _amount Amount of tokens to transfer.
  /// @return A boolean value indicating whether the operation succeeded.
  function transferFrom(
    address _from,
    address _to,
    uint256 _amount
  ) public override(ERC20Upgradeable, IStakeTogether) returns (bool) {
    _spendAllowance(_from, msg.sender, _amount);
    _transfer(_from, _to, _amount);
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
  function _transferShares(
    address _from,
    address _to,
    uint256 _sharesAmount
  ) private whenNotPaused nonReentrant {
    require(_from != address(0), 'ZA'); // ZA = Zero Address
    require(_to != address(0), 'ZA'); // ZA = Zero Address
    require(_sharesAmount <= shares[_from], 'IS'); // IS = Insufficient Shares
    shares[_from] -= _sharesAmount;
    shares[_to] += _sharesAmount;
    emit TransferShares(_from, _to, _sharesAmount);
  }

  /// @notice Returns the remaining number of tokens that an spender is allowed to spend on behalf of a token owner.
  /// @param _account Address of the token owner.
  /// @param _spender Address of the spender.
  /// @return A uint256 value representing the remaining number of tokens available for the spender.
  function allowance(
    address _account,
    address _spender
  ) public view override(ERC20Upgradeable, IStakeTogether) returns (uint256) {
    return allowances[_account][_spender];
  }

  /// @notice Sets the amount `_amount` as allowance of `_spender` over the caller's tokens.
  /// @param _spender Address of the spender.
  /// @param _amount Amount of allowance to be set.
  /// @return A boolean value indicating whether the operation succeeded.
  function approve(
    address _spender,
    uint256 _amount
  ) public override(ERC20Upgradeable, IStakeTogether) returns (bool) {
    _approve(msg.sender, _spender, _amount);
    return true;
  }

  /// @notice Internal function to set the approval amount for a given spender and owner.
  /// @param _account Address of the token owner.
  /// @param _spender Address of the spender.
  /// @param _amount Amount of allowance to be set.
  function _approve(address _account, address _spender, uint256 _amount) internal override {
    require(_account != address(0), 'ZA'); // ZA = Zero Address
    require(_spender != address(0), 'ZA'); // ZA = Zero Address
    allowances[_account][_spender] = _amount;
    emit Approval(_account, _spender, _amount);
  }

  /// @notice Increases the allowance granted to `_spender` by the caller.
  /// @param _spender Address of the spender.
  /// @param _addedValue The additional amount to increase the allowance by.
  /// @return A boolean value indicating whether the operation succeeded.
  function increaseAllowance(
    address _spender,
    uint256 _addedValue
  ) public override(ERC20Upgradeable, IStakeTogether) returns (bool) {
    _approve(msg.sender, _spender, allowances[msg.sender][_spender] + _addedValue);
    return true;
  }

  /// @notice Decreases the allowance granted to `_spender` by the caller.
  /// @param _spender Address of the spender.
  /// @param _subtractedValue The amount to subtract from the allowance.
  /// @return A boolean value indicating whether the operation succeeded.
  function decreaseAllowance(
    address _spender,
    uint256 _subtractedValue
  ) public override(ERC20Upgradeable, IStakeTogether) returns (bool) {
    uint256 currentAllowance = allowances[msg.sender][_spender];
    require(currentAllowance >= _subtractedValue, 'IA'); // IA = Insufficient Allowance
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
      require(currentAllowance >= _amount, 'IA'); // IA = Insufficient Allowance
      _approve(_account, _spender, currentAllowance - _amount);
    }
  }

  /// @notice Internal function to mint shares to a given address.
  /// @param _to Address to mint shares to.
  /// @param _sharesAmount Amount of shares to mint.
  function _mintShares(address _to, uint256 _sharesAmount) private whenNotPaused {
    require(_to != address(0), 'ZA'); // ZA = Zero Address
    shares[_to] += _sharesAmount;
    totalShares += _sharesAmount;
    emit MintShares(_to, _sharesAmount);
  }

  /// @notice Internal function to burn shares from a given address.
  /// @param _account Address to burn shares from.
  /// @param _sharesAmount Amount of shares to burn.
  function _burnShares(address _account, uint256 _sharesAmount) private whenNotPaused {
    require(_account != address(0), 'ZA'); // ZA = Zero Address
    require(_sharesAmount <= shares[_account], 'IS'); // IS = Insufficient Shares
    shares[_account] -= _sharesAmount;
    totalShares -= _sharesAmount;
    emit BurnShares(_account, _sharesAmount);
  }

  /***********
   ** STAKE **
   ***********/

  /// @notice Deposits the base amount to the specified address.
  /// @param _to The address to deposit to.
  /// @param _depositType The type of deposit (Pool or Donation).
  /// @param _referral The referral address.
  function _depositBase(address _to, DepositType _depositType, address _referral) private {
    require(config.feature.Deposit, 'FD'); // FD = Feature Disabled
    require(totalSupply() > 0, 'ZS'); // ZS = Zero Supply
    require(msg.value >= config.minDepositAmount, 'MD'); // MD = Min Deposit

    _resetLimits();

    if (msg.value + totalDeposited > config.depositLimit) {
      emit DepositLimitReached(_to, msg.value);
      revert('DLR'); // DLR = Deposit Limit Reached
    }

    _processStakeEntry(_to, msg.value);

    totalDeposited += msg.value;
    emit DepositBase(_to, msg.value, _depositType, _referral);
  }

  /// @notice Deposits into the pool with specific delegations.
  /// @param _delegations The array of delegations for the deposit.
  /// @param _referral The referral address.
  function depositPool(
    Delegation[] memory _delegations,
    address _referral
  ) external payable nonReentrant whenNotPaused {
    _depositBase(msg.sender, DepositType.Pool, _referral);
    _updateDelegations(msg.sender, _delegations);
  }

  /// @notice Deposits a donation to the specified address.
  /// @param _to The address to deposit to.
  /// @param _referral The referral address.
  function depositDonation(address _to, address _referral) external payable nonReentrant whenNotPaused {
    _depositBase(_to, DepositType.Donation, _referral);
  }

  /// @notice Withdraws the base amount with the specified withdrawal type.
  /// @param _amount The amount to withdraw.
  /// @param _withdrawType The type of withdrawal (Pool or Validator).
  function _withdrawBase(uint256 _amount, WithdrawType _withdrawType) private {
    require(_amount > 0, 'ZA'); // ZA = Zero Amount
    require(_amount <= balanceOf(msg.sender), 'IAB'); // IAB = Insufficient Account Balance
    require(_amount >= config.minWithdrawAmount, 'MW'); // MW = Min Withdraw

    _resetLimits();

    if (_amount + totalWithdrawn > config.withdrawalLimit) {
      emit WithdrawalsLimitReached(msg.sender, _amount);
      revert('WLR'); // WLR = Withdrawals Limit Reached
    }

    uint256 sharesToBurn = MathUpgradeable.mulDiv(_amount, shares[msg.sender], balanceOf(msg.sender));
    _burnShares(msg.sender, sharesToBurn);

    totalWithdrawn += _amount;
    emit WithdrawBase(msg.sender, _amount, _withdrawType);
  }

  /// @notice Withdraws from the pool with specific delegations and transfers the funds to the sender.
  /// @param _amount The amount to withdraw.
  /// @param _delegations The array of delegations for the withdrawal.
  function withdrawPool(
    uint256 _amount,
    Delegation[] memory _delegations
  ) external nonReentrant whenNotPaused {
    require(config.feature.WithdrawPool, 'FD'); // FD = Feature Disabled
    require(_amount <= address(this).balance, 'IB'); // IB = Insufficient Balance
    _withdrawBase(_amount, WithdrawType.Pool);
    _updateDelegations(msg.sender, _delegations);
    payable(msg.sender).transfer(_amount);
  }

  /// @notice Withdraws from the validators with specific delegations and mints tokens to the sender.
  /// @param _amount The amount to withdraw.
  /// @param _delegations The array of delegations for the withdrawal.
  function withdrawValidator(
    uint256 _amount,
    Delegation[] memory _delegations
  ) external nonReentrant whenNotPaused {
    require(config.feature.WithdrawValidator, 'FD'); // FD = Feature Disabled
    require(_amount <= beaconBalance, 'IBB'); // IB = Insufficient Beacon Balance
    require(_amount > address(this).balance, 'WFP'); // Withdraw From Pool
    _withdrawBase(_amount, WithdrawType.Validator);
    _setWithdrawBalance(withdrawBalance + _amount);
    _updateDelegations(msg.sender, _delegations);
    withdrawals.mint(msg.sender, _amount);
  }

  /// @notice Resets the daily limits for deposits and withdrawals.
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

  /// @notice Adds a permissionless pool with a specified address and listing status if feature enabled.
  /// @param _pool The address of the pool to add.
  /// @param _listed The listing status of the pool.
  function addPool(address _pool, bool _listed) external payable nonReentrant whenNotPaused {
    require(_pool != address(0), 'ZA'); // ZA = Zero Address
    require(!pools[_pool], 'PE'); // PE = Pool Exists
    if (!hasRole(POOL_MANAGER_ROLE, msg.sender) || msg.value > 0) {
      require(config.feature.AddPool, 'FD'); // FD = Feature Disabled
      require(msg.value == fees[FeeType.StakePool].value, 'IV'); // IV = Invalid Value
      _processStakePool();
    }
    pools[_pool] = true;
    emit AddPool(_pool, _listed, msg.value);
  }

  /// @notice Removes a pool by its address.
  /// @param _pool The address of the pool to remove.
  function removePool(address _pool) external whenNotPaused onlyRole(POOL_MANAGER_ROLE) {
    require(pools[_pool], 'PNF');
    pools[_pool] = false;
    emit RemovePool(_pool);
  }

  /// @notice Updates delegations for the sender's address.
  /// @param _delegations The array of delegations to update.
  function updateDelegations(Delegation[] memory _delegations) external {
    _updateDelegations(msg.sender, _delegations);
  }

  /// @notice Internal function to update delegations for a specific account.
  /// @param _account The address of the account to update delegations for.
  /// @param _delegations The array of delegations to update.
  function _updateDelegations(address _account, Delegation[] memory _delegations) private {
    _validateDelegations(_account, _delegations);
    emit UpdateDelegations(_account, _delegations);
  }

  /// @notice Validates delegations for a specific account.
  /// @param _account The address of the account to validate delegations for.
  /// @param _delegations The array of delegations to validate.
  function _validateDelegations(address _account, Delegation[] memory _delegations) private view {
    if (shares[_account] > 0) {
      require(_delegations.length <= config.maxDelegations, 'MD'); // MD = Max Delegations
      uint256 delegationShares = 0;
      for (uint i = 0; i < _delegations.length; i++) {
        require(pools[_delegations[i].pool], 'PNF'); // PNF = Pool Not Found
        delegationShares += _delegations[i].percentage;
      }
      require(delegationShares == 1 ether, 'IPS'); // IPS = Invalid Percentage Sum
    }
  }

  /***********************
   ** VALIDATORS ORACLE **
   ***********************/

  /// @notice Adds a new validator oracle by its address.
  /// @param _account The address of the validator oracle to add.
  function addValidatorOracle(address _account) external onlyRole(VALIDATOR_ORACLE_MANAGER_ROLE) {
    require(validatorsOracleIndices[_account] == 0, 'VE'); // VE = Validator Exists

    validatorsOracle.push(_account);
    validatorsOracleIndices[_account] = validatorsOracle.length;

    _grantRole(VALIDATOR_ORACLE_ROLE, _account);
    emit AddValidatorOracle(_account);
  }

  /// @notice Removes a validator oracle by its address.
  /// @param _account The address of the validator oracle to remove.
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

  /// @notice Checks if an address is a validator oracle.
  /// @param _account The address to check.
  /// @return True if the address is a validator oracle, false otherwise.
  function isValidatorOracle(address _account) public view returns (bool) {
    return hasRole(VALIDATOR_ORACLE_ROLE, _account) && validatorsOracleIndices[_account] > 0;
  }

  /// @notice Forces the selection of the next validator oracle.
  function forceNextValidatorOracle() external {
    require(
      hasRole(VALIDATOR_ORACLE_SENTINEL_ROLE, msg.sender) ||
        hasRole(VALIDATOR_ORACLE_MANAGER_ROLE, msg.sender),
      'NA'
    );
    _nextValidatorOracle();
  }

  /// @notice Internal function to update the current validator oracle.
  function _nextValidatorOracle() private {
    currentOracleIndex = (currentOracleIndex + 1) % validatorsOracle.length;
    emit NextValidatorOracle(currentOracleIndex, validatorsOracle[currentOracleIndex]);
  }

  /****************
   ** VALIDATORS **
   ****************/

  /// @notice Sets the beacon balance to the specified amount.
  /// @param _amount The amount to set as the beacon balance.
  /// @dev Only the router address can call this function.
  function setBeaconBalance(uint256 _amount) external payable nonReentrant {
    require(msg.sender == address(router), 'OR'); // Only Router
    _setBeaconBalance(_amount);
  }

  /// @notice Internal function to set the beacon balance.
  /// @param _amount The amount to set as the beacon balance.
  function _setBeaconBalance(uint256 _amount) private {
    beaconBalance = _amount;
    emit SetBeaconBalance(_amount);
  }

  /// @notice Sets the pending withdraw balance to the specified amount.
  /// @param _amount The amount to set as the pending withdraw balance.
  /// @dev Only the router address can call this function.
  function setWithdrawBalance(uint256 _amount) external payable nonReentrant {
    require(msg.sender == address(router), 'OR'); // Only Router
    _setWithdrawBalance(_amount);
  }

  /// @notice Internal function to set the pending withdraw balance.
  /// @param _amount The amount to set as the pending withdraw balance.
  function _setWithdrawBalance(uint256 _amount) private {
    withdrawBalance = _amount;
    emit SetWithdrawBalance(_amount);
  }

  /// @notice Creates a new validator with the given parameters.
  /// @param _publicKey The public key of the validator.
  /// @param _signature The signature of the validator.
  /// @param _depositDataRoot The deposit data root for the validator.
  /// @dev Only a valid validator oracle can call this function.
  function createValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external nonReentrant whenNotPaused {
    require(isValidatorOracle(msg.sender), 'OV');
    require(address(this).balance >= config.poolSize, 'NBP');
    require(!validators[_publicKey], 'VE');
    _processStakeValidator();
    _setBeaconBalance(beaconBalance + config.validatorSize);
    _nextValidatorOracle();
    validators[_publicKey] = true;
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

  /*************
   ** Airdrop **
   *************/

  /// @notice Function to claim rewards by transferring shares, accessible only by the airdrop fee address.
  /// @param _account Address to transfer the claimed rewards to.
  /// @param _sharesAmount Amount of shares to claim as rewards.
  function claimAirdrop(address _account, uint256 _sharesAmount) external whenNotPaused {
    address airdropFee = getFeeAddress(FeeRole.Airdrop);
    require(msg.sender == airdropFee, 'OA'); // OA = Only Airdrop
    _transferShares(airdropFee, _account, _sharesAmount);
  }

  /*****************
   **    FEES     **
   *****************/

  /// @notice Returns an array of fee roles.
  /// @return roles An array of FeeRole.
  function getFeesRoles() public pure returns (FeeRole[4] memory) {
    return [FeeRole.Airdrop, FeeRole.Operator, FeeRole.StakeTogether, FeeRole.Sender];
  }

  /// @notice Sets the fee address for a given role.
  /// @param _role The role for which the address will be set.
  /// @param _address The address to set.
  /// @dev Only an admin can call this function.
  function setFeeAddress(FeeRole _role, address payable _address) external onlyRole(ADMIN_ROLE) {
    feesRole[_role] = _address;
    emit SetFeeAddress(_role, _address);
  }

  /// @notice Gets the fee address for a given role.
  /// @param _role The role for which the address will be retrieved.
  /// @return The address associated with the given role.
  function getFeeAddress(FeeRole _role) public view returns (address) {
    return feesRole[_role];
  }

  /// @notice Sets the fee for a given fee type.
  /// @param _feeType The type of fee to set.
  /// @param _value The value of the fee.
  /// @param _allocations The allocations for the fee.
  /// @dev Only an admin can call this function.
  function setFee(
    FeeType _feeType,
    uint256 _value,
    uint256[] calldata _allocations
  ) external onlyRole(ADMIN_ROLE) {
    require(_allocations.length == 4, 'IL'); // IL = Invalid Length
    uint256 sum = 0;
    for (uint256 i = 0; i < _allocations.length; i++) {
      fees[_feeType].allocations[FeeRole(i)] = _allocations[i];
      sum += _allocations[i];
    }

    require(sum == 1 ether, 'IS'); // IS = Invalid Sum

    fees[_feeType].value = _value;

    emit SetFee(_feeType, _value, _allocations);
  }

  /// @notice Distributes fees according to their type, amount, and the destination.
  /// @param _feeType The type of fee being distributed.
  /// @param _sharesAmount The total shares amount for the fee.
  /// @param _to The address to distribute the fees.
  /// @dev This function computes how the fees are allocated to different roles.
  function _distributeFees(FeeType _feeType, uint256 _sharesAmount, address _to) private {
    uint256[4] memory allocatedShares;
    FeeRole[4] memory roles = getFeesRoles();

    uint256 feeValue = fees[_feeType].value;
    uint256 feeShares = MathUpgradeable.mulDiv(_sharesAmount, feeValue, 1 ether);
    uint256 totalAllocatedShares = 0;

    for (uint256 i = 0; i < roles.length - 1; i++) {
      uint256 allocation = fees[_feeType].allocations[roles[i]];
      allocatedShares[i] = MathUpgradeable.mulDiv(feeShares, allocation, 1 ether);
      totalAllocatedShares += allocatedShares[i];
    }

    allocatedShares[3] = _sharesAmount - totalAllocatedShares;

    uint length = (_feeType == FeeType.StakeEntry) ? roles.length : roles.length - 1;

    for (uint i = 0; i < length; i++) {
      if (allocatedShares[i] > 0) {
        if (_feeType == FeeType.StakeEntry && roles[i] == FeeRole.Sender) {
          _mintShares(_to, allocatedShares[i]);
        } else {
          _mintShares(getFeeAddress(roles[i]), allocatedShares[i]);
          emit MintFeeShares(getFeeAddress(roles[i]), allocatedShares[i], _feeType, roles[i]);
        }
      }
    }
  }

  /// @notice Processes a stake entry and distributes the associated fees.
  /// @param _to The address to receive the stake entry.
  /// @param _amount The amount staked.
  /// @dev Calls the distributeFees function internally.
  function _processStakeEntry(address _to, uint256 _amount) private {
    uint256 sharesAmount = MathUpgradeable.mulDiv(_amount, totalShares, totalSupply() - _amount);
    _distributeFees(FeeType.StakeEntry, sharesAmount, _to);
  }

  /// @notice Process staking rewards and distributes the rewards based on shares.
  /// @param _sharesAmount The amount of shares related to the staking rewards.
  /// @dev Requires the caller to be the router contract. This function will also emit the ProcessStakeRewards event.
  function processStakeRewards(uint256 _sharesAmount) external payable nonReentrant whenNotPaused {
    require(msg.sender == address(router), 'OR'); // OR = Only Router
    _distributeFees(FeeType.ProcessStakeRewards, _sharesAmount, address(0));
    emit ProcessStakeRewards(msg.value, _sharesAmount);
  }

  /// @notice Processes the staking pool fee and distributes it accordingly.
  /// @dev Calculates the shares amount and then distributes the staking pool fee.
  function _processStakePool() private {
    uint256 amount = fees[FeeType.StakePool].value;
    uint256 sharesAmount = MathUpgradeable.mulDiv(amount, totalShares, totalSupply() - amount);
    _distributeFees(FeeType.StakePool, sharesAmount, address(0));
  }

  /// @notice Transfers the staking validator fee to the operator role.
  /// @dev Transfers the associated amount to the Operator's address.
  function _processStakeValidator() private {
    emit ProcessStakeValidator(
      getFeeAddress(FeeRole.Operator),
      fees[FeeType.ProcessStakeValidator].value
    );
    payable(getFeeAddress(FeeRole.Operator)).transfer(fees[FeeType.ProcessStakeValidator].value);
  }
}
