// SPDX-FileCopyrightText: 2024 Together Technology LTD <legal@staketogether.org>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

interface IBridge {
  function bridgeETHTo(address _to, uint32 _minGasLimit, bytes calldata _extraData) external payable;
}
