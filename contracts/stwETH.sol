// SPDX-FileCopyrightText: 2023 Stake Together Labs <info@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;
import './StakeTogether.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

/// @custom:security-contact security@staketogether.app
contract stwETH is Ownable, Pausable, ReentrancyGuard, ERC20, ERC20Burnable, ERC20Permit {
  StakeTogether public stakeTogether;

  event EtherReceived(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);
  event Withdraw(address indexed user, uint256 amount);

  constructor()
    ERC20('Stake Together Withdrawal Ether', 'stwETH')
    ERC20Permit('Stake Together Withdrawal Ether')
  {}

  receive() external payable {
    _checkExtraAmount();
    emit EtherReceived(msg.sender, msg.value);
  }

  fallback() external payable {
    _checkExtraAmount();
    emit EtherReceived(msg.sender, msg.value);
  }

  function mint(address _to, uint256 _amount) public whenNotPaused {
    require(msg.sender == address(stakeTogether), 'ONLY_STAKE_TOGETHER_CONTRACT');
    _mint(_to, _amount);
  }

  function setStakeTogether(address _stakeTogether) external onlyOwner {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function withdraw(uint256 _amount) public whenNotPaused nonReentrant {
    require(address(stakeTogether) != address(0), 'STAKE_TOGETHER_NOT_SET');
    require(_amount > 0, 'ZERO_AMOUNT');
    require(balanceOf(msg.sender) >= _amount, 'INSUFFICIENT_stwETH_BALANCE');
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');

    _burn(msg.sender, _amount);
    payable(msg.sender).transfer(_amount);

    emit Withdraw(msg.sender, _amount);
  }

  function withdrawIsReady(uint256 _amount) public view returns (bool) {
    return address(this).balance >= _amount;
  }

  function _checkExtraAmount() internal {
    uint256 totalSupply = totalSupply();
    if (address(this).balance > totalSupply) {
      uint256 extraAmount = address(this).balance - totalSupply;
      _transferToStakeTogether(extraAmount);
    }
  }

  function _transferToStakeTogether(uint256 _amount) private {
    payable(address(stakeTogether)).transfer(_amount);
  }
}
