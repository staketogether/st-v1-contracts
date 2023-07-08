// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import './StakeTogether.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';

contract lETH is AccessControl, Pausable, ReentrancyGuard, ERC20, ERC20Burnable, ERC20Permit {
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  StakeTogether public stakeTogether;
  uint256 public liquidityFee = 0.001 ether;

  event EtherReceived(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);
  event AddLiquidity(address indexed user, uint256 amount);
  event RemoveLiquidity(address indexed user, uint256 amount);
  event Borrow(address indexed user, uint256 amount);
  event RepayLoan(address indexed user, uint256 amount);

  constructor() ERC20('ST Lending Ether', 'lETH') ERC20Permit('ST Lending Ether') {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
  }

  receive() external payable {
    _checkExtraAmount();
    emit EtherReceived(msg.sender, msg.value);
  }

  modifier onlyStakeTogether() {
    require(msg.sender == address(stakeTogether), 'ONLY_STAKE_TOGETHER_CONTRACT');
    _;
  }

  function mint(address _to, uint256 _amount) internal whenNotPaused {
    _mint(_to, _amount);
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function addLiquidity() public payable whenNotPaused nonReentrant {
    _mint(msg.sender, msg.value);
    emit AddLiquidity(msg.sender, msg.value);
  }

  function removeLiquidity(uint256 _amount) public whenNotPaused nonReentrant {
    require(_amount > 0, 'ZERO_AMOUNT');
    require(balanceOf(msg.sender) >= _amount, 'INSUFFICIENT_lETH_BALANCE');
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');

    _burn(msg.sender, _amount);
    payable(msg.sender).transfer(_amount);

    emit RemoveLiquidity(msg.sender, _amount);
  }

  function borrow(uint256 _amount) public whenNotPaused nonReentrant onlyStakeTogether {
    require(_amount > 0, 'ZERO_AMOUNT');
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');

    uint256 total = _amount + Math.mulDiv(_amount, liquidityFee, 1 ether);
    _mint(msg.sender, total);

    emit Borrow(msg.sender, _amount);
  }

  function repayLoan() public payable whenNotPaused nonReentrant onlyStakeTogether {
    require(msg.value > 0, 'ZERO_AMOUNT');
    require(balanceOf(msg.sender) >= msg.value, 'INSUFFICIENT_lETH_BALANCE');

    _burn(msg.sender, msg.value);
    emit RepayLoan(msg.sender, msg.value);
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
