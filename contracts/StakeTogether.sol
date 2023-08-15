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

  mapping(address => bool) private pools;

  address[] private validatorOracles;
  uint256 public currentOracleIndex;

  mapping(bytes => bool) private validators;
  uint256 private totalValidators;

  mapping(FeeRole => address payable) private feesRole;
  mapping(FeeType => Fee) private fees;

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

    _mintShares(address(this), 1);
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
    require(_config.poolSize >= config.validatorSize, 'IS');
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
    return weiByShares(shares[_account]);
  }

  function weiByShares(uint256 _sharesAmount) public view returns (uint256) {
    return MathUpgradeable.mulDiv(_sharesAmount, totalSupply(), totalShares, MathUpgradeable.Rounding.Up);
  }

  function sharesByWei(uint256 _amount) public view returns (uint256) {
    return MathUpgradeable.mulDiv(_amount, totalShares, totalSupply());
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
    return weiByShares(_sharesAmount);
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
    require(currentAllowance >= _subtractedValue, 'IA');
    _approve(msg.sender, _spender, currentAllowance - _subtractedValue);
    return true;
  }

  function _approve(address _account, address _spender, uint256 _amount) internal override {
    require(_account != address(0), 'ZA');
    require(_spender != address(0), 'ZA');
    allowances[_account][_spender] = _amount;
    emit Approval(_account, _spender, _amount);
  }

  function _mintShares(address _to, uint256 _sharesAmount) private whenNotPaused {
    require(_to != address(0), 'ZA');
    shares[_to] += _sharesAmount;
    totalShares += _sharesAmount;
    emit MintShares(_to, _sharesAmount);
  }

  function _burnShares(address _account, uint256 _sharesAmount) private whenNotPaused {
    require(_account != address(0), 'ZA');
    require(_sharesAmount <= shares[_account], 'IS');
    shares[_account] -= _sharesAmount;
    totalShares -= _sharesAmount;
    emit BurnShares(_account, _sharesAmount);
  }

  function _transfer(address _from, address _to, uint256 _amount) internal override whenNotPaused {
    uint256 _sharesToTransfer = sharesByWei(_amount);
    _transferShares(_from, _to, _sharesToTransfer);
    emit Transfer(_from, _to, _amount);
  }

  function _transferShares(address _from, address _to, uint256 _sharesAmount) private whenNotPaused {
    require(_from != address(0), 'ZA');
    require(_to != address(0), 'ZA');
    require(_sharesAmount <= shares[_from], 'IS');
    shares[_from] -= _sharesAmount;
    shares[_to] += _sharesAmount;
    emit TransferShares(_from, _to, _sharesAmount);
  }

  function _spendAllowance(address _account, address _spender, uint256 _amount) internal override {
    uint256 currentAllowance = allowances[_account][_spender];
    if (currentAllowance != ~uint256(0)) {
      require(currentAllowance >= _amount, 'IA');
      _approve(_account, _spender, currentAllowance - _amount);
    }
  }

  /*************
   ** REWARDS **
   *************/

  function _mintRewards(
    address _address,
    uint256 _amount,
    uint256 _sharesAmount,
    FeeType _feeType,
    FeeRole _feeRole
  ) private {
    _mintShares(_address, _sharesAmount);
    emit MintRewards(_address, _amount, _sharesAmount, _feeType, _feeRole);
  }

  function mintRewards(
    address _address,
    uint256 _sharesAmount,
    FeeType _feeType,
    FeeRole _feeRole
  ) public payable nonReentrant {
    require(msg.sender == router, 'OR');
    _mintRewards(_address, msg.value, _sharesAmount, _feeType, _feeRole);
  }

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
          _mintRewards(getFeeAddress(roles[i]), 0, _shares[i], FeeType.StakeEntry, roles[i]);
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
        _mintRewards(getFeeAddress(roles[i]), msg.value, _shares[i], FeeType.StakePool, roles[i]);
      }
    }
    pools[_pool] = true;
    emit AddPool(_pool, _listed, msg.value);
  }

  function removePool(address _pool) external onlyRole(POOL_MANAGER_ROLE) {
    require(pools[_pool], 'NF');
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
    require(validatorOracles.length > 0, 'NV');
    _nextValidatorOracle();
  }

  function isValidatorOracle(address _oracleAddress) public view returns (bool) {
    return
      hasRole(ORACLE_VALIDATOR_ROLE, _oracleAddress) &&
      validatorOracles[currentOracleIndex] == _oracleAddress;
  }

  function _nextValidatorOracle() private {
    require(validatorOracles.length > 1, 'NV');
    currentOracleIndex = (currentOracleIndex + 1) % validatorOracles.length;
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
    require(address(this).balance >= config.validatorSize, 'NB');
    require(!validators[_publicKey], 'VE');

    (uint256[4] memory _shares, ) = estimateFeeFixed(FeeType.StakeValidator);

    FeeRole[4] memory roles = getFeesRoles();

    for (uint i = 0; i < _shares.length - 1; i++) {
      if (_shares[i] > 0) {
        _mintRewards(getFeeAddress(roles[i]), 0, _shares[i], FeeType.StakeValidator, roles[i]);
      }
    }

    _setBeaconBalance(beaconBalance + config.validatorSize);
    validators[_publicKey] = true;
    totalValidators++;

    _nextValidatorOracle();

    deposit.deposit{ value: config.validatorSize }(
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

  function removeValidator(uint256 _epoch, bytes calldata _publicKey) external payable nonReentrant {
    require(msg.sender == address(router), 'OR');
    require(validators[_publicKey], 'OV');
    validators[_publicKey] = false;
    totalValidators--;
    emit RemoveValidator(msg.sender, _epoch, _publicKey, msg.value);
  }

  /*****************
   **    FEES     **
   *****************/

  function setFeeAddress(FeeRole _role, address payable _address) external onlyRole(ADMIN_ROLE) {
    feesRole[_role] = _address;
    emit SetFeeAddress(_role, _address);
  }

  function getFeeAddress(FeeRole _role) public view returns (address) {
    return feesRole[_role];
  }

  function getFeesRoles() public pure returns (FeeRole[4] memory) {
    FeeRole[4] memory roles = [FeeRole.Airdrop, FeeRole.Operator, FeeRole.StakeTogether, FeeRole.Sender];
    return roles;
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
    address[4] memory feeAddresses;

    for (uint256 i = 0; i < roles.length; i++) {
      feeAddresses[i] = getFeeAddress(roles[i]);
    }

    for (uint256 i = 0; i < feeAddresses.length - 1; i++) {
      require(feeAddresses[i] != address(0), 'ZA');
    }

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
