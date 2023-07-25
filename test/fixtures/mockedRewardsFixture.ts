import { AbiCoder, ethers } from 'ethers'
import { defaultFixture } from './defaultFixture'
import { multiDiv } from '../utils/multiDiv'
import { stObtainPools } from '../utils/stObtainPools'
import { StandardMerkleTree } from '@openzeppelin/merkle-tree'

export async function mockedRewardsFixture() {
  const {
    provider,
    owner,
    user1,
    user2,
    user3,
    user4,
    user5,
    user6,
    user7,
    user8,
    user9,
    nullAddress,
    initialDeposit,
    Router,
    Airdrop,
    Withdrawals,
    Liquidity,
    Validators,
    Fees,
    StakeTogether
  } = await defaultFixture()

  // Mocking the rewards percentage with real values

  // Mocking the rewards balance and obtaining necessary info for the calculation
  const lastConsensusEpoch = await Router.lastConsensusEpoch()
  const blockFrequency = await Router.reportBlockFrequency()
  const totalPooledEth = await StakeTogether.totalPooledEther()
  const totalShares = await StakeTogether.totalShares()

  const mockedRewardsBalance = ethers.parseEther('0.003')

  const pooledEthWithRewards = totalPooledEth + mockedRewardsBalance
  const pooledEthShares = await StakeTogether.sharesByPooledEth(totalPooledEth)
  const pooledEthWithRewardsShares = await StakeTogether.sharesByPooledEth(pooledEthWithRewards)
  const rewardsBalanceShares = pooledEthWithRewardsShares - pooledEthShares

  const STAKE_REWARDS_FEE = 3n
  const POOL_ROLE = 2
  const { shares } = await Fees.estimateFeePercentage(STAKE_REWARDS_FEE, rewardsBalanceShares)

  const feeRolesAddresses = await Fees.getFeeRolesAddresses()

  const STAKE_ACCOUNTS_ROLE = 0
  const LOCK_ACCOUNTS_ROLE = 1
  const POOLS_ROLE = 2
  const OPERATORS_ROLE = 3
  const ORACLES_ROLE = 4
  const STAKE_TOGETHER_ROLE = 5
  const LIQUIDITY_PROVIDERS_ROLE = 6
  const SENDER_ROLE = 7

  // TODO: Obtain pools addresses
  const stakedAddresses = [user1.address, user2.address]
  const lockedAddresses = [user3.address]
  const poolsAddresses: string[] = await stObtainPools(StakeTogether, provider)
  const operatorsAddresses = [user4.address]
  const oraclesAddresses = [user5.address]
  const stakeTogetherAddresses = [owner.address]
  const liquidityProvidersAddresses = [user6.address]

  const rewardsPerFeeRoleRootsPromises = feeRolesAddresses.map(async (feeRoleAddress, feeRoleIndex) => {
    const feeRoleShares = await StakeTogether.sharesOf(feeRoleAddress)

    switch (feeRoleIndex) {
      case STAKE_ACCOUNTS_ROLE:
        // Stake accounts percentage is the fee role shares divided by the staked accounts
        const stakedAccountsPercentage = multiDiv(feeRoleShares, BigInt(stakedAddresses.length))
        const stakeAccountsMerkleData = await Promise.all(
          stakedAddresses.map(async address => {
            // Account rewards is the account percentage of the fee role shares
            const accountRewards = multiDiv(feeRoleShares, stakedAccountsPercentage)

            return [address, accountRewards]
          })
        )

        const stakedAccountsMerkleTree = StandardMerkleTree.of(stakeAccountsMerkleData, [
          'address',
          'uint256'
        ])
        return stakedAccountsMerkleTree.root
      case LOCK_ACCOUNTS_ROLE:
        // Locked accounts percentage is the fee role shares divided by the locked accounts
        const lockedAccountsPercentage = multiDiv(feeRoleShares, BigInt(lockedAddresses.length))
        const lockedAccountsMerkleData = await Promise.all(
          lockedAddresses.map(async address => {
            // Account rewards is the account percentage of the fee role shares
            const accountRewards = multiDiv(feeRoleShares, lockedAccountsPercentage)

            return [address, accountRewards]
          })
        )
        const lockedAccountsMerkleTree = StandardMerkleTree.of(lockedAccountsMerkleData, [
          'address',
          'uint256'
        ])
        return lockedAccountsMerkleTree.root
      case POOLS_ROLE:
        const poolAccountsMerkleData = await Promise.all(
          poolsAddresses.map(async address => {
            // Account shares
            const accountShares = await StakeTogether.sharesOf(address)
            // Account percentage of the total shares
            const accountPercentage = multiDiv(accountShares, totalShares)
            // Account rewards is the account percentage of the fee role shares
            const accountRewards = multiDiv(feeRoleShares, accountPercentage)

            return [address, accountRewards]
          })
        )
        const poolAccountsMerkleTree = StandardMerkleTree.of(poolAccountsMerkleData, [
          'address',
          'uint256'
        ])

        return poolAccountsMerkleTree.root
      case OPERATORS_ROLE:
        // Operators percentage is the fee role shares divided by the operators
        const operatorsPercentage = multiDiv(feeRoleShares, BigInt(operatorsAddresses.length))
        const operatorAccountsMerkleData = await Promise.all(
          operatorsAddresses.map(async address => {
            // Account rewards is the account percentage of the fee role shares
            const accountRewards = multiDiv(feeRoleShares, operatorsPercentage)

            return [address, accountRewards]
          })
        )
        const operatorAccountsMerkleTree = StandardMerkleTree.of(operatorAccountsMerkleData, [
          'address',
          'uint256'
        ])

        return operatorAccountsMerkleTree.root
      case ORACLES_ROLE:
        // Oracles percentage is the fee role shares divided by the oracles
        const oraclesPercentage = multiDiv(feeRoleShares, BigInt(oraclesAddresses.length))
        const oracleAccountsMerkleData = await Promise.all(
          oraclesAddresses.map(async address => {
            // Account rewards is the account percentage of the fee role shares
            const accountRewards = multiDiv(feeRoleShares, oraclesPercentage)

            return [address, accountRewards]
          })
        )
        const oracleAccountsMerkleTree = StandardMerkleTree.of(oracleAccountsMerkleData, [
          'address',
          'uint256'
        ])

        return oracleAccountsMerkleTree.root
      case STAKE_TOGETHER_ROLE:
        // Stake Together percentage is the fee role shares divided by the Stake Together
        const stakeTogetherPercentage = multiDiv(feeRoleShares, BigInt(stakeTogetherAddresses.length))
        const stakeTogetherAccountsMerkleData = await Promise.all(
          stakeTogetherAddresses.map(async address => {
            // Account rewards is the account percentage of the fee role shares
            const accountRewards = multiDiv(feeRoleShares, stakeTogetherPercentage)

            return [address, accountRewards]
          })
        )
        const stakeTogetherAccountsMerkleTree = StandardMerkleTree.of(stakeTogetherAccountsMerkleData, [
          'address',
          'uint256'
        ])

        return stakeTogetherAccountsMerkleTree.root
      case LIQUIDITY_PROVIDERS_ROLE:
        // Liquidity providers percentage is the fee role shares divided by the liquidity providers
        const liquidityProvidersPercentage = multiDiv(
          feeRoleShares,
          BigInt(liquidityProvidersAddresses.length)
        )
        const liquidityProviderAccountsMerkleData = await Promise.all(
          liquidityProvidersAddresses.map(async address => {
            // Account rewards is the account percentage of the fee role shares
            const accountRewards = multiDiv(feeRoleShares, liquidityProvidersPercentage)

            return [address, accountRewards]
          })
        )
        const liquidityProviderAccountsMerkleTree = StandardMerkleTree.of(
          liquidityProviderAccountsMerkleData,
          ['address', 'uint256']
        )

        return liquidityProviderAccountsMerkleTree.root
      default:
        // Sender does not have rewards
        return []
    }
  })
  const rewardsPerFeeRoleRoots = await Promise.all(rewardsPerFeeRoleRootsPromises)

  const reportAbi = [
    'uint256', // blockNumber
    'uint256', // epoch
    'uint256', // profitAmount
    'uint256', // lossAmount
    'bytes32[7]', // merkleRoots
    '(address,bytes[])[]', // validatorsToExit
    'bytes[]', // exitedValidators
    'uint256', // withdrawAmount
    'uint256', // restWithdrawAmount
    'uint256' // routerExtraAmount
  ]

  const encoder = new AbiCoder()
  const mockedReport: any = [
    await provider.getBlockNumber(), // blockNumber
    lastConsensusEpoch, // epoch
    rewardsBalanceShares, // profitAmount
    0, // lossAmount
    rewardsPerFeeRoleRoots, // merkleRoots: ['0x00', '0x00', '0x00', '0x00', '0x00', '0x00', '0x00']
    [], // validatorsToExit: [['0x123...', ['0xabc...', '0xdef...']]]
    [], // exitedValidators: ['0x123...', '0x456...']
    0, // withdrawAmount
    0, // restWithdrawAmount
    0 // routerExtraAmount
  ]
  const mockedReportHash = encoder.encode(reportAbi, mockedReport)

  const auditedReport = await Router.auditReport(mockedReport, mockedReportHash)

  if (!auditedReport) {
    throw new Error('Audit report failed')
  }

  return {
    provider,
    owner,
    user1,
    user2,
    user3,
    user4,
    nullAddress,
    initialDeposit,
    Router,
    Airdrop,
    Withdrawals,
    Liquidity,
    Validators,
    Fees,
    StakeTogether
  }
}
