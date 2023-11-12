import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import { ethers, network, upgrades } from 'hardhat'
import {
  Airdrop,
  Airdrop__factory,
  MockDepositContract__factory,
  MockFlashLoan,
  MockFlashLoan__factory,
  MockRouter__factory,
  Router,
  StakeTogether,
  StakeTogether__factory,
  Withdrawals,
  Withdrawals__factory,
} from '../../typechain'

import { checkVariables } from '../utils/env'

async function deployAirdrop(owner: HardhatEthersSigner) {
  const AirdropFactory = new Airdrop__factory().connect(owner)
  const airdrop = await upgrades.deployProxy(AirdropFactory)
  await airdrop.waitForDeployment()
  const proxyAddress = await airdrop.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  const airdropContract = airdrop as unknown as Airdrop

  const AIR_ADMIN_ROLE = await airdropContract.ADMIN_ROLE()
  const AIR_UPGRADER_ROLE = await airdropContract.UPGRADER_ROLE()

  await airdropContract.connect(owner).grantRole(AIR_ADMIN_ROLE, owner)
  await airdropContract.connect(owner).grantRole(AIR_UPGRADER_ROLE, owner)

  return { proxyAddress, implementationAddress, airdropContract }
}

async function deployWithdrawals(owner: HardhatEthersSigner) {
  const WithdrawalsFactory = new Withdrawals__factory().connect(owner)

  const withdrawals = await upgrades.deployProxy(WithdrawalsFactory)
  await withdrawals.waitForDeployment()
  const proxyAddress = await withdrawals.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  const withdrawalsContract = withdrawals as unknown as Withdrawals

  const WITHDRAW_ADMIN_ROLE = await withdrawalsContract.ADMIN_ROLE()
  const WITHDRAW_UPGRADER_ROLE = await withdrawalsContract.UPGRADER_ROLE()

  await withdrawalsContract.connect(owner).grantRole(WITHDRAW_ADMIN_ROLE, owner)
  await withdrawalsContract.connect(owner).grantRole(WITHDRAW_UPGRADER_ROLE, owner)

  return { proxyAddress, implementationAddress, withdrawalsContract }
}

async function deployRouter(
  owner: HardhatEthersSigner,
  airdropContract: string,
  withdrawalsContract: string,
) {
  const RouterFactory = new MockRouter__factory().connect(owner)

  const router = await upgrades.deployProxy(RouterFactory, [airdropContract, withdrawalsContract])

  await router.waitForDeployment()
  const proxyAddress = await router.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  const config = {
    bunkerMode: false,
    maxValidatorsToExit: 100,
    reportDelayBlock: 60,

    reportNoConsensusMargin: 0,
    oracleQuorum: 5,
    oracleBlackListLimit: 3,
    reportFrequency: 1000,
  }

  const routerContract = router as unknown as Router

  const ROUTER_ADMIN_ROLE = await routerContract.ADMIN_ROLE()
  const ROUTER_UPGRADER_ROLE = await routerContract.UPGRADER_ROLE()
  const ROUTER_ORACLE_REPORT_MANAGER_ROLE = await routerContract.ORACLE_REPORT_MANAGER_ROLE()

  await routerContract.connect(owner).grantRole(ROUTER_ADMIN_ROLE, owner)
  await routerContract.connect(owner).grantRole(ROUTER_UPGRADER_ROLE, owner)
  await routerContract.connect(owner).grantRole(ROUTER_ORACLE_REPORT_MANAGER_ROLE, owner)

  await routerContract.setConfig(config)

  return { proxyAddress, implementationAddress, routerContract }
}

