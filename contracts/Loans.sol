// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import './StakeTogether.sol';
import './Router.sol';
import './Fees.sol';

/// @custom:security-contact security@staketogether.app
contract Loans is AccessControl, Pausable, ReentrancyGuard, ERC20, ERC20Burnable, ERC20Permit {
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant ORACLE_REPORT_ROLE = keccak256('ORACLE_REPORT_ROLE');
  bytes32 public constant ORACLE_REWARDS_ROLE = keccak256('ORACLE_REWARDS_ROLE');

  StakeTogether public stakeTogether;
  Router public routerContract;
  Fees public feesContract;

  event MintRewardsAccounts(address indexed sender, uint amount);
  event MintRewardsAccountsFallback(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);
  event MintShares(address indexed to, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  event SetEnableBorrow(bool enable);
  event AddLiquidity(address indexed user, uint256 amount);
  event RemoveLiquidity(address indexed user, uint256 amount);
  event Borrow(address indexed user, uint256 amount);
  event RepayLoan(address indexed user, uint256 amount);
  event SetEnableAnticipation(bool enable);
  event SetApr(uint256 epoch, uint256 apr);
  event AnticipateRewards(
    address indexed user,
    uint256 anticipatedAmount,
    uint256 netAmount,
    uint256 fee
  );
  event SetMaxBatchSize(uint256 size);
  event ReDeposit(address indexed user, uint256 amount);
  event ReDepositBatch(address indexed user, uint256[] amounts);

  constructor(
    address _routerContract,
    address _feesContract
  ) ERC20('ST Loan Ether', 'LETH') ERC20Permit('ST Loan Ether') {
    routerContract = Router(payable(_routerContract));
    feesContract = Fees(payable(_feesContract));

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
  }

  receive() external payable {
    emit MintRewardsAccounts(msg.sender, msg.value);
  }

  fallback() external payable {
    emit MintRewardsAccountsFallback(msg.sender, msg.value);
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  modifier onlyStakeTogether() {
    require(msg.sender == address(stakeTogether), 'ONLY_STAKE_TOGETHER_CONTRACT');
    _;
  }

  /************
   ** SHARES **
   ************/

  mapping(address => uint256) private shares;
  uint256 public totalShares = 0;
  mapping(address => mapping(address => uint256)) private allowances;

  function totalPooledEther() public view returns (uint256) {
    return address(this).balance + stakeTogether.loanBalance();
  }

  function totalSupply() public view override returns (uint256) {
    return totalPooledEther();
  }

  function balanceOf(address _account) public view override returns (uint256) {
    return pooledEthByShares(sharesOf(_account));
  }

  function sharesOf(address _account) public view returns (uint256) {
    return shares[_account];
  }

  function sharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
    return Math.mulDiv(_ethAmount, totalShares, totalPooledEther());
  }

  function pooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
    return Math.mulDiv(_sharesAmount, totalPooledEther(), totalShares);
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

  function transferSharesFrom(
    address _from,
    address _to,
    uint256 _sharesAmount
  ) external returns (uint256) {
    uint256 tokensAmount = pooledEthByShares(_sharesAmount);
    _spendAllowance(_from, msg.sender, tokensAmount);
    _transferShares(_from, _to, _sharesAmount);
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
    require(currentAllowance >= _subtractedValue, 'ALLOWANCE_BELOW_ZERO');
    _approve(msg.sender, _spender, currentAllowance - _subtractedValue);
    return true;
  }

  function _approve(address _account, address _spender, uint256 _amount) internal override {
    require(_account != address(0), 'APPROVE_FROM_ZERO_ADDR');
    require(_spender != address(0), 'APPROVE_TO_ZERO_ADDR');

    allowances[_account][_spender] = _amount;
    emit Approval(_account, _spender, _amount);
  }

  function _mintShares(address _to, uint256 _sharesAmount) internal whenNotPaused {
    require(_to != address(0), 'MINT_TO_ZERO_ADDR');

    shares[_to] = shares[_to] + _sharesAmount;
    totalShares += _sharesAmount;

    emit MintShares(_to, _sharesAmount);
  }

  function _burnShares(address _account, uint256 _sharesAmount) internal whenNotPaused {
    require(_account != address(0), 'BURN_FROM_ZERO_ADDR');
    require(_sharesAmount <= sharesOf(_account), 'BALANCE_EXCEEDED');

    shares[_account] = shares[_account] - _sharesAmount;
    totalShares -= _sharesAmount;

    emit BurnShares(_account, _sharesAmount);
  }

  function _transfer(address _from, address _to, uint256 _amount) internal override {
    uint256 _sharesToTransfer = sharesByPooledEth(_amount);
    _transferShares(_from, _to, _sharesToTransfer);
    emit Transfer(_from, _to, _amount);
  }

  function _transferShares(address _from, address _to, uint256 _sharesAmount) internal whenNotPaused {
    require(_from != address(0), 'TRANSFER_FROM_ZERO_ADDR');
    require(_to != address(0), 'TRANSFER_TO_ZERO_ADDR');
    require(_to != address(this), 'TRANSFER_TO_ST_CONTRACT');
    require(_sharesAmount <= sharesOf(_from), 'BALANCE_EXCEEDED');

    shares[_from] = shares[_from] - _sharesAmount;
    shares[_to] = shares[_to] + _sharesAmount;

    emit TransferShares(_from, _to, _sharesAmount);
  }

  function _spendAllowance(address _account, address _spender, uint256 _amount) internal override {
    uint256 currentAllowance = allowances[_account][_spender];
    if (currentAllowance != ~uint256(0)) {
      require(currentAllowance >= _amount, 'ALLOWANCE_EXCEEDED');
      _approve(_account, _spender, currentAllowance - _amount);
    }
  }

  /***********************
   ** LIQUIDITY **
   ***********************/

  bool public enableBorrow = true;

  function setEnableBorrow(bool _enable) external onlyRole(ADMIN_ROLE) {
    enableBorrow = _enable;
    emit SetEnableBorrow(_enable);
  }

  function addLiquidity() public payable whenNotPaused nonReentrant {
    uint256 sharesAmount = Math.mulDiv(msg.value, totalShares, totalPooledEther() - msg.value);

    _mintShares(msg.sender, sharesAmount);

    emit AddLiquidity(msg.sender, msg.value);
  }

  function removeLiquidity(uint256 _amount) public whenNotPaused nonReentrant {
    require(_amount > 0, 'ZERO_AMOUNT');
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');

    uint256 accountBalance = balanceOf(msg.sender);
    require(_amount <= accountBalance, 'AMOUNT_EXCEEDS_BALANCE');

    uint256 sharesToBurn = Math.mulDiv(_amount, sharesOf(msg.sender), accountBalance);

    _burnShares(msg.sender, sharesToBurn);

    payable(msg.sender).transfer(_amount);
    emit RemoveLiquidity(msg.sender, _amount);
  }

  function borrow(uint256 _amount, address _pool) public whenNotPaused nonReentrant onlyStakeTogether {
    require(enableBorrow, 'BORROW_DISABLED');
    require(_amount > 0, 'ZERO_AMOUNT');
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');

    (uint256[6] memory _shares, uint256[6] memory _amounts) = feesContract.estimateFeePercentage(
      Fees.FeeType.Borrow,
      _amount
    );

    if (_shares[0] > 0) {
      stakeTogether.mintFeeShares{ value: _amounts[0] }(_pool, _shares[0]);
    }

    if (_shares[1] > 0) {
      stakeTogether.mintFeeShares{ value: _amounts[1] }(
        feesContract.getFeeAddress(Fees.Roles.Operators),
        _shares[1]
      );
    }

    if (_shares[2] > 0) {
      stakeTogether.mintFeeShares{ value: _amounts[2] }(
        feesContract.getFeeAddress(Fees.Roles.StakeTogether),
        _shares[2]
      );
    }

    payable(address(stakeTogether)).transfer(_amounts[3]);

    stakeTogether.setLoanBalance(stakeTogether.loanBalance() + _amount + _amounts[4]);

    payable(msg.sender).transfer(_amounts[5]);

    emit Borrow(msg.sender, _amount);
  }

  function repayLoan() public payable nonReentrant onlyStakeTogether {
    require(msg.value > 0, 'ZERO_AMOUNT');
    emit RepayLoan(msg.sender, msg.value);
  }

  /***********************
   ** ANTICIPATION **
   ***********************/

  modifier onlyRouter() {
    require(msg.sender == address(routerContract), 'ONLY_DISTRIBUTOR_CONTRACT');
    _;
  }

  bool public enableAnticipation = false;

  function setEnableAnticipation(bool _enable) external onlyRole(ADMIN_ROLE) {
    enableAnticipation = _enable;
    emit SetEnableAnticipation(_enable);
  }

  function anticipateRewards(uint256 _amount, address _pool, uint256 _days) external nonReentrant {
    require(enableAnticipation, 'ANTICIPATION_DISABLED');
    require(_amount > 0, 'ZERO_AMOUNT');
    require(_days > 0, 'ZERO_DAYS');

    uint256 accountBalance = stakeTogether.balanceOf(msg.sender);
    require(accountBalance >= _amount, 'INSUFFICIENT_USER_BALANCE');

    (
      uint256 anticipatedValue,
      uint256 riskMarginValue,
      uint256 reduction,
      uint256[6] memory anticipationShares,
      uint256[6] memory anticipationAmounts,
      uint256 daysBlock
    ) = feesContract.estimateAnticipation(_amount, _days);

    require(address(this).balance >= anticipatedValue, 'INSUFFICIENT_CONTRACT_BALANCE');

    uint256 sharesToLock = stakeTogether.sharesByPooledEth(riskMarginValue);

    stakeTogether.lockShares(sharesToLock, riskMarginValue, daysBlock);

    if (anticipationShares[0] > 0) {
      stakeTogether.mintFeeShares(_pool, anticipationShares[0]);
    }

    if (anticipationShares[1] > 0) {
      stakeTogether.mintFeeShares(
        feesContract.getFeeAddress(Fees.Roles.Operators),
        anticipationShares[1]
      );
    }

    if (anticipationShares[2] > 0) {
      stakeTogether.mintFeeShares(
        feesContract.getFeeAddress(Fees.Roles.StakeTogether),
        anticipationShares[2]
      );
    }

    payable(address(stakeTogether)).transfer(anticipationAmounts[3]);

    stakeTogether.setLoanBalance(stakeTogether.loanBalance() + _amount + anticipationAmounts[4]);

    require(riskMarginValue > 0, 'ZERO_VALUE');
    payable(msg.sender).transfer(riskMarginValue);

    emit AnticipateRewards(msg.sender, _amount, anticipatedValue, reduction);
  }

  /***************
   ** REDEPOSIT **
   ***************/

  uint256 public maxBatchSize = 100;

  function setMaxBatchSize(uint256 _size) external onlyRole(ADMIN_ROLE) {
    require(_size > 0, 'ZERO_SIZE');
    maxBatchSize = _size;
    emit SetMaxBatchSize(_size);
  }

  function reDeposit(
    uint256 _amount,
    address _pool,
    address _referral
  ) public whenNotPaused nonReentrant onlyRole(ORACLE_REWARDS_ROLE) {
    require(_amount > 0, 'ZERO_AMOUNT');
    require(balanceOf(msg.sender) >= _amount, 'INSUFFICIENT_LETH_BALANCE');
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');

    _burn(msg.sender, _amount);
    stakeTogether.depositPool{ value: _amount }(_pool, _referral);
    emit ReDeposit(msg.sender, _amount);
  }

  function reDepositBatch(
    uint256[] memory _amounts,
    address[] memory _pools,
    address[] memory _referrals
  ) public whenNotPaused nonReentrant onlyRole(ORACLE_REWARDS_ROLE) {
    require(_amounts.length <= maxBatchSize, 'BATCH_SIZE_TOO_LARGE');
    require(_amounts.length == _pools.length, 'ARRAY_LENGTH_MISMATCH');
    require(_pools.length == _referrals.length, 'ARRAY_LENGTH_MISMATCH');

    for (uint i = 0; i < _amounts.length; i++) {
      require(_amounts[i] > 0, 'ZERO_AMOUNT');
      require(balanceOf(msg.sender) >= _amounts[i], 'INSUFFICIENT_LETH_BALANCE');
      require(address(this).balance >= _amounts[i], 'INSUFFICIENT_ETH_BALANCE');

      _burn(msg.sender, _amounts[i]);
      stakeTogether.depositPool{ value: _amounts[i] }(_pools[i], _referrals[i]);
    }

    emit ReDepositBatch(msg.sender, _amounts);
  }
}
