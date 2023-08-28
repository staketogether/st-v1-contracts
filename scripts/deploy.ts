import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import * as dotenv from 'dotenv'
import { ethers, network, upgrades } from 'hardhat'
import { checkVariables } from '../test/utils/env'
import {
  Airdrop,
  Airdrop__factory,
  Router,
  Router__factory,
  StakeTogether,
  StakeTogether__factory,
  Withdrawals,
  Withdrawals__factory,
} from '../typechain'

// TODO!: Remove Extra Roles Initializations on Mainnet Deploy (Only needed for testing on goerli)

dotenv.config()

const depositAddress = String(process.env.GOERLI_DEPOSIT_ADDRESS)

export async function deploy() {
  checkVariables()

  const [owner] = await ethers.getSigners()

  // DEPLOY

  const airdrop = await deployAirdrop(owner)
  const withdrawals = await deployWithdrawals(owner)
  const router = await deployRouter(owner, airdrop.proxyAddress, withdrawals.proxyAddress)

  const stakeTogether = await deployStakeTogether(owner, router.proxyAddress, withdrawals.proxyAddress)

  // CONFIG

  await configContracts(owner, airdrop, stakeTogether, withdrawals, router)

  // LOG

  console.log('\n🔷 All ST V2 Contracts Deployed!\n')

  verifyContracts(
    airdrop.proxyAddress,
    airdrop.implementationAddress,
    router.proxyAddress,
    router.implementationAddress,
    stakeTogether.proxyAddress,
    stakeTogether.implementationAddress,
    withdrawals.proxyAddress,
    withdrawals.implementationAddress,
  )
}

export async function deployAirdrop(owner: HardhatEthersSigner) {
  const AirdropFactory = new Airdrop__factory().connect(owner)
  const airdrop = await upgrades.deployProxy(AirdropFactory)
  await airdrop.waitForDeployment()
  const proxyAddress = await airdrop.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Airdrop\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Airdrop\t\t Implementation\t\t ${implementationAddress}`)

  const airdropContract = airdrop as unknown as Airdrop

  const AIR_ADMIN_ROLE = await airdropContract.ADMIN_ROLE()
  const AIR_UPGRADER_ROLE = await airdropContract.UPGRADER_ROLE()

  await airdropContract.connect(owner).grantRole(AIR_ADMIN_ROLE, owner)
  await airdropContract.connect(owner).grantRole(AIR_UPGRADER_ROLE, owner)

  return { proxyAddress, implementationAddress, airdropContract }
}

export async function deployWithdrawals(owner: HardhatEthersSigner) {
  const WithdrawalsFactory = new Withdrawals__factory().connect(owner)

  const withdrawals = await upgrades.deployProxy(WithdrawalsFactory)
  await withdrawals.waitForDeployment()
  const proxyAddress = await withdrawals.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Withdrawals\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Withdrawals\t Implementation\t\t ${implementationAddress}`)

  const withdrawalsContract = withdrawals as unknown as Withdrawals

  const WITHDRAW_ADMIN_ROLE = await withdrawalsContract.ADMIN_ROLE()
  const WITHDRAW_UPGRADER_ROLE = await withdrawalsContract.UPGRADER_ROLE()

  await withdrawalsContract.connect(owner).grantRole(WITHDRAW_ADMIN_ROLE, owner)
  await withdrawalsContract.connect(owner).grantRole(WITHDRAW_UPGRADER_ROLE, owner)

  return { proxyAddress, implementationAddress, withdrawalsContract }
}