async function deployStakeTogether(
  owner: HardhatEthersSigner,
  airdropContract: string,
  routerContract: string,
  withdrawalsContract: string,
) {
  const MockDepositContractFactory = new MockDepositContract__factory().connect(owner)
  const mockDepositContract = await MockDepositContractFactory.deploy()
  const depositAddress = await mockDepositContract.getAddress()

  function convertToWithdrawalAddress(eth1Address: string): string {
    if (!ethers.isAddress(eth1Address)) {
      throw new Error('Invalid ETH1 address format.')
    }

    const address = eth1Address.startsWith('0x') ? eth1Address.slice(2) : eth1Address
    const paddedAddress = address.padStart(62, '0')
    const withdrawalAddress = '0x01' + paddedAddress
    return withdrawalAddress
  }

  const withdrawalsCredentials = convertToWithdrawalAddress(routerContract)

  if (withdrawalsCredentials.length !== 66) {
    throw new Error('Withdrawals credentials are not the correct length')
  }

  const StakeTogetherFactory = new StakeTogether__factory().connect(owner)

  const withdrawalsCredentialsAddress = convertToWithdrawalAddress(routerContract)

  const stakeTogether = await upgrades.deployProxy(StakeTogetherFactory, [
    airdropContract,
    depositAddress,
    routerContract,
    withdrawalsContract,
    withdrawalsCredentialsAddress,
  ])

  await stakeTogether.waitForDeployment()
  const proxyAddress = await stakeTogether.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  const stakeTogetherContract = stakeTogether as unknown as StakeTogether

  const ST_ADMIN_ROLE = await stakeTogetherContract.ADMIN_ROLE()
  const ST_UPGRADER_ROLE = await stakeTogetherContract.UPGRADER_ROLE()
  const ST_POOL_MANAGER_ROLE = await stakeTogetherContract.POOL_MANAGER_ROLE()

  await stakeTogetherContract.connect(owner).grantRole(ST_ADMIN_ROLE, owner)
  await stakeTogetherContract.connect(owner).grantRole(ST_UPGRADER_ROLE, owner)
  await stakeTogetherContract.connect(owner).grantRole(ST_POOL_MANAGER_ROLE, owner)

  const stakeEntry = ethers.parseEther('0.003')
  const stakeRewardsFee = ethers.parseEther('0.09')
  const stakePoolFee = ethers.parseEther('1')
  const stakeValidatorFee = ethers.parseEther('0.01')

  const poolSize = ethers.parseEther('32')

  const config = {
    blocksPerDay: 7200n,
    validatorSize: ethers.parseEther('32'),
    poolSize: poolSize + stakeValidatorFee,
    minDepositAmount: ethers.parseEther('0.001'),
    minWithdrawAmount: ethers.parseEther('0.00001'),
    depositLimit: ethers.parseEther('1000'),
    withdrawalPoolLimit: ethers.parseEther('1000'),
    withdrawalValidatorLimit: ethers.parseEther('1000'),
    maxDelegations: 64n,
    withdrawDelay: 10n,
    withdrawBeaconDelay: 10n,
    feature: {
      AddPool: true,
      Deposit: true,
      WithdrawPool: true,
      WithdrawBeacon: true,
    },
  }

  await stakeTogetherContract.setConfig(config)

  // Set the StakeEntry fee to 0.003 ether and make it a percentage-based fee
  await stakeTogetherContract.setFee(0n, stakeEntry, [
    ethers.parseEther('0.6'),
    0n,
    ethers.parseEther('0.4'),
    0n,
  ])

  // Set the ProcessStakeRewards fee to 0.09 ether and make it a percentage-based fee
  await stakeTogetherContract.setFee(1n, stakeRewardsFee, [
    ethers.parseEther('0.33'),
    ethers.parseEther('0.33'),
    ethers.parseEther('0.34'),
    0n,
  ])

  // Set the StakePool fee to 1 ether and make it a fixed fee
  await stakeTogetherContract.setFee(2n, stakePoolFee, [
    ethers.parseEther('0.4'),
    0n,
    ethers.parseEther('0.6'),
    0n,
  ])

  // Set the ProcessStakeValidator fee to 0.01 ether and make it a fixed fee
  await stakeTogetherContract.setFee(3n, stakeValidatorFee, [0n, 0n, ethers.parseEther('1'), 0n])

  await owner.sendTransaction({ to: proxyAddress, value: ethers.parseEther('1') })

  return { proxyAddress, implementationAddress, stakeTogetherContract }
}

async function deployMockFlashLoan(
  owner: HardhatEthersSigner,
  stakeTogether: string,
  stakeTogetherProxy: string,
  withdrawals: string,
) {
  const MockFlashLoanFactory = new MockFlashLoan__factory().connect(owner)
  const mockFlashLoan = await upgrades.deployProxy(MockFlashLoanFactory, [
    stakeTogether,
    stakeTogetherProxy,
    withdrawals,
  ])
  await mockFlashLoan.waitForDeployment()

  const mockFlashLoanContract = mockFlashLoan as unknown as MockFlashLoan

  return { mockFlashLoanContract }
}

