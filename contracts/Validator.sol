// SPDX-FileCopyrightText: 2023 Stake Together <info@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './interfaces/IDepositContract.sol';
import './interfaces/ISSVNetwork.sol';
import './StakeTogether.sol';

contract Validator is Ownable {
  struct EthValidator {
    bytes pubkey;
    bytes signature;
    bytes32 deposit_data_root;
  }

  StakeTogether public stakeTogether;
  IDepositContract public immutable depositContract;
  ISSVNetwork public immutable ssvNetwork;
  IERC20 public immutable ssvToken;

  uint256 public validatorIndex = 0;

  bytes public withdrawalCredentials;

  event ValidatorCreated(
    address indexed creator,
    bytes pubkey,
    bytes withdrawal_credentials,
    bytes signature,
    bytes32 deposit_data_root
  );

  event ValidatorRegistered(
    bytes publicKey,
    uint64[] operatorIds,
    bytes sharesEncrypted,
    uint256 amount,
    uint256 clusterIndex
  );

  modifier onlyStakeTogether() {
    require(msg.sender == address(stakeTogether), 'Only StakeTogether contract can call this function');
    _;
  }

  constructor(address _depositContract, address _ssvNetwork, address _ssvToken) {
    depositContract = IDepositContract(_depositContract);
    ssvNetwork = ISSVNetwork(_ssvNetwork);
    ssvToken = IERC20(_ssvToken);
  }

  function setStakeTogether(address _stakeTogether) external onlyOwner {
    require(address(stakeTogether) == address(0), 'StakeTogether address can only be set once');
    stakeTogether = StakeTogether(_stakeTogether);
  }

  function setWithdrawalCredentials(bytes memory _withdrawalCredentials) external onlyOwner {
    require(withdrawalCredentials.length == 0, 'Withdrawal Credentials can only be set once');
    withdrawalCredentials = _withdrawalCredentials;
  }

  function createValidator(
    bytes memory pubkey,
    bytes memory signature,
    bytes32 deposit_data_root
  ) external payable onlyStakeTogether {
    require(msg.value == 32 ether, 'Must deposit 32 ether');

    depositContract.deposit{ value: msg.value }(
      pubkey,
      withdrawalCredentials,
      signature,
      deposit_data_root
    );

    validatorIndex++;

    emit ValidatorCreated(msg.sender, pubkey, withdrawalCredentials, signature, deposit_data_root);
  }

  function registerValidator(
    bytes calldata publicKey,
    uint64[] memory operatorIds,
    bytes calldata sharesEncrypted,
    uint256 amount,
    ISSVNetwork.Cluster memory cluster
  ) public {
    ssvNetwork.registerValidator(publicKey, operatorIds, sharesEncrypted, amount, cluster);
    emit ValidatorRegistered(publicKey, operatorIds, sharesEncrypted, amount, cluster.index);
  }
}
