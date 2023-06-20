// SPDX-FileCopyrightText: 2023 Stake Together Labs <info@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './StakeTogether.sol';

/// @custom:security-contact security@staketogether.app
contract Rewards is Ownable, Pausable, ReentrancyGuard {
  StakeTogether public stakeTogether;

  struct RewardReport {
    uint256 reportPart;
    uint256 reportTotalParts;
    uint256 totalRewardsShares;
    uint256 totalRewardsAmount;
    uint256 stakeTogetherShares;
    uint256 stakeTogetherAmount;
    uint256 operatorShares;
    uint256 operatorAmount;
    uint256 poolShares;
    uint256 poolAmount;
  }

  struct Report {
    uint256 reportBlock;
    address reportNode;
    uint256 beaconBalance;
    uint256 totalBeaconValidators;
    uint256 totalTransientValidators;
    uint256 totalExitedValidators;
    RewardReport rewardReport;
    bytes[] excludedValidators;
  }

  uint256 public reportLastBlock = 0;
  uint256 public reportNextBlock = 1;
  uint256 public reportFrequency = 1;
  uint256 public reportQuorum = 1;
  bool public isInConsensus = false;
  bool public bunkerMode = false;

  address[] private nodes;
  mapping(bytes32 => Report[]) public nodesReport;

  mapping(uint256 => uint256) private consensusBlock;
  mapping(uint256 => uint256) private reportsBlockCount;
  mapping(bytes32 => uint256) private reportsHashCount;
  mapping(uint256 => mapping(uint256 => uint256)) private reportsBalanceCount;

  event ConsensusApproved(uint256 indexed blockNumber, bytes32 reportHash);
  event ConsensusFail(uint256 indexed blockNumber, bytes32 reportHash);
  event ReportQuorumNotAchieved(uint256 indexed blockNumber, bytes32 reportHash);
  event NonConsensusValueReported(
    address indexed node,
    uint256 reportedBlock,
    uint256 reportedBalance,
    uint256 beaconBalance
  );
  event SetStakeTogether(address stakeTogether);
  event SetReportMaxFrequency(uint256 newFrequency);
  event SetReportQuorum(uint256 newQuorum);
  event SetNextBlock(uint256 newBlock);
  event AddNode(address node);
  event RemoveNode(address node);
  event BlacklistNode(address node);
  event SetBunkerMode(bool bunkerMode);

  modifier onlyNodes() {
    require(_isNode(msg.sender), 'ONLY_NODES');
    _;
  }

  function setStakeTogether(address _stakeTogether) external onlyOwner {
    require(address(stakeTogether) == address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function setBunkerMode(bool _bunkerMode) external onlyOwner {
    bunkerMode = _bunkerMode;
    emit SetBunkerMode(_bunkerMode);
  }

  function report(uint256 _reportNextBlock, Report[] memory _reports) public onlyNodes {
    require(address(stakeTogether) != address(0), 'STAKE_TOGETHER_NOT_SET');

    if (block.number >= reportNextBlock + reportFrequency) {
      reportNextBlock = reportNextBlock + reportFrequency;
      emit SetNextBlock(reportNextBlock);
    }

    require(block.number >= reportNextBlock, 'TOO_EARLY_TO_REPORT');

    bytes32 reportsHash = keccak256(abi.encode(_reports));

    for (uint256 i = 0; i < _reports.length; i++) {
      Report memory _report = _reports[i];

      require(_report.reportNode == msg.sender, 'REPORTER_NOT_NODE');
      require(_report.reportBlock == reportNextBlock, 'NON_NEXT_BLOCK');
      require(_report.beaconBalance > 0, 'ZERO_VALUE');
      require(nodesReport[reportsHash].length == 0, 'NODE_ALREADY_REPORTED');
    }

    nodesReport[reportsHash] = _reports;
    reportsHashCount[reportsHash]++;
    reportsBlockCount[_reportNextBlock]++;

    if (reportsBlockCount[_reportNextBlock] >= reportQuorum) {
      if (reportsHashCount[reportsHash] >= reportQuorum) {
        approveConsensus(reportsHash);
      } else {
        emit ConsensusFail(_reportNextBlock, reportsHash);
      }
    }
  }

  function approveConsensus(bytes32 _reportsHash) internal nonReentrant {
    Report[] memory reports = nodesReport[_reportsHash];

    reportLastBlock = reportNextBlock;
    reportNextBlock = block.number + reportFrequency;
    emit SetNextBlock(reportNextBlock);

    // actions

    emit ConsensusApproved(reportNextBlock, _reportsHash);
  }

  function setReportMaxFrequency(uint256 newFrequency) external onlyOwner {
    reportFrequency = newFrequency;
    emit SetReportMaxFrequency(newFrequency);
  }

  function setReportQuorum(uint256 newQuorum) external onlyOwner {
    require(newQuorum >= 1, 'QUORUM_NEEDS_TO_BE_AT_LEAST_1');
    require(newQuorum <= nodes.length, 'QUORUM_CAN_NOT_BE_GREATER_THAN_NODES');
    reportQuorum = newQuorum;
    emit SetReportQuorum(newQuorum);
  }

  function getNodes() external view returns (address[] memory) {
    return nodes;
  }

  function isNode(address node) external view returns (bool) {
    return _isNode(node);
  }

  function isNodeBlacklisted(address node) external view returns (bool) {
    return !_isNode(node);
  }

  function addNode(address node) external onlyOwner {
    require(!_isNode(node), 'NODE_ALREADY_EXISTS');
    nodes.push(node);
    emit AddNode(node);
  }

  function removeNode(address node) external onlyOwner {
    _removeNode(node);
  }

  // function _sanityCheck(
  //   Reward memory _stakeTogetherReward,
  //   Reward memory _operatorReward,
  //   Reward[] memory _poolRewards,
  //   RewardReport memory _rewardReport
  // ) internal view {
  //   require(_rewardReport.reportBlock > 0, 'INVALID_REPORT_BLOCK');
  //   require(_rewardReport.reportPart > 0, 'INVALID_REPORT_PART');
  //   require(_rewardReport.reportPart <= _rewardReport.reportTotalParts, 'INVALID_REPORT_TOTAL_PART');
  //   require(_stakeTogetherReward.recipient == stakeTogetherFeeAddress, 'INVALID_STAKE_TOGETHER_ADDRESS');
  //   require(_operatorReward.recipient == operatorFeeAddress, 'INVALID_OPERATOR_ADDRESS');
  //   require(
  //     _rewardReport.totalRewardsShares == getSharesByPooledEth(_rewardReport.totalRewardsAmount),
  //     'INVALID_TOTAL_SHARES'
  //   );
  //   require(
  //     _rewardReport.totalRewardsAmount == pooledEthByShares(_rewardReport.totalRewardsShares),
  //     'INVALID_TOTAL_AMOUNT'
  //   );
  //   require(
  //     _rewardReport.stakeTogetherShares <= _rewardReport.totalRewardsShares,
  //     'INVALID_STAKE_TOGETHER_SHARES'
  //   );
  //   require(
  //     _rewardReport.operatorShares <= _rewardReport.totalRewardsShares,
  //     'INVALID_STAKE_TOGETHER_AMOUNT'
  //   );
  //   for (uint i = 0; i < _poolRewards.length; i++) {
  //     Reward memory poolReward = _poolRewards[i];
  //     require(poolReward.shares <= totalPoolShares, 'POOL_SHARES_EXCEED_TOTAL');
  //   }

  //   uint256 maxTotalRewards = Math.mulDiv(totalPooledEther(), rewardsSanityLimit, 1 ether);
  //   require(_rewardReport.totalRewardsAmount <= maxTotalRewards, 'EXCEED_SANITY_LIMIT');
  //   require(
  //     pooledEthByShares(_rewardReport.totalRewardsAmount) <= maxTotalRewards,
  //     'EXCEED_SANITY_LIMIT'
  //   );

  //   uint256 maxStakeTogetherRewards = Math.mulDiv(
  //     _rewardReport.totalRewardsAmount,
  //     stakeTogetherFee,
  //     1 ether
  //   );
  //   require(_rewardReport.stakeTogetherAmount <= maxStakeTogetherRewards, 'EXCEED_STAKE_TOGETHER_LIMIT');

  //   uint256 maxOperatorRewards = Math.mulDiv(_rewardReport.totalRewardsAmount, operatorFee, 1 ether);
  //   require(_rewardReport.operatorAmount <= maxOperatorRewards, 'EXCEED_OPERATOR_LIMIT');

  //   uint256 maxPoolRewards = Math.mulDiv(_rewardReport.totalRewardsAmount, poolFee, 1 ether);
  //   require(_rewardReport.poolAmount <= maxPoolRewards, 'EXCEED_POOL_LIMIT');
  // }

  function _isNode(address node) internal view returns (bool) {
    for (uint256 i = 0; i < nodes.length; i++) {
      if (nodes[i] == node) {
        return true;
      }
    }
    return false;
  }

  function _removeNode(address node) internal {
    require(_isNode(node), 'NODE_DOES_NOT_EXIST');

    for (uint256 i = 0; i < nodes.length; i++) {
      if (nodes[i] == node) {
        nodes[i] = nodes[nodes.length - 1];
        nodes.pop();
        break;
      }
    }
    emit RemoveNode(node);

    if (nodes.length < reportQuorum) {
      _pause();
    }
  }

  function _blacklistNode(address node) internal {
    _removeNode(node);
    emit BlacklistNode(node);
  }
}
