// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @title StakeTogether Report Configuration
/// @notice This module includes configuration and reports related to the StakeTogether protocol.
/// @custom:security-contact security@staketogether.app
interface IRouter {
  /// @dev Config structure used for configuring the reporting mechanism in StakeTogether protocol.
  /// @param bunkerMode A boolean flag to indicate whether the bunker mode is active or not.
  /// @param reportFrequency The frequency in which reports need to be generated.
  /// @param reportDelayBlocks The number of blocks to delay before a report is considered.
  /// @param oracleBlackListLimit The maximum number of oracles that can be blacklisted.
  /// @param oracleQuorum The quorum required among oracles for a report to be considered.
  /// @param minOracleQuorum The minimum required quorum among oracles for a report.
  struct Config {
    bool bunkerMode;
    uint256 reportFrequency;
    uint256 reportDelayBlocks;
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
  event ConsensusApprove(Report report, bytes32 hash);

  /// @notice Emitted when consensus is not reached for a report.
  /// @param report The report details.
  /// @param hash The hash of the report for reference.
  event ConsensusNotReached(Report report, bytes32 hash);

  /// @notice Emitted when a report is executed.
  /// @param report The report details.
  /// @param hash The hash of the report for reference.
  event ExecuteReport(Report report, bytes32 hash);

  /// @notice Emitted when the contract receives ether.
  /// @param amount The amount of ether received.
  event ReceiveEther(uint256 amount);

  /// @notice Emitted when an oracle is removed from reporting.
  /// @param reportOracle The address of the oracle that was removed.
  event RemoveReportOracle(address indexed reportOracle);

  /// @notice Emitted when a consensus report is revoked.
  /// @param blockNumber The block number at which the consensus was revoked.
  /// @param epoch The epoch for which the consensus was revoked.
  /// @param hash The hash of the report for which the consensus was revoked.
  event RevokeConsensusReport(uint256 indexed blockNumber, uint256 indexed epoch, bytes32 hash);

  /// @notice Emitted when the protocol configuration is updated.
  /// @param config The updated configuration.
  event SetConfig(Config config);

  /// @notice Emitted when the last consensus epoch is set.
  /// @param epoch The epoch set as the last consensus epoch.
  event SetLastConsensusEpoch(uint256 epoch);

  /// @notice Emitted when the StakeTogether address is set.
  /// @param stakeTogether The address of the StakeTogether contract.
  event SetStakeTogether(address stakeTogether);

  /// @notice Emitted when the next report frequency is skipped.
  /// @param epoch The epoch for which the report frequency was skipped.
  /// @param blockNumber The block number at which the report frequency was skipped.
  event AdvanceNextBlock(uint256 indexed epoch, uint256 indexed blockNumber);

  /// @notice Emitted when a report is submitted.
  /// @param report The details of the submitted report.
  /// @param hash The hash of the submitted report.
  event SubmitReport(Report report, bytes32 hash);

  /// @notice Emitted when an oracle is unblacklisted.
  /// @param reportOracle The address of the oracle that was unblacklisted.
  event UnBlacklistReportOracle(address indexed reportOracle);

  /// @notice Emitted when validators are set to be removed.
  /// @param epoch The epoch at which validators are set to be removed.
  /// @param validatorsHash The list of hashes representing validators to be removed.
  event ValidatorsToRemove(uint256 indexed epoch, bytes32[] validatorsHash);

  /// @notice Initializes the contract after deployment.
  /// @dev Initializes various base contract functionalities and sets the initial state.
  /// @param _airdrop The address of the Airdrop contract.
  /// @param _withdrawals The address of the Withdrawals contract.
  /// @param _reportFrequency The frequency in which reports need to be generated.
  function initialize(address _airdrop, address _withdrawals, uint256 _reportFrequency) external;

  /// @notice Pauses the contract functionalities.
  /// @dev Only the ADMIN_ROLE can pause the contract.
  function pause() external;

  /// @notice Resumes the contract functionalities after being paused.
  /// @dev Only the ADMIN_ROLE can unpause the contract.
  function unpause() external;

  /// @notice Receive ether to the contract.
  /// @dev An event is emitted with the amount of ether received.
  receive() external payable;

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
  /// @return A boolean indicating if the address is an active report oracle.
  function isReportOracle(address _account) external view returns (bool);

  /// @notice Checks if a report oracle is blacklisted.
  /// @param _account Address of the oracle to be checked.
  /// @return A boolean indicating if the address is a blacklisted report oracle.
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

  /// @notice Allows an active report oracle to submit a new report for a given epoch.
  /// @dev Ensures report submission conditions are met.
  /// @param _epoch The epoch for which the report is submitted.
  /// @param _report The data structure containing report details.
  function submitReport(uint256 _epoch, Report calldata _report) external;

  /// @notice Allows an active report oracle to execute an approved report.
  /// @dev Executes the actions based on the consensus-approved report.
  /// @param _report The data structure containing report details.
  function executeReport(Report calldata _report) external;

  /// @notice Computes and returns the hash of a given report.
  /// @param _report The data structure containing report details.
  /// @return The keccak256 hash of the report.
  function getReportHash(Report calldata _report) external pure returns (bytes32);

  /// @notice Revokes a consensus-approved report for a given epoch.
  /// @dev Only accounts with the ORACLE_SENTINEL_ROLE can call this function.
  /// @param _epoch The epoch for which the report was approved.
  /// @param _hash The hash of the report that needs to be revoked.
  function revokeConsensusReport(uint256 _epoch, bytes32 _hash) external;

  /// @notice Set the last epoch for which a consensus was reached.
  /// @dev Only accounts with the ADMIN_ROLE can call this function.
  /// @param _epoch The last epoch for which consensus was reached.
  function setLastConsensusEpoch(uint256 _epoch) external;

  /// @notice Validates if conditions to submit a report for an epoch are met.
  /// @dev Verifies conditions such as block number, consensus epoch, executed reports, and oracle votes.
  /// @param _epoch The epoch for which the report is to be submitted.
  /// @param _report The data structure containing report details.
  /// @return The keccak256 hash of the report.
  function isReadyToSubmit(uint256 _epoch, Report calldata _report) external view returns (bytes32);

  /// @notice Validates if conditions to execute a report are met.
  /// @dev Verifies conditions like revoked reports, executed reports, consensus reports, and beacon balance.
  /// @param _report The data structure containing report details.
  /// @return The keccak256 hash of the report.
  function isReadyToExecute(Report calldata _report) external view returns (bytes32);
}
