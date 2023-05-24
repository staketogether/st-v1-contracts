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

  mapping(address => uint256) private shares;
  uint256 public totalShares = 0;
  mapping(address => mapping(address => uint256)) private allowances;

  event SharesBurnt(
    address indexed account,
    uint256 preRebaseTokenAmount,
    uint256 postRebaseTokenAmount,
    uint256 sharesAmount
  );

  event TransferShares(address indexed from, address indexed to, uint256 sharesValue);

  function _bootstrap() internal {
    address stakeTogether = address(this);
    uint256 balance = stakeTogether.balance;

    require(balance > 0, 'NON_ZERO_VALUE');

    _mintShares(stakeTogether, balance);
    _mintDelegatedShares(stakeTogether, stakeTogether, balance);
  }

  function pause() public onlyOwner {
    _pause();
  }

  function unpause() public onlyOwner {
    _unpause();
  }

  function totalSupply() public view override returns (uint256) {
    return getTotalPooledEther();
  }

  function balanceOf(address _account) public view override returns (uint256) {
    return getPooledEthByShares(sharesOf(_account));
  }

  function sharesOf(address _account) public view returns (uint256) {
    return shares[_account];
  }

  function getSharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
    return (_ethAmount * totalShares) / getTotalPooledEther();
  }

  function getPooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
    return (_sharesAmount * getTotalPooledEther()) / totalShares;
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

  function getTotalPooledEther() public view virtual returns (uint256);

  function _transfer(address _from, address _to, uint256 _amount) internal override {
    uint256 _sharesToTransfer = getSharesByPooledEth(_amount);
    _transferShares(_from, _to, _sharesToTransfer);
    emit Transfer(_from, _to, _amount);
  }

  function _transferShares(address _from, address _to, uint256 _sharesAmount) internal whenNotPaused {
    require(_from != address(0), 'TRANSFER_FROM_ZERO_ADDR');
    require(_to != address(0), 'TRANSFER_TO_ZERO_ADDR');
    require(_to != address(this), 'TRANSFER_TO_STETH_CONTRACT');

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

    uint256 preRebaseTokenAmount = getPooledEthByShares(_sharesAmount);

    shares[_account] = accountShares - _sharesAmount;
    totalShares -= _sharesAmount;

    uint256 postRebaseTokenAmount = getPooledEthByShares(_sharesAmount);

    emit SharesBurnt(_account, preRebaseTokenAmount, postRebaseTokenAmount, _sharesAmount);
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

  event BurnDelegatedShares(
    address indexed from,
    address indexed delegate,
    uint256 sharesAmount,
    uint256 preDelegatedShares,
    uint256 postDelegatedShares,
    uint256 preTotalDelegatedShares,
    uint256 postTotalDelegatedShares
  );

  event TransferDelegatedShares(
    address indexed from,
    address indexed to,
    address indexed delegate,
    uint256 sharesValue
  );

  uint256 public maxDelegations = 128;
  mapping(address => uint256) private delegatedShares;
  uint256 public totalDelegatedShares = 0;

  mapping(address => mapping(address => uint256)) private delegations;
  mapping(address => address[]) private delegators;
  mapping(address => address[]) private delegateds;
  mapping(address => mapping(address => bool)) private alreadyDelegating;
  mapping(address => mapping(address => bool)) private alreadyDelegated;

  function delegationSharesOf(address _account, address _delegated) public view returns (uint256) {
    return delegations[_account][_delegated];
  }

  function delegatedSharesOf(address _account) public view returns (uint256) {
    return delegatedShares[_account];
  }

  function getDelegationsOf(address _address) public view returns (address[] memory, uint256[] memory) {
    address[] memory _delegatorAddresses = delegators[_address];
    uint256[] memory _delegatedAmount = new uint256[](_delegatorAddresses.length);

    for (uint i = 0; i < _delegatorAddresses.length; i++) {
      _delegatedAmount[i] = getPooledEthByShares(delegations[_delegatorAddresses[i]][_address]);
    }

    return (_delegatorAddresses, _delegatedAmount);
  }

  function getDelegatesOf(address _address) public view returns (address[] memory, uint256[] memory) {
    address[] memory _delegatedAddresses = delegateds[_address];
    uint256[] memory _delegatedAmount = new uint256[](_delegatedAddresses.length);

    for (uint i = 0; i < _delegatedAddresses.length; i++) {
      _delegatedAmount[i] = getPooledEthByShares(delegations[_address][_delegatedAddresses[i]]);
    }

    return (_delegatedAddresses, _delegatedAmount);
  }

  function _mintDelegatedShares(
    address _to,
    address _delegated,
    uint256 _sharesAmount
  ) internal whenNotPaused {
    require(_to != address(0), 'MINT_TO_ZERO_ADDR');
    require(_delegated != address(0), 'MINT_TO_ZERO_ADDR');
    require(delegators[_delegated].length < maxDelegations, 'MAX_DELEGATIONS_REACHED');
    require(_isCommunity(_delegated), 'ONLY_CAN_DELEGATE_TO_COMMUNITY');

    delegatedShares[_delegated] += _sharesAmount;
    delegations[_delegated][_to] += _sharesAmount;
    totalDelegatedShares += _sharesAmount;

    if (!alreadyDelegating[_to][_delegated]) {
      delegators[_to].push(_delegated);
      alreadyDelegating[_to][_delegated] = true;
    }

    if (!alreadyDelegated[_delegated][_to]) {
      delegateds[_delegated].push(_to);
      alreadyDelegated[_delegated][_to] = true;
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

    uint256 preDelegatedShares = delegatedShares[_delegated];
    uint256 preTotalDelegatedShares = totalDelegatedShares;

    delegatedShares[_delegated] -= _sharesAmount;
    delegations[_delegated][_from] -= _sharesAmount;
    totalDelegatedShares -= _sharesAmount;

    if (delegations[_delegated][_from] == 0) {
      alreadyDelegating[_from][_delegated] = false;

      for (uint i = 0; i < delegators[_from].length - 1; i++) {
        if (delegators[_from][i] == _delegated) {
          delegators[_from][i] = delegators[_from][delegators[_from].length - 1];
          break;
        }
      }
      delegators[_from].pop();
    }

    if (delegatedShares[_delegated] == 0) {
      alreadyDelegated[_delegated][_from] = false;

      for (uint i = 0; i < delegateds[_delegated].length - 1; i++) {
        if (delegateds[_delegated][i] == _from) {
          delegateds[_delegated][i] = delegateds[_delegated][delegateds[_delegated].length - 1];
          break;
        }
      }
      delegateds[_delegated].pop();
    }

    emit BurnDelegatedShares(
      _from,
      _delegated,
      _sharesAmount,
      preDelegatedShares,
      delegatedShares[_delegated],
      preTotalDelegatedShares,
      totalDelegatedShares
    );
  }

  /*****************
   ** REWARDS **
   *****************/

  uint256 public clBalance = 0;

  address public stakeTogetherFeeRecipient = owner();
  address public operatorFeeRecipient = owner();

  // Todo: Define Basis point before audit
  uint256 public basisPoints = 1 ether;
  uint256 public stakeTogetherFee = 0.03 ether;
  uint256 public operatorFee = 0.03 ether;
  uint256 public communityFee = 0.03 ether;

  // Todo: Remove rewards temp var before audit
  mapping(address => uint256) internal tempUserBalanceHistory;
  mapping(address => uint256) internal tempCommunityRewards;

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

  function setStakeTogetherFeeRecipient(address _to) external onlyOwner {
    require(_to != address(0), 'NON_ZERO_ADDR');
    stakeTogetherFeeRecipient = _to;
  }

  function setOperatorFeeRecipient(address _to) external onlyOwner {
    require(_to != address(0), 'NON_ZERO_ADDR');
    operatorFeeRecipient = _to;
  }

  function setStakeTogetherFee(uint256 _fee) external onlyOwner {
    stakeTogetherFee = _fee;
  }

  function setCommunityFee(uint256 _fee) external onlyOwner {
    communityFee = _fee;
  }

  function setOperatorFee(uint256 _fee) external onlyOwner {
    operatorFee = _fee;
  }

  function setClBalance(uint256 _balance) external virtual {}

  // Todo: temp remove before audit
  function getTempUserRewards(address _account) external view returns (uint256) {
    return getPooledEthByShares(sharesOf(_account)) - tempUserBalanceHistory[_account];
  }

  // Todo: temp remove before audit
  function getTempCommunityRewards(address _account) external view returns (uint256) {
    return getPooledEthByShares(tempCommunityRewards[_account]);
  }

  function _processRewards(uint256 _preClBalance, uint256 _posClBalance) internal {
    if (_posClBalance <= _preClBalance) {
      return;
    }

    uint256 rewards = _posClBalance - _preClBalance;
    uint256 totalPooledEtherWithRewards = getTotalPooledEther() + rewards;
    uint256 growthFactor = (rewards * basisPoints) / getTotalPooledEther();

    uint256 stakeTogetherFeeAdjust = stakeTogetherFee + (stakeTogetherFee * growthFactor) / basisPoints;
    uint256 operatorFeeAjust = operatorFee + (operatorFee * growthFactor) / basisPoints;
    uint256 communityFeeAjust = communityFee + (communityFee * growthFactor) / basisPoints;

    uint256 totalFee = stakeTogetherFeeAdjust + operatorFeeAjust + communityFeeAjust;

    uint256 sharesMintedAsFees = (rewards * totalFee * totalShares) /
      (totalPooledEtherWithRewards * basisPoints - rewards * totalFee);

    uint256 stakeTogetherFeeShares = (sharesMintedAsFees * stakeTogetherFeeAdjust) / totalFee;
    uint256 operatorFeeShares = (sharesMintedAsFees * operatorFeeAjust) / totalFee;
    uint256 communityFeeShares = (sharesMintedAsFees * communityFeeAjust) / totalFee;

    _mintShares(stakeTogetherFeeRecipient, stakeTogetherFeeShares);
    _mintShares(operatorFeeRecipient, operatorFeeShares);

    for (uint i = 0; i < communities.length; i++) {
      address community = communities[i];
      uint256 communityProportion = delegatedSharesOf(community);
      uint256 communityShares = (communityFeeShares * communityProportion) / totalDelegatedShares;
      _mintShares(community, communityShares);
      _mintDelegatedShares(community, community, communityShares);

      // Todo: remove before audit
      tempCommunityRewards[community] += communityShares;
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

  event CommunityAdded(address account);
  event CommunityRemoved(address account);

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
    emit CommunityAdded(account);
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
    emit CommunityRemoved(account);
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
