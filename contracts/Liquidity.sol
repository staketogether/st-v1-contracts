// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './StakeTogether.sol';
import './Router.sol';
import './Fees.sol';

import './interfaces/IFees.sol';

/// @custom:security-contact security@staketogether.app
contract Liquidity is
  Initializable,
  ERC20Upgradeable,
  ERC20BurnableUpgradeable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  ERC20PermitUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuardUpgradeable
{
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  StakeTogether public stakeTogether;
  Router public routerContract;
  Fees public feesContract;
  bool private bootstrapped = false;

  event Bootstrap(address sender, uint256 balance);
  event MintRewardsWithdrawalLenders(address indexed sender, uint amount);
  event MintRewardsWithdrawalLendersFallback(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);
  event SetRouterContract(address routerContract);
  event SetFees(address feesContract);
  event MintShares(address indexed to, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  event SetEnableLiquidity(bool enable);
  event SetEnableDeposit(bool enableDeposit);
  event SetDepositLimit(uint256 newLimit);
  event SetWithdrawalLimit(uint256 newLimit);
  event SetWithdrawalLiquidityLimit(uint256 newLimit);
  event SetMinDepositPoolAmount(uint256 amount);
  event SetBlocksInterval(uint256 blocksInterval);
  event DepositPool(address indexed user, uint256 amount);
  event WithdrawPool(address indexed user, uint256 amount);
  event WithdrawLiquidity(address indexed user, uint256 amount);
  event SupplyLiquidity(address indexed user, uint256 amount);

  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __ERC20_init('ST Liquidity Provider ETH', 'lpETH');
    __ERC20Burnable_init();
    __Pausable_init();
    __AccessControl_init();
    __ERC20Permit_init('ST Liquidity Provider ETH');
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
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

  receive() external payable {
    emit MintRewardsWithdrawalLenders(msg.sender, msg.value);
  }

  fallback() external payable {
    emit MintRewardsWithdrawalLendersFallback(msg.sender, msg.value);
  }

  function bootstrap() external payable {
    require(!bootstrapped, 'ALREADY_BOOTSTRAPPED');
    require(hasRole(ADMIN_ROLE, msg.sender), 'ONLY_ADMIN');

    bootstrapped = true;

    _mintShares(address(this), msg.value);

    emit Bootstrap(msg.sender, msg.value);
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

  function setRouterContract(address _routerContract) external onlyRole(ADMIN_ROLE) {
    require(_routerContract != address(0), 'ROUTER_CONTRACT_ALREADY_SET');
    routerContract = Router(payable(_routerContract));
    emit SetRouterContract(_routerContract);
  }

  function setFees(address _feesContract) external onlyRole(ADMIN_ROLE) {
    require(_feesContract != address(0), 'FEES_CONTRACT_ALREADY_SET');
    feesContract = Fees(payable(_feesContract));
    emit SetFees(_feesContract);
  }

  /************
   ** SHARES **
   ************/

  mapping(address => uint256) private withdrawalsShares;
  uint256 public totalWithdrawalsShares = 0;
  mapping(address => mapping(address => uint256)) private allowances;

  function totalPooledEther() public view returns (uint256) {
    return address(this).balance + stakeTogether.liquidityBalance();
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
    return MathUpgradeable.mulDiv(_ethAmount, totalWithdrawalsShares, totalPooledEther());
  }

  function pooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
    return
      MathUpgradeable.mulDiv(
        _sharesAmount,
        totalPooledEther(),
        totalWithdrawalsShares,
        MathUpgradeable.Rounding.Up
      );
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

  bool public enableLiquidity = true;
  bool public enableDeposit = true;
  uint256 public minDepositAmount = 0.001 ether;
  uint256 public depositLimit = 1000 ether;
  uint256 public withdrawalLimit = 1000 ether;
  uint256 public withdrawalLiquidityLimit = 1000 ether;
  uint256 public blocksPerDay = 6500;
  uint256 public lastResetBlock;
  uint256 public totalDeposited;
  uint256 public totalWithdrawn;
  uint256 public totalLiquidityWithdrawn;

  function depositPool() public payable whenNotPaused nonReentrant {
    require(enableDeposit, 'DEPOSIT_DISABLED');
    require(msg.value > 0, 'ZERO_VALUE');
    require(msg.value >= minDepositAmount, 'AMOUNT_BELOW_MIN_DEPOSIT');

    _resetLimits();

    (uint256[8] memory _shares, uint256[8] memory _amounts) = feesContract.estimateFeePercentage(
      IFees.FeeType.LiquidityProvideEntry,
      msg.value
    );

    IFees.FeeRoles[8] memory roles = feesContract.getFeesRoles();
    for (uint i = 0; i < roles.length - 1; i++) {
      if (_shares[i] > 0) {
        stakeTogether.mintRewards{ value: _amounts[i] }(
          feesContract.getFeeAddress(roles[i]),
          feesContract.getFeeAddress(IFees.FeeRoles.StakeTogether),
          _shares[i]
        );
      }
    }

    totalDeposited += msg.value;

    emit DepositPool(msg.sender, msg.value);
  }

  function withdrawPool(uint256 _amount) public whenNotPaused nonReentrant {
    require(_amount > 0, 'ZERO_AMOUNT');
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');

    uint256 accountBalance = balanceOf(msg.sender);
    require(_amount <= accountBalance, 'AMOUNT_EXCEEDS_BALANCE');

    _resetLimits();

    uint256 sharesToBurn = MathUpgradeable.mulDiv(_amount, sharesOf(msg.sender), accountBalance);

    _burnShares(msg.sender, sharesToBurn);

    totalWithdrawn += _amount;

    payable(msg.sender).transfer(_amount);
    emit WithdrawPool(msg.sender, _amount);
  }

  function withdrawLiquidity(
    uint256 _amount,
    address _pool
  ) public whenNotPaused nonReentrant onlyStakeTogether {
    require(enableLiquidity, 'LIQUIDITY_DISABLED');
    require(_amount > 0, 'ZERO_AMOUNT');
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');

    (uint256[8] memory _shares, uint256[8] memory _amounts) = feesContract.estimateDynamicFeePercentage(
      IFees.FeeType.LiquidityProvide,
      _amount
    );

    IFees.FeeRoles[8] memory roles = feesContract.getFeesRoles();

    for (uint i = 0; i < roles.length - 1; i++) {
      if (_shares[i] > 0) {
        if (roles[i] == IFees.FeeRoles.Pools) {
          stakeTogether.mintRewards(_pool, _pool, _shares[i]);
        } else {
          stakeTogether.mintRewards(
            feesContract.getFeeAddress(roles[i]),
            feesContract.getFeeAddress(IFees.FeeRoles.StakeTogether),
            _shares[i]
          );
        }
      }
    }

    stakeTogether.setLiquidityBalance(stakeTogether.liquidityBalance() + _amounts[7]);

    payable(msg.sender).transfer(_amounts[7]);

    totalLiquidityWithdrawn += _amounts[7];

    emit WithdrawLiquidity(msg.sender, _amount);
  }

  function supplyLiquidity() public payable nonReentrant onlyStakeTogether {
    require(msg.value > 0, 'ZERO_AMOUNT');
    emit SupplyLiquidity(msg.sender, msg.value);
  }

  function setEnableLiquidity(bool _enable) external onlyRole(ADMIN_ROLE) {
    enableLiquidity = _enable;
    emit SetEnableLiquidity(_enable);
  }

  function setEnableDeposit(bool _enableDeposit) external onlyRole(ADMIN_ROLE) {
    enableDeposit = _enableDeposit;
    emit SetEnableDeposit(_enableDeposit);
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

  function setWithdrawalLiquidityLimit(uint256 _newLimit) external onlyRole(ADMIN_ROLE) {
    withdrawalLiquidityLimit = _newLimit;
    emit SetWithdrawalLiquidityLimit(_newLimit);
  }

  function setBlocksInterval(uint256 _newBlocksInterval) external onlyRole(ADMIN_ROLE) {
    blocksPerDay = _newBlocksInterval;
    emit SetBlocksInterval(_newBlocksInterval);
  }

  function _resetLimits() internal {
    if (block.number > lastResetBlock + blocksPerDay) {
      totalDeposited = 0;
      totalWithdrawn = 0;
      totalLiquidityWithdrawn = 0;
      lastResetBlock = block.number;
    }
  }
}
