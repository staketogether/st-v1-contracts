// SPDX-FileCopyrightText: 2023 Stake Together <info@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './interfaces/IDepositContract.sol';
import './interfaces/ISSVNetwork.sol';
import './StakeTogether.sol';

contract STValidator is Ownable {
  struct EthValidator {
    bytes pubkey;
    bytes signature;
    bytes32 deposit_data_root;
  }

  StakeTogether public stakeTogether;
  IDepositContract public immutable depositContract;
  ISSVNetwork public immutable ssvNetwork;
  IERC20 public immutable ssvToken;

  bytes[] public validators;

  bytes public withdrawalCredentials;

  event ValidatorCreated(
    address indexed creator,
    bytes pubkey,
    bytes withdrawal_credentials,
    bytes signature,
    bytes32 deposit_data_root
  );

  event SSVNetworkRegistered(bytes publicKey, uint64[] operatorIds, uint256 amount, uint256 clusterIndex);
  event SSVNetworkRemoved(bytes publicKey, uint64[] operatorIds, uint256 clusterIndex);
  event SSVNetworkLiquidated(address owner, uint64[] operatorIds, uint256 clusterIndex);
  event SSVNetworkReactivated(uint64[] operatorIds, uint256 amount, uint256 clusterIndex);

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

  function getValidators() external view returns (bytes[] memory) {
    return validators;
  }

  function isValidator(bytes memory pubkey) external view returns (bool) {
    for (uint256 i = 0; i < validators.length; i++) {
      if (keccak256(validators[i]) == keccak256(pubkey)) {
        return true;
      }
    }
    return false;
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

    validators.push(pubkey);

    emit ValidatorCreated(msg.sender, pubkey, withdrawalCredentials, signature, deposit_data_root);
  }

  function registerValidator(
    bytes calldata publicKey,
    uint64[] calldata operatorIds,
    bytes calldata sharesEncrypted,
    uint256 amount,
    ISSVNetwork.Cluster calldata cluster
  ) external onlyOwner {
    ssvNetwork.registerValidator(publicKey, operatorIds, sharesEncrypted, amount, cluster);

    emit SSVNetworkRegistered(publicKey, operatorIds, amount, cluster.index);
  }

  function removeValidator(
    bytes calldata publicKey,
    uint64[] calldata operatorIds,
    ISSVNetwork.Cluster calldata cluster
  ) external onlyOwner {
    ssvNetwork.removeValidator(publicKey, operatorIds, cluster);
    emit SSVNetworkRemoved(publicKey, operatorIds, cluster.index);
  }

  function liquidateSSVNetwork(
    address owner,
    uint64[] calldata operatorIds,
    ISSVNetwork.Cluster calldata cluster
  ) external {
    ssvNetwork.liquidate(owner, operatorIds, cluster);
    emit SSVNetworkLiquidated(owner, operatorIds, cluster.index);
  }

  function reactivateSSV(
    uint64[] calldata operatorIds,
    uint256 amount,
    ISSVNetwork.Cluster calldata cluster
  ) external payable onlyOwner {
    ssvNetwork.reactivate(operatorIds, amount, cluster);
    emit SSVNetworkReactivated(operatorIds, amount, cluster.index);
  }

  function deposit(
    uint64[] calldata operatorIds,
    uint256 amount,
    ISSVNetwork.Cluster calldata cluster
  ) external onlyOwner {
    ssvNetwork.deposit(address(this), operatorIds, amount, cluster);
  }

  function withdraw(
    uint64[] calldata operatorIds,
    uint256 amount,
    ISSVNetwork.Cluster calldata cluster
  ) external onlyOwner {
    ssvNetwork.withdraw(operatorIds, amount, cluster);
  }

  function approve() external onlyOwner {
    uint256 maxValue = type(uint256).max;
    ssvToken.approve(address(ssvToken), maxValue);
  }

  function setFeeRecipientAddress(address account) external onlyOwner {
    ssvNetwork.setFeeRecipientAddress(account);
  }

  function withdrawSSVToken(uint256 amount) external onlyOwner {
    require(amount > 0, 'Amount must be greater than 0');
    uint256 contractBalance = ssvToken.balanceOf(address(this));
    require(contractBalance >= amount, 'Not enough SSV tokens in the contract');

    ssvToken.transfer(owner(), amount);
  }

  function withdrawAllEthToStakeTogether() external onlyOwner {
    require(
      address(stakeTogether) != address(0),
      'StakeTogether address must be set before withdrawing ETH'
    );
    uint256 contractBalance = address(this).balance;
    payable(address(stakeTogether)).transfer(contractBalance);
  }
}
