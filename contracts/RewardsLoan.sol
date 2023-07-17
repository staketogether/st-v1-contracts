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
contract RewardsLoan is AccessControl, Pausable, ReentrancyGuard, ERC20, ERC20Burnable, ERC20Permit {
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  StakeTogether public stakeTogether;
  Router public routerContract;
  Fees public feesContract;

  event MintRewardsAccounts(address indexed sender, uint amount);
  event MintRewardsAccountsFallback(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);
  event MintShares(address indexed to, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  event SetEnableLoan(bool enable);
  event AddLiquidity(address indexed user, uint256 amount);
  event RemoveLiquidity(address indexed user, uint256 amount);
  event AnticipateRewards(
    address indexed user,
    uint256 anticipatedAmount,
    uint256 netAmount,
    uint256 fee
  );

  constructor(
    address _routerContract,
    address _feesContract
  ) ERC20('ST Rewards Loan Ether', 'rlETH') ERC20Permit('ST Rewards Loan Ether') {
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

  mapping(address => uint256) private rewardsShares;
  uint256 public totalRewardsShares = 0;
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
    return rewardsShares[_account];
  }

  function sharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
    return Math.mulDiv(_ethAmount, totalRewardsShares, totalPooledEther());
  }

  function pooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
    return Math.mulDiv(_sharesAmount, totalPooledEther(), totalRewardsShares);
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

    rewardsShares[_to] = rewardsShares[_to] + _sharesAmount;
    totalRewardsShares += _sharesAmount;

    emit MintShares(_to, _sharesAmount);
  }

  function _burnShares(address _account, uint256 _sharesAmount) internal whenNotPaused {
    require(_account != address(0), 'BURN_FROM_ZERO_ADDR');
    require(_sharesAmount <= sharesOf(_account), 'BALANCE_EXCEEDED');

    rewardsShares[_account] = rewardsShares[_account] - _sharesAmount;
    totalRewardsShares -= _sharesAmount;

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

    rewardsShares[_from] = rewardsShares[_from] - _sharesAmount;
    rewardsShares[_to] = rewardsShares[_to] + _sharesAmount;

    emit TransferShares(_from, _to, _sharesAmount);
  }

  function _spendAllowance(address _account, address _spender, uint256 _amount) internal {
    uint256 currentAllowance = allowances[_account][_spender];
    if (currentAllowance != ~uint256(0)) {
      require(currentAllowance >= _amount, 'ALLOWANCE_EXCEEDED');
      _approve(_account, _spender, currentAllowance - _amount);
    }
  }

  /***********************
   ** LIQUIDITY **
   ***********************/

  bool public enableLoan = true;

  function setEnableLoan(bool _enable) external onlyRole(ADMIN_ROLE) {
    enableLoan = _enable;
    emit SetEnableLoan(_enable);
  }

  function addLiquidity() public payable whenNotPaused nonReentrant {
    // Todo: implement fee
    uint256 sharesAmount = Math.mulDiv(msg.value, totalRewardsShares, totalPooledEther() - msg.value);

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

  /***********************
   ** ANTICIPATION **
   ***********************/

  modifier onlyRouter() {
    require(msg.sender == address(routerContract), 'ONLY_DISTRIBUTOR_CONTRACT');
    _;
  }

  function anticipateRewards(uint256 _amount, address _pool, uint256 _days) external nonReentrant {
    require(enableLoan, 'ANTICIPATION_DISABLED');
    require(_amount > 0, 'ZERO_AMOUNT');
    require(_days > 0, 'ZERO_DAYS');

    uint256 accountBalance = stakeTogether.balanceOf(msg.sender);
    require(accountBalance >= _amount, 'INSUFFICIENT_USER_BALANCE');

    // (
    //   uint256 maxValue,
    //   uint256 secureValue,
    //   uint256 reduction,
    //   uint256[7] memory _shares,
    //   uint256[7] memory _amounts,
    //   uint256 daysBlock
    // ) = feesContract.estimateAnticipation(_amount, _days);

    // require(address(this).balance >= maxValue, 'INSUFFICIENT_CONTRACT_BALANCE');

    // uint256 lockShares = stakeTogether.sharesByPooledEth(secureValue);

    // uint256 debitShares = 0;
    // // Todo: implement operation

    // stakeTogether.lockShares(msg.sender, lockShares, debitShares, daysBlock, _pool);

    // if (_shares[0] > 0) {
    //   stakeTogether.mintFeeShares{ value: _amounts[0] }(_pool, _pool, _shares[0]);
    // }

    // if (_shares[1] > 0) {
    //   stakeTogether.mintFeeShares{ value: _amounts[1] }(
    //     feesContract.getFeeAddress(Fees.FeeRoles.Operators),
    //     feesContract.getFeeAddress(Fees.FeeRoles.StakeTogether),
    //     _shares[1]
    //   );
    // }

    // if (_shares[2] > 0) {
    //   stakeTogether.mintFeeShares{ value: _amounts[2] }(
    //     feesContract.getFeeAddress(Fees.FeeRoles.StakeTogether),
    //     feesContract.getFeeAddress(Fees.FeeRoles.StakeTogether),
    //     _shares[2]
    //   );
    // }

    // if (_shares[3] > 0) {
    //   stakeTogether.mintFeeShares(
    //     feesContract.getFeeAddress(Fees.FeeRoles.Accounts),
    //     feesContract.getFeeAddress(Fees.FeeRoles.StakeTogether),
    //     _shares[3]
    //   );
    // }

    // stakeTogether.setWithdrawalsLoanBalance(
    //   stakeTogether.withdrawalsLoanBalance() + _amount + _amounts[4]
    // );

    // require(secureValue > 0, 'ZERO_VALUE');
    // payable(msg.sender).transfer(secureValue);

    // emit AnticipateRewards(msg.sender, _amount, maxValue, reduction);
  }
}
