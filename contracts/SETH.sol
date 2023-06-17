// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

abstract contract SETH is ERC20, ERC20Permit, Pausable, Ownable, ReentrancyGuard {
  constructor() ERC20('ST Staked Ether', 'SETH') ERC20Permit('ST Staked Ether') {
    _bootstrap();
  }

  event Bootstrap(address sender, uint256 balance);

  event MintShares(address indexed from, address indexed to, uint256 sharesAmount);
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
    _mintDelegatedShares(stakeTogether, stakeTogether, balance);

    setStakeTogetherFeeAddress(msg.sender);
    setOperatorFeeAddress(msg.sender);
    setValidatorModuleAddress(msg.sender);
    setPoolModuleAddress(msg.sender);
  }

  function pause() public onlyOwner {
    _pause();
  }

  function unpause() public onlyOwner {
    _unpause();
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
    return (_ethAmount * totalShares) / totalPooledEther();
  }

  function pooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
    return (_sharesAmount * totalPooledEther()) / totalShares;
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

  function allowance(address _owner, address _spender) public view override returns (uint256) {
    return allowances[_owner][_spender];
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

  function _approve(address _owner, address _spender, uint256 _amount) internal override {
    require(_owner != address(0), 'APPROVE_FROM_ZERO_ADDR');
    require(_spender != address(0), 'APPROVE_TO_ZERO_ADDR');

    allowances[_owner][_spender] = _amount;
    emit Approval(_owner, _spender, _amount);
  }

  function _mintShares(address _to, uint256 _sharesAmount) internal whenNotPaused {
    require(_to != address(0), 'MINT_TO_ZERO_ADDR');

    shares[_to] = shares[_to] + _sharesAmount;
    totalShares += _sharesAmount;

    emit MintShares(address(0), _to, _sharesAmount);
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

  function _spendAllowance(address _owner, address _spender, uint256 _amount) internal override {
    uint256 currentAllowance = allowances[_owner][_spender];
    if (currentAllowance != ~uint256(0)) {
      require(currentAllowance >= _amount, 'ALLOWANCE_EXCEEDED');
      _approve(_owner, _spender, currentAllowance - _amount);
    }
  }

  /*****************
   ** DELEGATIONS **
   *****************/

  uint256 public maxDelegations = 64;
  mapping(address => uint256) private delegatedShares;
  uint256 public totalDelegatedShares = 0;
  mapping(address => mapping(address => uint256)) private delegationsShares;
  mapping(address => address[]) private delegates;
  mapping(address => mapping(address => bool)) private isDelegator;

  event MintDelegatedShares(
    address indexed from,
    address indexed to,
    address indexed delegated,
    uint256 sharesAmount
  );

  event TransferDelegatedShares(
    address indexed from,
    address indexed to,
    address indexed delegated,
    uint256 sharesAmount
  );

  event TransferPoolDelegatedShares(
    address indexed account,
    address indexed fromDelegated,
    address indexed toDelegated,
    uint256 sharesAmount
  );

  event BurnDelegatedShares(address indexed from, address indexed delegated, uint256 sharesAmount);

  function delegatedSharesOf(address _account) public view returns (uint256) {
    return delegatedShares[_account];
  }

  function delegationSharesOf(address _account, address _delegate) public view returns (uint256) {
    return delegationsShares[_account][_delegate];
  }

  function transferPoolDelegatedShares(
    address _fromDelegated,
    address _toDelegated,
    uint256 _sharesAmount
  ) external {
    _transferPoolDelegatedShares(msg.sender, _fromDelegated, _toDelegated, _sharesAmount);
  }

  function _mintDelegatedShares(
    address _to,
    address _delegated,
    uint256 _sharesAmount
  ) internal whenNotPaused {
    require(_to != address(0), 'MINT_TO_ZERO_ADDR');
    require(_delegated != address(0), 'MINT_TO_ZERO_ADDR');
    require(isPool(_delegated), 'ONLY_CAN_DELEGATE_TO_POOL');
    require(delegates[_to].length < maxDelegations, 'MAX_DELEGATIONS_REACHED');

    delegatedShares[_delegated] += _sharesAmount;
    delegationsShares[_to][_delegated] += _sharesAmount;
    totalDelegatedShares += _sharesAmount;

    if (!isDelegator[_to][_delegated]) {
      delegates[_to].push(_delegated);
      isDelegator[_to][_delegated] = true;
    }

    emit MintDelegatedShares(address(0), _to, _delegated, _sharesAmount);
  }

  function _burnDelegatedShares(
    address _from,
    address _delegated,
    uint256 _sharesAmount
  ) internal whenNotPaused {
    require(_from != address(0), 'BURN_FROM_ZERO_ADDR');
    require(_delegated != address(0), 'BURN_FROM_ZERO_ADDR');
    require(isPool(_delegated), 'ONLY_CAN_BURN_FROM_POOL');

    delegatedShares[_delegated] -= _sharesAmount;
    delegationsShares[_from][_delegated] -= _sharesAmount;
    totalDelegatedShares -= _sharesAmount;

    if (delegationsShares[_from][_delegated] == 0) {
      isDelegator[_from][_delegated] = false;
    }

    emit BurnDelegatedShares(_from, _delegated, _sharesAmount);
  }

  function _transferDelegationShares(
    address _from,
    address _to,
    uint256 _sharesToTransfer
  ) internal whenNotPaused {
    require(_sharesToTransfer <= sharesOf(_from), 'TRANSFER_EXCEEDS_BALANCE');

    for (uint256 i = 0; i < delegates[_from].length; i++) {
      address delegate = delegates[_from][i];
      uint256 delegationSharesToTransfer = (delegationSharesOf(_from, delegate) * _sharesToTransfer) /
        sharesOf(_from);

      delegationsShares[_from][delegate] -= delegationSharesToTransfer;

      if (!isDelegator[_to][delegate]) {
        require(delegates[_to].length < maxDelegations, 'MAX_DELEGATIONS_REACHED');
        delegates[_to].push(delegate);
        isDelegator[_to][delegate] = true;
      }

      delegationsShares[_to][delegate] += delegationSharesToTransfer;

      if (delegationSharesOf(_from, delegate) == 0) {
        isDelegator[_from][delegate] = false;
      }

      emit TransferDelegatedShares(_from, _to, delegate, delegationSharesToTransfer);
    }
  }

  function _transferPoolDelegatedShares(
    address _account,
    address _fromDelegated,
    address _toDelegated,
    uint256 _sharesAmount
  ) internal whenNotPaused {
    require(_fromDelegated != address(0), 'TRANSFER_FROM_ZERO_ADDR');
    require(_toDelegated != address(0), 'TRANSFER_TO_ZERO_ADDR');
    require(_toDelegated != address(this), 'TRANSFER_TO_CETH_CONTRACT');
    require(isPool(_toDelegated), 'ONLY_CAN_DELEGATE_TO_POOL');

    require(_sharesAmount <= delegationsShares[_account][_fromDelegated], 'BALANCE_EXCEEDED');

    delegatedShares[_fromDelegated] -= _sharesAmount;
    delegationsShares[_account][_fromDelegated] -= _sharesAmount;

    delegatedShares[_toDelegated] += _sharesAmount;
    delegationsShares[_account][_toDelegated] += _sharesAmount;

    emit TransferPoolDelegatedShares(_account, _fromDelegated, _toDelegated, _sharesAmount);
  }

  /*****************
   ** ADDRESSES **
   *****************/

  address public stakeTogetherFeeAddress;
  address public operatorFeeAddress;
  address public validatorModuleAddress;
  address public poolModuleAddress;

  event SetStakeTogetherFeeAddress(address indexed to);
  event SetOperatorFeeAddress(address indexed to);
  event SetValidatorModuleAddress(address indexed to);
  event SetPoolModuleAddress(address indexed to);

  function setStakeTogetherFeeAddress(address _to) public onlyOwner {
    require(_to != address(0), 'NON_ZERO_ADDR');
    stakeTogetherFeeAddress = _to;
    emit SetStakeTogetherFeeAddress(_to);
  }

  function setOperatorFeeAddress(address _to) public onlyOwner {
    require(_to != address(0), 'NON_ZERO_ADDR');
    operatorFeeAddress = _to;
    emit SetOperatorFeeAddress(_to);
  }

  function setValidatorModuleAddress(address _to) public onlyOwner {
    require(_to != address(0), 'NON_ZERO_ADDR');
    validatorModuleAddress = _to;
    emit SetValidatorModuleAddress(_to);
  }

  function setPoolModuleAddress(address _to) public onlyOwner {
    require(_to != address(0), 'NON_ZERO_ADDR');
    poolModuleAddress = _to;
    emit SetPoolModuleAddress(_to);
  }

  /*****************
   ** REWARDS **
   *****************/
  uint256 public transientBalance = 0;
  uint256 public beaconBalance = 0;

  // Todo: Define Basis point before audit
  uint256 public basisPoints = 1 ether;
  uint256 public stakeTogetherFee = 0.03 ether;
  uint256 public operatorFee = 0.03 ether;
  uint256 public poolFee = 0.03 ether;

  event ProcessRewards(
    uint256 preClBalance,
    uint256 posClBalance,
    uint256 rewards,
    uint256 growthFactor,
    uint256 stakeTogetherFee,
    uint256 operatorFee,
    uint256 poolFee,
    uint256 stakeTogetherFeeShares,
    uint256 operatorFeeShares,
    uint256 poolFeeShares
  );

  event MintOperatorRewards(address indexed from, address indexed to, uint256 sharesAmount);
  event MintStakeTogetherRewards(address indexed from, address indexed to, uint256 sharesAmount);
  event MintPoolRewards(address indexed from, address indexed to, uint256 sharesAmount);

  event SetStakeTogetherFee(uint256 fee);
  event SetOperatorFee(uint256 fee);
  event SetPoolFee(uint256 fee);

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

  function setTransientBalance(uint256 _transientBalance) external virtual {}

  function setBeaconBalance(uint256 _beaconBalance) external virtual {}

  function _processRewards(uint256 _preClBalance, uint256 _posClBalance) internal {
    if (_posClBalance <= _preClBalance) {
      return;
    }

    uint256 rewards = _posClBalance - _preClBalance;
    uint256 totalPooledEtherWithRewards = totalPooledEther() + rewards;
    uint256 growthFactor = (rewards * basisPoints) / totalPooledEther();

    uint256 stakeTogetherFeeAdjust = stakeTogetherFee + (stakeTogetherFee * growthFactor) / basisPoints;
    uint256 operatorFeeAdjust = operatorFee + (operatorFee * growthFactor) / basisPoints;
    uint256 poolFeeAdjust = poolFee + (poolFee * growthFactor) / basisPoints;

    uint256 totalFee = stakeTogetherFeeAdjust + operatorFeeAdjust + poolFeeAdjust;

    uint256 sharesMintedAsFees = (rewards * totalFee * totalShares) /
      (totalPooledEtherWithRewards * basisPoints - rewards * totalFee);

    uint256 stakeTogetherFeeShares = (sharesMintedAsFees * stakeTogetherFeeAdjust) / totalFee;
    uint256 operatorFeeShares = (sharesMintedAsFees * operatorFeeAdjust) / totalFee;
    uint256 poolFeeShares = (sharesMintedAsFees * poolFeeAdjust) / totalFee;

    emit MintOperatorRewards(address(0), operatorFeeAddress, operatorFeeShares);
    _mintShares(operatorFeeAddress, operatorFeeShares);

    emit MintStakeTogetherRewards(address(0), stakeTogetherFeeAddress, stakeTogetherFeeShares);
    _mintShares(stakeTogetherFeeAddress, stakeTogetherFeeShares);

    for (uint i = 0; i < pools.length; i++) {
      address pool = pools[i];
      uint256 poolProportion = delegatedSharesOf(pool);
      uint256 poolShares = (poolFeeShares * poolProportion) / totalDelegatedShares;
      emit MintPoolRewards(address(0), pool, poolShares);
      _mintShares(pool, poolShares);
      _mintDelegatedShares(pool, pool, poolShares);
    }

    emit ProcessRewards(
      _preClBalance,
      _posClBalance,
      rewards,
      growthFactor,
      stakeTogetherFee,
      operatorFee,
      poolFee,
      stakeTogetherFeeShares,
      operatorFeeShares,
      poolFeeShares
    );
  }

  function _isStakeTogetherFeeAddress(address account) internal view returns (bool) {
    return address(stakeTogetherFeeAddress) == account;
  }

  function _isOperatorFeeAddress(address account) internal view returns (bool) {
    return address(operatorFeeAddress) == account;
  }

  /*****************
   ** POOLS **
   *****************/

  address[] private pools;

  modifier onlyPoolModule() {
    require(msg.sender == poolModuleAddress, 'ONLY_POOL_MODULE');
    _;
  }

  event AddPool(address account);
  event RemovePool(address account);

  function getPools() public view returns (address[] memory) {
    return pools;
  }

  function addPool(address account) external onlyPoolModule {
    require(account != address(0), 'ZERO_ADDR');
    require(!isPool(account), 'NON_POOL');
    require(!_isStakeTogetherFeeAddress(account), 'IS_STAKE_TOGETHER_FEE_RECIPIENT');
    require(!_isOperatorFeeAddress(account), 'IS_OPERATOR_FEE_RECIPIENT');

    pools.push(account);
    emit AddPool(account);
  }

  function removePool(address account) external onlyPoolModule {
    require(isPool(account), 'POOL_NOT_FOUND');

    for (uint256 i = 0; i < pools.length; i++) {
      if (pools[i] == account) {
        pools[i] = pools[pools.length - 1];
        pools.pop();
        break;
      }
    }
    emit RemovePool(account);
  }

  function isPool(address account) internal view returns (bool) {
    if (account == address(this)) {
      return true;
    }

    for (uint256 i = 0; i < pools.length; i++) {
      if (pools[i] == account) {
        return true;
      }
    }
    return false;
  }
}
