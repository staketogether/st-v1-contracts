import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import * as dotenv from 'dotenv'
import { ethers, network, upgrades } from 'hardhat'
import {
  ELAirdrop,
  ELAirdrop__factory,
  ELRouter,
  ELRouter__factory,
  ELStakeTogether,
  ELStakeTogether__factory,
  ELWithdrawals,
  ELWithdrawals__factory,
} from '../../typechain'
import { checkGeneralVariables } from '../../utils/env'

dotenv.config()

export async function deploy() {
  checkDeployVariables()
  const bridgeContract = String(process.env.OP_SEPOLIA_BRIDGE_ADDRESS)
  const l1Adapter = String(process.env.OP_SEPOLIA_L1_ADAPTER_ADDRESS)

  const [owner] = await ethers.getSigners()

  // DEPLOY
  const airdrop = await deployAirdrop(owner)
  const withdrawals = await deployWithdrawals(owner)
  const router = await deployRouter(owner, airdrop.proxyAddress, bridgeContract, withdrawals.proxyAddress)

  const stakeTogether = await deployStakeTogether(
    owner,
    airdrop.proxyAddress,
    bridgeContract,
    router.proxyAddress,
    withdrawals.proxyAddress,
  )

  // CONFIG

  await configContracts(owner, airdrop, l1Adapter, stakeTogether, withdrawals, router)

  // LOG

  console.log('\n🔷 All ST Eigen Layer Contracts Deployed!\n')

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
  const AirdropFactory = new ELAirdrop__factory().connect(owner)
  const airdrop = await upgrades.deployProxy(AirdropFactory)
  await airdrop.waitForDeployment()
  const proxyAddress = await airdrop.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`ELAirdrop\t\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`ELAirdrop\t\t\t Implementation\t\t ${implementationAddress}`)

  const airdropContract = airdrop as unknown as ELAirdrop

  const AIR_ADMIN_ROLE = await airdropContract.ADMIN_ROLE()
  await airdropContract.connect(owner).grantRole(AIR_ADMIN_ROLE, owner)

  return { proxyAddress, implementationAddress, airdropContract }
}

export async function deployWithdrawals(owner: HardhatEthersSigner) {
  const WithdrawalsFactory = new ELWithdrawals__factory().connect(owner)

  const withdrawals = await upgrades.deployProxy(WithdrawalsFactory)
  await withdrawals.waitForDeployment()
  const proxyAddress = await withdrawals.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`ELWithdrawals\t\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`ELWithdrawals\t\t\t Implementation\t\t ${implementationAddress}`)

  const withdrawalsContract = withdrawals as unknown as ELWithdrawals

  const WITHDRAW_ADMIN_ROLE = await withdrawalsContract.ADMIN_ROLE()
  await withdrawalsContract.connect(owner).grantRole(WITHDRAW_ADMIN_ROLE, owner)

  return { proxyAddress, implementationAddress, withdrawalsContract }
}

