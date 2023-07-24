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
  const totalPooledEth = await StakeTogether.totalPooledEther()
  const totalShares = await StakeTogether.totalShares()
  // TODO: Obtain pools addresses
  const poolsAddresses: string[] = await stObtainPools(StakeTogether, provider)

  const mockedRewardsBalance = ethers.parseEther('0.003')

  const pooledEthWithRewards = totalPooledEth + mockedRewardsBalance
  const pooledEthShares = await StakeTogether.sharesByPooledEth(totalPooledEth)
  const pooledEthWithRewardsShares = await StakeTogether.sharesByPooledEth(pooledEthWithRewards)
  const rewardsBalanceShares = pooledEthWithRewardsShares - pooledEthShares

  const STAKE_REWARDS_FEE = 3n
  const POOL_ROLE = 2
  const { shares } = await Fees.estimateFeePercentage(STAKE_REWARDS_FEE, rewardsBalanceShares)

  const poolRewards = shares[POOL_ROLE]
  const rewardsPerPoolPromises = poolsAddresses.map(async poolAddress => {
    const poolShares = await StakeTogether.sharesOf(poolAddress)
    const poolPercentage = multiDiv(poolShares, totalShares)
    const poolSharesAmount = multiDiv(poolRewards, poolPercentage)

    return [poolAddress, poolSharesAmount]
  })

  const rewardsPerPool = await Promise.all(rewardsPerPoolPromises)
  const rewardsPerPoolMerkleTree = StandardMerkleTree.of(rewardsPerPool, ['address', 'uint256'])

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
    1, // blockNumber
    1, // epoch
    1, // profitAmount
    1, // lossAmount
    [, , rewardsPerPoolMerkleTree.root, , , ,], // merkleRoots: ['0x00', '0x00', '0x00', '0x00', '0x00', '0x00', '0x00']
    [], // validatorsToExit: [['0x123...', ['0xabc...', '0xdef...']]]
    [], // exitedValidators: ['0x123...', '0x456...']
    1, // withdrawAmount
    1, // restWithdrawAmount
    1 // routerExtraAmount
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
