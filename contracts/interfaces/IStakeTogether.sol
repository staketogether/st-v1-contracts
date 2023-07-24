// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1

interface IStakeTogether {
  struct Config {
    bool enableDeposit;
    bool enableLock;
    bool enableWithdrawPool;
    uint256 poolSize;
    uint256 minDepositAmount;
    uint256 minLockDays;
    uint256 maxLockDays;
    uint256 depositLimit;
    uint256 withdrawalLimit;
    uint256 blocksPerDay;
    uint256 maxPools;
    bool permissionLessAddPool;
  }

  struct LockedShares {
    uint256 id;
    uint256 amount;
    uint256 unlockTime;
    uint256 lockDays;
  }

  event AddPool(address account);
  event BurnPoolShares(address indexed from, address indexed pool, uint256 sharesAmount);
  event BurnShares(address indexed account, uint256 sharesAmount);
  event ClaimRewards(address indexed account, uint256 sharesAmount);
  event CreateValidator(
    address indexed creator,
    uint256 indexed amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );
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
  event DepositDonationPool(
    address indexed donor,
    address indexed account,
    uint256 amount,
    address pool,
    address referral
  );
  event DepositPool(address indexed account, uint256 amount, address pool, address referral);
  event DepositProtocolLimitReached(address indexed sender, uint256 amount);
  event DepositWalletLimitReached(address indexed sender, uint256 amount);
  event LockShares(address indexed user, uint256 id, uint256 amount, uint256 lockDays);
  event MintPenalty(uint256 amount);
  event MintPoolShares(address indexed to, address indexed pool, uint256 sharesAmount);
  event MintRewards(address indexed to, address indexed pool, uint256 sharesAmount);
  event MintRewardsAccounts(address indexed sender, uint amount);
  event MintRewardsAccountsFallback(address indexed sender, uint amount);
  event MintShares(address indexed to, uint256 sharesAmount);
  event RefundPool(address indexed sender, uint256 amount);
  event RemovePool(address account);
  event SetBeaconBalance(uint256 amount);
  event SetConfig(Config config);
  event SetLiquidityBalance(uint256 amount);
  event SupplyLiquidity(uint256 amount);
  event TransferDelegationShares(address indexed from, address indexed to, uint256 sharesAmount);
  event TransferPoolDelegationShares(
    address indexed from,
    address indexed to,
    address indexed pool,
    uint256 sharesAmount
  );
  event TransferPoolShares(
    address indexed from,
    address indexed to,
    address indexed pool,
    uint256 sharesAmount
  );
  event TransferShares(address indexed from, address indexed to, uint256 sharesAmount);
  event UnlockShares(address indexed user, uint256 id, uint256 amount);
  event WithdrawLiquidity(address indexed account, uint256 amount, address pool);
  event WithdrawPool(address indexed account, uint256 amount, address pool);
  event WithdrawalLimitReached(address indexed sender, uint256 amount);
  event WithdrawValidator(address indexed account, uint256 amount, address pool);
}