export async function configContracts(
  owner: HardhatEthersSigner,
  airdrop: {
    proxyAddress: string
    implementationAddress: string
    airdropContract: Airdrop
  },
  stakeTogether: {
    proxyAddress: string
    implementationAddress: string
    stakeTogetherContract: StakeTogether
  },
  withdrawals: {
    proxyAddress: string
    implementationAddress: string
    withdrawalsContract: Withdrawals
  },
  router: {
    proxyAddress: string
    implementationAddress: string
    routerContract: Router
  },
) {
  await stakeTogether.stakeTogetherContract.setFeeAddress(0, airdrop.proxyAddress)
  await stakeTogether.stakeTogetherContract.setFeeAddress(1, owner)
  await stakeTogether.stakeTogetherContract.setFeeAddress(2, owner)
  await stakeTogether.stakeTogetherContract.setFeeAddress(3, owner)

  await airdrop.airdropContract.setStakeTogether(stakeTogether.proxyAddress)
  await airdrop.airdropContract.setRouter(router.proxyAddress)

  await withdrawals.withdrawalsContract.setStakeTogether(stakeTogether.proxyAddress)
  await withdrawals.withdrawalsContract.setRouter(router.proxyAddress)

  await router.routerContract.setStakeTogether(stakeTogether.proxyAddress)
}

export async function stakeTogetherFixture() {
  checkVariables()

  const provider = ethers.provider

  let owner: HardhatEthersSigner
  let user1: HardhatEthersSigner
  let user2: HardhatEthersSigner
  let user3: HardhatEthersSigner
  let user4: HardhatEthersSigner
  let user5: HardhatEthersSigner
  let user6: HardhatEthersSigner
  let user7: HardhatEthersSigner
  let user8: HardhatEthersSigner

  let nullAddress: string = '0x0000000000000000000000000000000000000000'

  ;[owner, user1, user2, user3, user4, user5, user6, user7, user8] = await ethers.getSigners()

  // DEPLOY
  const airdrop = await deployAirdrop(owner)
  const withdrawals = await deployWithdrawals(owner)
  const router = await deployRouter(owner, airdrop.proxyAddress, withdrawals.proxyAddress)
  const stakeTogether = await deployStakeTogether(
    owner,
    airdrop.proxyAddress,
    router.proxyAddress,
    withdrawals.proxyAddress,
  )
  const { mockFlashLoanContract } = await deployMockFlashLoan(
    owner,
    stakeTogether.proxyAddress,
    stakeTogether.proxyAddress,
    stakeTogether.proxyAddress,
  )

  await configContracts(owner, airdrop, stakeTogether, withdrawals, router)

  const ADMIN_ROLE = await stakeTogether.stakeTogetherContract.ADMIN_ROLE()
  const UPGRADER_ROLE = await stakeTogether.stakeTogetherContract.UPGRADER_ROLE()
  const POOL_MANAGER_ROLE = await stakeTogether.stakeTogetherContract.POOL_MANAGER_ROLE()
  const VALIDATOR_ORACLE_ROLE = await stakeTogether.stakeTogetherContract.VALIDATOR_ORACLE_ROLE()
  const VALIDATOR_ORACLE_MANAGER_ROLE =
    await stakeTogether.stakeTogetherContract.VALIDATOR_ORACLE_MANAGER_ROLE()
  const VALIDATOR_ORACLE_SENTINEL_ROLE =
    await stakeTogether.stakeTogetherContract.VALIDATOR_ORACLE_SENTINEL_ROLE()
  const VALIDATOR_MANAGER_ROLE = await stakeTogether.stakeTogetherContract.VALIDATOR_MANAGER_ROLE()

  return {
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
    nullAddress,
    stakeTogether: stakeTogether.stakeTogetherContract,
    stakeTogetherProxy: stakeTogether.proxyAddress,
    mockRouter: router.routerContract,
    mockRouterProxy: router.proxyAddress,
    withdrawals: withdrawals.withdrawalsContract,
    withdrawalsProxy: withdrawals.proxyAddress,
    mockFlashLoan: mockFlashLoanContract,
    ADMIN_ROLE,
    UPGRADER_ROLE,
    POOL_MANAGER_ROLE,
    VALIDATOR_ORACLE_ROLE,
    VALIDATOR_ORACLE_MANAGER_ROLE,
    VALIDATOR_ORACLE_SENTINEL_ROLE,
    VALIDATOR_MANAGER_ROLE,
  }
}
