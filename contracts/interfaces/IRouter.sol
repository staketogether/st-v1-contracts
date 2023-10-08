// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.org>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title StakeTogether Report Configuration
/// @notice This module includes configuration and reports related to the StakeTogether protocol.
/// @custom:security-contact security@staketogether.org
interface IRouter {
  /// @notice Emitted when a report for a specific block has already been executed.
  error AlreadyExecuted();

  /// @notice Emitted when an oracle has already reported for a specific block.
  error AlreadyReported();

  /// @notice Emitted when the beacon's balance is not enough to cover the loss amount.
  error BeaconBalanceTooLow();

  /// @notice Emitted when the block number has not yet reached the expected value for reporting.
  error BlockNumberNotReached();

  /// @notice Emitted when the report configuration is not yet set.
  error ConfigNotSet();

  /// @notice Emitted when the consensus is not yet delayed.
  error ConsensusNotDelayed();

  /// @notice Emitted when trying to execute too early.
  error EarlyExecution();

  /// @notice Emitted when the epoch should be greater than the last executed epoch.
  error EpochShouldBeGreater();

  /// @notice Emitted when the report's profit amount A is not enough for execution.
  error IncreaseOraclesToUseMargin();

  /// @notice Emitted when ETH balance is not enough for transaction.
  error InsufficientEthBalance();

  /// @notice Emitted when the oracles' margin is too high.
  error MarginTooHigh();

  /// @notice Emitted when there's no active consensus for a report block.
  error NoActiveConsensus();

  /// @notice Emitted when there is no pending execution for consensus.
  error NoPendingExecution();

  /// @notice Emitted when the report block is not yet reached.
  error OracleAlreadyReported();

  /// @notice Emitted when an oracle is not in the report oracles list.
  error OracleNotExists();

  /// @notice Emitted when an oracle is already in the report oracles list.
  error OracleExists();

  /// @notice Emitted when an oracle is blacklisted.
  error OracleBlacklisted();

  /// @notice Emitted when an oracle is not blacklisted.
  error OracleNotBlacklisted();

  /// @notice Emitted when an oracle is active.
  error OnlyActiveOracle();

  /// @notice Emitted when an action is attempted by an address other than the stakeTogether contract.
  error OnlyStakeTogether();

  /// @notice Emitted when there is a pending execution for consensus.
  error PendingExecution();

  /// @notice Emitted when the report delay blocks are too high.
  error ReportDelayBlocksTooHigh();

  /// @notice Emitted when a report for a specific block has already been revoked.
  error ReportRevoked();

  /// Emits when the report block is not greater than the last executed epoch.
  error ReportBlockShouldBeGreater();

  /// @notice Emitted when there are not enough oracles to use the margin.
  error RequiredMoreOracles();

  /// @notice Emitted when the report's loss amount must be zero for execution.
  error LossMustBeZero();

  /// @notice Emitted when the report's profit amount A must be zero for execution.
  error ProfitAmountMustBeZero();

  /// @notice Emitted when the report's profit shares S must be zero for execution.
  error ProfitSharesMustBeZero();

  /// @notice Emitted when the quorum is not yet reached for consensus.
  error QuorumNotReached();

  /// @notice Emitted when a sentinel exists in the oracles list.
  error SentinelExists();

  /// @notice Emitted when a sentinel does not exist in the oracles list.
  error SentinelNotExists();

  /// @notice Emitted when trying to set the stakeTogether address that is already set.
  error StakeTogetherAlreadySet();

  /// @notice Emitted when the stakeTogether's withdraw balance is not enough.
  error WithdrawBalanceTooLow();

  /// @notice Thrown if the address trying to make a claim is the zero address.
  error ZeroAddress();

  /// @dev Config structure used for configuring the reporting mechanism in StakeTogether protocol.
  /// @param bunkerMode A boolean flag to indicate whether the bunker mode is active or not.
  /// @param reportFrequency The frequency in which reports need to be generated.
  /// @param reportDelayBlock The number of blocks to delay before a report is considered.
  /// @param oracleBlackListLimit The maximum number of oracles that can be blacklisted.
  /// @param oracleQuorum The quorum required among oracles for a report to be considered.
  struct Config {
    bool bunkerMode;
    uint256 reportFrequency;
    uint256 reportDelayBlock;
    uint256 reportNoConsensusMargin;
    uint256 oracleBlackListLimit;
    uint256 oracleQuorum;
  }