export async function deployRouter(
  owner: HardhatEthersSigner,
  airdropContract: string,
  withdrawalsContract: string,
) {
  const RouterFactory = new Router__factory().connect(owner)

  const reportFrequency = 1_296_000n // 1 once a day
  const router = await upgrades.deployProxy(RouterFactory, [airdropContract, withdrawalsContract])

  await router.waitForDeployment()
  const proxyAddress = await router.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Router\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Router\t\t Implementation\t\t ${implementationAddress}`)

  // Create the configuration
  const config = {
    bunkerMode: false,
    maxValidatorsToExit: 100,
    reportDelayBlock: 600,

    oracleQuorum: 5,
    oracleBlackListLimit: 3,
    reportFrequency: reportFrequency,
  }

  // Cast the contract to the correct type
  const routerContract = router as unknown as Router

  const ROUTER_ADMIN_ROLE = await routerContract.ADMIN_ROLE()
  const ROUTER_UPGRADER_ROLE = await routerContract.UPGRADER_ROLE()
  const ROUTER_ORACLE_REPORT_MANAGER_ROLE = await routerContract.ORACLE_REPORT_MANAGER_ROLE()

  await routerContract.connect(owner).grantRole(ROUTER_ADMIN_ROLE, owner)
  await routerContract.connect(owner).grantRole(ROUTER_UPGRADER_ROLE, owner)
  await routerContract.connect(owner).grantRole(ROUTER_ORACLE_REPORT_MANAGER_ROLE, owner)

  // Set the configuration
  await routerContract.setConfig(config)

  return { proxyAddress, implementationAddress, routerContract }
}

export async function deployStakeTogether(
  owner: HardhatEthersSigner,
  routerContract: string,
  withdrawalsContract: string,
) {
  function convertToWithdrawalAddress(eth1Address: string): string {
    const address = eth1Address.startsWith('0x') ? eth1Address.slice(2) : eth1Address
    const paddedAddress = address.padStart(64, '0')
    const withdrawalAddress = '0x01' + paddedAddress
    return withdrawalAddress
  }

  const StakeTogetherFactory = new StakeTogether__factory().connect(owner)

  const stakeTogether = await upgrades.deployProxy(StakeTogetherFactory, [
    routerContract,
    withdrawalsContract,
    depositAddress,
    convertToWithdrawalAddress(routerContract),
  ])

  await stakeTogether.waitForDeployment()
  const proxyAddress = await stakeTogether.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`StakeTogether\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`StakeTogether\t Implementation\t\t ${implementationAddress}`)

  const stakeTogetherContract = stakeTogether as unknown as StakeTogether

  const ST_ADMIN_ROLE = await stakeTogetherContract.ADMIN_ROLE()
  const ST_UPGRADER_ROLE = await stakeTogetherContract.UPGRADER_ROLE()
  const ST_POOL_MANAGER_ROLE = await stakeTogetherContract.POOL_MANAGER_ROLE()

  await stakeTogetherContract.connect(owner).grantRole(ST_ADMIN_ROLE, owner)
  await stakeTogetherContract.connect(owner).grantRole(ST_UPGRADER_ROLE, owner)
  await stakeTogetherContract.connect(owner).grantRole(ST_POOL_MANAGER_ROLE, owner)

  const config = {
    validatorSize: ethers.parseEther('32'),
    poolSize: ethers.parseEther('32'),
    minDepositAmount: ethers.parseEther('0.001'),
    minWithdrawAmount: ethers.parseEther('0.00001'),
    depositLimit: ethers.parseEther('1000'),
    withdrawalLimit: ethers.parseEther('1000'),
    blocksPerDay: 7200n,
    maxDelegations: 64n,
    feature: {
      AddPool: false,
      Deposit: true,
      WithdrawPool: true,
      WithdrawValidator: true,
    },
  }

  await stakeTogetherContract.setConfig(config)

  // Set the StakeEntry fee to 0.003 ether and make it a percentage-based fee
  await stakeTogetherContract.setFee(0n, ethers.parseEther('0.003'), [
    ethers.parseEther('0.6'),
    0n,
    ethers.parseEther('0.4'),
    0n,
  ])

  // Set the ProcessStakeRewards fee to 0.09 ether and make it a percentage-based fee
  await stakeTogetherContract.setFee(1n, ethers.parseEther('0.09'), [
    ethers.parseEther('0.33'),
    ethers.parseEther('0.33'),
    ethers.parseEther('0.34'),
    0n,
  ])

  // Set the StakePool fee to 1 ether and make it a fixed fee
  await stakeTogetherContract.setFee(2n, ethers.parseEther('1'), [
    ethers.parseEther('0.4'),
    0n,
    ethers.parseEther('0.6'),
    0n,
  ])

  // Set the ProcessStakeValidator fee to 0.01 ether and make it a fixed fee
  await stakeTogetherContract.setFee(3n, ethers.parseEther('0.01'), [0n, 0n, ethers.parseEther('1'), 0n])

  await owner.sendTransaction({ to: proxyAddress, value: ethers.parseEther('1') })

  return { proxyAddress, implementationAddress, stakeTogetherContract }
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

async function verifyContracts(
  airdropProxy: string,
  airdropImplementation: string,
  routerProxy: string,
  routerImplementation: string,
  stakeTogetherProxy: string,
  stakeTogetherImplementation: string,
  withdrawalsProxy: string,
  withdrawalsImplementation: string,
) {
  console.log('\nRUN COMMAND TO VERIFY ON ETHERSCAN\n')

  console.log(`npx hardhat verify --network goerli ${airdropProxy} &&`)
  console.log(`npx hardhat verify --network goerli ${airdropImplementation} &&`)
  console.log(`npx hardhat verify --network goerli ${withdrawalsProxy} &&`)
  console.log(`npx hardhat verify --network goerli ${withdrawalsImplementation} &&`)
  console.log(`npx hardhat verify --network goerli ${routerProxy} &&`)
  console.log(`npx hardhat verify --network goerli ${routerImplementation} &&`)
  console.log(`npx hardhat verify --network goerli ${stakeTogetherProxy} &&`)
  console.log(`npx hardhat verify --network goerli ${stakeTogetherImplementation}`)
}

deploy().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
