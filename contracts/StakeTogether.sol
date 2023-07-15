// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;
import './Shares.sol';

/// @custom:security-contact security@staketogether.app
contract StakeTogether is Shares {
  event DepositBase(
    address indexed to,
    address indexed pool,
    uint256 amount,
    uint256 poolsShares,
    uint256 operatorsShares,
    uint256 stakeTogetherShares,
    uint256 accountShares,
    uint256 senderShares
  );
  event DepositLimitReached(address indexed sender, uint256 amount);
  event DepositPool(address indexed account, uint256 amount, address delegated, address referral);
  event DepositDonationPool(
    address indexed donor,
    address indexed account,
    uint256 amount,
    address pool,
    address referral
  );
  event WithdrawalLimitReached(address indexed sender, uint256 amount);
  event WithdrawPool(address indexed account, uint256 amount, address pool);
  event WithdrawBorrow(address indexed account, uint256 amount, address pool);
  event WithdrawValidator(address indexed account, uint256 amount, address pool);
  event SetDepositLimit(uint256 newLimit);
  event SetWithdrawalLimit(uint256 newLimit);
  event SetAccountDepositLimit(uint256 newLimit);
  event SetMinDepositPoolAmount(uint256 amount);
  event SetPoolSize(uint256 amount);
  event SetBlocksInterval(uint256 blocksInterval);
  event SetWithdrawalCredentials(bytes withdrawalCredentials);
  event CreateValidator(
    address indexed creator,
    uint256 indexed amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );

  constructor(
    address _routerContract,
    address _feesContract,
    address _poolsContract,
    address _withdrawalsContract,
    address _loansContract,
    address _validatorsContract
  ) payable ERC20('ST Staked Ether', 'SETH') ERC20Permit('ST Staked Ether') {
    routerContract = Router(payable(_routerContract));
    feesContract = Fees(payable(_feesContract));
    poolsContract = Pools(payable(_poolsContract));
    withdrawalsContract = Withdrawals(payable(_withdrawalsContract));
    loansContract = Loans(payable(_loansContract));
    validatorsContract = Validators(payable(_validatorsContract));

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);

    _bootstrap();
  }

  /*********************
   ** ACCOUNT REWARDS **
   *********************/

  receive() external payable {
    emit MintRewardsAccounts(msg.sender, msg.value);
    _repayLoan(msg.value);
  }

  fallback() external payable {
    emit MintRewardsAccountsFallback(msg.sender, msg.value);
    _repayLoan(msg.value);
  }

  function _repayLoan(uint256 _amount) internal {
    if (loanBalance > 0) {
      uint256 loanAmount = 0;
      if (loanBalance >= _amount) {
        loanAmount = _amount;
      } else {
        loanAmount = loanBalance;
      }
      loansContract.repayLoan{ value: loanAmount }();

      uint256 sharesToBurn = Math.mulDiv(loanAmount, sharesOf(address(loansContract)), loanBalance);
      _burnShares(address(loansContract), sharesToBurn);

      emit RepayLoan(loanAmount);
    }
  }

  /*****************
   ** STAKE **
   *****************/

  uint256 public poolSize = 32 ether;
  uint256 public minDepositAmount = 0.001 ether;
  uint256 public depositLimit = 1000 ether;
  uint256 public walletDepositLimit = 2 ether;
  uint256 public withdrawalLimit = 1000 ether;
  uint256 public blocksPerDay = 6500;
  uint256 public lastResetBlock;
  uint256 public totalDeposited;
  uint256 public totalWithdrawn;

  function _depositBase(address _to, address _pool) internal {
    require(poolsContract.isPool(_pool), 'NON_POOL_DELEGATE');
    require(msg.value > 0, 'ZERO_VALUE');
    require(msg.value >= minDepositAmount, 'NON_MIN_AMOUNT');

    if (walletDepositLimit > 0) {
      require(balanceOf(_to) + msg.value <= walletDepositLimit, 'WALLET_DEPOSIT_LIMIT_REACHED');
    }

    if (msg.value + totalDeposited > depositLimit) {
      emit DepositLimitReached(_to, msg.value);
      revert('DEPOSIT_LIMIT_REACHED');
    }

    (uint256[6] memory shares, ) = feesContract.estimateFeePercentage(Fees.FeeType.EntryStake, msg.value);

    if (shares[0] > 0) {
      _mintShares(_pool, shares[0]);
      _mintPoolShares(_pool, _pool, shares[0]);
    }

    if (shares[1] > 0) {
      _mintShares(feesContract.getFeeAddress(Fees.Roles.Operators), shares[1]);
      _mintPoolShares(
        feesContract.getFeeAddress(Fees.Roles.Operators),
        feesContract.getFeeAddress(Fees.Roles.Operators),
        shares[1]
      );
    }

    if (shares[2] > 0) {
      _mintShares(feesContract.getFeeAddress(Fees.Roles.StakeTogether), shares[2]);
      _mintPoolShares(
        feesContract.getFeeAddress(Fees.Roles.StakeTogether),
        feesContract.getFeeAddress(Fees.Roles.StakeTogether),
        shares[2]
      );
    }

    require(shares[5] > 0, 'ZERO_SHARES');
    _mintShares(_to, shares[5]);
    _mintPoolShares(_to, _pool, shares[5]);

    totalDeposited += msg.value;

    if (block.number > lastResetBlock + blocksPerDay) {
      totalDeposited = msg.value;
      totalWithdrawn = 0;
      lastResetBlock = block.number;
    }

    _repayLoan(msg.value);

    emit DepositBase(_to, _pool, msg.value, shares[0], shares[1], shares[2], shares[3], shares[5]);
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

  function _withdrawBase(uint256 _amount, address _pool) internal whenNotPaused {
    require(_amount > 0, 'ZERO_VALUE');
    require(_pool != address(0), 'MINT_TO_ZERO_ADDR');
    require(balanceOf(msg.sender) >= _amount, 'AMOUNT_EXCEEDS_BALANCE');
    require(delegationSharesOf(msg.sender, _pool) > 0, 'NOT_DELEGATION_SHARES');

    if (_amount + totalWithdrawn > withdrawalLimit) {
      emit WithdrawalLimitReached(msg.sender, _amount);
      revert('WITHDRAWAL_LIMIT_REACHED');
    }

    uint256 accountBalance = balanceOf(msg.sender);
    require(_amount <= accountBalance, 'AMOUNT_EXCEEDS_BALANCE');

    uint256 sharesToBurn = Math.mulDiv(_amount, sharesOf(msg.sender), accountBalance);

    _burnShares(msg.sender, sharesToBurn);
    _burnPoolShares(msg.sender, _pool, sharesToBurn);

    totalWithdrawn += _amount;

    if (block.number > lastResetBlock + blocksPerDay) {
      totalDeposited = 0;
      totalWithdrawn = _amount;
      lastResetBlock = block.number;
    }
  }

  function withdrawPool(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(_amount <= poolBalance(), 'NOT_ENOUGH_POOL_BALANCE');
    emit WithdrawPool(msg.sender, _amount, _pool);
    _withdrawBase(_amount, _pool);
    payable(msg.sender).transfer(_amount);
  }

  function withdrawBorrow(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(_amount <= address(loansContract).balance, 'NOT_ENOUGH_LOAN_BALANCE');
    _withdrawBase(_amount, _pool);
    loansContract.borrow(_amount, _pool);
    emit WithdrawBorrow(msg.sender, _amount, _pool);
  }

  function withdrawValidator(uint256 _amount, address _pool) external nonReentrant whenNotPaused {
    require(_amount <= beaconBalance, 'NOT_ENOUGH_BEACON_BALANCE');
    emit WithdrawValidator(msg.sender, _amount, _pool);
    _withdrawBase(_amount, _pool);
    beaconBalance -= _amount;
    withdrawalsContract.mint(msg.sender, _amount);
  }

  function setDepositLimit(uint256 _newLimit) external onlyRole(ADMIN_ROLE) {
    depositLimit = _newLimit;
    emit SetDepositLimit(_newLimit);
  }

  function setWithdrawalLimit(uint256 _newLimit) external onlyRole(ADMIN_ROLE) {
    withdrawalLimit = _newLimit;
    emit SetWithdrawalLimit(_newLimit);
  }

  function setAccountDepositLimit(uint256 _newLimit) external onlyRole(ADMIN_ROLE) {
    walletDepositLimit = _newLimit;
    emit SetAccountDepositLimit(_newLimit);
  }

  function setMinDepositPoolAmount(uint256 _amount) external onlyRole(ADMIN_ROLE) {
    minDepositAmount = _amount;
    emit SetMinDepositPoolAmount(_amount);
  }

  function setPoolSize(uint256 _amount) external onlyRole(ADMIN_ROLE) {
    require(
      _amount >= validatorsContract.validatorSize() + address(loansContract).balance,
      'POOL_SIZE_TOO_LOW'
    );
    poolSize = _amount;
    emit SetPoolSize(_amount);
  }

  function poolBalance() public view returns (uint256) {
    return address(this).balance - loanBalance;
  }

  function totalPooledEther() public view override returns (uint256) {
    return poolBalance() + beaconBalance;
  }

  function setBlocksInterval(uint256 _newBlocksInterval) external onlyRole(ADMIN_ROLE) {
    blocksPerDay = _newBlocksInterval;
    emit SetBlocksInterval(_newBlocksInterval);
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
