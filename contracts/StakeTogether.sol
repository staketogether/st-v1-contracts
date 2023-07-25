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
    address _routerContract,
    address _feesContract,
    address _airdropContract,
    address _withdrawalsContract,
    address _liquidityContract,
    address _validatorsContract
  ) public initializer {
    __ERC20_init('ST Staked Ether', 'sETH');
    __ERC20Burnable_init();
    __Pausable_init();
    __AccessControl_init();
    __ERC20Permit_init('ST Staked Ether');
    __UUPSUpgradeable_init();

    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);

    routerContract = Router(payable(_routerContract));
    feesContract = Fees(payable(_feesContract));
    airdropContract = Airdrop(payable(_airdropContract));
    withdrawalsContract = Withdrawals(payable(_withdrawalsContract));
    liquidityContract = Liquidity(payable(_liquidityContract));
    validatorsContract = Validators(payable(_validatorsContract));

    beaconBalance = 0;
    liquidityBalance = 0;
    totalShares = 0;
    totalLockedShares = 0;
    lockSharesId = 1;
    totalPoolShares = 0;
  }

  function initializeShares() external payable onlyRole(ADMIN_ROLE) {
    require(totalShares == 0);
    addPool(address(this));
    _mintShares(address(this), msg.value);
    _mintPoolShares(address(this), address(this), msg.value);
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  receive() external payable nonReentrant {
    _supplyLiquidity(msg.value);
    emit MintRewardsAccounts(msg.sender, msg.value - liquidityBalance);
  }

  fallback() external payable nonReentrant {
    _supplyLiquidity(msg.value);
    emit MintRewardsAccountsFallback(msg.sender, msg.value - liquidityBalance);
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
      liquidityContract.supplyLiquidity{ value: debitAmount }();
      emit SupplyLiquidity(debitAmount);
    }
  }

  /************
   ** CONFIG **
   ************/

  function setConfig(Config memory _config) public onlyRole(ADMIN_ROLE) {
    require(_config.poolSize >= validatorsContract.validatorSize());
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

  uint256 public lastResetBlock;
  uint256 public totalDeposited;
  uint256 public totalWithdrawn;

  function _depositBase(address _to, address _pool) internal {
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

    (uint256[8] memory _shares, ) = feesContract.distributeFeePercentage(
      IFees.FeeType.StakeEntry,
      sharesAmount,
      0
    );

    IFees.FeeRoles[8] memory roles = feesContract.getFeesRoles();
    for (uint i = 0; i < roles.length; i++) {
      if (_shares[i] > 0) {
        if (roles[i] == IFees.FeeRoles.Sender) {
          _mintShares(_to, _shares[i]);
          _mintPoolShares(_to, _pool, _shares[i]);
        } else if (roles[i] == IFees.FeeRoles.Pools) {
          _mintRewards(_pool, _pool, _shares[i]);
        } else {
          _mintRewards(
            feesContract.getFeeAddress(roles[i]),
            feesContract.getFeeAddress(IFees.FeeRoles.StakeTogether),
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
    require(_amount > 0);
    require(_amount <= balanceOf(msg.sender));
    require(pools[_pool]);
    require(delegationSharesOf(msg.sender, _pool) > 0);

    _resetLimits();

    if (_amount + totalWithdrawn > config.withdrawalLimit) {
      emit WithdrawalsLimitReached(msg.sender, _amount);
      revert();
    }

    uint256 sharesToBurn = MathUpgradeable.mulDiv(
      _amount,
      netSharesOf(msg.sender),
      balanceOf(msg.sender)
    );

    totalWithdrawn += _amount;

    _burnShares(msg.sender, sharesToBurn);
    _burnPoolShares(msg.sender, _pool, sharesToBurn);
  }

  function withdrawPool(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(config.feature.WithdrawPool);
    require(_amount <= address(this).balance);
    _withdrawBase(_amount, _pool);
    emit WithdrawPool(msg.sender, _amount, _pool);
    payable(msg.sender).transfer(_amount);
  }

  function withdrawLiquidity(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(config.feature.WithdrawLiquidity);
    require(_amount <= address(liquidityContract).balance);
    _withdrawBase(_amount, _pool);
    emit WithdrawLiquidity(msg.sender, _amount, _pool);
    liquidityContract.withdrawLiquidity(_amount, _pool);
  }

  function withdrawValidator(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(config.feature.WithdrawValidator);
    require(_amount <= beaconBalance);
    beaconBalance -= _amount;
    _withdrawBase(_amount, _pool);
    emit WithdrawValidator(msg.sender, _amount, _pool);
    withdrawalsContract.mint(msg.sender, _amount);
  }

  function refundPool() external payable {
    require(msg.sender == address(routerContract));
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
    require(validatorsContract.isValidatorOracle(msg.sender));
    require(address(this).balance >= validatorsContract.validatorSize());
    validatorsContract.createValidator{ value: validatorsContract.validatorSize() }(
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );
  }
}
