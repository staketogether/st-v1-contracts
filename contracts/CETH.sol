// SPDX-FileCopyrightText: 2023 Stake Together <info@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

abstract contract CETH is ERC20, ERC20Permit, Pausable, Ownable {
  address[] private communities;

  mapping(address => uint256) private shares;
  mapping(address => uint256) private delegatedShares;
  uint256 private totalShares = 0;
  uint256 private totalDelegatedShares = 0;

  mapping(address => mapping(address => uint256)) private delegations;
  mapping(address => address[]) private delegators;
  mapping(address => address[]) private delegates;
  mapping(address => mapping(address => bool)) private alreadyDelegating;
  mapping(address => mapping(address => bool)) private alreadyDelegated;

  mapping(address => mapping(address => uint256)) private allowances;

  address public stakeTogetherFeeRecipient = owner();
  uint256 public stakeTogetherFee = 0.03 ether;

  address public operatorFeeRecipient = owner();
  uint256 public operatorFee = 0.03 ether;

  uint256 public communityFee = 0.03 ether;

  uint256 public maxDelegations = 128;

  event MintShares(
    address indexed recipient,
    uint256 sharesAmount,
    uint256 preTotalShares,
    uint256 postTotalShares,
    uint256 preRecipientShares,
    uint256 postRecipientShares
  );
  event BurnShares(
    address indexed account,
    uint256 preRebaseTokenAmount,
    uint256 postRebaseTokenAmount,
    uint256 sharesAmount
  );

  event TransferShares(address indexed from, address indexed to, uint256 sharesValue);

  event MintDelegatedShares(
    address indexed recipient,
    address indexed delegate,
    uint256 sharesAmount,
    uint256 preDelegatedShares,
    uint256 postDelegatedShares,
    uint256 preTotalDelegatedShares,
    uint256 postTotalDelegatedShares
  );

  event BurnDelegatedShares(
    address indexed from,
    address indexed delegate,
    uint256 sharesAmount,
    uint256 preDelegatedShares,
    uint256 postDelegatedShares,
    uint256 preTotalDelegatedShares,
    uint256 postTotalDelegatedShares
  );

  event CommunityAdded(address community);
  event CommunityRemoved(address community);

  constructor() ERC20('Community Ether', 'CETH') ERC20Permit('Community Ether') {}

  function pause() public onlyOwner {
    _pause();
  }

  function unpause() public onlyOwner {
    _unpause();
  }

  function setStakeTogetherFee(uint256 _fee) public onlyOwner {
    require(_fee > 0, 'Fee must be greater than 0');
    require(_fee + communityFee + operatorFee <= 0.1 ether, 'Fee must be less than 10%');
    stakeTogetherFee = _fee;
  }

  function setCommunityFee(uint256 _fee) public onlyOwner {
    require(_fee > 0, 'Fee must be greater than 0');
    require(_fee + stakeTogetherFee + operatorFee <= 0.1 ether, 'Fee must be less than 10%');
    communityFee = _fee;
  }

  function setOperatorFee(uint256 _fee) public onlyOwner {
    require(_fee > 0, 'Fee must be greater than 0');
    require(_fee + stakeTogetherFee + communityFee <= 0.1 ether, 'Fee must be less than 10%');
    communityFee = _fee;
  }

  function setStakeTogetherFeeRecipient(address _recipient) public onlyOwner {
    stakeTogetherFeeRecipient = _recipient;
  }

  function setOperatorFeeRecipient(address _recipient) public onlyOwner {
    operatorFeeRecipient = _recipient;
  }

  function totalSupply() public view override returns (uint256) {
    return _getTotalPooledEther();
  }

  function getCommunities() public view returns (address[] memory) {
    return communities;
  }

  function getCommunityByAddress(address community) public view returns (bool) {
    return _isCommunity(community);
  }

  function getTotalPooledEther() public view returns (uint256) {
    return _getTotalPooledEther();
  }

  function getTotalShares() public view returns (uint256) {
    return _getTotalShares();
  }

  function getTotalDelegatedShares() public view returns (uint256) {
    return _getTotalDelegatedShares();
  }

  function balanceOf(address _account) public view override returns (uint256) {
    return getPooledEthByShares(_sharesOf(_account));
  }

  function sharesOf(address _account) public view returns (uint256) {
    return _sharesOf(_account);
  }

  function delegatedSharesOf(address _account) public view returns (uint256) {
    return _delegatedSharesOf(_account);
  }

  function getSharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
    return (_ethAmount * _getTotalShares()) / _getTotalPooledEther();
  }

  function getPooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
    return (_sharesAmount * _getTotalPooledEther()) / _getTotalShares();
  }

  function transferShares(address _recipient, uint256 _sharesAmount) public returns (uint256) {
    _transferShares(msg.sender, _recipient, _sharesAmount);
    uint256 tokensAmount = getPooledEthByShares(_sharesAmount);
    _emitTransferEvents(msg.sender, _recipient, tokensAmount, _sharesAmount);
    return tokensAmount;
  }

  function transferSharesFrom(
    address _sender,
    address _recipient,
    uint256 _sharesAmount
  ) external returns (uint256) {
    uint256 tokensAmount = getPooledEthByShares(_sharesAmount);
    _spendAllowance(_sender, msg.sender, tokensAmount);
    _transferShares(_sender, _recipient, _sharesAmount);
    _emitTransferEvents(_sender, _recipient, tokensAmount, _sharesAmount);
    return tokensAmount;
  }

  function getDelegationsOf(address _address) public view returns (address[] memory, uint256[] memory) {
    address[] memory _delegatorAddresses = delegators[_address];
    uint256[] memory _delegatedShares = new uint256[](_delegatorAddresses.length);

    for (uint i = 0; i < _delegatorAddresses.length; i++) {
      _delegatedShares[i] = delegations[_delegatorAddresses[i]][_address];
    }

    return (_delegatorAddresses, _delegatedShares);
  }

  function getDelegatesOf(address _address) public view returns (address[] memory, uint256[] memory) {
    address[] memory _delegatedAddresses = delegates[_address];
    uint256[] memory _delegatedShares = new uint256[](_delegatedAddresses.length);

    for (uint i = 0; i < _delegatedAddresses.length; i++) {
      _delegatedShares[i] = delegations[_address][_delegatedAddresses[i]];
    }

    return (_delegatedAddresses, _delegatedShares);
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

  function addCommunity(address community) external onlyOwner {
    require(!_isCommunity(community), 'Community already exists');
    require(!_stakeTogetherFeeRecipient(community), 'Community cannot be the st fee recipient');
    require(!_operatorFeeRecipient(community), 'Community cannot be the operator fee recipient');
    require(sharesOf(community) == 0, 'Community need to do not have shares');
    communities.push(community);
    emit CommunityAdded(community);
  }

  function removeCommunity(address community) external onlyOwner {
    require(_isCommunity(community), 'Community does not exist');

    for (uint256 i = 0; i < communities.length; i++) {
      if (communities[i] == community) {
        communities[i] = communities[communities.length - 1];
        communities.pop();
        break;
      }
    }
    emit CommunityRemoved(community);
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override whenNotPaused {
    super._beforeTokenTransfer(from, to, amount);
  }

  function _stakeTogetherFeeRecipient(address account) internal view returns (bool) {
    return address(stakeTogetherFeeRecipient) == account;
  }

  function _operatorFeeRecipient(address account) internal view returns (bool) {
    return address(operatorFeeRecipient) == account;
  }

  function _isCommunity(address community) internal view returns (bool) {
    if (community == address(this)) {
      return true;
    }

    for (uint256 i = 0; i < communities.length; i++) {
      if (communities[i] == community) {
        return true;
      }
    }
    return false;
  }

  function _distributeFee(uint256 beaconBalance, uint256 lastBeaconBalance) internal {
    if (beaconBalance > lastBeaconBalance) {
      uint256 beaconBalanceDifference = beaconBalance - lastBeaconBalance;

      uint256 growthPercentage = (beaconBalanceDifference * 1 ether) / _getTotalPooledEther();

      uint256 stakeTogetherFeeAdjust = stakeTogetherFee +
        ((stakeTogetherFee * growthPercentage) / 1 ether);

      uint256 operatorFeeAjust = operatorFee + ((operatorFee * growthPercentage) / 1 ether);

      uint256 communityFeeAjust = communityFee + ((communityFee * growthPercentage) / 1 ether);

      uint256 _totalShares = _getTotalShares();

      uint256 totalPooledEtherWithRewards = _getTotalPooledEther() + beaconBalanceDifference;

      uint256 totalFee = stakeTogetherFeeAdjust + operatorFeeAjust + communityFeeAjust;

      uint256 sharesMintedAsFees = (beaconBalanceDifference * totalFee * _totalShares) /
        (totalPooledEtherWithRewards * 1 ether - beaconBalanceDifference * totalFee);

      uint256 stakeTogetherFeeShares = (sharesMintedAsFees * stakeTogetherFeeAdjust) / totalFee;
      _mintShares(stakeTogetherFeeRecipient, stakeTogetherFeeShares);

      uint256 operatorFeeShares = (sharesMintedAsFees * operatorFeeAjust) / totalFee;
      _mintShares(operatorFeeRecipient, operatorFeeShares);

      uint256 communityFeeShares = (sharesMintedAsFees * communityFeeAjust) / totalFee;

      uint256 _totalDelegatedShares = _getTotalDelegatedShares();

      for (uint i = 0; i < communities.length; i++) {
        address community = communities[i];
        uint256 communityProportion = _delegatedSharesOf(community);
        uint256 communityShares = (communityFeeShares * communityProportion) / _totalDelegatedShares;
        _mintShares(community, communityShares);
      }
    }
  }

  function _getTotalPooledEther() internal view virtual returns (uint256);

  function _getTotalShares() internal view returns (uint256) {
    return totalShares;
  }

  function _getTotalDelegatedShares() internal view returns (uint256) {
    return totalDelegatedShares;
  }

  function _sharesOf(address _account) internal view returns (uint256) {
    return shares[_account];
  }

  function _delegationsOf(address _account, address _delegate) internal view returns (uint256) {
    return delegations[_account][_delegate];
  }

  function _delegatedSharesOf(address _account) internal view returns (uint256) {
    return delegatedShares[_account];
  }

  function _transfer(address _sender, address _recipient, uint256 _amount) internal override {
    uint256 _sharesToTransfer = getSharesByPooledEth(_amount);
    _transferShares(_sender, _recipient, _sharesToTransfer);
    _emitTransferEvents(_sender, _recipient, _amount, _sharesToTransfer);
  }

  function _transferShares(
    address _sender,
    address _recipient,
    uint256 _sharesAmount
  ) internal whenNotPaused {
    require(_sender != address(0), 'TRANSFER_FROM_ZERO_ADDR');
    require(_recipient != address(0), 'TRANSFER_TO_ZERO_ADDR');
    require(_recipient != address(this), 'TRANSFER_TO_STETH_CONTRACT');

    uint256 currentSenderShares = shares[_sender];
    require(_sharesAmount <= currentSenderShares, 'BALANCE_EXCEEDED');

    shares[_sender] = currentSenderShares - _sharesAmount;
    shares[_recipient] = shares[_recipient] + _sharesAmount;
  }

  function _approve(address _owner, address _spender, uint256 _amount) internal override {
    require(_owner != address(0), 'APPROVE_FROM_ZERO_ADDR');
    require(_spender != address(0), 'APPROVE_TO_ZERO_ADDR');

    allowances[_owner][_spender] = _amount;
    emit Approval(_owner, _spender, _amount);
  }

  function _mintShares(address _recipient, uint256 _sharesAmount) internal whenNotPaused {
    require(_recipient != address(0), 'MINT_TO_ZERO_ADDR');

    uint256 preTotalShares = totalShares;
    uint256 preRecipientShares = shares[_recipient];

    totalShares += _sharesAmount;
    shares[_recipient] = shares[_recipient] + _sharesAmount;

    emit MintShares(
      _recipient,
      _sharesAmount,
      preTotalShares,
      totalShares,
      preRecipientShares,
      shares[_recipient]
    );
  }

  function _mintDelegatedShares(
    address _recipient,
    address _delegate,
    uint256 _sharesAmount
  ) internal whenNotPaused {
    require(_recipient != address(0), 'MINT_TO_ZERO_ADDR');
    require(_delegate != address(0), 'MINT_TO_ZERO_ADDR');
    require(delegators[_delegate].length < maxDelegations, 'MAX_DELEGATIONS_REACHED');
    require(_isCommunity(_delegate), 'Only can mintShares for communities');

    uint256 preDelegatedShares = delegatedShares[_delegate];
    uint256 preTotalDelegatedShares = totalDelegatedShares;

    delegatedShares[_delegate] += _sharesAmount;
    delegations[_delegate][_recipient] += _sharesAmount;
    totalDelegatedShares += _sharesAmount;

    if (!alreadyDelegating[_recipient][_delegate]) {
      delegators[_recipient].push(_delegate);
      alreadyDelegating[_recipient][_delegate] = true;
    }

    if (!alreadyDelegated[_delegate][_recipient]) {
      delegates[_delegate].push(_recipient);
      alreadyDelegated[_delegate][_recipient] = true;
    }

    emit MintDelegatedShares(
      _recipient,
      _delegate,
      _sharesAmount,
      preDelegatedShares,
      delegatedShares[_delegate],
      preTotalDelegatedShares,
      totalDelegatedShares
    );
  }

  function _burnShares(address _account, uint256 _sharesAmount) internal whenNotPaused {
    require(_account != address(0), 'BURN_FROM_ZERO_ADDR');

    uint256 accountShares = shares[_account];
    require(_sharesAmount <= accountShares, 'BALANCE_EXCEEDED');

    uint256 preRebaseTokenAmount = getPooledEthByShares(_sharesAmount);

    shares[_account] = accountShares - _sharesAmount;
    totalShares -= _sharesAmount;

    uint256 postRebaseTokenAmount = getPooledEthByShares(_sharesAmount);

    emit BurnShares(_account, preRebaseTokenAmount, postRebaseTokenAmount, _sharesAmount);
  }

  function _burnDelegatedShares(
    address _from,
    address _delegate,
    uint256 _sharesAmount
  ) internal whenNotPaused {
    require(_from != address(0), 'BURN_FROM_ZERO_ADDR');
    require(_delegate != address(0), 'BURN_FROM_ZERO_ADDR');

    uint256 preDelegatedShares = delegatedShares[_delegate];
    uint256 preTotalDelegatedShares = totalDelegatedShares;

    delegatedShares[_delegate] -= _sharesAmount;
    delegations[_delegate][_from] -= _sharesAmount;
    totalDelegatedShares -= _sharesAmount;

    if (delegations[_delegate][_from] == 0) {
      alreadyDelegating[_from][_delegate] = false;

      for (uint i = 0; i < delegators[_from].length - 1; i++) {
        if (delegators[_from][i] == _delegate) {
          delegators[_from][i] = delegators[_from][delegators[_from].length - 1];
          break;
        }
      }
      delegators[_from].pop();
    }

    if (delegatedShares[_delegate] == 0) {
      alreadyDelegated[_delegate][_from] = false;

      for (uint i = 0; i < delegates[_delegate].length - 1; i++) {
        if (delegates[_delegate][i] == _from) {
          delegates[_delegate][i] = delegates[_delegate][delegates[_delegate].length - 1];
          break;
        }
      }
      delegates[_delegate].pop();
    }

    emit BurnDelegatedShares(
      _from,
      _delegate,
      _sharesAmount,
      preDelegatedShares,
      delegatedShares[_delegate],
      preTotalDelegatedShares,
      totalDelegatedShares
    );
  }

  function _spendAllowance(address _owner, address _spender, uint256 _amount) internal override {
    uint256 currentAllowance = allowances[_owner][_spender];
    if (currentAllowance != ~uint256(0)) {
      require(currentAllowance >= _amount, 'ALLOWANCE_EXCEEDED');
      _approve(_owner, _spender, currentAllowance - _amount);
    }
  }

  function _emitTransferEvents(
    address _from,
    address _to,
    uint _tokenAmount,
    uint256 _sharesAmount
  ) internal {
    emit Transfer(_from, _to, _tokenAmount);
    emit TransferShares(_from, _to, _sharesAmount);
  }
}
