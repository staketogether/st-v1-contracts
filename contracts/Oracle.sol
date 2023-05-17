// SPDX-FileCopyrightText: 2023 Stake Together <info@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './StakeTogether.sol';

contract Oracle is Ownable, Pausable {
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
    require(_isNode(msg.sender), 'Caller should be a registered node');
    _;
  }

  function setStakeTogether(address _stakeTogether) external onlyOwner {
    require(address(stakeTogether) == address(0), 'StakeTogether address can only be set once');
    stakeTogether = StakeTogether(_stakeTogether);
  }

  function report(uint256 reportBlock, uint256 reportBalance) public onlyNodes whenNotPaused {
    require(address(stakeTogether) != address(0), 'StakeTogether should be set');
    require(reportBalance > 0, 'Report balance must be greater than 0');
    require(reportBlock == reportNextBlock, 'Report is not for the next block');
    require(block.number >= reportNextBlock, 'Block window not yet reached');
    require(nodeReports[msg.sender][reportBlock] == 0, 'Node has already reported for this block');

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

  function rebase(uint256 consensusBalance) internal {
    beaconBalance = consensusBalance;
    beaconLastReportBlock = reportNextBlock;
    reportNextBlock = block.number + reportFrequency;

    stakeTogether.setBeaconBalance(beaconBalance);

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
    require(newFrequency >= 240, 'Frequency must be at least 1 hour (approx 240 blocks)');
    reportFrequency = newFrequency;
    emit ReportMaxFrequencyChanged(newFrequency);
  }

  function setReportQuorum(uint256 newQuorum) external onlyOwner {
    require(newQuorum >= 1, 'Quorum must be at least 1');
    require(newQuorum <= nodes.length, 'Quorum cannot exceed current number of nodes');
    reportQuorum = newQuorum;
    emit ReportQuorumChanged(newQuorum);
  }

  function addNode(address node) external onlyOwner {
    require(!_isNode(node), 'Node already exists');
    nodes.push(node);
    emit NodeAdded(node);
  }

  function removeNode(address node) external onlyOwner {
    _removeNode(node);
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
    require(_isNode(node), 'Node does not exist');

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