  /// @dev Report structure used for reporting the state of the protocol at different epochs.
  /// @param epoch The epoch for which this report is generated.
  /// @param merkleRoot The merkle root representing the state of the protocol.
  /// @param profitAmount The amount of profit generated during this epoch.
  /// @param profitShares The shares associated with the profit.
  /// @param lossAmount The loss incurred during this epoch.
  /// @param withdrawAmount The amount withdrawn during this epoch.
  /// @param withdrawRefundAmount The amount refunded during withdrawals in this epoch.
  /// @param routerExtraAmount Extra amount available with the router.
  /// @param validatorsToRemove The list of validators to be removed in this epoch.
  struct Report {
    uint256 epoch;
    bytes32 merkleRoot;
    uint256 profitAmount;
    uint256 profitShares;
    uint256 lossAmount;
    uint256 withdrawAmount;
    uint256 withdrawRefundAmount;
    uint256 routerExtraAmount;
    bytes32[] validatorsToRemove;
    uint256 accumulatedReports;
  }
  /// @notice Emitted when a new oracle is added for reporting.
  /// @param reportOracle The address of the oracle that was added.
  event AddReportOracle(address indexed reportOracle);

  /// @notice Emitted when an oracle is blacklisted.
  /// @param reportOracle The address of the oracle that was blacklisted.
  event BlacklistReportOracle(address indexed reportOracle);

  /// @notice Emitted when a report is approved by consensus.
  /// @param report The report details.
  /// @param hash The hash of the report for reference.
  event ConsensusApprove(uint256 reportBlock, Report report, bytes32 hash);

  /// @notice Emitted when a report is approved by consensus.
  /// @param report The report details.
  /// @param hash The hash of the report for reference.
  event ConsensusFail(uint256 reportBlock, Report report, bytes32 hash);

  /// @notice Emitted when a report is executed.
  /// @param report The report details.
  /// @param hash The hash of the report for reference.
  event ExecuteReport(uint256 reportBlock, Report report, bytes32 hash);

  /// @notice Emitted when the contract receives ether.
  /// @param amount The amount of ether received.
  event ReceiveEther(uint256 amount);

  /// @notice Emitted when Ether is received from Stake Together
  /// @param amount The amount of Ether received
  event ReceiveWithdrawEther(uint256 amount);

  /// @notice Emitted when an oracle is removed from reporting.
  /// @param reportOracle The address of the oracle that was removed.
  event RemoveReportOracle(address indexed reportOracle);

  /// @notice Emitted when a consensus report is revoked.
  /// @param reportBlock The block number at which the consensus was revoked.
  event RevokeConsensusReport(uint256 reportBlock);

  /// @notice Emitted when the protocol configuration is updated.
  /// @param config The updated configuration.
  event SetConfig(Config config);

  /// @notice Emitted when the last consensus block is set.
  /// @param epoch The block number set as the last consensus epoch.
  event SetLastExecutedEpoch(uint256 epoch);

  /// @notice Emitted when the StakeTogether address is set.
  /// @param stakeTogether The address of the StakeTogether contract.
  event SetStakeTogether(address stakeTogether);

  /// @notice Emitted when the next report frequency is skipped.
  /// @param reportBlock The epoch for which the report frequency was skipped.
  /// @param reportNextBlock The block number at which the report frequency was skipped.
  event AdvanceNextBlock(uint256 indexed reportBlock, uint256 indexed reportNextBlock);

  /// @notice Emitted when a report is submitted.
  /// @param report The details of the submitted report.
  /// @param hash The hash of the submitted report.
  event SubmitReport(Report report, bytes32 hash);

  /// @notice Emitted when an oracle is unblacklisted.
  /// @param reportOracle The address of the oracle that was unblacklisted.
  event UnBlacklistReportOracle(address indexed reportOracle);

  /// @notice Emitted when validators are set to be removed.
  /// @param reportBlock The epoch at which validators are set to be removed.
  /// @param validatorsHash The list of hashes representing validators to be removed.
  event ValidatorsToRemove(uint256 indexed reportBlock, bytes32[] validatorsHash);

  /// @notice Initializes the contract after deployment.
  /// @dev Initializes various base contract functionalities and sets the initial state.
  /// @param _airdrop The address of the Airdrop contract.
  /// @param _withdrawals The address of the Withdrawals contract.
  function initialize(address _airdrop, address _withdrawals) external;

  /// @notice Pauses the contract functionalities.
  /// @dev Only the ADMIN_ROLE can pause the contract.
  function pause() external;

