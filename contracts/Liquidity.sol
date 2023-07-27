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

import './Fees.sol';
import './Router.sol';
import './StakeTogether.sol';

import './interfaces/IFees.sol';
import './interfaces/ILiquidity.sol';

/// @custom:security-contact security@staketogether.app
contract Liquidity is
  Initializable,
  ERC20Upgradeable,
  ERC20BurnableUpgradeable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  ERC20PermitUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuardUpgradeable,
  ILiquidity
{
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  StakeTogether public stakeTogether;
  Router public router;
  Fees public fees;
  Config public config;

  /// @custom:oz-upgrades-unsafe-allow constructor
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

    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);

    totalShares = 0;
  }

  function initializeShares() external payable onlyRole(ADMIN_ROLE) {
    require(totalShares == 0);
    _mintShares(msg.sender, msg.value);
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

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  modifier onlyStakeTogether() {
    require(msg.sender == address(stakeTogether), 'ONLY_STAKE_TOGETHER_CONTRACT');
    _;
  }

  function setRouter(address _router) external onlyRole(ADMIN_ROLE) {
    require(_router != address(0), 'ROUTER_CONTRACT_ALREADY_SET');
    router = Router(payable(_router));
    emit SetRouter(_router);
  }

  /************
   ** CONFIG **
   ************/

  function setConfig(Config memory _config) external onlyRole(ADMIN_ROLE) {
    config = _config;
    emit SetConfig(_config);
  }

  /************
   ** SHARES **
   ************/

  mapping(address => uint256) private shares;
  uint256 public totalShares;
  mapping(address => mapping(address => uint256)) private allowances;

  function totalPooledEther() public view returns (uint256) {
    return address(this).balance + stakeTogether.liquidityBalance();
  }

  function totalSupply() public view override returns (uint256) {
    return totalPooledEther();
  }

  function balanceOf(address _account) public view override returns (uint256) {
    return pooledEthByShares(shares[_account]);
  }

  function sharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
    return MathUpgradeable.mulDiv(_ethAmount, totalShares, totalPooledEther());
  }

  function pooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
    return
      MathUpgradeable.mulDiv(_sharesAmount, totalPooledEther(), totalShares, MathUpgradeable.Rounding.Up);
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
    require(_sharesAmount <= shares[_account], 'BALANCE_EXCEEDED');

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
    require(_sharesAmount <= shares[_from], 'BALANCE_EXCEEDED');

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

  /***************
   ** LIQUIDITY **
   ***************/

  uint256 public lastResetBlock;
  uint256 public totalDeposited;
  uint256 public totalWithdrawn;
  uint256 public totalLiquidityWithdrawn;

  function depositPool() public payable whenNotPaused nonReentrant {
    require(config.feature.Deposit, 'DEPOSIT_DISABLED');
    require(msg.value > 0, 'ZERO_VALUE');
    require(msg.value >= config.minDepositAmount, 'AMOUNT_BELOW_MIN_DEPOSIT');

    _resetLimits();

    (uint256[8] memory _shares, uint256[8] memory _amounts) = fees.estimateFeePercentage(
      IFees.FeeType.LiquidityProvideEntry,
      msg.value
    );

    IFees.FeeRoles[8] memory roles = fees.getFeesRoles();
    for (uint i = 0; i < roles.length - 1; i++) {
      if (_shares[i] > 0) {
        stakeTogether.mintRewards{ value: _amounts[i] }(
          fees.getFeeAddress(roles[i]),
          fees.getFeeAddress(IFees.FeeRoles.StakeTogether),
          _shares[i]
        );
      }
    }

    totalDeposited += msg.value;

    emit DepositPool(msg.sender, msg.value);
  }

  function withdrawPool(uint256 _amount) public whenNotPaused nonReentrant {
    require(config.feature.Withdraw, 'WITHDRAW_DISABLED');
    require(_amount > 0, 'ZERO_AMOUNT');
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');

    uint256 accountBalance = balanceOf(msg.sender);
    require(_amount <= accountBalance, 'AMOUNT_EXCEEDS_BALANCE');

    _resetLimits();

    uint256 sharesToBurn = MathUpgradeable.mulDiv(_amount, shares[msg.sender], accountBalance);
    _burnShares(msg.sender, sharesToBurn);
    totalWithdrawn += _amount;

    payable(msg.sender).transfer(_amount);
    emit WithdrawPool(msg.sender, _amount);
  }

  function withdrawLiquidity(
    uint256 _amount,
    address _pool
  ) public whenNotPaused nonReentrant onlyStakeTogether {
    require(config.feature.Liquidity, 'LIQUIDITY_DISABLED');
    require(_amount > 0, 'ZERO_AMOUNT');
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');

    (uint256[8] memory _shares, uint256[8] memory _amounts) = fees.estimateDynamicFeePercentage(
      IFees.FeeType.LiquidityProvide,
      _amount
    );

    IFees.FeeRoles[8] memory roles = fees.getFeesRoles();

    for (uint i = 0; i < roles.length - 1; i++) {
      if (_shares[i] > 0) {
        if (roles[i] == IFees.FeeRoles.Pools) {
          stakeTogether.mintRewards(_pool, _pool, _shares[i]);
        } else {
          stakeTogether.mintRewards(
            fees.getFeeAddress(roles[i]),
            fees.getFeeAddress(IFees.FeeRoles.StakeTogether),
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

  function _resetLimits() internal {
    if (block.number > lastResetBlock + config.blocksInterval) {
      totalDeposited = 0;
      totalWithdrawn = 0;
      totalLiquidityWithdrawn = 0;
      lastResetBlock = block.number;
    }
  }
}
