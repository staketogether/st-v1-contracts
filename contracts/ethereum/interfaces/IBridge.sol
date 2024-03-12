// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IBridge {
  function bridgeETHTo(address _to, uint32 _minGasLimit, bytes calldata _extraData) public payable;
}
