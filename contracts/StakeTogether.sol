// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;
import './Shares.sol';

/// @custom:security-contact security@staketogether.app
contract StakeTogether is Shares {
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address _routerContract,
    address _feesContract,
    address _airdropContract,
    address _withdrawalsContract,
    address _liquidityContract,
    address _validatorsContract,
    bytes memory _withdrawalCredentials
  ) public payable initializer {
    __ERC20_init('ST Staked Ether', 'sETH');
    __ERC20Burnable_init();
    __Pausable_init();
    __AccessControl_init();
    __ERC20Permit_init('ST Staked Ether');
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(PAUSER_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);

    routerContract = Router(payable(_routerContract));
    feesContract = Fees(payable(_feesContract));
    airdropContract = Airdrop(payable(_airdropContract));
    withdrawalsContract = Withdrawals(payable(_withdrawalsContract));
    liquidityContract = Liquidity(payable(_liquidityContract));
    validatorsContract = Validators(payable(_validatorsContract));
    withdrawalCredentials = _withdrawalCredentials;

    this.addPool(address(this));

    _mintShares(address(this), msg.value);
    _mintPoolShares(address(this), address(this), msg.value);
  }

  function pause() public onlyRole(PAUSER_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(PAUSER_ROLE) {
    _unpause();
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override whenNotPaused {
    super._beforeTokenTransfer(from, to, amount);
  }

  /************
   ** CONFIG **
   ************/

  function setConfig(Config memory _config) public onlyRole('ADMIN_ROLE') {
    require(_config.poolSize >= validatorsContract.validatorSize(), 'POOL_SIZE_TOO_LOW');
    config = _config;
    emit SetConfig(_config);
  }

  /*********************
   ** ACCOUNT REWARDS **
   *********************/

  receive() external payable nonReentrant {
    _supplyLiquidity(msg.value);
    emit MintRewardsAccounts(msg.sender, msg.value - liquidityBalance);
  }

  fallback() external payable nonReentrant {
    _supplyLiquidity(msg.value);
    emit MintRewardsAccounts(msg.sender, msg.value - liquidityBalance);
  }

  function _supplyLiquidity(uint256 _amount) internal {
    if (liquidityBalance > 0) {
      uint256 debitAmount = 0;

      if (liquidityBalance >= _amount) {
        debitAmount = _amount;
      } else {
        debitAmount = liquidityBalance;
      }

      liquidityBalance -= debitAmount;
      liquidityContract.supplyLiquidity{ value: debitAmount }();

      emit SupplyLiquidity(debitAmount);
    }
  }

  /*****************
   ** STAKE **
   *****************/

  uint256 public lastResetBlock;
  uint256 public totalDeposited;
  uint256 public totalWithdrawn;

  function _depositBase(address _to, address _pool) internal {
    require(config.enableDeposit, 'DEPOSIT_DISABLED');
    require(_to != address(0), 'MINT_TO_ZERO_ADDR');
    require(isPool(_pool), 'POOL_NOT_FOUND');
    require(msg.value > 0, 'ZERO_VALUE');
    require(msg.value >= config.minDepositAmount, 'AMOUNT_BELOW_MIN_DEPOSIT');

    _resetLimits();

    if (msg.value + totalDeposited > config.depositLimit) {
      emit DepositProtocolLimitReached(_to, msg.value);
      revert('DEPOSIT_LIMIT_REACHED');
    }

    uint256 sharesAmount = (msg.value * totalShares) / (totalPooledEther() - msg.value);

    (uint256[8] memory _shares, ) = feesContract.distributeFeePercentage(
      Fees.FeeType.StakeEntry,
      sharesAmount,
      0
    );

    Fees.FeeRoles[8] memory roles = feesContract.getFeesRoles();
    for (uint i = 0; i < roles.length; i++) {
      if (_shares[i] > 0) {
        if (roles[i] == Fees.FeeRoles.Sender) {
          _mintShares(_to, _shares[i]);
          _mintPoolShares(_to, _pool, _shares[i]);
        } else if (roles[i] == Fees.FeeRoles.Pools) {
          _mintRewards(_pool, _pool, _shares[i]);
        } else {
          _mintRewards(
            feesContract.getFeeAddress(roles[i]),
            feesContract.getFeeAddress(Fees.FeeRoles.StakeTogether),
            _shares[i]
          );
        }
      }
    }

    totalDeposited += msg.value;
    _supplyLiquidity(msg.value);
    emit DepositBase(_to, _pool, msg.value, _shares);
  }

  function depositPool(address _pool, address _referral) external payable nonReentrant whenNotPaused {
    _depositBase(msg.sender, _pool);
    emit DepositPool(msg.sender, msg.value, _pool, _referral);
  }

  function depositDonationPool(
    address _to,
    address _pool,
    address _referral
  ) external payable nonReentrant whenNotPaused {
    _depositBase(_to, _pool);
    emit DepositDonationPool(msg.sender, _to, msg.value, _pool, _referral);
  }

  function _withdrawBase(uint256 _amount, address _pool) internal {
    require(_amount > 0, 'ZERO_VALUE');
    require(isPool(_pool), 'POOL_NOT_FOUND');
    require(_amount <= balanceOf(msg.sender), 'AMOUNT_EXCEEDS_BALANCE');
    require(delegationSharesOf(msg.sender, _pool) > 0, 'NO_DELEGATION_SHARES');

    _resetLimits();

    if (_amount + totalWithdrawn > config.withdrawalLimit) {
      emit WithdrawalLimitReached(msg.sender, _amount);
      revert('WITHDRAWAL_LIMIT_REACHED');
    }

    uint256 sharesToBurn = Math.mulDiv(_amount, netSharesOf(msg.sender), balanceOf(msg.sender));

    totalWithdrawn += _amount;

    _burnShares(msg.sender, sharesToBurn);
    _burnPoolShares(msg.sender, _pool, sharesToBurn);
  }

  function withdrawPool(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(config.enableWithdrawPool, 'WITHDRAW_POOL_DISABLED');
    require(_amount <= poolBalance(), 'NOT_ENOUGH_POOL_BALANCE');
    _withdrawBase(_amount, _pool);
    emit WithdrawPool(msg.sender, _amount, _pool);
    payable(msg.sender).transfer(_amount);
  }

  function withdrawLiquidity(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(_amount <= address(liquidityContract).balance, 'NOT_ENOUGH_LOAN_BALANCE');
    _withdrawBase(_amount, _pool);
    emit WithdrawLiquidity(msg.sender, _amount, _pool);
    liquidityContract.withdrawLiquidity(_amount, _pool);
  }

  function withdrawValidator(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(_amount <= beaconBalance, 'NOT_ENOUGH_BEACON_BALANCE');
    beaconBalance -= _amount;
    _withdrawBase(_amount, _pool);
    emit WithdrawValidator(msg.sender, _amount, _pool);
    withdrawalsContract.mint(msg.sender, _amount);
  }

  function refundPool() external payable onlyRouter {
    beaconBalance -= msg.value;
    emit RefundPool(msg.sender, msg.value);
  }

  function poolBalance() public view returns (uint256) {
    return address(this).balance;
  }

  function totalPooledEther() public view override returns (uint256) {
    return poolBalance() + beaconBalance - liquidityBalance;
  }

  function _resetLimits() internal {
    if (block.number > lastResetBlock + config.blocksPerDay) {
      totalDeposited = 0;
      totalWithdrawn = 0;
      lastResetBlock = block.number;
    }
  }

  /***********
   ** POOLS **
   ***********/

  uint256 public poolCount = 0;
  mapping(address => bool) private pools;

  function addPool(address _pool) external payable nonReentrant {
    require(_pool != address(0), 'ZERO_ADDR');
    require(!isPool(_pool), 'POOL_ALREADY_ADDED');
    require(poolCount < config.maxPools, 'MAX_POOLS_REACHED');

    if (!hasRole(POOL_MANAGER_ROLE, msg.sender) && msg.sender != address(this)) {
      require(config.permissionLessAddPool, 'ONLY_POOL_MANAGER_OR_ST_CONTRACT');

      uint256[8] memory feeAmounts = feesContract.estimateFeeFixed(Fees.FeeType.StakePool);

      Fees.FeeRoles[8] memory roles = feesContract.getFeesRoles();

      for (uint i = 0; i < roles.length - 1; i++) {
        mintRewards(
          feesContract.getFeeAddress(roles[i]),
          feesContract.getFeeAddress(Fees.FeeRoles.StakeTogether),
          feeAmounts[i]
        );
      }
    }

    pools[_pool] = true;
    poolCount += 1;
    emit AddPool(_pool);
  }

  function removePool(address _pool) external onlyRole(POOL_MANAGER_ROLE) {
    require(isPool(_pool), 'POOL_NOT_FOUND');
    pools[_pool] = false;
    poolCount -= 1;
    emit RemovePool(_pool);
  }

  function isPool(address _pool) public view override returns (bool) {
    return pools[_pool];
  }

  /*****************
   ** VALIDATORS **
   *****************/

  function createValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external nonReentrant {
    require(validatorsContract.isValidatorOracle(msg.sender), 'ONLY_VALIDATOR_ORACLE');
    require(poolBalance() >= validatorsContract.validatorSize(), 'NOT_ENOUGH_POOL_BALANCE');

    validatorsContract.createValidator{ value: validatorsContract.validatorSize() }(
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );
  }
}
