// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IStakeTogether {
  event ReceiveEther(address indexed sender, uint amount);
  event FallbackEther(address indexed sender, uint amount);

  receive() external payable;

  fallback() external payable;

  function pause() external;

  function unpause() external;

  event Bootstrap(address sender, uint256 balance);

  /************
   ** SHARES **
   ************/

  event MintShares(address indexed to, uint256 sharesAmount);
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);

  function contractBalance() external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function balanceOf(address _account) external view returns (uint256);

  function sharesOf(address _account) external returns (uint256);

  function netSharesOf(address _account) external view returns (uint256);

  function sharesByPooledEth(uint256 _ethAmount) external view returns (uint256);

  function pooledEthByShares(uint256 _sharesAmount) external view returns (uint256);

  function transfer(address _to, uint256 _amount) external returns (bool);

  function transferFrom(address _from, address _to, uint256 _amount) external returns (bool);

  function transferShares(address _to, uint256 _sharesAmount) external returns (uint256);

  function transferSharesFrom(
    address _from,
    address _to,
    uint256 _sharesAmount
  ) external returns (uint256);

  function allowance(address _account, address _spender) external view returns (uint256);

  function approve(address _spender, uint256 _amount) external returns (bool);

  function increaseAllowance(address _spender, uint256 _addedValue) external returns (bool);

  function decreaseAllowance(address _spender, uint256 _subtractedValue) external returns (bool);

  function totalPooledEther() external view returns (uint256);

  /*****************
   ** LOCK SHARES **
   *****************/

  struct Lock {
    uint256 amount;
    uint256 unlockBlock;
    // Todo: unlockAmount
  }

  event SetMaxActiveLocks(uint256 amount);
  event SharesLocked(address indexed account, uint256 amount, uint256 unlockBlock);
  event SharesUnlocked(address indexed account, uint256 amount);

  function setMaxActiveLocks(uint256 _amount) external;

  function lockedSharesOf(address _account) external view returns (uint256);

  function lockShares(uint256 _sharesAmount, uint256 _blocks) external;

  function unlockShares() external;

  function unlockSpecificLock(uint256 _index) external;

  /*****************
   ** POOLS SHARES **
   *****************/

  event MintPoolShares(address indexed to, address indexed pool, uint256 sharesAmount);
  event TransferPoolShares(
    address indexed from,
    address indexed to,
    address indexed pool,
    uint256 sharesAmount
  );
  event TransferDelegationShares(
    address indexed from,
    address indexed to,
    address indexed pool,
    uint256 sharesAmount
  );
  event BurnPoolShares(address indexed from, address indexed pool, uint256 sharesAmount);

  function poolSharesOf(address _account) external view returns (uint256);

  function delegationSharesOf(address _account, address _pool) external view returns (uint256);

  function transferPoolShares(address _fromPool, address _toPool, uint256 _sharesAmount) external;

  /*****************
   ** ADDRESSES **
   *****************/

  event SetPoolsFeeAddress(address indexed to);
  event SetOperatorsFeeAddress(address indexed to);
  event SetStakeTogetherFeeAddress(address indexed to);

  function setPoolsFeeAddress(address _to) external;

  function setOperatorFeeAddress(address _to) external;

  function setStakeTogetherFeeAddress(address _to) external;

  /*****************
   ** FEES **
   *****************/

  event SetStakeTogetherFee(uint256 fee);
  event SetPoolsFee(uint256 fee);
  event SetOperatorsFee(uint256 fee);
  event SetValidatorsFee(uint256 fee);
  event SetAddPoolFee(uint256 fee);
  event SetEntryFee(uint256 fee);

  function setStakeTogetherFee(uint256 _fee) external;

  function setPoolsFee(uint256 _fee) external;

  function setOperatorFee(uint256 _fee) external;

  function setValidatorFee(uint256 _fee) external;

  function setAddPoolFee(uint256 _fee) external;

  function setEntryFee(uint256 _fee) external;

  /*****************
   ** REWARDS **
   *****************/

  struct Reward {
    address recipient;
    uint256 shares;
    uint256 amount;
  }

  enum RewardType {
    StakeTogether,
    Operator,
    Pools
  }

  event MintRewards(uint256 epoch, address indexed to, uint256 sharesAmount, RewardType rewardType);
  event MintPenalty(uint256 epoch, uint256 amount);
  event RefundPool(uint256 epoch, uint256 amount);
  event DepositPool(uint256 amount);
  event ClaimPoolRewards(address indexed account, uint256 sharesAmount);

  function mintRewards(uint256 _epoch, address _rewardAddress, uint256 _sharesAmount) external payable;

  function mintPenalty(uint256 _blockNumber, uint256 _lossAmount) external;

  function refundPool(uint256 _epoch) external payable;

  function depositPool() external payable;

  function claimPoolRewards(address _account, uint256 _sharesAmount) external;

  /*****************
   ** STAKE **
   *****************/

  event DepositPool(address indexed account, uint256 amount, address delegated, address referral);
  event DepositDonationPool(
    address indexed donor,
    address indexed account,
    uint256 amount,
    address pool,
    address referral
  );

  event WithdrawPool(address indexed account, uint256 amount, address pool);
  event WithdrawBorrow(address indexed account, uint256 amount, address pool);
  event WithdrawValidator(address indexed account, uint256 amount, address pool);

  event SetMinDepositPoolAmount(uint256 amount);
  event SetPoolSize(uint256 amount);
  event SetDepositLimit(uint256 newLimit);
  event SetWalletDepositLimit(uint256 newLimit);
  event SetWithdrawalLimit(uint256 newLimit);
  event SetBlocksInterval(uint256 blocksInterval);

  event DepositLimitReached(address indexed sender, uint256 amount);
  event WalletDepositLimitReached(address indexed sender, uint256 amount);
  event WithdrawalLimitReached(address indexed sender, uint256 amount);

  function depositPool(address _pool, address _referral) external payable;

  function depositDonationPool(address _pool, address _referral, address _to) external payable;

  function withdrawPool(uint256 _amount, address _pool) external;

  function withdrawBorrow(uint256 _amount, address _pool) external;

  function withdrawValidator(uint256 _amount, address _pool) external;

  function setDepositLimit(uint256 _newLimit) external;

  function setWithdrawalLimit(uint256 _newLimit) external;

  function setWalletDepositLimit(uint256 _newLimit) external;

  function setBlocksInterval(uint256 _newBlocksInterval) external;

  function setMinDepositPoolAmount(uint256 _amount) external;

  function setPoolSize(uint256 _amount) external;

  function poolBalance() external view returns (uint256);

  /***********************
   ** VALIDATOR ORACLES **
   ***********************/

  event AddValidatorOracle(address indexed account);
  event RemoveValidatorOracle(address indexed account);

  function addValidatorOracle(address _oracleAddress) external;

  function removeValidatorOracle(address _oracleAddress) external;

  function forceNextValidatorOracle() external;

  function currentValidatorOracle() external view returns (address);

  /*****************
   ** VALIDATORS **
   *****************/

  event CreateValidator(
    address indexed creator,
    uint256 indexed amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );
  event RemoveValidator(address indexed account, uint256 epoch, bytes publicKey);
  event SetValidatorSize(uint256 newValidatorSize);
  event SetWithdrawalCredentials(bytes withdrawalCredentials);

  function setWithdrawalCredentials(bytes memory _withdrawalCredentials) external;

  function createValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external;

  function removeValidator(uint256 _epoch, bytes calldata _publicKey) external payable;

  function setValidatorSize(uint256 _newSize) external;

  function isValidator(bytes memory _publicKey) external view returns (bool);
}
