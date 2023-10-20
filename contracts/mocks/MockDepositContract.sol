// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.20;

import '../interfaces/IDepositContract.sol';

contract MockDepositContract is IDepositContract {
  // This can be set to an appropriate value for mocking purposes
  bytes32 public depositRoot = bytes32(0);
  uint64 public depositCount = 0;

  function get_deposit_root() external view override returns (bytes32) {
    return depositRoot;
  }

  function get_deposit_count() external view override returns (bytes memory) {
    return to_little_endian_64(depositCount);
  }

  function deposit(
    bytes calldata pubkey,
    bytes calldata withdrawal_credentials,
    bytes calldata signature,
    bytes32 deposit_data_root
  ) external payable {}

  function to_little_endian_64(uint64 value) internal pure returns (bytes memory ret) {
    ret = new bytes(value);
  }
}
