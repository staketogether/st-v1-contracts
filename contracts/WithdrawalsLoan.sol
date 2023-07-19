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
contract WithdrawalsLoan is AccessControl, Pausable, ReentrancyGuard, ERC20, ERC20Burnable, ERC20Permit {
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  StakeTogether public stakeTogether;
  Router public routerContract;
  Fees public feesContract;

  event MintRewardsWithdrawalLenders(address indexed sender, uint amount); // @audit-ok | FM
  event MintRewardsWithdrawalLendersFallback(address indexed sender, uint amount); // @audit-ok | FM
  event SetStakeTogether(address stakeTogether);
  event SetRouter(address routerContract);
  event SetFeesContract(address feesContract);
  event MintShares(address indexed to, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  event SetEnableLoan(bool enable);
  event AddLiquidity(address indexed user, uint256 amount);
  event RemoveLiquidity(address indexed user, uint256 amount);
  event WithdrawLoan(address indexed user, uint256 amount);
  event RepayLoan(address indexed user, uint256 amount);

  constructor() ERC20('ST Withdrawals Loan Ether', 'wlETH') ERC20Permit('ST Withdrawals Loan Ether') {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
  }

  // @audit-ok | FM
  receive() external payable {
    emit MintRewardsWithdrawalLenders(msg.sender, msg.value);
  }

  // @audit-ok | FM
  fallback() external payable {
    emit MintRewardsWithdrawalLendersFallback(msg.sender, msg.value);
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

  // @audit-ok | FM
  function setRouter(address _routerContract) external onlyRole(ADMIN_ROLE) {
    require(_routerContract != address(0), 'ROUTER_CONTRACT_ALREADY_SET');
    routerContract = Router(payable(_routerContract));
    emit SetRouter(_routerContract);
  }

  function setFees(address _feesContract) external onlyRole(ADMIN_ROLE) {
    require(_feesContract != address(0), 'FEES_CONTRACT_ALREADY_SET');
    feesContract = Fees(payable(_feesContract));
    emit SetFeesContract(_feesContract);
  }

  /************
   ** SHARES **
   ************/

  mapping(address => uint256) private withdrawalsShares;
  uint256 public totalWithdrawalsShares = 0;
  mapping(address => mapping(address => uint256)) private allowances;

  function totalPooledEther() public view returns (uint256) {
    return address(this).balance + stakeTogether.withdrawalsLoanBalance();
  }

  function totalSupply() public view override returns (uint256) {
    return totalPooledEther();
  }

  function balanceOf(address _account) public view override returns (uint256) {
    return pooledEthByShares(sharesOf(_account));
  }

  function sharesOf(address _account) public view returns (uint256) {
    return withdrawalsShares[_account];
  }

  function sharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
    return Math.mulDiv(_ethAmount, totalWithdrawalsShares, totalPooledEther());
  }

  function pooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
    return Math.mulDiv(_sharesAmount, totalPooledEther(), totalWithdrawalsShares);
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

    withdrawalsShares[_to] = withdrawalsShares[_to] + _sharesAmount;
    totalWithdrawalsShares += _sharesAmount;

    emit MintShares(_to, _sharesAmount);
  }

  function _burnShares(address _account, uint256 _sharesAmount) internal whenNotPaused {
    require(_account != address(0), 'BURN_FROM_ZERO_ADDR');
    require(_sharesAmount <= sharesOf(_account), 'BALANCE_EXCEEDED');

    withdrawalsShares[_account] = withdrawalsShares[_account] - _sharesAmount;
    totalWithdrawalsShares -= _sharesAmount;

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

    withdrawalsShares[_from] = withdrawalsShares[_from] - _sharesAmount;
    withdrawalsShares[_to] = withdrawalsShares[_to] + _sharesAmount;

    emit TransferShares(_from, _to, _sharesAmount);
  }

  function _spendAllowance(address _account, address _spender, uint256 _amount) internal override {
    uint256 currentAllowance = allowances[_account][_spender];
    if (currentAllowance != ~uint256(0)) {
      require(currentAllowance >= _amount, 'ALLOWANCE_EXCEEDED');
      _approve(_account, _spender, currentAllowance - _amount);
    }
  }

  /***************
   ** LIQUIDITY **
   ***************/

  bool public enableLoan = true;

  function setEnableLoan(bool _enable) external onlyRole(ADMIN_ROLE) {
    enableLoan = _enable;
    emit SetEnableLoan(_enable);
  }

  function addLiquidity() public payable whenNotPaused nonReentrant {
    // Todo: add fee entry loans
    uint256 sharesAmount = Math.mulDiv(msg.value, totalWithdrawalsShares, totalPooledEther() - msg.value);
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

  function withdrawLoan(
    uint256 _amount,
    address _pool
  ) public whenNotPaused nonReentrant onlyStakeTogether {
    require(enableLoan, 'BORROW_DISABLED');
    require(_amount > 0, 'ZERO_AMOUNT');
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');

    (uint256[9] memory _shares, uint256[9] memory _amounts) = feesContract.estimateFeePercentage(
      Fees.FeeType.Lenders,
      _amount
    );

    if (_shares[0] > 0) {
      stakeTogether.mintFeeShares{ value: _amounts[0] }(_pool, _pool, _shares[0]);
    }

    if (_shares[1] > 0) {
      stakeTogether.mintFeeShares{ value: _amounts[1] }(
        feesContract.getFeeAddress(Fees.FeeRoles.Operators),
        feesContract.getFeeAddress(Fees.FeeRoles.StakeTogether),
        _shares[1]
      );
    }

    if (_shares[2] > 0) {
      stakeTogether.mintFeeShares{ value: _amounts[2] }(
        feesContract.getFeeAddress(Fees.FeeRoles.StakeTogether),
        feesContract.getFeeAddress(Fees.FeeRoles.StakeTogether),
        _shares[2]
      );
    }

    if (_shares[3] > 0) {
      stakeTogether.mintFeeShares{ value: _amounts[3] }(
        feesContract.getFeeAddress(Fees.FeeRoles.StakeAccounts),
        feesContract.getFeeAddress(Fees.FeeRoles.StakeTogether),
        _shares[3]
      );
    }

    stakeTogether.setWithdrawalsLoanBalance(
      stakeTogether.withdrawalsLoanBalance() + _amount + _amounts[6]
    );

    payable(msg.sender).transfer(_amounts[8]);

    emit WithdrawLoan(msg.sender, _amount);
  }

  function repayLoan() public payable nonReentrant onlyStakeTogether {
    require(msg.value > 0, 'ZERO_AMOUNT');
    emit RepayLoan(msg.sender, msg.value);
  }
}
