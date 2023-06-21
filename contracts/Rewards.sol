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

  // event EtherReceived(address indexed sender, uint amount);

  // receive() external payable {
  //   emit EtherReceived(msg.sender, msg.value);
  // }

  // fallback() external payable {
  //   emit EtherReceived(msg.sender, msg.value);
  // }

  function setStakeTogether(address _stakeTogether) external onlyOwner {
    require(address(stakeTogether) == address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  /*****************
   ** TIME LOCK **
   *****************/

  event ProposeTimeLockAction(string action, uint256 value, address target, uint256 executionTime);
  event ExecuteTimeLockAction(string action);

  struct TimeLockedProposal {
    uint256 value;
    address target;
    uint256 executionTime;
  }

  uint256 public timeLockDuration = 1 days / 15;
  mapping(string => TimeLockedProposal) public timeLockedProposals;

  function proposeTimeLockAction(
    string calldata action,
    uint256 value,
    address target
  ) external onlyOwner {
    TimeLockedProposal storage proposal = timeLockedProposals[action];
    require(proposal.executionTime < block.timestamp, 'Previous proposal still pending.');

    proposal.value = value;
    proposal.target = target;
    proposal.executionTime = block.timestamp + timeLockDuration;

    emit ProposeTimeLockAction(action, value, target, proposal.executionTime);
  }

  function executeTimeLockAction(string calldata action) external onlyOwner {
    TimeLockedProposal storage proposal = timeLockedProposals[action];
    require(block.timestamp >= proposal.executionTime, 'Time lock not expired yet.');

    if (keccak256(bytes(action)) == keccak256(bytes('setTimeLockDuration'))) {
      timeLockDuration = proposal.value;
    } else if (keccak256(bytes(action)) == keccak256(bytes('setDisagreementLimit'))) {
      disagreementLimit = proposal.value;
    } else if (keccak256(bytes(action)) == keccak256(bytes('addOracle'))) {
      _addOracle(proposal.target);
    } else if (keccak256(bytes(action)) == keccak256(bytes('removeOracle'))) {
      _removeOracle(proposal.target);
    } else if (keccak256(bytes(action)) == keccak256(bytes('setPenalize'))) {
      penalizeLimit = proposal.value;
    }

    proposal.executionTime = 0;
    emit ExecuteTimeLockAction(action);
  }

  function isProposalReady(string memory proposalName) public view returns (bool) {
    TimeLockedProposal storage proposal = timeLockedProposals[proposalName];
    return block.timestamp >= proposal.executionTime;
  }

  /*****************
   ** ORACLES **
   *****************/

  modifier onlyOracle() {
    require(activeOracles[msg.sender] && oraclesBlacklist[msg.sender] < penalizeLimit, 'ONLY_ORACLES');
    _;
  }

  event AddOracle(address oracle);
  event RemoveOracle(address oracle);
  event SetBunkerMode(bool bunkerMode);
  event SetOracleQuorum(uint256 newQuorum);
  event OraclePenalized(
    address indexed oracle,
    uint256 penalties,
    bytes32 faultyReportHash,
    Report faultyReport,
    bool removed
  );

  address[] private oracles;
  mapping(address => bool) private activeOracles;
  mapping(address => uint256) public oraclesBlacklist;
  uint256 public oracleQuorum = 1; // Todo: Mainnet = 3
  uint256 public penalizeLimit = 3;
  bool public bunkerMode = false;

  function getOracles() external view returns (address[] memory) {
    return oracles;
  }

  function getActiveOracleCount() internal view returns (uint256) {
    uint256 activeCount = 0;
    for (uint256 i = 0; i < oracles.length; i++) {
      if (activeOracles[oracles[i]]) {
        activeCount++;
      }
    }
    return activeCount;
  }

  function isOracle(address _oracle) public view returns (bool) {
    return activeOracles[_oracle] && oraclesBlacklist[_oracle] < penalizeLimit;
  }

  function setBunkerMode(bool _bunkerMode) external onlyOwner {
    bunkerMode = _bunkerMode;
    emit SetBunkerMode(_bunkerMode);
  }

  function _addOracle(address oracle) internal {
    require(!activeOracles[oracle], 'ORACLE_EXISTS');
    oracles.push(oracle);
    activeOracles[oracle] = true;
    emit AddOracle(oracle);
    _updateQuorum();
  }

  function _removeOracle(address oracle) internal {
    require(activeOracles[oracle], 'ORACLE_NOT_EXISTS');
    activeOracles[oracle] = false;
    emit RemoveOracle(oracle);
    _updateQuorum();
  }

  function _updateQuorum() internal onlyOwner {
    uint256 totalOracles = getActiveOracleCount();
    uint256 newQuorum = (totalOracles * 8) / 10;

    newQuorum = newQuorum < 3 ? 3 : newQuorum;
    newQuorum = newQuorum > totalOracles ? totalOracles : newQuorum;

    oracleQuorum = newQuorum;
    emit SetOracleQuorum(newQuorum);
  }

  function _penalizeOracle(address oracle, bytes32 faultyReportHash) internal {
    oraclesBlacklist[oracle]++;

    bool remove = oraclesBlacklist[oracle] >= penalizeLimit;
    if (remove) {
      _removeOracle(oracle);
    }

    emit OraclePenalized(
      oracle,
      oraclesBlacklist[oracle],
      faultyReportHash,
      reports[faultyReportHash],
      remove
    );
  }

  /*****************
   ** REPORTS **
   *****************/

modifier onlyAfterBlockConsensus(bytes32 reportHash) {
    require(reports[reportHash].consensusExecuted, "Block report consensus not executed yet");
    _;
}

  event ConsensusApproved(uint256 indexed blockNumber, bytes32 reportHash);
  event ConsensusFail(uint256 indexed blockNumber, bytes32 reportHash);
  event ReportQuorumNotAchieved(uint256 indexed blockNumber, bytes32 reportHash);

  event SetStakeTogether(address stakeTogether);
  event SetReportMaxFrequency(uint256 newFrequency);
  event SetReportQuorum(uint256 newQuorum);
  event SetNextBlock(uint256 newBlock);

  event SetRewardsSanityLimit(uint256 amount);

  struct Report {
    uint256 blockNumber;
    uint256 beaconBalance;
    uint256 totalRewardsAmount;
    uint256 totalRewardsShares;
    uint256 stakeTogetherShares;
    uint256 operatorShares;
    uint256 poolShares;
    bytes[] exitedValidators;
    bool consensusExecuted; 
    uint256 poolSharesSubmitted; 
  }

  struct PoolReport {
    address pool;
    address sharesAmount;
    bytes32 reportHash;
    bool consensusExecuted; 
  }

  mapping(bytes32 => Report) public reports;
  mapping(uint256 => bytes32[]) public reportsByBlock;
  mapping(bytes32 => PoolReport) public poolReports;
  mapping(bytes32 => PoolReport[]) public poolReportsByBlock;

  uint256 public reportLastBlock = 0;
  uint256 public reportNextBlock = 1;
  uint256 public reportFrequency = 1;

  uint256 public disagreementLimit = 3;

  function submitBlockReport(
    uint256 blockNumber,
    uint256 beaconBalance,
    uint256 totalRewardsAmount,
    uint256 totalRewardsShares,
    uint256 stakeTogetherShares,
    uint256 operatorShares,
    uint256 poolShares,
    bytes[] calldata exitedValidators
  ) external onlyOracle whenNotPaused {
    require(blockNumber > reportNextBlock, 'Invalid blockNumber');
    require(blockNumber <= block.number, 'Block number is in the future');
    require(block.number - blockNumber <= 256, 'Block is too old');

    bytes32 reportHash = keccak256(
      abi.encode(
        blockNumber,
        beaconBalance,
        totalRewardsAmount,
        totalRewardsShares,
        stakeTogetherShares,
        operatorShares,
        poolShares,
        exitedValidators
      )
    );

    reports[reportHash] = Report(
      blockNumber,
      beaconBalance,
      totalRewardsAmount,
      totalRewardsShares,
      stakeTogetherShares,
      operatorShares,
      poolShares,
      exitedValidators
    );

    reportsByBlock[blockNumber].push(reportHash);
  }

  function executeBlockConsensus(uint256 blockNumber) external onlyOwner {
    require(
    reports[consensusReportHash].poolShares == reports[consensusReportHash].poolSharesSubmitted,
    "Mismatch between reported and submitted poolShares"
);
    bytes32[] storage blockReports = reportsByBlock[blockNumber];
    uint256 maxVotes = 0;
    bytes32 consensusReportHash;

    // We iterate through each report once
    for (uint256 i = 0; i < blockReports.length; i++) {
      bytes32 currentReportHash = blockReports[i];
      uint256 currentVotes = 0;

      // And count how many reports are equal to it
      for (uint256 j = 0; j < blockReports.length; j++) {
        if (currentReportHash == blockReports[j]) {
          currentVotes++;
        }
      }

      // We update the consensusReportHash and maxVotes
      // if currentVotes is greater than maxVotes
      if (currentVotes > maxVotes) {
        consensusReportHash = currentReportHash;
        maxVotes = currentVotes;
      }
    }

    // If we got more votes than the oracleQuorum,
    // we consider it a valid report and update the state
if (maxVotes >= oracleQuorum) {
    Report storage consensusReport = reports[consensusReportHash];
    
    consensusReport.consensusExecuted = true;

      // Todo: Integrate Stake Together

      reportNextBlock = consensusReport.blockNumber + 1;
      emit ConsensusApproved(blockNumber, consensusReportHash);
    } else {
      reportNextBlock = blockNumber + reportFrequency;
      emit ConsensusFail(blockNumber, consensusReportHash);
    }
  }

  function isReportReady(uint256 blockNumber) public view returns (bool) {
    return reportsByBlock[blockNumber].length >= oracleQuorum;
  }

  function submitPoolReport(
    bytes32 reportHash,
    address[] calldata pools,
    uint256[] calldata sharesAmounts
  ) external onlyOracle onlyAfterBlockConsensus whenNotPaused {
require(reports[reportHash].blockNumber != 0, "Report not submitted yet");
    require(pools.length == sharesAmounts.length, 'Mismatch in array lengths');
    
    bytes32 poolReportHash = keccak256(abi.encode(reportHash, pools, sharesAmounts));

    for (uint256 i = 0; i < sharesAmounts.length; i++) {
        reports[reportHash].poolSharesSubmitted += sharesAmounts[i];
    }

    poolReports[poolReportHash] = PoolReport(pools, sharesAmounts, reportHash);
    poolReportsByReportHash[reportHash].push(poolReportHash);
  }

 function executePoolConsensus(uint256 blockNumber, uint256 pageNumber) external onlyOwner {
    bytes32[] storage poolBlockReports = poolReportsByBlock[blockNumber];
    uint256 maxVotes = 0;
    bytes32 consensusReportHash;

    // Similar loop to find consensus report hash

    // If we got more votes than the oracleQuorum,
    // we consider it a valid report and update the state
   if (maxVotes >= oracleQuorum) {
        // Check if consensus was already executed for this pool report
        require(!consensusPoolReport.consensusExecuted, "Consensus already executed for this pool report");
        
        consensusPoolReport.consensusExecuted = true;
        PoolReport memory consensusPoolReport = poolReports[consensusReportHash];

        uint256 pageSize = 100; // Define your preferred page size here
        uint256 startIndex = pageNumber * pageSize;
        require(startIndex < consensusPoolReport.pools.length, "Page number out of range");

        uint256 endIndex = startIndex + pageSize > consensusPoolReport.pools.length 
            ? consensusPoolReport.pools.length 
            : startIndex + pageSize;

        uint256 totalShares = 0;
        for (uint256 i = startIndex; i < endIndex; i++) {
            totalShares += consensusPoolReport.sharesAmounts[i];
            // Process the pool shares here based on consensusPoolReport.sharesAmounts[i]
        }

        // Get the report of the block
        bytes32 generalReportHash = // Need to find the general report hash for the block
        Report memory generalReport = reports[generalReportHash];

        require(totalShares <= generalReport.poolShares, "Mismatch in poolShares total");

        if (endIndex == consensusPoolReport.pools.length) {
            // We've processed the last page
            emit PoolConsensusApproved(blockNumber, consensusReportHash);
        }
    } else {
        emit PoolConsensusFail(blockNumber, consensusReportHash);
    }
}


}
