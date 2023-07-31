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
    address _airdrop,
    address _fees,
    address _liquidity,
    address _router,
    address _validators,
    address _withdrawals
  ) public initializer {
    __ERC20_init('ST Staked Ether', 'sETH');
    __ERC20Burnable_init();
    __Pausable_init();
    __AccessControl_init();
    __ERC20Permit_init('ST Staked Ether');
    __UUPSUpgradeable_init();

    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);
    _grantRole(POOL_MANAGER_ROLE, msg.sender);

    version = 1;

    airdrop = Airdrop(payable(_airdrop));
    fees = Fees(payable(_fees));
    liquidity = Liquidity(payable(_liquidity));
    router = Router(payable(_router));
    validators = Validators(payable(_validators));
    withdrawals = Withdrawals(payable(_withdrawals));

    beaconBalance = 0;
    liquidityBalance = 0;
    totalShares = 0;
    totalLockedShares = 0;
    lockId = 1;
    totalPoolShares = 0;
  }

  function initializeShares() external payable onlyRole(ADMIN_ROLE) {
    require(totalShares == 0);
    address stakeTogetherFee = fees.getFeeAddress(IFees.FeeRole.StakeTogether);
    addPool(stakeTogetherFee, false);
    _mintShares(address(this), msg.value);
    _mintPoolShares(address(this), stakeTogetherFee, msg.value);
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
    _supplyLiquidity(msg.value);
  }

  function _supplyLiquidity(uint256 _amount) internal {
    uint256 debitAmount = 0;
    if (liquidityBalance >= _amount) {
      debitAmount = _amount;
    } else {
      debitAmount = liquidityBalance;
    }
    if (debitAmount > 0) {
      liquidityBalance -= debitAmount;
      liquidity.supplyLiquidity{ value: debitAmount }();
      emit SupplyLiquidity(debitAmount);
    }
  }

  /************
   ** CONFIG **
   ************/

  function setConfig(Config memory _config) public onlyRole(ADMIN_ROLE) {
    require(_config.poolSize >= validators.validatorSize());
    config = _config;
    emit SetConfig(_config);
  }

  function setWithdrawalsCredentials(bytes memory _withdrawalCredentials) external onlyRole(ADMIN_ROLE) {
    require(withdrawalCredentials.length == 0);
    withdrawalCredentials = _withdrawalCredentials;
    emit SetWithdrawalsCredentials(_withdrawalCredentials);
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

    uint256 sharesAmount = (msg.value * totalShares) / (totalPooledEther() - msg.value);

    (uint256[5] memory _shares, ) = fees.distributeFee(IFees.FeeType.StakeEntry, sharesAmount, false);

    IFees.FeeRole[5] memory roles = fees.getFeesRoles();
    for (uint i = 0; i < roles.length; i++) {
      if (_shares[i] > 0) {
        if (roles[i] == IFees.FeeRole.Sender) {
          _mintShares(_to, _shares[i]);
          _mintPoolShares(_to, _pool, _shares[i]);
        } else if (roles[i] == IFees.FeeRole.Pool) {
          _mintRewards(_pool, _pool, _shares[i], IFees.FeeType.StakeEntry, roles[i]);
        } else {
          _mintRewards(
            fees.getFeeAddress(roles[i]),
            fees.getFeeAddress(IFees.FeeRole.StakeTogether),
            _shares[i],
            IFees.FeeType.StakeEntry,
            roles[i]
          );
        }
      }
    }

    totalDeposited += msg.value;
    _supplyLiquidity(msg.value);
    emit DepositBase(_to, _pool, msg.value, _shares, _depositType, referral);
  }

  function depositPool(address _pool, address _referral) external payable nonReentrant whenNotPaused {
    _depositBase(msg.sender, _pool, DepositType.Pool, _referral);
  }

  // function depositDonationPool(
  //   address _to,
  //   address _pool,
  //   address _referral
  // ) external payable nonReentrant whenNotPaused {
  //   _depositBase(_to, _pool, DepositType.DonationPool, _referral);
  // }

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

    uint256 sharesToBurn = MathUpgradeable.mulDiv(_amount, netShares(msg.sender), balanceOf(msg.sender));

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

  function withdrawLiquidity(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(config.feature.WithdrawLiquidity);
    require(_amount <= address(liquidity).balance);
    _withdrawBase(_amount, _pool, WithdrawType.Liquidity);
    liquidity.withdrawLiquidity(_amount, _pool);
  }

  function withdrawValidator(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(config.feature.WithdrawValidator);
    require(_amount <= beaconBalance);
    beaconBalance -= _amount;
    _withdrawBase(_amount, _pool, WithdrawType.Validator);
    withdrawals.mint(msg.sender, _amount);
  }

  function refundPool() external payable {
    require(msg.sender == address(router));
    beaconBalance -= msg.value;
    emit RefundPool(msg.sender, msg.value);
  }

  function totalPooledEther() public view override returns (uint256) {
    return address(this).balance + beaconBalance - liquidityBalance;
  }

  function _resetLimits() private {
    if (block.number > lastResetBlock + config.blocksPerDay) {
      totalDeposited = 0;
      totalWithdrawn = 0;
      lastResetBlock = block.number;
    }
  }

  /*****************
   ** VALIDATORS **
   *****************/

  function createValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external nonReentrant whenNotPaused {
    require(validators.isValidatorOracle(msg.sender));
    require(address(this).balance >= validators.validatorSize());
    validators.createValidator{ value: validators.validatorSize() }(
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );
  }
}
