// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.org>
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

import './interfaces/IStakeTogether.sol';
import './interfaces/IStakeTogetherWrapper.sol';

/// @title StakeTogether Wrapper Pool Contract
/// @notice The StakeTogether contract is the primary entry point for interaction with the StakeTogether protocol.
/// It provides functionalities for staking, withdrawals, fee management, and interactions with pools and validators.
/// @custom:security-contact security@staketogether.org
contract StakeTogetherWrapper is
  Initializable,
  ERC20Upgradeable,
  ERC20BurnableUpgradeable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  ERC20PermitUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuardUpgradeable,
  IStakeTogetherWrapper
{
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE'); /// Role for managing upgrades.
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE'); /// Role for administration.

  uint256 public version; /// Contract version.
  IStakeTogether public stakeTogether; /// Instance of the StakeTogether contract.

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __ERC20_init('Wrapped Stake Together Protocol', 'wstpETH');
    __ERC20Burnable_init();
    __Pausable_init();
    __AccessControl_init();
    __ERC20Permit_init('Wrapped Stake Together Protocol');
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

    version = 1;
  }

  /// @notice Pauses the contract, preventing certain actions.
  /// @dev Only callable by the admin role.
  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  /// @notice Unpauses the contract, allowing actions to resume.
  /// @dev Only callable by the admin role.
  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function _update(address from, address to, uint256 amount) internal override whenNotPaused {
    super._update(from, to, amount);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  /// @notice Receive function to accept incoming ETH transfers.
  receive() external payable nonReentrant {
    emit ReceiveEther(msg.value);
  }

  /// @notice Transfers any extra amount of ETH in the contract to the StakeTogether fee address.
  /// @dev Only callable by the admin role. Requires that extra amount exists in the contract balance.
  function transferExtraAmount() external whenNotPaused nonReentrant onlyRole(ADMIN_ROLE) {
    uint256 extraAmount = address(this).balance - totalSupply();
    if (extraAmount <= 0) revert NoExtraAmountAvailable();
    address stakeTogetherFee = stakeTogether.getFeeAddress(IStakeTogether.FeeRole.StakeTogether);
    payable(stakeTogetherFee).transfer(extraAmount);
  }

  /// @notice Sets the StakeTogether contract address.
  /// @param _stakeTogether The address of the new StakeTogether contract.
  /// @dev Only callable by the admin role.
  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    if (address(stakeTogether) != address(0)) revert StakeTogetherAlreadySet();
    if (address(_stakeTogether) == address(0)) revert ZeroAddress();
    stakeTogether = IStakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }
}
