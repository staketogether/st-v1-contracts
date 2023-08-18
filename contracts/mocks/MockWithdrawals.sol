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

import '../StakeTogether.sol';
import '../interfaces/IWithdrawals.sol';

/// @custom:security-contact security@staketogether.app
contract MockWithdrawals is
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
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  uint256 public version;

  StakeTogether public stakeTogether;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initializeV2() external onlyRole(UPGRADER_ROLE) {
    version = 2;
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  receive() external payable {
    emit ReceiveEther(msg.sender, msg.value);
    _transferExtraAmount();
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override whenNotPaused {
    super._beforeTokenTransfer(from, to, amount);
  }

  /**************
   ** WITHDRAW **
   **************/

  function mint(address _to, uint256 _amount) public whenNotPaused {
    require(msg.sender == address(stakeTogether), 'ONLY_STAKE_TOGETHER_CONTRACT');
    _mint(_to, _amount);
  }

  function withdraw(uint256 _amount) public whenNotPaused nonReentrant {
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');
    require(balanceOf(msg.sender) >= _amount, 'INSUFFICIENT_STW_BALANCE');
    require(_amount > 0, 'ZERO_AMOUNT');

    _burn(msg.sender, _amount);
    payable(msg.sender).transfer(_amount);
  }

  function isWithdrawReady(uint256 _amount) public view returns (bool) {
    return address(this).balance >= _amount;
  }

  function _transferExtraAmount() private {
    uint256 _supply = totalSupply();
    if (address(this).balance > _supply) {
      uint256 extraAmount = address(this).balance - _supply;
      payable(address(stakeTogether)).transfer(extraAmount);
    }
  }
}
