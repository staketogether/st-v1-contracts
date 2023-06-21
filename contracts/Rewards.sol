// SPDX-FileCopyrightText: 2023 Stake Together Labs <info@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import './StakeTogether.sol';

/// @custom:security-contact security@staketogether.app
contract Rewards is Ownable, Pausable, ReentrancyGuard {
  StakeTogether public stakeTogether;

  /*****************
   ** TIME LOCK **
   *****************/

  event ProposeSetTimeLockDuration(uint256 duration, uint256 executionTime);
  event ExecuteSetTimeLockDuration(uint256 duration);
  event ProposeSetDisagreementLimit(uint256 limit, uint256 executionTime);
  event ExecuteSetDisagreementLimit(uint256 limit);
  event ProposeAddOracle(address oracle, uint256 executionTime);
  event ExecuteAddOracle(address oracle);
  event ProposeRemoveOracle(address oracle, uint256 executionTime);
  event ExecuteRemoveOracle(address oracle);

  struct TimeLockedProposal {
    address target;
    uint256 value;
    uint256 executionTime;
  }

  uint256 public timeLockDuration = 1 days / 15;
  mapping(string => TimeLockedProposal) public timeLockedProposals;

  mapping(address => uint256) public disagreementCounts;
  uint256 public disagreementLimit = 3;

  function proposeSetTimeLockDuration(uint256 _duration) external onlyOwner {
    TimeLockedProposal storage proposal = timeLockedProposals['setTimeLockDuration'];
    require(
      proposal.executionTime < block.timestamp,
      'Previous setTimeLockDuration proposal still pending.'
    );

    proposal.value = _duration;
    proposal.executionTime = block.timestamp + timeLockDuration;

    emit ProposeSetTimeLockDuration(_duration, proposal.executionTime);
  }

  function executeSetTimeLockDuration() external onlyOwner {
    TimeLockedProposal storage proposal = timeLockedProposals['setTimeLockDuration'];
    require(block.timestamp >= proposal.executionTime, 'TIME_LOCK_NOT_EXPIRED');
    timeLockDuration = proposal.value;
    proposal.executionTime = 0;
    emit ExecuteSetTimeLockDuration(timeLockDuration);
  }

  function proposeSetDisagreementLimit(uint256 _limit) external onlyOwner {
    TimeLockedProposal storage proposal = timeLockedProposals['setDisagreementLimit'];
    require(
      proposal.executionTime < block.timestamp,
      'Previous setDisagreementLimit proposal still pending.'
    );

    proposal.value = _limit;
    proposal.executionTime = block.timestamp + timeLockDuration;

    emit ProposeSetDisagreementLimit(_limit, proposal.executionTime);
  }

  function executeSetDisagreementLimit() external onlyOwner {
    TimeLockedProposal storage proposal = timeLockedProposals['setDisagreementLimit'];
    require(
      block.timestamp >= proposal.executionTime,
      'Time lock for setDisagreementLimit not expired yet.'
    );

    disagreementLimit = proposal.value;

    proposal.executionTime = 0;

    emit ExecuteSetDisagreementLimit(disagreementLimit);
  }

  // Todo: Add Option to Add Multiples Oracles at once
  function proposeAddOracle(address _oracle) external onlyOwner {
    TimeLockedProposal storage proposal = timeLockedProposals['addOracle'];
    require(proposal.executionTime < block.timestamp, 'PREVIOUS_PROPOSAL_PENDING');

    proposal.target = _oracle;
    proposal.executionTime = block.timestamp + timeLockDuration;

    emit ProposeAddOracle(_oracle, proposal.executionTime);
  }

  function executeAddOracle() external onlyOwner {
    TimeLockedProposal storage proposal = timeLockedProposals['addOracle'];
    require(block.timestamp >= proposal.executionTime, 'TIME_LOCK_PENDING');

    _addOracle(proposal.target);

    proposal.executionTime = 0;

    emit ExecuteAddOracle(proposal.target);
  }

  function proposeRemoveOracle(address _oracle) external onlyOwner {
    TimeLockedProposal storage proposal = timeLockedProposals['removeOracle'];
    require(proposal.executionTime < block.timestamp, 'PREVIOUS_PROPOSAL_PENDING');

    proposal.target = _oracle;
    proposal.executionTime = block.timestamp + timeLockDuration;

    emit ProposeRemoveOracle(_oracle, proposal.executionTime);
  }

  function executeRemoveOracle() external onlyOwner {
    TimeLockedProposal storage proposal = timeLockedProposals['removeOracle'];
    require(block.timestamp >= proposal.executionTime, 'TIME_LOCK_PENDING');

    _removeOracle(proposal.target);

    proposal.executionTime = 0;

    emit ExecuteRemoveOracle(proposal.target);
  }

  function isProposalReady(string memory proposalName) public view returns (bool) {
    TimeLockedProposal storage proposal = timeLockedProposals[proposalName];
    return block.timestamp >= proposal.executionTime;
  }

  /*****************
   ** REPORTS **
   *****************/

  // Todo: Implement Ether Receive

  event ConsensusApproved(uint256 indexed blockNumber, bytes32 reportHash);
  event ConsensusFail(uint256 indexed blockNumber, bytes32 reportHash);
  event ReportQuorumNotAchieved(uint256 indexed blockNumber, bytes32 reportHash);

  event SetStakeTogether(address stakeTogether);
  event SetReportMaxFrequency(uint256 newFrequency);
  event SetReportQuorum(uint256 newQuorum);
  event SetNextBlock(uint256 newBlock);

  event SetRewardsSanityLimit(uint256 amount);

  modifier onlyOracle() {
    require(isOracle(msg.sender), 'ONLY_ORACLES');
    _;
  }

  struct Report {
    uint256 blockNumber;
    uint256 beaconBalance;
    uint256 totalRewardsAmount;
    uint256 totalRewardsShares;
    uint256 stakeTogetherShares;
    uint256 operatorShares;
    uint256 poolShares;
    bytes[] exitedValidators;
  }

  uint256 public reportLastBlock = 0;
  uint256 public reportNextBlock = 1;
  uint256 public reportFrequency = 1;
  uint256 public reportQuorum = 1; // Todo: Mainnet = 3

  address[] private oracles;
  mapping(address => bool) public oraclesBlacklist;
  mapping(bytes32 => Report[]) public oracleReport;

  mapping(uint256 => uint256) private consensusBlock;
  mapping(uint256 => uint256) private reportBlockCount;
  mapping(bytes32 => uint256) private reportHashCount;

  uint256 public rewardsSanityLimit = 0.01 ether;
  bool bunkerMode = false;

  function submitBlockReport(uint256 _reportBlock, Report memory _report) public onlyOracle {
    require(address(stakeTogether) != address(0), 'STAKE_TOGETHER_NOT_SET');

    if (block.number >= reportNextBlock + reportFrequency) {
      reportNextBlock = reportNextBlock + reportFrequency;
      emit SetNextBlock(reportNextBlock);
    }

    require(block.number >= reportNextBlock, 'TOO_EARLY_TO_REPORT');

    _validBlockReport(_report);

    bytes32 reportHash = keccak256(abi.encode(_report));

    reportHashCount[reportHash]++;
    reportBlockCount[_reportBlock]++;

    if (reportBlockCount[_reportBlock] >= reportQuorum) {
      if (reportHashCount[reportHash] >= reportQuorum) {
        approveBlockConsensus(reportHash);
      } else {
        // Todo: Double Check on this logic
        disagreementCounts[msg.sender]++;
        if (disagreementCounts[msg.sender] >= disagreementLimit) {
          _addOracleBlacklist(msg.sender);
        }
        emit ConsensusFail(_reportBlock, reportHash);
      }
    }
  }

  function approveBlockConsensus(bytes32 _reportsHash) internal nonReentrant {
    reportLastBlock = reportNextBlock;
    reportNextBlock = block.number + reportFrequency;
    emit SetNextBlock(reportNextBlock);

    // Todo: Execute actions

    emit ConsensusApproved(reportNextBlock, _reportsHash);
  }

  function setReportMaxFrequency(uint256 newFrequency) external onlyOwner {
    reportFrequency = newFrequency;
    emit SetReportMaxFrequency(newFrequency);
  }

  function _validBlockReport(Report memory _report) internal pure {
    require(
      _report.totalRewardsShares ==
        _report.stakeTogetherShares + _report.operatorShares + _report.poolShares,
      'INVALID_REWARDS_SHARES'
    );
  }

  /*****************
   ** ORACLES **
   *****************/

  event SetBunkerMode(bool bunkerMode);
  event AddOracle(address oracle);
  event RemoveOracle(address oracle);
  event AddOracleBlacklist(address oracle);
  event RemoveOracleBlacklist(address oracle);

  function getOracles() external view returns (address[] memory) {
    return oracles;
  }

  function isOracle(address _oracle) public view returns (bool) {
    if (oraclesBlacklist[_oracle]) {
      return false;
    }
    for (uint256 i = 0; i < oracles.length; i++) {
      if (oracles[i] == _oracle) {
        return true;
      }
    }
    return false;
  }

  function _addOracle(address _oracle) internal onlyOwner {
    require(!isOracle(_oracle), 'ORACLE_ALREADY_EXISTS');
    require(_oracle != address(0), 'Oracle address cannot be zero');
    oracles.push(_oracle);
    _updateQuorum();
    emit AddOracle(_oracle);
  }

  function _removeOracle(address _oracle) internal onlyOwner {
    require(isOracle(_oracle), 'ORACLE_DOES_NOT_EXIST');

    for (uint256 i = 0; i < oracles.length; i++) {
      if (oracles[i] == _oracle) {
        oracles[i] = oracles[oracles.length - 1];
        oracles.pop();
        break;
      }
    }
    emit RemoveOracle(_oracle);

    if (oracles.length < reportQuorum) {
      _pause();
    }
    _updateQuorum();
  }

  function _addOracleBlacklist(address _oracle) internal onlyOwner {
    require(isOracle(_oracle), 'NODE_DOES_NOT_EXIST');
    require(_oracle != address(0), 'Oracle address cannot be zero');
    oraclesBlacklist[_oracle] = true;
    emit AddOracleBlacklist(_oracle);
  }

  function _removeOracleBlacklist(address _oracle) internal onlyOwner {
    require(oraclesBlacklist[_oracle], 'NODE_NOT_UN_BLACKLISTED');
    oraclesBlacklist[_oracle] = false;
    emit RemoveOracleBlacklist(_oracle);
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

  function setRewardsSanityLimit(uint256 _rewardsSanityLimit) external onlyOwner {
    rewardsSanityLimit = _rewardsSanityLimit;
    emit SetRewardsSanityLimit(_rewardsSanityLimit);
  }

  function _updateQuorum() internal {
    uint256 newQuorum = (oracles.length + 1) / 2;
    newQuorum = newQuorum < 3 ? 3 : newQuorum;
    reportQuorum = newQuorum;
    emit SetReportQuorum(newQuorum);
  }
}
