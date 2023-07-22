// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;
import './Shares.sol';

/// @custom:security-contact security@staketogether.app
contract StakeTogether is Shares {
  event Bootstrap(address sender, uint256 balance);
  event MintRewardsAccounts(address indexed sender, uint amount);
  event MintRewardsAccountsFallback(address indexed sender, uint amount);
  event SupplyLiquidity(uint256 amount);
  event DepositBase(
    address indexed to,
    address indexed pool,
    uint256 amount,
    uint256 stakeAccountShares,
    uint256 lockAccountShares,
    uint256 poolsShares,
    uint256 operatorsShares,
    uint256 oraclesShares,
    uint256 stakeTogetherShares,
    uint256 liquidityProvidersShares,
    uint256 senderShares
  );

  event DepositWalletLimitReached(address indexed sender, uint256 amount);
  event DepositProtocolLimitReached(address indexed sender, uint256 amount);
  event DepositPool(address indexed account, uint256 amount, address pool, address referral);
  event DepositDonationPool(
    address indexed donor,
    address indexed account,
    uint256 amount,
    address pool,
    address referral
  );
  event WithdrawalLimitReached(address indexed sender, uint256 amount);
  event WithdrawPool(address indexed account, uint256 amount, address pool);
  event WithdrawLiquidity(address indexed account, uint256 amount, address pool);
  event WithdrawValidator(address indexed account, uint256 amount, address pool);
  event SetEnableDeposit(bool enableDeposit);
  event SetEnableWithdrawPool(bool enableWithdrawPool);
  event SetDepositLimit(uint256 newLimit);
  event SetWithdrawalLimit(uint256 newLimit);
  event SetMinDepositPoolAmount(uint256 amount);
  event SetPoolSize(uint256 amount);
  event SetBlocksInterval(uint256 blocksInterval);
  event AddPool(address account);
  event RemovePool(address account);
  event SetMaxPools(uint256 maxPools);
  event SetPermissionLessAddPool(bool permissionLessAddPool);
  event SetWithdrawalCredentials(bytes withdrawalCredentials);
  event CreateValidator(
    address indexed creator,
    uint256 indexed amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );
  event RefundPool(address indexed sender, uint256 amount);

  bool private bootstrapped = false;

  constructor(
    address _routerContract,
    address _feesContract,
    address _airdropContract,
    address _withdrawalsContract,
    address _liquidityContract,
    address _validatorsContract
  ) payable ERC20('ST Staked Ether', 'SETH') ERC20Permit('ST Staked Ether') {
    routerContract = Router(payable(_routerContract));
    feesContract = Fees(payable(_feesContract));
    airdropContract = Airdrop(payable(_airdropContract));
    withdrawalsContract = Withdrawals(payable(_withdrawalsContract));
    liquidityContract = Liquidity(payable(_liquidityContract));
    validatorsContract = Validators(payable(_validatorsContract));

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
  }

  function bootstrap() external payable {
    require(!bootstrapped, 'ALREADY_BOOTSTRAPPED');
    require(hasRole(ADMIN_ROLE, msg.sender), 'ONLY_ADMIN');
    require(!isPool(address(this)), 'ALREADY_EXISTS_POOL');

    bootstrapped = true;

    this.addPool(address(this));

    _mintShares(address(this), msg.value);
    _mintPoolShares(address(this), address(this), msg.value);

    emit Bootstrap(msg.sender, msg.value);
  }

  /*********************
   ** ACCOUNT REWARDS **
   *********************/

  receive() external payable nonReentrant {
    emit MintRewardsAccounts(msg.sender, msg.value);
    _supplyLiquidity(msg.value);
  }

  fallback() external payable nonReentrant {
    emit MintRewardsAccountsFallback(msg.sender, msg.value);
    _supplyLiquidity(msg.value);
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

  bool public enableDeposit = true;
  bool public enableWithdrawPool = true;
  uint256 public poolSize = 32 ether;
  uint256 public minDepositAmount = 0.001 ether;
  uint256 public depositLimit = 1000 ether;
  uint256 public withdrawalLimit = 1000 ether;
  uint256 public blocksPerDay = 6500;
  uint256 public lastResetBlock;
  uint256 public totalDeposited;
  uint256 public totalWithdrawn;

  function _depositBase(address _to, address _pool) internal {
    require(enableDeposit, 'DEPOSIT_DISABLED');
    require(_to != address(0), 'MINT_TO_ZERO_ADDR');
    require(isPool(_pool), 'POOL_NOT_FOUND');
    require(msg.value > 0, 'ZERO_VALUE');
    require(msg.value >= minDepositAmount, 'AMOUNT_BELOW_MIN_DEPOSIT');

    _resetLimits();

    if (msg.value + totalDeposited > depositLimit) {
      emit DepositProtocolLimitReached(_to, msg.value);
      revert('DEPOSIT_LIMIT_REACHED');
    }

    uint256 sharesAmount = (msg.value * totalShares) / (totalPooledEther() - msg.value);

    (uint256[8] memory _shares, ) = feesContract.distributeFeePercentage(
      Fees.FeeType.StakeEntry,
      sharesAmount
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

    emit DepositBase(
      _to,
      _pool,
      msg.value,
      _shares[0],
      _shares[1],
      _shares[2],
      _shares[3],
      _shares[4],
      _shares[5],
      _shares[6],
      _shares[7]
    );
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

    if (_amount + totalWithdrawn > withdrawalLimit) {
      emit WithdrawalLimitReached(msg.sender, _amount);
      revert('WITHDRAWAL_LIMIT_REACHED');
    }

    uint256 sharesToBurn = Math.mulDiv(_amount, sharesOf(msg.sender), balanceOf(msg.sender));

    _burnShares(msg.sender, sharesToBurn);
    _burnPoolShares(msg.sender, _pool, sharesToBurn);

    totalWithdrawn += _amount;
  }

  function withdrawPool(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(enableWithdrawPool, 'WITHDRAW_POOL_DISABLED');
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

  function refundPool() external payable onlyRouterContract {
    beaconBalance -= msg.value;
    emit RefundPool(msg.sender, msg.value);
  }

  function _resetLimits() internal {
    if (block.number > lastResetBlock + blocksPerDay) {
      totalDeposited = 0;
      totalWithdrawn = 0;
      lastResetBlock = block.number;
    }
  }

  function setEnableDeposit(bool _enableDeposit) external onlyRole(ADMIN_ROLE) {
    enableDeposit = _enableDeposit;
    emit SetEnableDeposit(_enableDeposit);
  }

  function setEnableWithdrawPool(bool _enableWithdrawPool) external onlyRole(ADMIN_ROLE) {
    enableWithdrawPool = _enableWithdrawPool;
    emit SetEnableWithdrawPool(_enableWithdrawPool);
  }

  function setMinDepositPoolAmount(uint256 _amount) external onlyRole(ADMIN_ROLE) {
    minDepositAmount = _amount;
    emit SetMinDepositPoolAmount(_amount);
  }

  function setDepositLimit(uint256 _newLimit) external onlyRole(ADMIN_ROLE) {
    depositLimit = _newLimit;
    emit SetDepositLimit(_newLimit);
  }

  function setWithdrawalLimit(uint256 _newLimit) external onlyRole(ADMIN_ROLE) {
    withdrawalLimit = _newLimit;
    emit SetWithdrawalLimit(_newLimit);
  }

  function setBlocksInterval(uint256 _newBlocksInterval) external onlyRole(ADMIN_ROLE) {
    blocksPerDay = _newBlocksInterval;
    emit SetBlocksInterval(_newBlocksInterval);
  }

  function setPoolSize(uint256 _amount) external onlyRole(ADMIN_ROLE) {
    require(
      _amount >= validatorsContract.validatorSize() + address(liquidityContract).balance,
      'POOL_SIZE_TOO_LOW'
    );
    poolSize = _amount;
    emit SetPoolSize(_amount);
  }

  function poolBalance() public view returns (uint256) {
    return address(this).balance - liquidityBalance;
  }

  function totalPooledEther() public view override returns (uint256) {
    return poolBalance() + beaconBalance;
  }

  /***********
   ** POOLS **
   ***********/

  uint256 public maxPools = 100000;
  uint256 public poolCount = 0;
  mapping(address => bool) private pools;
  bool public permissionLessAddPool = false;

  function setMaxPools(uint256 _maxPools) external onlyRole(ADMIN_ROLE) {
    require(_maxPools >= poolCount, 'INVALID_MAX_POOLS');
    maxPools = _maxPools;
    emit SetMaxPools(_maxPools);
  }

  function setPermissionLessAddPool(bool _permissionLessAddPool) external onlyRole(ADMIN_ROLE) {
    permissionLessAddPool = _permissionLessAddPool;
    emit SetPermissionLessAddPool(_permissionLessAddPool);
  }

  function addPool(address _pool) external payable nonReentrant {
    require(_pool != address(0), 'ZERO_ADDR');
    require(!isPool(_pool), 'POOL_ALREADY_ADDED');
    require(poolCount < maxPools, 'MAX_POOLS_REACHED');

    if (!hasRole(POOL_MANAGER_ROLE, msg.sender) && msg.sender != address(this)) {
      require(permissionLessAddPool, 'ONLY_POOL_MANAGER_OR_ST_CONTRACT');

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

  bytes public withdrawalCredentials;

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
    validatorsContract.createValidator{ value: validatorsContract.validatorSize() }(
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );

    uint256[8] memory feeAmounts = feesContract.estimateFeeFixed(Fees.FeeType.StakeValidator);

    Fees.FeeRoles[8] memory roles = feesContract.getFeesRoles();

    for (uint i = 0; i < feeAmounts.length - 1; i++) {
      if (feeAmounts[i] > 0) {
        mintRewards(
          feesContract.getFeeAddress(roles[i]),
          feesContract.getFeeAddress(Fees.FeeRoles.StakeTogether),
          feeAmounts[i]
        );
      }
    }

    emit CreateValidator(
      msg.sender,
      validatorsContract.validatorSize(),
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );
  }
}
