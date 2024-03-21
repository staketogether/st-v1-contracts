// SPDX-FileCopyrightText: 2024 Together Technology LTD <legal@staketogether.org>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';

import '../StakeTogether.sol';
import '../Withdrawals.sol';

contract MockFlashLoan is Initializable, PausableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

  StakeTogether public stakeTogether;
  Withdrawals public withdrawals;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _stakeTogether, address _withdrawals) public initializer {
    stakeTogether = StakeTogether(payable(_stakeTogether));
    withdrawals = Withdrawals(payable(_withdrawals));
  }

  receive() external payable {}

  function _authorizeUpgrade(address _newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  function depositAndWithdraw(address _pool, bytes calldata _referral) external payable {
    require(msg.value == 1 ether, 'Must deposit 1 ETH');

    stakeTogether.depositPool{ value: 1 ether }(_pool, _referral);

    uint256 withdrawAmount = 0.5 ether;
    stakeTogether.withdrawPool(withdrawAmount, _pool);

    payable(msg.sender).transfer(withdrawAmount);
  }

  function doubleWithdraw() external payable {
    uint256 amount = 0.5 ether;
    withdrawals.withdraw(amount);
    withdrawals.withdraw(amount);
  }
}
