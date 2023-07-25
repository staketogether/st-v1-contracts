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

import './StakeTogether.sol';

/// @custom:security-contact security@staketogether.app
contract Withdrawals is
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

  modifier onlyStakeTogether() {
    require(msg.sender == address(stakeTogether), 'ONLY_STAKE_TOGETHER_CONTRACT');
    _;
  }

  event ReceiveEther(address indexed sender, uint amount);
  event FallbackEther(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);
  event Withdraw(address indexed user, uint256 amount);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __ERC20_init('ST Withdrawals ETH', 'wETH');
    __ERC20Burnable_init();
    __Pausable_init();
    __AccessControl_init();
    __ERC20Permit_init('ST Withdrawals ETH');
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

  receive() external payable nonReentrant {
    emit ReceiveEther(msg.sender, msg.value);
    _checkExtraAmount();
  }

  fallback() external payable nonReentrant {
    emit FallbackEther(msg.sender, msg.value);
    _checkExtraAmount();
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  /**************
   ** WITHDRAW **
   **************/

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
    uint256 _supply = totalSupply();
    if (address(this).balance > _supply) {
      uint256 routerExtraAmount = address(this).balance - _supply;
      _transferToStakeTogether(routerExtraAmount);
    }
  }

  function _transferToStakeTogether(uint256 _amount) private {
    payable(address(stakeTogether)).transfer(_amount);
  }
}
