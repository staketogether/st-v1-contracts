// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;
import './StakeTogether.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';

/// @custom:security-contact security@staketogether.app
contract Withdrawals is AccessControl, Pausable, ReentrancyGuard, ERC20, ERC20Burnable, ERC20Permit {
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  StakeTogether public stakeTogether;

  modifier onlyStakeTogether() {
    require(msg.sender == address(stakeTogether), 'ONLY_STAKE_TOGETHER_CONTRACT');
    _;
  }

  event ReceiveEther(address indexed sender, uint amount);
  event FallbackEther(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);
  event Withdraw(address indexed user, uint256 amount);

  constructor() ERC20('ST Withdrawal Ether', 'stwETH') ERC20Permit('ST Withdrawal Ether') {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
  }

  receive() external payable {
    _checkExtraAmount();
    emit ReceiveEther(msg.sender, msg.value);
  }

  fallback() external payable {
    _checkExtraAmount();
    emit FallbackEther(msg.sender, msg.value);
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

  function mint(address _to, uint256 _amount) public whenNotPaused onlyStakeTogether {
    _mint(_to, _amount);
  }

  function withdraw(uint256 _amount) public whenNotPaused nonReentrant {
    require(address(stakeTogether) != address(0), 'STAKE_TOGETHER_NOT_SET');
    require(_amount > 0, 'ZERO_AMOUNT');
    require(balanceOf(msg.sender) >= _amount, 'INSUFFICIENT_WETH_BALANCE');
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');

    _burn(msg.sender, _amount);
    payable(msg.sender).transfer(_amount);

    emit Withdraw(msg.sender, _amount);
  }

  function isWithdrawReady(uint256 _amount) public view returns (bool) {
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
