// SPDX-FileCopyrightText: 2023 Stake Together <info@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import 'hardhat/console.sol';

abstract contract CETH is ERC20, ERC20Permit, Pausable, Ownable, ReentrancyGuard {
  constructor() ERC20('Community Ether', 'CETH') ERC20Permit('Community Ether') {
    _bootstrap();
  }

  event Bootstrap(address sender, uint256 balance);

  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);

  mapping(address => uint256) private shares;
  uint256 public totalShares = 0;
  mapping(address => mapping(address => uint256)) private allowances;

  function _bootstrap() internal {
    address stakeTogether = address(this);
    uint256 balance = stakeTogether.balance;

    require(balance > 0, 'NON_ZERO_VALUE');

    _mintShares(stakeTogether, balance);
    _mintDelegatedShares(stakeTogether, stakeTogether, balance);

    setStakeTogetherFeeRecipient(msg.sender);
    setOperatorFeeRecipient(msg.sender);

    emit Bootstrap(msg.sender, balance);
  }

  function pause() public onlyOwner {
    _pause();
  }

  function unpause() public onlyOwner {
    _unpause();
  }

  function totalSupply() public view override returns (uint256) {
    return totalPooledEther();
  }

  function balanceOf(address _account) public view override returns (uint256) {
    return getPooledEthByShares(sharesOf(_account));
  }

  function sharesOf(address _account) public view returns (uint256) {
    return shares[_account];
  }

  function getSharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
    return (_ethAmount * totalShares) / totalPooledEther();
  }

  function getPooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
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
    uint256 tokensAmount = getPooledEthByShares(_sharesAmount);
    return tokensAmount;
  }

  function transferSharesFrom(
    address _from,
    address _to,
    uint256 _sharesAmount
  ) external returns (uint256) {
    uint256 tokensAmount = getPooledEthByShares(_sharesAmount);
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

    uint256 currentSenderShares = shares[_from];
    require(_sharesAmount <= currentSenderShares, 'BALANCE_EXCEEDED');

    shares[_from] = currentSenderShares - _sharesAmount;
    shares[_to] = shares[_to] + _sharesAmount;

    emit TransferShares(_from, _to, _sharesAmount);
  }

  function _approve(address _owner, address _spender, uint256 _amount) internal override {
    require(_owner != address(0), 'APPROVE_FROM_ZERO_ADDR');
    require(_spender != address(0), 'APPROVE_TO_ZERO_ADDR');

    allowances[_owner][_spender] = _amount;
    emit Approval(_owner, _spender, _amount);
  }

  function _mintShares(address _to, uint256 _sharesAmount) internal whenNotPaused {
    require(_to != address(0), 'MINT_TO_ZERO_ADDR');

    totalShares += _sharesAmount;
    shares[_to] = shares[_to] + _sharesAmount;

    emit TransferShares(address(0), _to, _sharesAmount);
  }

  function _burnShares(address _account, uint256 _sharesAmount) internal whenNotPaused {
    require(_account != address(0), 'BURN_FROM_ZERO_ADDR');

    uint256 accountShares = shares[_account];
    require(_sharesAmount <= accountShares, 'BALANCE_EXCEEDED');

    shares[_account] = accountShares - _sharesAmount;
    totalShares -= _sharesAmount;

    emit BurnShares(_account, _sharesAmount);
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

  event BurnDelegatedShares(address indexed from, address indexed delegate, uint256 sharesAmount);

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
    require(_isCommunity(_delegated), 'ONLY_CAN_DELEGATE_TO_COMMUNITY');
    require(delegates[_to].length < maxDelegations, 'MAX_DELEGATIONS_REACHED');

    delegatedShares[_delegated] += _sharesAmount;
    delegationsShares[_to][_delegated] += _sharesAmount;
    totalDelegatedShares += _sharesAmount;

    if (!isDelegator[_to][_delegated]) {
      delegates[_to].push(_delegated);
      isDelegator[_to][_delegated] = true;
    }

    emit TransferDelegatedShares(address(0), _to, _delegated, _sharesAmount);
  }

  function _burnDelegatedShares(
    address _from,
    address _delegated,
    uint256 _sharesAmount
  ) internal whenNotPaused {
    require(_from != address(0), 'BURN_FROM_ZERO_ADDR');
    require(_delegated != address(0), 'BURN_FROM_ZERO_ADDR');
    require(_isCommunity(_delegated), 'ONLY_CAN_BURN_FROM_COMMUNITY');

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

    // Transfer delegation shares proportionally
    for (uint256 i = 0; i < delegates[_from].length; i++) {
      address delegate = delegates[_from][i];
      uint256 delegationSharesToTransfer = (delegationSharesOf(_from, delegate) * _sharesToTransfer) /
        sharesOf(_from);

      // Subtract from the sender
      delegationsShares[_from][delegate] -= delegationSharesToTransfer;

      // If the recipient is not already a delegator for this delegate, add them
      if (!isDelegator[_to][delegate]) {
        require(delegates[_to].length < maxDelegations, 'MAX_DELEGATIONS_REACHED');
        delegates[_to].push(delegate);
        isDelegator[_to][delegate] = true;
      }

      // Add to the recipient
      delegationsShares[_to][delegate] += delegationSharesToTransfer;

      // If the sender no longer has any delegation shares for this delegate, remove them as a delegator
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
    require(_isCommunity(_toDelegated), 'ONLY_CAN_DELEGATE_TO_COMMUNITY');

    uint256 currentSenderShares = delegationsShares[_account][_fromDelegated];
    require(_sharesAmount <= currentSenderShares, 'BALANCE_EXCEEDED');

    delegatedShares[_fromDelegated] -= _sharesAmount;
    delegationsShares[_account][_fromDelegated] -= _sharesAmount;

    delegatedShares[_toDelegated] += _sharesAmount;
    delegationsShares[_account][_toDelegated] += _sharesAmount;

    emit TransferPoolDelegatedShares(_account, _fromDelegated, _toDelegated, _sharesAmount);
  }

  /*****************
   ** REWARDS **
   *****************/

  uint256 public contractBalance = address(this).balance;
  uint256 public transientBalance = 0;
  uint256 public beaconBalance = 0;

  address public stakeTogetherFeeRecipient;
  address public operatorFeeRecipient;

  // Todo: Define Basis point before audit
  uint256 public basisPoints = 1 ether;
  uint256 public stakeTogetherFee = 0.03 ether;
  uint256 public operatorFee = 0.03 ether;
  uint256 public communityFee = 0.03 ether;

  event ProcessRewards(
    uint256 preClBalance,
    uint256 posClBalance,
    uint256 rewards,
    uint256 growthFactor,
    uint256 stakeTogetherFee,
    uint256 operatorFee,
    uint256 communityFee,
    uint256 stakeTogetherFeeShares,
    uint256 operatorFeeShares,
    uint256 communityFeeShares
  );

  event TransferRewardsShares(address indexed from, address indexed to, uint256 sharesAmount);
  event SetStakeTogetherFeeRecipient(address indexed to);
  event SetOperatorFeeRecipient(address indexed to);
  event SetStakeTogetherFee(uint256 fee);
  event OperatorFeeSet(uint256 fee);
  event SetCommunityFee(uint256 fee);

  function setStakeTogetherFeeRecipient(address _to) public onlyOwner {
    require(_to != address(0), 'NON_ZERO_ADDR');
    stakeTogetherFeeRecipient = _to;
    emit SetStakeTogetherFeeRecipient(_to);
  }

  function setOperatorFeeRecipient(address _to) public onlyOwner {
    require(_to != address(0), 'NON_ZERO_ADDR');
    operatorFeeRecipient = _to;
    emit SetOperatorFeeRecipient(_to);
  }

  function setStakeTogetherFee(uint256 _fee) external onlyOwner {
    stakeTogetherFee = _fee;
    emit SetStakeTogetherFee(_fee);
  }

  function setCommunityFee(uint256 _fee) external onlyOwner {
    communityFee = _fee;
    emit SetCommunityFee(_fee);
  }

  function setOperatorFee(uint256 _fee) external onlyOwner {
    operatorFee = _fee;
    emit OperatorFeeSet(_fee);
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
    uint256 communityFeeAdjust = communityFee + (communityFee * growthFactor) / basisPoints;

    uint256 totalFee = stakeTogetherFeeAdjust + operatorFeeAdjust + communityFeeAdjust;

    uint256 sharesMintedAsFees = (rewards * totalFee * totalShares) /
      (totalPooledEtherWithRewards * basisPoints - rewards * totalFee);

    uint256 stakeTogetherFeeShares = (sharesMintedAsFees * stakeTogetherFeeAdjust) / totalFee;
    uint256 operatorFeeShares = (sharesMintedAsFees * operatorFeeAdjust) / totalFee;
    uint256 communityFeeShares = (sharesMintedAsFees * communityFeeAdjust) / totalFee;

    _mintShares(stakeTogetherFeeRecipient, stakeTogetherFeeShares);
    emit TransferRewardsShares(address(0), stakeTogetherFeeRecipient, stakeTogetherFeeShares);

    _mintShares(operatorFeeRecipient, operatorFeeShares);
    emit TransferRewardsShares(address(0), operatorFeeRecipient, operatorFeeShares);

    for (uint i = 0; i < communities.length; i++) {
      address community = communities[i];
      uint256 communityProportion = delegatedSharesOf(community);
      uint256 communityShares = (communityFeeShares * communityProportion) / totalDelegatedShares;
      _mintShares(community, communityShares);
      _mintDelegatedShares(community, community, communityShares);
      emit TransferRewardsShares(address(0), community, communityShares);
    }

    emit ProcessRewards(
      _preClBalance,
      _posClBalance,
      rewards,
      growthFactor,
      stakeTogetherFee,
      operatorFee,
      communityFee,
      stakeTogetherFeeShares,
      operatorFeeShares,
      communityFeeShares
    );
  }

  function _isStakeTogetherFeeRecipient(address account) internal view returns (bool) {
    return address(stakeTogetherFeeRecipient) == account;
  }

  function _isOperatorFeeRecipient(address account) internal view returns (bool) {
    return address(operatorFeeRecipient) == account;
  }

  /*****************
   ** COMMUNITIES **
   *****************/

  event AddCommunity(address account);
  event RemoveCommunity(address account);

  address[] private communities;

  function getCommunities() public view returns (address[] memory) {
    return communities;
  }

  function addCommunity(address account) external onlyOwner {
    require(account != address(0), 'ZERO_ADDR');
    require(!_isCommunity(account), 'NON_COMMUNITY');
    require(!_isStakeTogetherFeeRecipient(account), 'IS_STAKE_TOGETHER_FEE_RECIPIENT');
    require(!_isOperatorFeeRecipient(account), 'IS_OPERATOR_FEE_RECIPIENT');

    communities.push(account);
    emit AddCommunity(account);
  }

  function removeCommunity(address account) external onlyOwner {
    require(_isCommunity(account), 'COMMUNITY_NOT_FOUND');

    for (uint256 i = 0; i < communities.length; i++) {
      if (communities[i] == account) {
        communities[i] = communities[communities.length - 1];
        communities.pop();
        break;
      }
    }
    emit RemoveCommunity(account);
  }

  function isCommunity(address account) external view returns (bool) {
    return _isCommunity(account);
  }

  function _isCommunity(address account) internal view returns (bool) {
    if (account == address(this)) {
      return true;
    }

    for (uint256 i = 0; i < communities.length; i++) {
      if (communities[i] == account) {
        return true;
      }
    }
    return false;
  }
}
