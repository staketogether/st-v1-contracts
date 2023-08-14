import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import { ethers, network, upgrades } from 'hardhat'
import {
  Airdrop,
  Airdrop__factory,
  MockStakeTogether,
  MockStakeTogether__factory,
  Router,
  Router__factory,
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

  await airdropContract.setMaxBatchSize(100)

  return { proxyAddress, implementationAddress, airdropContract }
}

async function deployWithdrawals(owner: HardhatEthersSigner) {
  const WithdrawalsFactory = new Withdrawals__factory().connect(owner)

  const withdrawals = await upgrades.deployProxy(WithdrawalsFactory)
  await withdrawals.waitForDeployment()
  const proxyAddress = await withdrawals.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  const withdrawalsContract = withdrawals as unknown as Withdrawals

  return { proxyAddress, implementationAddress, withdrawalsContract }
}

async function deployRouter(
  owner: HardhatEthersSigner,
  airdropContract: string,
  withdrawalsContract: string,
) {
  const RouterFactory = new Router__factory().connect(owner)

  const router = await upgrades.deployProxy(RouterFactory, [airdropContract, withdrawalsContract])

  await router.waitForDeployment()
  const proxyAddress = await router.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  // Create the configuration
  const config = {
    bunkerMode: false,
    maxValidatorsToExit: 100,
    minBlocksBeforeExecution: 600,
    minReportOracleQuorum: 5,
    reportOracleQuorum: 5,
    oracleBlackListLimit: 3,
    reportBlockFrequency: 1,
  }

  // Cast the contract to the correct type
  const routerContract = router as unknown as Router

  // Set the configuration
  await routerContract.setConfig(config)

  return { proxyAddress, implementationAddress, routerContract }
}

export async function routerFixture() {
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

  const airdrop = await deployAirdrop(owner)
  const withdrawals = await deployWithdrawals(owner)
  const router = await deployRouter(owner, airdrop.proxyAddress, withdrawals.proxyAddress)

  const MockStakeTogether = new MockStakeTogether__factory().connect(owner)
  const mockStakeTogether = await upgrades.deployProxy(MockStakeTogether)
  await mockStakeTogether.waitForDeployment()

  const stakeTogetherProxy = await mockStakeTogether.getAddress()
  const stakeTogetherImplementation = await getImplementationAddress(network.provider, stakeTogetherProxy)

  const stakeTogether = mockStakeTogether as unknown as MockStakeTogether

  const UPGRADER_ROLE = await router.routerContract.UPGRADER_ROLE()
  const ADMIN_ROLE = await router.routerContract.ADMIN_ROLE()

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
    router: router.routerContract,
    routerProxy: router.proxyAddress,
    stakeTogether,
    stakeTogetherProxy,
    UPGRADER_ROLE,
    ADMIN_ROLE,
  }
}
