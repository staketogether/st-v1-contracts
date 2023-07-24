// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1

interface IStakeTogether {
  struct LockedShares {
    uint256 id;
    uint256 amount;
    uint256 unlockTime;
    uint256 lockDays;
  }

  event Bootstrap(address sender, uint256 balance);
  event MintRewardsAccounts(address indexed sender, uint amount);
  event MintRewardsAccountsFallback(address indexed sender, uint amount);
  event SupplyLiquidity(uint256 amount);
  event DepositBase(
    address indexed to,
    address indexed pool,
    uint256 amount,
    uint256 stakeAccountShares,
    uint256 lockAccountShares,
    uint256 poolsShares,
    uint256 operatorsShares,
    uint256 oraclesShares,
    uint256 stakeTogetherShares,
    uint256 liquidityProvidersShares,
    uint256 senderShares
  );

  event DepositWalletLimitReached(address indexed sender, uint256 amount);
  event DepositProtocolLimitReached(address indexed sender, uint256 amount);
  event DepositPool(address indexed account, uint256 amount, address pool, address referral);
  event DepositDonationPool(
    address indexed donor,
    address indexed account,
    uint256 amount,
    address pool,
    address referral
  );
  event WithdrawalLimitReached(address indexed sender, uint256 amount);
  event WithdrawPool(address indexed account, uint256 amount, address pool);
  event WithdrawLiquidity(address indexed account, uint256 amount, address pool);
  event WithdrawValidator(address indexed account, uint256 amount, address pool);
  event SetEnableDeposit(bool enableDeposit);
  event SetEnableWithdrawPool(bool enableWithdrawPool);
  event SetDepositLimit(uint256 newLimit);
  event SetWithdrawalLimit(uint256 newLimit);
  event SetMinDepositPoolAmount(uint256 amount);
  event SetPoolSize(uint256 amount);
  event SetBlocksInterval(uint256 blocksInterval);
  event AddPool(address account);
  event RemovePool(address account);
  event SetMaxPools(uint256 maxPools);
  event SetPermissionLessAddPool(bool permissionLessAddPool);
  event SetWithdrawalCredentials(bytes withdrawalCredentials);
  event CreateValidator(
    address indexed creator,
    uint256 indexed amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );
  event RefundPool(address indexed sender, uint256 amount);

  event SetBeaconBalance(uint256 amount);
  event SetLiquidityBalance(uint256 amount);
  event MintShares(address indexed to, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  event MintPoolShares(address indexed to, address indexed pool, uint256 sharesAmount);
  event BurnPoolShares(address indexed from, address indexed pool, uint256 sharesAmount);
  event TransferPoolShares(
    address indexed from,
    address indexed to,
    address indexed pool,
    uint256 sharesAmount
  );
  event TransferDelegationShares(address indexed from, address indexed to, uint256 sharesAmount);
  event TransferPoolDelegationShares(
    address indexed from,
    address indexed to,
    address indexed pool,
    uint256 sharesAmount
  );
  event MintRewards(address indexed to, address indexed pool, uint256 sharesAmount);
  event MintPenalty(uint256 amount);
  event ClaimRewards(address indexed account, uint256 sharesAmount);

  event LockShares(address indexed user, uint256 id, uint256 amount, uint256 lockDays);
  event UnlockShares(address indexed user, uint256 id, uint256 amount);
  event SetMinLockDays(uint256 minLockDays);
  event SetMaxLockDays(uint256 maxLockDays);
  event SetEnableLock(bool enableLock);
}
