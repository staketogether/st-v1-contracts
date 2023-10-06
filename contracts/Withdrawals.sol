// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol';

import './Router.sol';
import './StakeTogether.sol';
import './interfaces/IWithdrawals.sol';
import './interfaces/IStakeTogether.sol';

/// @title Withdrawals Contract for StakeTogether
/// @notice The Withdrawals contract handles all withdrawal-related activities within the StakeTogether protocol.
/// It allows users to withdraw their staked tokens and interact with the associated stake contracts.
/// @custom:security-contact security@staketogether.app
contract Withdrawals is
  Initializable,
  ERC20Upgradeable,
  ERC20BurnableUpgradeable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  ERC20PermitUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuardUpgradeable,
  IWithdrawals
{
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE'); /// Role for managing upgrades.
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE'); /// Role for administration.

  uint256 public version; /// Contract version.
  StakeTogether public stakeTogether; /// Instance of the StakeTogether contract.
  Router public router; /// Instance of the Router contract.

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initialization function for Withdrawals contract.
  function initialize() external initializer {
    __ERC20_init('Stake Together Withdrawals', 'stwETH');
    __ERC20Burnable_init();
    __Pausable_init();
    __AccessControl_init();
    __ERC20Permit_init('Stake Together Withdrawals');
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

    version = 1;
  }

  /// @notice Pauses withdrawals.
  /// @dev Only callable by the admin role.
  function pause() external onlyRole(ADMIN_ROLE) {
    _pause();
  }

  /// @notice Unpauses withdrawals.
  /// @dev Only callable by the admin role.
  function unpause() external onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  /// @notice Internal function to authorize an upgrade.
  /// @param _newImplementation Address of the new contract implementation.
  /// @dev Only callable by the upgrader role.
  function _authorizeUpgrade(address _newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  /// @notice Receive function to accept incoming ETH transfers.
  receive() external payable nonReentrant {
    emit ReceiveEther(msg.value);
  }

  /// @notice Allows the router to send ETH to the contract.
  /// @dev This function can only be called by the router.
  function receiveWithdrawEther() external payable {
    require(msg.sender == address(router), 'ONLY_ROUTER');
    emit ReceiveWithdrawEther(msg.value);
  }

  /// @notice Transfers any extra amount of ETH in the contract to the StakeTogether fee address.
  /// @dev Only callable by the admin role. Requires that extra amount exists in the contract balance.
  function transferExtraAmount() external whenNotPaused nonReentrant onlyRole(ADMIN_ROLE) {
    uint256 extraAmount = address(this).balance - totalSupply();
    require(extraAmount > 0, 'NO_EXTRA_AMOUNT');
    address stakeTogetherFee = stakeTogether.getFeeAddress(IStakeTogether.FeeRole.StakeTogether);
    payable(stakeTogetherFee).transfer(extraAmount);
  }

  /// @notice Sets the StakeTogether contract address.
  /// @param _stakeTogether The address of the new StakeTogether contract.
  /// @dev Only callable by the admin role.
  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  /// @notice Sets the Router contract address.
  /// @param _router The address of the router.
  /// @dev Only callable by the admin role.
  function setRouter(address _router) external onlyRole(ADMIN_ROLE) {
    require(_router != address(0), 'ROUTER_CONTRACT_ALREADY_SET');
    router = Router(payable(_router));
    emit SetRouter(_router);
  }

  /// @notice Hook that is called before any token transfer.
  /// @param from Address transferring the tokens.
  /// @param to Address receiving the tokens.
  /// @param amount The amount of tokens to be transferred.
  /// @dev This override ensures that transfers are paused when the contract is paused.
  function _update(address from, address to, uint256 amount) internal override whenNotPaused {
    super._update(from, to, amount);
  }

  /**************
   ** WITHDRAW **
   **************/

  /// @notice Mints tokens to a specific address.
  /// @param _to Address to receive the minted tokens.
  /// @param _amount Amount of tokens to mint.
  /// @dev Only callable by the StakeTogether contract.
  function mint(address _to, uint256 _amount) public whenNotPaused {
    require(msg.sender == address(stakeTogether), 'ONLY_STAKE_TOGETHER_CONTRACT');
    _mint(_to, _amount);
  }

  /// @notice Withdraws the specified amount of ETH, burning tokens in exchange.
  /// @param _amount Amount of ETH to withdraw.
  /// @dev The caller must have a balance greater or equal to the amount, and the contract must have sufficient ETH balance.
  function withdraw(uint256 _amount) public whenNotPaused nonReentrant {
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');
    require(balanceOf(msg.sender) >= _amount, 'INSUFFICIENT_STW_BALANCE');
    require(_amount > 0, 'ZERO_AMOUNT');
    emit Withdraw(msg.sender, _amount);
    _burn(msg.sender, _amount);
    payable(msg.sender).transfer(_amount);
  }

  /// @notice Checks if the contract is ready to withdraw the specified amount.
  /// @param _amount Amount of ETH to check.
  /// @return A boolean indicating if the contract has sufficient balance to withdraw the specified amount.
  function isWithdrawReady(uint256 _amount) public view returns (bool) {
    return address(this).balance >= _amount;
  }
}
