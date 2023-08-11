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
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant POOL_MANAGER_ROLE = keccak256('POOL_MANAGER_ROLE');
  bytes32 public constant ORACLE_VALIDATOR_ROLE = keccak256('ORACLE_VALIDATOR_ROLE');
  bytes32 public constant ORACLE_VALIDATOR_MANAGER_ROLE = keccak256('ORACLE_VALIDATOR_MANAGER_ROLE');
  bytes32 public constant ORACLE_VALIDATOR_SENTINEL_ROLE = keccak256('ORACLE_VALIDATOR_SENTINEL_ROLE');

  uint256 public version;

  address public router;
  Withdrawals public withdrawals;
  IDepositContract public deposit;

  bytes public withdrawalCredentials;
  uint256 public beaconBalance;
  Config public config;

  mapping(address => uint256) public shares;
  uint256 public totalShares;
  mapping(address => mapping(address => uint256)) private allowances;

  uint256 public lastResetBlock;
  uint256 public totalDeposited;
  uint256 public totalWithdrawn;

  mapping(address => bool) internal pools;

  address[] public validatorOracles;
  uint256 public currentOracleIndex;

  mapping(bytes => bool) public validators;
  uint256 public totalValidators;
  uint256 public validatorSize;

  mapping(FeeRole => address payable) public roleAddresses;
  mapping(FeeType => Fee) public fees;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
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
    require(_config.poolSize >= config.validatorSize, 'PSS');
    config = _config;
    emit SetConfig(_config);
  }

  /************
   ** SHARES **
   ************/

  function totalSupply() public view override returns (uint256) {
    return address(this).balance + beaconBalance;
  }

  function balanceOf(address _account) public view override returns (uint256) {
    return pooledEthByShares(shares[_account]);
  }

  function sharesByPooledEth(uint256 _amount) public view returns (uint256) {
    return MathUpgradeable.mulDiv(_amount, totalShares, totalSupply());
  }

  function pooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
    return MathUpgradeable.mulDiv(_sharesAmount, totalSupply(), totalShares, MathUpgradeable.Rounding.Up);
  }

  function transfer(address _to, uint256 _amount) public override returns (bool) {
    _transfer(msg.sender, _to, _amount);
    return true;
  }

  function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
    _spendAllowance(_from, msg.sender, _amount);
    _transfer(_from, _to, _amount);

    return true;
  }

  function transferShares(address _to, uint256 _sharesAmount) public returns (uint256) {
    _transferShares(msg.sender, _to, _sharesAmount);
    uint256 tokensAmount = pooledEthByShares(_sharesAmount);
    return tokensAmount;
  }

  function allowance(address _account, address _spender) public view override returns (uint256) {
    return allowances[_account][_spender];
  }

  function approve(address _spender, uint256 _amount) public override returns (bool) {
    _approve(msg.sender, _spender, _amount);
    return true;
  }

  function increaseAllowance(address _spender, uint256 _addedValue) public override returns (bool) {
    _approve(msg.sender, _spender, allowances[msg.sender][_spender] + _addedValue);
    return true;
  }

  function decreaseAllowance(address _spender, uint256 _subtractedValue) public override returns (bool) {
    uint256 currentAllowance = allowances[msg.sender][_spender];
    require(currentAllowance >= _subtractedValue, 'ATL');
    _approve(msg.sender, _spender, currentAllowance - _subtractedValue);
    return true;
  }

  function _approve(address _account, address _spender, uint256 _amount) internal override {
    require(_account != address(0), 'ZA');
    require(_spender != address(0), 'ZA');

    allowances[_account][_spender] = _amount;
    emit Approval(_account, _spender, _amount);
  }

  function _mintShares(address _to, uint256 _sharesAmount) internal whenNotPaused {
    require(_to != address(0), 'ZA');

    shares[_to] = shares[_to] + _sharesAmount;
    totalShares += _sharesAmount;

    emit MintShares(_to, _sharesAmount);
  }

  function _burnShares(address _account, uint256 _sharesAmount) internal whenNotPaused {
    require(_account != address(0), 'ZA');
    require(_sharesAmount <= shares[_account], 'BAH');

    shares[_account] = shares[_account] - _sharesAmount;
    totalShares -= _sharesAmount;

    emit BurnShares(_account, _sharesAmount);
  }

  function _transfer(address _from, address _to, uint256 _amount) internal override whenNotPaused {
    uint256 _sharesToTransfer = sharesByPooledEth(_amount);
    _transferShares(_from, _to, _sharesToTransfer);
    emit Transfer(_from, _to, _amount);
  }

  function _transferShares(address _from, address _to, uint256 _sharesAmount) internal whenNotPaused {
    require(_from != address(0), 'ZA');
    require(_to != address(0), 'ZA');
    require(_sharesAmount <= shares[_from], 'TAH');
    shares[_from] = shares[_from] - _sharesAmount;
    shares[_to] = shares[_to] + _sharesAmount;
    emit TransferShares(_from, _to, _sharesAmount);
  }

  function _spendAllowance(address _account, address _spender, uint256 _amount) internal override {
    uint256 currentAllowance = allowances[_account][_spender];
    if (currentAllowance != ~uint256(0)) {
      require(currentAllowance >= _amount, 'ATL');
      _approve(_account, _spender, currentAllowance - _amount);
    }
  }

  /*****************
   ** REWARDS **
   *****************/

  function _mintRewards(
    address _address,
    uint256 _amount,
    uint256 _sharesAmount,
    FeeType _feeType,
    FeeRole _feeRole
  ) internal {
    _mintShares(_address, _sharesAmount);
    emit MintRewards(_address, _amount, _sharesAmount, _feeType, _feeRole);
  }

  function mintRewards(
    address _address,
    uint256 _sharesAmount,
    FeeType _feeType,
    FeeRole _feeRole
  ) public payable {
    require(msg.sender == router, 'OR');
    _mintRewards(_address, msg.value, _sharesAmount, _feeType, _feeRole);
  }

  function claimRewards(address _account, uint256 _sharesAmount) external whenNotPaused {
    address airdropFee = getFeeAddress(FeeRole.Airdrop);
    require(msg.sender == airdropFee, 'OA');
    _transferShares(airdropFee, _account, _sharesAmount);
    emit ClaimRewards(_account, _sharesAmount);
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
    require(config.feature.Deposit, 'FD');
    require(_to != address(0), 'ZA');
    require(msg.value >= config.minDepositAmount, 'MDA');

    _resetLimits();

    if (msg.value + totalDeposited > config.depositLimit) {
      emit DepositLimitReached(_to, msg.value);
      revert();
    }

    uint256 sharesAmount = MathUpgradeable.mulDiv(msg.value, totalShares, totalSupply() - msg.value);

    (uint256[4] memory _shares, ) = estimateFee(FeeType.StakeEntry, sharesAmount);

    FeeRole[4] memory roles = getFeesRoles();
    for (uint i = 0; i < roles.length; i++) {
      if (_shares[i] > 0) {
        if (roles[i] == FeeRole.Sender) {
          _mintShares(_to, _shares[i]);
        } else {
          _mintRewards(getFeeAddress(roles[i]), 0, _shares[i], FeeType.StakeEntry, roles[i]);
        }
      }
    }

    if (_depositType == DepositType.DonationPool) {
      _validateDelegations(_to, _delegations);
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
    require(_amount > 0, 'ZA');
    require(_amount <= balanceOf(msg.sender), 'IB');

    _resetLimits();

    if (_amount + totalWithdrawn > config.withdrawalLimit) {
      emit WithdrawalsLimitReached(msg.sender, _amount);
      revert();
    }

    uint256 sharesToBurn = MathUpgradeable.mulDiv(_amount, shares[msg.sender], balanceOf(msg.sender));
    _burnShares(msg.sender, sharesToBurn);

    _validateDelegations(msg.sender, _delegations);
    totalWithdrawn += _amount;
    emit WithdrawBase(msg.sender, _delegations, _amount, sharesToBurn, _withdrawType);
  }

  function withdrawPool(
    uint256 _amount,
    Delegation[] memory _delegations
  ) external nonReentrant whenNotPaused {
    require(config.feature.WithdrawPool, 'FD');
    require(_amount <= address(this).balance, 'IPB');
    _withdrawBase(_amount, _delegations, WithdrawType.Pool);
    payable(msg.sender).transfer(_amount);
  }

  function withdrawValidator(
    uint256 _amount,
    Delegation[] memory _delegations
  ) external nonReentrant whenNotPaused {
    require(config.feature.WithdrawValidator, 'FD');
    require(_amount <= beaconBalance, 'IBB');
    beaconBalance -= _amount;
    _withdrawBase(_amount, _delegations, WithdrawType.Validator);
    withdrawals.mint(msg.sender, _amount);
  }

  function refundPool() external payable {
    require(msg.sender == router, 'OR');
    beaconBalance -= msg.value;
    emit RefundPool(msg.sender, msg.value);
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
    require(_pool != address(0), 'ZA');
    require(!pools[_pool], 'PE');
    if (!hasRole(POOL_MANAGER_ROLE, msg.sender)) {
      require(config.feature.AddPool, 'FD');
      (uint256[4] memory _shares, ) = estimateFeeFixed(FeeType.StakePool);
      FeeRole[4] memory roles = getFeesRoles();
      for (uint i = 0; i < roles.length - 1; i++) {
        _mintRewards(getFeeAddress(roles[i]), msg.value, _shares[i], FeeType.StakePool, roles[i]);
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
    _validateDelegations(msg.sender, _delegations);
    emit UpdateDelegations(msg.sender, _delegations);
  }

  function _validateDelegations(address _account, Delegation[] memory _delegations) internal view {
    uint256 totalDelegationsShares = 0;

    for (uint i = 0; i < _delegations.length; i++) {
      require(pools[_delegations[i].pool], 'PNF');
      totalDelegationsShares += _delegations[i].shares;
    }

    require(totalDelegationsShares == shares[_account], 'ITS');
    require(_delegations.length <= config.maxDelegations, 'TMD');
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
      'NA'
    );
    require(validatorOracles.length > 0, 'NVO');
    _nextValidatorOracle();
  }

  function isValidatorOracle(address _oracleAddress) public view returns (bool) {
    return
      hasRole(ORACLE_VALIDATOR_ROLE, _oracleAddress) &&
      validatorOracles[currentOracleIndex] == _oracleAddress;
  }

  function _nextValidatorOracle() internal {
    require(validatorOracles.length > 1, 'NVO');
    currentOracleIndex = (currentOracleIndex + 1) % validatorOracles.length;
  }

  /*****************
   ** VALIDATORS **
   *****************/

  function setBeaconBalance(uint256 _amount) external {
    require(msg.sender == address(router), 'OR');
    beaconBalance = _amount;
    emit SetBeaconBalance(_amount);
  }

  function createValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external nonReentrant whenNotPaused {
    require(isValidatorOracle(msg.sender), 'OVO');
    require(address(this).balance >= config.validatorSize, 'IPB');
    require(!validators[_publicKey], 'VAC');

    (uint256[4] memory _shares, ) = estimateFeeFixed(FeeType.StakeValidator);

    FeeRole[4] memory roles = getFeesRoles();

    for (uint i = 0; i < _shares.length - 1; i++) {
      if (_shares[i] > 0) {
        _mintRewards(getFeeAddress(roles[i]), 0, _shares[i], FeeType.StakeValidator, roles[i]);
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
    require(msg.sender == address(router), 'OR');
    require(validators[_publicKey], 'OV');

    validators[_publicKey] = false;
    totalValidators--;

    emit RemoveValidator(msg.sender, _epoch, _publicKey, msg.value);
  }

  /*****************
   ** VALIDATORS **
   *****************/

  function getFeesRoles() public pure returns (FeeRole[4] memory) {
    FeeRole[4] memory roles = [FeeRole.Airdrop, FeeRole.Operator, FeeRole.StakeTogether, FeeRole.Sender];
    return roles;
  }

  function setFeeAddress(FeeRole _role, address payable _address) external onlyRole(ADMIN_ROLE) {
    roleAddresses[_role] = _address;
    emit SetFeeAddress(_role, _address);
  }

  function getFeeAddress(FeeRole _role) public view returns (address) {
    return roleAddresses[_role];
  }

  function setFee(
    FeeType _feeType,
    uint256 _value,
    FeeMath _mathType,
    uint256[] calldata _allocations
  ) external onlyRole(ADMIN_ROLE) {
    require(_allocations.length == 4);

    fees[_feeType].value = _value;
    fees[_feeType].mathType = _mathType;

    uint256 sum = 0;
    for (uint256 i = 0; i < _allocations.length; i++) {
      uint256 allocation = _allocations[i];
      fees[_feeType].allocations[FeeRole(i)] = allocation;
      sum += allocation;
    }

    require(sum == 1 ether);
    emit SetFee(_feeType, _value, _mathType, _allocations);
  }

  /*************
   * ESTIMATES *
   *************/

  function estimateFee(
    FeeType _feeType,
    uint256 _sharesAmount
  ) public view returns (uint256[4] memory _shares, uint256[4] memory _amounts) {
    FeeRole[4] memory roles = getFeesRoles();
    address[4] memory feeAddresses;

    for (uint256 i = 0; i < roles.length; i++) {
      feeAddresses[i] = getFeeAddress(roles[i]);
    }

    uint256[4] memory allocations;

    for (uint256 i = 0; i < feeAddresses.length - 1; i++) {
      require(feeAddresses[i] != address(0), 'ZA');
    }

    for (uint256 i = 0; i < allocations.length; i++) {
      allocations[i] = fees[_feeType].allocations[roles[i]];
    }

    uint256 feeValue = fees[_feeType].value;

    uint256 feeShares = MathUpgradeable.mulDiv(_sharesAmount, feeValue, 1 ether);

    uint256 totalAllocatedShares = 0;

    for (uint256 i = 0; i < roles.length - 1; i++) {
      _shares[i] = MathUpgradeable.mulDiv(feeShares, allocations[i], 1 ether);
      totalAllocatedShares += _shares[i];
    }

    _shares[3] = _sharesAmount - totalAllocatedShares;

    for (uint256 i = 0; i < roles.length; i++) {
      _amounts[i] = pooledEthByShares(_shares[i]);
    }

    return (_shares, _amounts);
  }

  function estimateFeePercentage(
    FeeType _feeType,
    uint256 _amount
  ) public view returns (uint256[4] memory _shares, uint256[4] memory _amounts) {
    require(fees[_feeType].mathType == FeeMath.PERCENTAGE);
    uint256 sharesAmount = sharesByPooledEth(_amount);
    return estimateFee(_feeType, sharesAmount);
  }

  function estimateFeeFixed(
    FeeType _feeType
  ) public view returns (uint256[4] memory _shares, uint256[4] memory _amounts) {
    require(fees[_feeType].mathType == FeeMath.FIXED);
    return estimateFee(_feeType, fees[_feeType].value);
  }
}