  /// @notice Resumes the contract functionalities after being paused.
  /// @dev Only the ADMIN_ROLE can unpause the contract.
  function unpause() external;

  /// @notice Receive ether to the contract.
  /// @dev An event is emitted with the amount of ether received.
  receive() external payable;

  /// @notice Allows the Stake Together to send ETH to the contract.
  /// @dev This function can only be called by the Stake Together.
  function receiveWithdrawEther() external payable;

  /// @notice Sets the address for the StakeTogether contract.
  /// @dev Only the ADMIN_ROLE can set the address, and the provided address must not be zero.
  /// @param _stakeTogether The address of the StakeTogether contract.
  function setStakeTogether(address _stakeTogether) external;

  /// @notice Sets the configuration parameters for the contract.
  /// @dev Only the ADMIN_ROLE can set the configuration, and it ensures a minimum report delay block.
  /// @param _config A struct containing various configuration parameters.
  function setConfig(Config memory _config) external;

  /// @notice Checks if an address is an active report oracle.
  /// @param _account Address of the oracle to be checked.
  function isReportOracle(address _account) external returns (bool);

  /// @notice Checks if a report oracle is blacklisted.
  /// @param _account Address of the oracle to be checked.
  function isReportOracleBlackListed(address _account) external view returns (bool);

  /// @notice Adds a new report oracle.
  /// @dev Only an account with the ORACLE_REPORT_MANAGER_ROLE can call this function.
  /// @param _account Address of the oracle to be added.
  function addReportOracle(address _account) external;

  /// @notice Removes an existing report oracle.
  /// @dev Only an account with the ORACLE_REPORT_MANAGER_ROLE can call this function.
  /// @param _account Address of the oracle to be removed.
  function removeReportOracle(address _account) external;

  /// @notice Blacklists a report oracle.
  /// @dev Only an account with the ORACLE_SENTINEL_ROLE can call this function.
  /// @param _account Address of the oracle to be blacklisted.
  function blacklistReportOracle(address _account) external;

  /// @notice Removes a report oracle from the blacklist.
  /// @dev Only an account with the ORACLE_SENTINEL_ROLE can call this function.
  /// @param _account Address of the oracle to be removed from the blacklist.
  function unBlacklistReportOracle(address _account) external;

  /// @notice Adds a new sentinel account.
  /// @dev Only an account with the ADMIN_ROLE can call this function.
  /// @param _account Address of the account to be added as sentinel.
  function addSentinel(address _account) external;

  /// @notice Removes an existing sentinel account.
  /// @dev Only an account with the ADMIN_ROLE can call this function.
  /// @param _account Address of the sentinel account to be removed.
  function removeSentinel(address _account) external;

  /// @notice Submit a report for the current reporting block.
  /// @dev Handles report submissions, checking for consensus or thresholds and preps next block if needed.
  /// It uses a combination of total votes for report to determine consensus.
  /// @param _report Data structure of the report.
  function submitReport(Report calldata _report) external;

  /// @notice Allows an active report oracle to execute an approved report.
  /// @dev Executes the actions based on the consensus-approved report.
  /// @param _report The data structure containing report details.
  function executeReport(Report calldata _report) external;

  /// @notice Forces to advance to nextReportBlock.
  function forceNextReportBlock() external;

  /// @notice Computes and returns the hash of a given report.
  /// @param _report The data structure containing report details.
  function getReportHash(Report calldata _report) external pure returns (bytes32);

  // @notice Revokes a consensus-approved report for a given epoch.
  /// @dev Only accounts with the ORACLE_SENTINEL_ROLE can call this function.
  /// @param _reportBlock The epoch for which the report was approved.
  function revokeConsensusReport(uint256 _reportBlock) external;

  /// @notice Set the last epoch for which a consensus was reached.
  /// @dev Only accounts with the ADMIN_ROLE can call this function.
  /// @param _epoch The last epoch for which consensus was reached.
  function setLastExecutedEpoch(uint256 _epoch) external;

  /// @notice Validates if conditions to submit a report for an epoch are met.
  /// @dev Verifies conditions such as block number, consensus epoch, executed reports, and oracle votes.
  /// @param _report The data structure containing report details.
  function isReadyToSubmit(Report calldata _report) external view returns (bytes32);

  /// @notice Validates if conditions to execute a report are met.
  /// @dev Verifies conditions like revoked reports, executed reports, consensus reports, and beacon balance.
  /// @param _report The data structure containing report details.
  function isReadyToExecute(Report calldata _report) external view returns (bytes32);
}
