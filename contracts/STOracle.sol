// SPDX-FileCopyrightText: 2023 Stake Together <info@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './StakeTogether.sol';

contract STOracle is Ownable, Pausable, ReentrancyGuard {
  StakeTogether public stakeTogether;
  uint256 public beaconBalance;
  uint256 public beaconLastReportBlock = 0;

  uint256 public reportFrequency = 5760;
  uint256 public reportQuorum = 2;
  uint256 public reportNextBlock = 5760;

  address[] public nodes;

  mapping(address => mapping(uint256 => uint256)) private nodeReports;
  mapping(uint256 => uint256) private reportCount;
  mapping(uint256 => uint256) private blockConsensus;
  mapping(uint256 => mapping(uint256 => uint256)) private balanceCount;

  event ConsensusApproved(uint256 indexed blockNumber, uint256 balance);
  event ConsensusFail(uint256 indexed blockNumber);
  event NonConsensusValueReported(
    address indexed node,
    uint256 reportedBlock,
    uint256 reportedBalance,
    uint256 consensusBalance
  );
  event ReportMaxFrequencyChanged(uint256 newFrequency);
  event ReportQuorumChanged(uint256 newQuorum);
  event NodeAdded(address node);
  event NodeRemoved(address node);
  event NodeBlacklisted(address node);

  modifier onlyNodes() {
    require(_isNode(msg.sender), 'ONLY_NODES');
    _;
  }

  function setStakeTogether(address _stakeTogether) external onlyOwner {
    require(address(stakeTogether) == address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(_stakeTogether);
  }

  function report(uint256 reportBlock, uint256 reportBalance) public onlyNodes whenNotPaused {
    require(address(stakeTogether) != address(0), 'STAKE_TOGETHER_NOT_SET');
    require(reportBalance > 0, 'ZERO_VALUE');
    require(reportBlock == reportNextBlock, 'NON_NEXT_BLOCK');
    require(block.number >= reportNextBlock, 'TOO_EARLY_TO_REPORT');
    require(nodeReports[msg.sender][reportBlock] == 0, 'NODE_ALREADY_REPORTED');

    nodeReports[msg.sender][reportNextBlock] = reportBalance;
    reportCount[reportNextBlock]++;
    balanceCount[reportNextBlock][reportBalance]++;

    if (reportCount[reportNextBlock] >= reportQuorum) {
      checkForConsensus();
    }
  }

  function checkForConsensus() internal {
    uint256 consensusBalance = 0;
    uint256 maxCount = 0;

    for (uint256 i = 0; i < nodes.length; i++) {
      uint256 balance = nodeReports[nodes[i]][reportNextBlock];
      uint256 count = balanceCount[reportNextBlock][balance];

      if (count > maxCount) {
        maxCount = count;
        consensusBalance = balance;
      }
    }

    if (maxCount >= reportQuorum) {
      blockConsensus[reportNextBlock] = consensusBalance;
      checkForNonConsensusReports(consensusBalance);
      rebase(consensusBalance);
    } else {
      emit ConsensusFail(reportNextBlock);
    }
  }

  function rebase(uint256 consensusBalance) internal nonReentrant {
    beaconBalance = consensusBalance;
    beaconLastReportBlock = reportNextBlock;
    reportNextBlock = block.number + reportFrequency;

    stakeTogether.setClBalance(beaconBalance);

    emit ConsensusApproved(reportNextBlock, beaconBalance);
  }

  function checkForNonConsensusReports(uint256 consensusBalance) internal {
    for (uint256 i = 0; i < nodes.length; i++) {
      address node = nodes[i];
      uint256 reportedBalance = nodeReports[node][reportNextBlock];
      if (reportedBalance != consensusBalance && reportedBalance > 0) {
        emit NonConsensusValueReported(node, reportNextBlock, reportedBalance, consensusBalance);
        _blacklistNode(node);
      }
    }
  }

  function setReportMaxFrequency(uint256 newFrequency) external onlyOwner {
    // require(newFrequency >= 240, 'Frequency must be at least 1 hour (approx 240 blocks)');
    reportFrequency = newFrequency;
    emit ReportMaxFrequencyChanged(newFrequency);
  }

  function setReportQuorum(uint256 newQuorum) external onlyOwner {
    require(newQuorum >= 1, 'QUORUM_NEEDS_TO_BE_AT_LEAST_1');
    require(newQuorum <= nodes.length, 'QUORUM_CAN_NOT_BE_GREATER_THAN_NODES');
    reportQuorum = newQuorum;
    emit ReportQuorumChanged(newQuorum);
  }

  function getNodes() external view returns (address[] memory) {
    return nodes;
  }

  function isNode(address node) external view returns (bool) {
    return _isNode(node);
  }

  function isNodeBlaclisted(address node) external view returns (bool) {
    return !_isNode(node);
  }

  function addNode(address node) external onlyOwner {
    require(!_isNode(node), 'NODE_ALREADY_EXISTS');
    nodes.push(node);
    emit NodeAdded(node);
  }

  function removeNode(address node) external onlyOwner {
    _removeNode(node);
  }

  function getNodeReportByBlock(address node, uint256 blockNumber) external view returns (uint256) {
    return nodeReports[node][blockNumber];
  }

  function getNodeReports(address node, uint256 blockNumber) external view returns (uint256) {
    return nodeReports[node][blockNumber];
  }

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
    emit NodeRemoved(node);

    if (nodes.length < reportQuorum) {
      _pause();
    }
  }

  function _blacklistNode(address node) internal {
    _removeNode(node);
    emit NodeBlacklisted(node);
  }
}
