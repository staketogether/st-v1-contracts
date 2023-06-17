// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './StakeTogether.sol';

contract STOracle is Ownable, Pausable, ReentrancyGuard {
  StakeTogether public stakeTogether;

  struct Report {
    uint256 beaconBalance;
    uint256 transientBalance;
    uint256 totalBeaconValidators;
    uint256 totalTransientValidators;
    uint256 totalExitedValidators;
  }

  uint256 public beaconBalance;
  uint256 public transientBalance;

  uint256 public reportLastBlock = 0;
  uint256 public reportNextBlock = 1;
  uint256 public reportFrequency = 1;
  uint256 public reportQuorum = 1;
  bool public isInConsensus = false;

  address[] private nodes;
  mapping(address => mapping(uint256 => uint256)) private nodesReports;

  mapping(uint256 => uint256) private consensusBlock;
  mapping(uint256 => uint256) private reportsCount;
  mapping(uint256 => mapping(uint256 => uint256)) private reportsBalanceCount;

  event ConsensusApproved(uint256 indexed blockNumber, uint256 transientBalance, uint256 beaconBalance);
  event ConsensusFail(uint256 indexed blockNumber);
  event ReportQuorumNotAchieved(uint256 indexed blockNumber);
  event NonConsensusValueReported(
    address indexed node,
    uint256 reportedBlock,
    uint256 reportedBalance,
    uint256 beaconBalance
  );
  event SetStakeTogether(address stakeTogether);
  event SetReportMaxFrequency(uint256 newFrequency);
  event SetReportQuorum(uint256 newQuorum);
  event AddNode(address node);
  event RemoveNode(address node);
  event BlacklistNode(address node);

  modifier onlyNodes() {
    require(_isNode(msg.sender), 'ONLY_NODES');
    _;
  }

  function setStakeTogether(address _stakeTogether) external onlyOwner {
    require(address(stakeTogether) == address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function report(uint256 _reportBlock, Report memory _report) public onlyNodes {
    require(address(stakeTogether) != address(0), 'STAKE_TOGETHER_NOT_SET');
    require(_report.beaconBalance > 0, 'ZERO_VALUE');
    require(_reportBlock == reportNextBlock, 'NON_NEXT_BLOCK');
    require(block.number >= reportNextBlock, 'TOO_EARLY_TO_REPORT');
    require(nodesReports[msg.sender][_reportBlock] == 0, 'NODE_ALREADY_REPORTED');

    uint256 consensusBalance = _report.transientBalance + _report.beaconBalance;

    nodesReports[msg.sender][reportNextBlock] = consensusBalance;
    reportsCount[reportNextBlock]++;
    reportsBalanceCount[reportNextBlock][consensusBalance]++;

    if (reportsCount[reportNextBlock] >= reportQuorum) {
      validConsensus(_report.transientBalance, _report.beaconBalance);
    } else {
      emit ReportQuorumNotAchieved(reportNextBlock);
    }
  }

  function validConsensus(uint256 _transientBalance, uint256 _beaconBalance) internal {
    uint256 totalReports = 0;
    uint256 consensusBalance = 0;

    for (uint256 i = 0; i < nodes.length; i++) {
      uint256 balance = nodesReports[nodes[i]][reportNextBlock];
      uint256 count = reportsBalanceCount[reportNextBlock][balance];

      if (count > totalReports) {
        totalReports = count;
        consensusBalance = balance;
      }
    }

    if (totalReports >= reportQuorum) {
      consensusBlock[reportNextBlock] = consensusBalance;
      checkForNonConsensusReports(consensusBalance);
      if (isInConsensus) {
        approveConsensus(_transientBalance, _beaconBalance);
      } else {
        emit ConsensusFail(reportNextBlock);
      }
    }
  }

  function approveConsensus(uint256 _transientBalance, uint256 _beaconBalance) internal nonReentrant {
    transientBalance = _transientBalance;
    beaconBalance = _beaconBalance;
    reportLastBlock = reportNextBlock;
    reportNextBlock = block.number + reportFrequency;

    stakeTogether.setTransientBalance(_transientBalance);
    stakeTogether.setBeaconBalance(_beaconBalance);

    emit ConsensusApproved(reportNextBlock, _transientBalance, _beaconBalance);
  }

  function checkForNonConsensusReports(uint256 _consensusBalance) internal {
    bool checkConsensus = true;
    for (uint256 i = 0; i < nodes.length; i++) {
      address node = nodes[i];
      uint256 reportedBalance = nodesReports[node][reportNextBlock];
      if (reportedBalance != _consensusBalance && reportedBalance > 0) {
        emit NonConsensusValueReported(node, reportNextBlock, reportedBalance, _consensusBalance);
        _blacklistNode(node);
        checkConsensus = false;
      }
    }
    isInConsensus = checkConsensus;
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

  function getNodeReportByBlock(address node, uint256 blockNumber) external view returns (uint256) {
    return nodesReports[node][blockNumber];
  }

  function getNodeReports(address node, uint256 blockNumber) external view returns (uint256) {
    return nodesReports[node][blockNumber];
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
