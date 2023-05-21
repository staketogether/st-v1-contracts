// SPDX-FileCopyrightText: 2023 Stake Together <info@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './interfaces/IDepositContract.sol';
import './interfaces/ISSVNetwork.sol';
import './StakeTogether.sol';

contract STValidator is Ownable, ReentrancyGuard {
  StakeTogether public stakeTogether;
  IDepositContract public immutable depositContract;
  ISSVNetwork public immutable ssvNetwork;
  IERC20 public immutable ssvToken;

  bytes public withdrawalCredentials;

  constructor(address _depositContract, address _ssvNetwork, address _ssvToken) {
    depositContract = IDepositContract(_depositContract);
    ssvNetwork = ISSVNetwork(_ssvNetwork);
    ssvToken = IERC20(_ssvToken);
  }

  modifier onlyStakeTogether() {
    require(msg.sender == address(stakeTogether), 'ONLY_STAKE_TOGETHER');
    _;
  }

  function setStakeTogether(address _stakeTogether) external onlyOwner {
    require(address(stakeTogether) == address(0), 'ST_ALREADY_SET');
    stakeTogether = StakeTogether(_stakeTogether);
  }

  function setWithdrawalCredentials(bytes memory _withdrawalCredentials) external onlyOwner {
    require(withdrawalCredentials.length == 0, 'WITHDRAWAL_CREDENTIALS_ALREADY_SET');
    withdrawalCredentials = _withdrawalCredentials;
  }

  /*****************
   ** ETH Validator **
   *****************/

  event ValidatorCreated(
    address indexed creator,
    bytes pubkey,
    bytes withdrawal_credentials,
    bytes signature,
    bytes32 deposit_data_root
  );

  bytes[] public validators;

  function createValidator(
    bytes memory pubkey,
    bytes memory signature,
    bytes32 deposit_data_root
  ) external payable onlyStakeTogether nonReentrant {
    require(msg.value == 32 ether, 'MUST_SEND_32_ETH');

    depositContract.deposit{ value: msg.value }(
      pubkey,
      withdrawalCredentials,
      signature,
      deposit_data_root
    );

    validators.push(pubkey);

    emit ValidatorCreated(msg.sender, pubkey, withdrawalCredentials, signature, deposit_data_root);
  }

  function isValidator(bytes memory pubkey) public view returns (bool) {
    for (uint256 i = 0; i < validators.length; i++) {
      if (keccak256(validators[i]) == keccak256(pubkey)) {
        return true;
      }
    }
    return false;
  }

  /*****************
   ** DVT **
   *****************/

  event SSVNetworkRegistered(bytes publicKey, uint64[] operatorIds, uint256 amount, uint256 clusterIndex);
  event SSVNetworkRemoved(bytes publicKey, uint64[] operatorIds, uint256 clusterIndex);
  event SSVNetworkLiquidated(address owner, uint64[] operatorIds, uint256 clusterIndex);
  event SSVNetworkReactivated(uint64[] operatorIds, uint256 amount, uint256 clusterIndex);

  function registerValidator(
    bytes calldata publicKey,
    uint64[] calldata operatorIds,
    bytes calldata sharesEncrypted,
    uint256 amount,
    ISSVNetwork.Cluster calldata cluster
  ) external onlyOwner nonReentrant {
    require(isValidator(publicKey), 'NON_ST_VALIDATOR');
    ssvNetwork.registerValidator(publicKey, operatorIds, sharesEncrypted, amount, cluster);

    emit SSVNetworkRegistered(publicKey, operatorIds, amount, cluster.index);
  }

  function removeValidator(
    bytes calldata publicKey,
    uint64[] calldata operatorIds,
    ISSVNetwork.Cluster calldata cluster
  ) external onlyOwner nonReentrant {
    require(isValidator(publicKey), 'NON_ST_VALIDATOR');
    ssvNetwork.removeValidator(publicKey, operatorIds, cluster);
    emit SSVNetworkRemoved(publicKey, operatorIds, cluster.index);
  }

  function liquidateSSVNetwork(
    address _owner,
    uint64[] calldata operatorIds,
    ISSVNetwork.Cluster calldata cluster
  ) external onlyOwner nonReentrant {
    ssvNetwork.liquidate(_owner, operatorIds, cluster);
    emit SSVNetworkLiquidated(_owner, operatorIds, cluster.index);
  }

  function reactivateSSV(
    uint64[] calldata operatorIds,
    uint256 amount,
    ISSVNetwork.Cluster calldata cluster
  ) external payable onlyOwner nonReentrant {
    ssvNetwork.reactivate(operatorIds, amount, cluster);
    emit SSVNetworkReactivated(operatorIds, amount, cluster.index);
  }

  function deposit(
    uint64[] calldata operatorIds,
    uint256 amount,
    ISSVNetwork.Cluster calldata cluster
  ) external onlyOwner nonReentrant {
    ssvNetwork.deposit(address(this), operatorIds, amount, cluster);
  }

  function withdraw(
    uint64[] calldata operatorIds,
    uint256 amount,
    ISSVNetwork.Cluster calldata cluster
  ) external onlyOwner nonReentrant {
    ssvNetwork.withdraw(operatorIds, amount, cluster);
  }

  function approve() external onlyOwner returns (bool) {
    uint256 maxValue = type(uint256).max;
    return ssvToken.approve(address(ssvToken), maxValue);
  }

  function setFeeRecipientAddress(address account) external onlyOwner {
    ssvNetwork.setFeeRecipientAddress(account);
  }

  function withdrawSSVToken(uint256 amount) external onlyOwner returns (bool) {
    require(amount > 0, 'ZERO_AMOUNT');
    uint256 contractBalance = ssvToken.balanceOf(address(this));
    require(contractBalance >= amount, 'NO_ENOUGHT_SSV_BALANCE');

    return ssvToken.transfer(owner(), amount);
  }

  function withdrawETHToStakeTogether() external onlyOwner {
    require(address(stakeTogether) != address(0), 'NEED_TO_SET_STAKE_TOGETHER_ADDRESS_FIRST');
    uint256 contractBalance = address(this).balance;
    payable(address(stakeTogether)).transfer(contractBalance);
  }
}