export async function deployRouter(
  owner: HardhatEthersSigner,
  airdropContract: string,
  bridgeContract: string,
  withdrawalsContract: string,
) {
  const RouterFactory = new ELRouter__factory().connect(owner)

  const router = await upgrades.deployProxy(RouterFactory, [
    airdropContract,
    bridgeContract,
    withdrawalsContract,
  ])

  await router.waitForDeployment()
  const proxyAddress = await router.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`ELRouter\t\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`ELRouter\t\t\t Implementation\t\t ${implementationAddress}`)

  // Create the configuration
  const config = {
    reportFrequency: 7200n,
    reportDelayBlock: 1200n,
    reportNoConsensusMargin: 0n,
    oracleQuorum: 2n,
  }

  const routerContract = router as unknown as ELRouter

  const ROUTER_ADMIN_ROLE = await routerContract.ADMIN_ROLE()
  await routerContract.connect(owner).grantRole(ROUTER_ADMIN_ROLE, owner)

  await routerContract.setConfig(config)

  return { proxyAddress, implementationAddress, routerContract }
}

export async function deployStakeTogether(
  owner: HardhatEthersSigner,
  airdropContract: string,
  bridgeContract: string,
  routerContract: string,
  withdrawalsContract: string,
) {
  const StakeTogetherFactory = new ELStakeTogether__factory().connect(owner)

  const stakeTogether = await upgrades.deployProxy(StakeTogetherFactory, [
    airdropContract,
    bridgeContract,
    routerContract,
    withdrawalsContract,
  ])

  await stakeTogether.waitForDeployment()
  const proxyAddress = await stakeTogether.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`ELStakeTogether\t\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`ELStakeTogether\t\t\t Implementation\t\t ${implementationAddress}`)

  const stakeTogetherContract = stakeTogether as unknown as ELStakeTogether

  const ST_ADMIN_ROLE = await stakeTogetherContract.ADMIN_ROLE()
  await stakeTogetherContract.connect(owner).grantRole(ST_ADMIN_ROLE, owner)

  const stakeEntry = ethers.parseEther('0.003')
  const stakeRewardsFee = ethers.parseEther('0.09')
  const stakePoolFee = ethers.parseEther('1')
  const stakeValidatorFee = ethers.parseEther('0.01')

  const poolSize = ethers.parseEther('32')

  const config = {
    blocksPerDay: 7200n,
    depositLimit: ethers.parseEther('3200'),
    maxDelegations: 64n,
    minDepositAmount: ethers.parseEther('0.01'),
    minWithdrawAmount: ethers.parseEther('0.009'),
    poolSize: poolSize + stakeValidatorFee,
    validatorSize: ethers.parseEther('32'),
    withdrawalPoolLimit: ethers.parseEther('640'),
    withdrawalValidatorLimit: ethers.parseEther('640'),
    withdrawDelay: 7200n,
    withdrawBeaconDelay: 7200n,
    feature: {
      AddPool: false,
      Deposit: true,
      WithdrawPool: true,
      WithdrawBeacon: false,
    },
  }

  await stakeTogetherContract.setConfig(config)

  // ELAirdrop,
  // Operator,
  // ELStakeTogether,
  // Sender

  // Set the StakeEntry fee to 0.003 ether and make it a percentage-based fee
  await stakeTogetherContract.setFee(0n, stakeEntry, [
    ethers.parseEther('0.6'),
    0n,
    ethers.parseEther('0.4'),
    0n,
  ])

  // Set the ProcessStakeRewards fee to 0.09 ether and make it a percentage-based fee
  await stakeTogetherContract.setFee(1n, stakeRewardsFee, [
    ethers.parseEther('0.444'),
    ethers.parseEther('0.278'),
    ethers.parseEther('0.278'),
    0n,
  ])

  // Set the StakePool fee to 1 ether and make it a fixed fee
  await stakeTogetherContract.setFee(2n, stakePoolFee, [0n, 0n, ethers.parseEther('1'), 0n])

  // Set the ProcessStakeValidator fee to 0.01 ether and make it a fixed fee
  await stakeTogetherContract.setFee(3n, stakeValidatorFee, [0n, 0n, ethers.parseEther('1'), 0n])

  await owner.sendTransaction({ to: proxyAddress, value: ethers.parseEther('0.00001') })

  return { proxyAddress, implementationAddress, stakeTogetherContract }
}

export async function configContracts(
  owner: HardhatEthersSigner,
  airdrop: {
    proxyAddress: string
    implementationAddress: string
    airdropContract: ELAirdrop
  },
  l1AdapterContract: string,
  stakeTogether: {
    proxyAddress: string
    implementationAddress: string
    stakeTogetherContract: ELStakeTogether
  },
  withdrawals: {
    proxyAddress: string
    implementationAddress: string
    withdrawalsContract: ELWithdrawals
  },
  router: {
    proxyAddress: string
    implementationAddress: string
    routerContract: ELRouter
  },
) {
  await airdrop.airdropContract.setStakeTogether(stakeTogether.proxyAddress)
  await airdrop.airdropContract.setRouter(router.proxyAddress)

  await router.routerContract.setStakeTogether(stakeTogether.proxyAddress)

  await withdrawals.withdrawalsContract.setStakeTogether(stakeTogether.proxyAddress)
  await withdrawals.withdrawalsContract.setRouter(router.proxyAddress)

  await stakeTogether.stakeTogetherContract.setFeeAddress(0, airdrop.proxyAddress)
  await stakeTogether.stakeTogetherContract.setFeeAddress(1, owner)
  await stakeTogether.stakeTogetherContract.setFeeAddress(2, owner)
  await stakeTogether.stakeTogetherContract.setFeeAddress(3, owner)
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
  console.log('\nRUN COMMAND TO VERIFY ON OP ETHERSCAN\n')

  console.log(`npx hardhat verify --network op-sepolia ${airdropProxy} &&`)
  console.log(`npx hardhat verify --network op-sepolia ${airdropImplementation} &&`)
  console.log(`npx hardhat verify --network op-sepolia ${withdrawalsProxy} &&`)
  console.log(`npx hardhat verify --network op-sepolia ${withdrawalsImplementation} &&`)
  console.log(`npx hardhat verify --network op-sepolia ${routerProxy} &&`)
  console.log(`npx hardhat verify --network op-sepolia ${routerImplementation} &&`)
  console.log(`npx hardhat verify --network op-sepolia ${stakeTogetherProxy} &&`)
  console.log(`npx hardhat verify --network op-sepolia ${stakeTogetherImplementation}`)
}

function checkDeployVariables() {
  checkGeneralVariables()
  const missingVariables = []

  if (!process.env.OP_SEPOLIA_BRIDGE_ADDRESS) missingVariables.push('OP_SEPOLIA_BRIDGE_ADDRESS')
  if (!process.env.OP_SEPOLIA_L1_ADAPTER_ADDRESS) missingVariables.push('OP_SEPOLIA_L1_ADAPTER_ADDRESS')

  if (missingVariables.length > 0) {
    throw new Error(`Missing environment variables: ${missingVariables.join(', ')}`)
  }
}

deploy().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
