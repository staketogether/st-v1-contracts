// SPDX-FileCopyrightText: 2023 Stake Together Labs <info@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import './Validator.sol';
import './Distributor.sol';
import './Pool.sol';
import './stwETH.sol';

/// @custom:security-contact security@staketogether.app
abstract contract SETH is ERC20, ERC20Permit, Pausable, Ownable, ReentrancyGuard {
  Distributor public distributorContract;
  Pool public poolContract;
  Validator public validatorContract;
  stwETH public stwETHContract;

  constructor() ERC20('Stake Together Ether', 'SETH') ERC20Permit('Stake Together Ether') {
    _bootstrap();
  }

  event Bootstrap(address sender, uint256 balance);

  event MintShares(address indexed to, uint256 sharesAmount);
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);

  mapping(address => uint256) private shares;
  uint256 public totalShares = 0;
  mapping(address => mapping(address => uint256)) private allowances;

  function _bootstrap() internal {
    address stakeTogether = address(this);
    uint256 balance = stakeTogether.balance;

    require(balance > 0, 'NON_ZERO_VALUE');

    emit Bootstrap(msg.sender, balance);

    _mintShares(stakeTogether, balance);
    _mintPoolShares(stakeTogether, stakeTogether, balance);

    setStakeTogetherFeeAddress(msg.sender);
    setOperatorFeeAddress(msg.sender);
    setValidatorFeeAddress(msg.sender);
  }

  function contractBalance() public view returns (uint256) {
    return address(this).balance;
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

  function getSharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
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

  function totalPooledEther() public view virtual returns (uint256);

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
    uint256 _sharesToTransfer = getSharesByPooledEth(_amount);
    _transferShares(_from, _to, _sharesToTransfer);
    _transferDelegationShares(_from, _to, _sharesToTransfer);
    emit Transfer(_from, _to, _amount);
  }

  function _transferShares(address _from, address _to, uint256 _sharesAmount) internal whenNotPaused {
    require(_from != address(0), 'TRANSFER_FROM_ZERO_ADDR');
    require(_to != address(0), 'TRANSFER_TO_ZERO_ADDR');
    require(_to != address(this), 'TRANSFER_TO_CETH_CONTRACT');
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

  /*****************
   ** DELEGATIONS **
   *****************/

  mapping(address => uint256) private poolShares;
  uint256 public totalPoolShares = 0;
  mapping(address => mapping(address => uint256)) private delegationsShares;
  mapping(address => address[]) private delegates;
  mapping(address => mapping(address => bool)) private isDelegate;
  uint256 public maxDelegations = 64; // Todo: verify merkle tree

  event MintPoolShares(address indexed to, address indexed pool, uint256 sharesAmount);

  event TransferPoolShares(
    address indexed from,
    address indexed to,
    address indexed pool,
    uint256 sharesAmount
  );

  event BurnPoolShares(address indexed from, address indexed pool, uint256 sharesAmount);

  function poolSharesOf(address _account) public view returns (uint256) {
    return poolShares[_account];
  }

  function delegationSharesOf(address _account, address _pool) public view returns (uint256) {
    return delegationsShares[_account][_pool];
  }

  function transferPoolShares(address _to, address _pool, uint256 _sharesAmount) external {
    _transferPoolShares(msg.sender, _to, _pool, _sharesAmount);
  }

  function _mintPoolShares(address _to, address _pool, uint256 _sharesAmount) internal whenNotPaused {
    require(_to != address(0), 'MINT_TO_ZERO_ADDR');
    require(poolContract.isPool(_pool), 'ONLY_CAN_DELEGATE_TO_POOL');
    require(delegates[_to].length < maxDelegations, 'MAX_DELEGATIONS_REACHED');

    poolShares[_pool] += _sharesAmount;
    delegationsShares[_to][_pool] += _sharesAmount;
    totalPoolShares += _sharesAmount;

    if (!isDelegate[_to][_pool]) {
      delegates[_to].push(_pool);
      isDelegate[_to][_pool] = true;
    }

    emit MintPoolShares(_to, _pool, _sharesAmount);
  }

  function _burnPoolShares(address _from, address _pool, uint256 _sharesAmount) internal whenNotPaused {
    require(_from != address(0), 'BURN_FROM_ZERO_ADDR');
    require(poolContract.isPool(_pool), 'ONLY_CAN_BURN_FROM_POOL');

    poolShares[_pool] -= _sharesAmount;
    delegationsShares[_from][_pool] -= _sharesAmount;
    totalPoolShares -= _sharesAmount;

    if (delegationsShares[_from][_pool] == 0) {
      isDelegate[_from][_pool] = false;
      // Todo: revise, need to remove from delegates array
    }

    emit BurnPoolShares(_from, _pool, _sharesAmount);
  }

  function _transferDelegationShares(
    address _from,
    address _to,
    uint256 _sharesToTransfer
  ) internal whenNotPaused {
    require(_sharesToTransfer <= sharesOf(_from), 'TRANSFER_EXCEEDS_BALANCE');

    for (uint256 i = 0; i < delegates[_from].length; i++) {
      address pool = delegates[_from][i];
      uint256 delegationSharesToTransfer = Math.mulDiv(
        delegationSharesOf(_from, pool),
        _sharesToTransfer,
        sharesOf(_from)
      );

      delegationsShares[_from][pool] -= delegationSharesToTransfer;

      if (!isDelegate[_to][pool]) {
        require(delegates[_to].length < maxDelegations, 'MAX_DELEGATIONS_REACHED');
        delegates[_to].push(pool);
        isDelegate[_to][pool] = true;
      }

      delegationsShares[_to][pool] += delegationSharesToTransfer;

      if (delegationSharesOf(_from, pool) == 0) {
        isDelegate[_from][pool] = false;
      }

      emit TransferPoolShares(_from, _to, pool, delegationSharesToTransfer);
    }
  }

  function _transferPoolShares(
    address _account,
    address _from,
    address _to,
    uint256 _sharesAmount
  ) internal whenNotPaused {
    require(_from != address(0), 'TRANSFER_FROM_ZERO_ADDR');
    require(_to != address(0), 'TRANSFER_TO_ZERO_ADDR');
    require(_to != address(this), 'TRANSFER_TO_SETH_CONTRACT');
    require(poolContract.isPool(_to), 'ONLY_CAN_STAKE_TO_POOL');

    require(_sharesAmount <= delegationsShares[_account][_from], 'BALANCE_EXCEEDED');

    poolShares[_from] -= _sharesAmount;
    delegationsShares[_account][_from] -= _sharesAmount;

    poolShares[_to] += _sharesAmount;
    delegationsShares[_account][_to] += _sharesAmount;

    emit TransferPoolShares(_account, _from, _to, _sharesAmount);
  }

  /*****************
   ** ADDRESSES **
   *****************/

  address public poolFeeAddress;
  address public operatorFeeAddress;
  address public stakeTogetherFeeAddress;
  address public validatorFeeAddress;
  address public liquidityFeeAddress;

  event SetPoolFeeAddress(address indexed to);
  event SetOperatorFeeAddress(address indexed to);
  event SetStakeTogetherFeeAddress(address indexed to);
  event SetValidatorFeeAddress(address indexed to);
  event SetLiquidityFeeAddress(address indexed to);

  function setPoolFeeAddress(address _to) public onlyOwner {
    require(_to != address(0), 'NON_ZERO_ADDR');
    poolFeeAddress = _to;
    emit SetPoolFeeAddress(_to);
  }

  function setOperatorFeeAddress(address _to) public onlyOwner {
    require(_to != address(0), 'NON_ZERO_ADDR');
    operatorFeeAddress = _to;
    emit SetOperatorFeeAddress(_to);
  }

  function setStakeTogetherFeeAddress(address _to) public onlyOwner {
    require(_to != address(0), 'NON_ZERO_ADDR');
    stakeTogetherFeeAddress = _to;
    emit SetStakeTogetherFeeAddress(_to);
  }

  function setValidatorFeeAddress(address _to) public onlyOwner {
    require(_to != address(0), 'NON_ZERO_ADDR');
    validatorFeeAddress = _to;
    emit SetValidatorFeeAddress(_to);
  }

  function setLiquidityFeeAddress(address _to) public onlyOwner {
    require(_to != address(0), 'NON_ZERO_ADDR');
    liquidityFeeAddress = _to;
    emit SetLiquidityFeeAddress(_to);
  }

  /*****************
   ** FEES **
   *****************/

  uint256 public basisPoints = 1 ether;
  uint256 public stakeTogetherFee = 0.03 ether;
  uint256 public operatorFee = 0.03 ether;
  uint256 public poolFee = 0.03 ether;
  uint256 public validatorFee = 0.001 ether;

  event SetStakeTogetherFee(uint256 fee);
  event SetPoolFee(uint256 fee);
  event SetOperatorFee(uint256 fee);
  event SetNewPoolFee(uint256 fee);
  event SetValidatorFee(uint256 fee);

  function setStakeTogetherFee(uint256 _fee) external onlyOwner {
    stakeTogetherFee = _fee;
    emit SetStakeTogetherFee(_fee);
  }

  function setPoolFee(uint256 _fee) external onlyOwner {
    poolFee = _fee;
    emit SetPoolFee(_fee);
  }

  function setOperatorFee(uint256 _fee) external onlyOwner {
    operatorFee = _fee;
    emit SetOperatorFee(_fee);
  }

  function setValidatorFee(uint256 _fee) external onlyOwner {
    validatorFee = _fee;
    emit SetValidatorFee(_fee);
  }

  /*****************
   ** REWARDS **
   *****************/

  modifier onlyRewardsContract() {
    require(msg.sender == address(distributorContract), 'ONLY_REWARDS_CONTACT');
    _;
  }

  struct Reward {
    address recipient;
    uint256 shares;
    uint256 amount;
  }

  enum RewardType {
    StakeTogether,
    Operator,
    Pool
  }

  uint256 public beaconBalance = 0;

  event MintRewards(uint256 epoch, address indexed to, uint256 sharesAmount, RewardType rewardType);
  event MintLoss(uint256 epoch, uint256 amount);

  function mintRewards(
    uint256 _epoch,
    address _rewardAddress,
    uint256 _sharesAmount
  ) external payable nonReentrant onlyRewardsContract {
    _mintShares(_rewardAddress, _sharesAmount);
    _mintPoolShares(_rewardAddress, _rewardAddress, _sharesAmount);

    if (_rewardAddress == stakeTogetherFeeAddress) {
      emit MintRewards(_epoch, _rewardAddress, _sharesAmount, RewardType.StakeTogether);
    } else if (_rewardAddress == operatorFeeAddress) {
      emit MintRewards(_epoch, _rewardAddress, _sharesAmount, RewardType.Operator);
    } else {
      emit MintRewards(_epoch, _rewardAddress, _sharesAmount, RewardType.Pool);
    }
  }

  function mintLoss(uint256 _blockNumber, uint256 _lossAmount) external nonReentrant onlyRewardsContract {
    beaconBalance -= _lossAmount;
    require(totalPooledEther() - _lossAmount > 0, 'NEGATIVE_TOTAL_POOLED_ETHER_BALANCE');
    emit MintLoss(_blockNumber, _lossAmount);
  }
}
