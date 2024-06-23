import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import * as dotenv from 'dotenv'
import { ethers, network, upgrades } from 'hardhat'
import {
  ChilizAirdrop as Airdrop,
  ChilizAirdrop__factory as Airdrop__factory,
  ChilizRouter as Router,
  ChilizRouter__factory as Router__factory,
  ChilizStakeTogether as StakeTogether,
  ChilizStakeTogether__factory as StakeTogether__factory,
  ChilizWithdrawals as Withdrawals,
  ChilizWithdrawals__factory as Withdrawals__factory,
} from '../../typechain'
import { checkGeneralVariables } from '../../utils/env'

dotenv.config()

export async function deploy() {
  checkGeneralVariables()

  const stakingAddress = String(process.env.CHZ_SPICY_STAKING_ADDRESS)

  const [owner] = await ethers.getSigners()

  // DEPLOY
  const airdrop = await deployAirdrop(owner)
  const withdrawals = await deployWithdrawals(owner)
  const router = await deployRouter(owner, airdrop.proxyAddress, stakingAddress, withdrawals.proxyAddress)

  const stakeTogether = await deployStakeTogether(
    owner,
    airdrop.proxyAddress,
    router.proxyAddress,
    withdrawals.proxyAddress,
  )

  await configContracts(owner, airdrop, stakeTogether, withdrawals, router)

  console.log('\n🔷 All ST Contracts Deployed!\n')

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

  console.log(`Airdrop\t\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Airdrop\t\t\t Implementation\t\t ${implementationAddress}`)

  const airdropContract = airdrop as unknown as Airdrop

  const AIR_ADMIN_ROLE = await airdropContract.ADMIN_ROLE()
  const adminGrantRole = await airdropContract.connect(owner).grantRole(AIR_ADMIN_ROLE, owner)
  await adminGrantRole.wait()

  return { proxyAddress, implementationAddress, airdropContract }
}

export async function deployWithdrawals(owner: HardhatEthersSigner) {
  const WithdrawalsFactory = new Withdrawals__factory().connect(owner)

  const withdrawals = await upgrades.deployProxy(WithdrawalsFactory)
  await withdrawals.waitForDeployment()
  const proxyAddress = await withdrawals.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Withdrawals\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Withdrawals\t\t Implementation\t\t ${implementationAddress}`)

  const withdrawalsContract = withdrawals as unknown as Withdrawals

  const WITHDRAW_ADMIN_ROLE = await withdrawalsContract.ADMIN_ROLE()
  const adminGrantRole = await withdrawalsContract.connect(owner).grantRole(WITHDRAW_ADMIN_ROLE, owner)
  await adminGrantRole.wait()

  return { proxyAddress, implementationAddress, withdrawalsContract }
}

export async function deployRouter(
  owner: HardhatEthersSigner,
  airdropContract: string,
  stakingContract: string,
  withdrawalsContract: string,
) {
  const RouterFactory = new Router__factory().connect(owner)

  const router = await upgrades.deployProxy(RouterFactory, [
    airdropContract,
    stakingContract,
    withdrawalsContract,
  ])

  await router.waitForDeployment()
  const proxyAddress = await router.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Router\t\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Router\t\t\t Implementation\t\t ${implementationAddress}`)

  // Create the configuration
  const config = {
    reportFrequency: 7200n,
    reportDelayBlock: 1200n,
    reportNoConsensusMargin: 0n,
    oracleQuorum: 1n,
  }

  const routerContract = router as unknown as Router

  const ROUTER_ADMIN_ROLE = await routerContract.ADMIN_ROLE()
  const grantRole = await routerContract.connect(owner).grantRole(ROUTER_ADMIN_ROLE, owner)
  await grantRole.wait()

  await routerContract.connect(owner).setConfig(config)

  return { proxyAddress, implementationAddress, routerContract }
}

export async function deployStakeTogether(
  owner: HardhatEthersSigner,
  airdropContract: string,
  routerContract: string,
  withdrawalsContract: string,
) {
  const StakeTogetherFactory = new StakeTogether__factory().connect(owner)

  const stakeTogether = await upgrades.deployProxy(StakeTogetherFactory, [
    airdropContract,
    routerContract,
    withdrawalsContract,
  ])

  await stakeTogether.waitForDeployment()
  const proxyAddress = await stakeTogether.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`StakeTogether\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`StakeTogether\t\t Implementation\t\t ${implementationAddress}`)

  const stakeTogetherContract = stakeTogether as unknown as StakeTogether

  const ST_ADMIN_ROLE = await stakeTogetherContract.ADMIN_ROLE()
  const grantAdminRole = await stakeTogetherContract.connect(owner).grantRole(ST_ADMIN_ROLE, owner)
  await grantAdminRole.wait()

  // TEMP

  const ST_VALIDATOR_ORACLE_MANAGER = await stakeTogetherContract.VALIDATOR_ORACLE_MANAGER_ROLE()
  const grantValidatorOracleManager = await stakeTogetherContract
    .connect(owner)
    .grantRole(ST_VALIDATOR_ORACLE_MANAGER, owner)
  await grantValidatorOracleManager.wait()

  const ST_POOL_MANAGER_ROLE = await stakeTogetherContract.POOL_MANAGER_ROLE()
  const grantPoolManager = await stakeTogetherContract
    .connect(owner)
    .grantRole(ST_POOL_MANAGER_ROLE, owner)
  await grantPoolManager.wait()

  // TEMP

  const stakeEntry = ethers.parseEther('0.003')
  const stakeRewardsFee = ethers.parseEther('0.09')
  const stakePoolFee = ethers.parseEther('1')
  const stakeValidatorFee = ethers.parseEther('0.01')

  const config = {
    blocksPerDay: 7200n,
    depositLimit: ethers.parseEther('3200'),
    maxDelegations: 64n,
    minDepositAmount: ethers.parseEther('0.01'),
    minWithdrawAmount: ethers.parseEther('0.009'),
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

  await stakeTogetherContract.connect(owner).setConfig(config)

  // Airdrop,
  // Operator,
  // StakeTogether,
  // Sender

  // Set the StakeEntry fee to 0.003 ether and make it a percentage-based fee
  await stakeTogetherContract
    .connect(owner)
    .setFee(0n, stakeEntry, [ethers.parseEther('0.6'), 0n, ethers.parseEther('0.4'), 0n])

  // Set the ProcessStakeRewards fee to 0.09 ether and make it a percentage-based fee
  await stakeTogetherContract
    .connect(owner)
    .setFee(1n, stakeRewardsFee, [
      ethers.parseEther('0.444'),
      ethers.parseEther('0.278'),
      ethers.parseEther('0.278'),
      0n,
    ])

  // Set the StakePool fee to 1 ether and make it a fixed fee
  await stakeTogetherContract
    .connect(owner)
    .setFee(2n, stakePoolFee, [0n, 0n, ethers.parseEther('1'), 0n])

  // Set the ProcessStakeValidator fee to 0.01 ether and make it a fixed fee
  await stakeTogetherContract
    .connect(owner)
    .setFee(3n, stakeValidatorFee, [0n, 0n, ethers.parseEther('1'), 0n])

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
  console.log('\nRUN COMMAND TO VERIFY ON ETHERSCAN\n')

  console.log(`npx hardhat verify --network chz-spicy ${airdropProxy} &&`)
  console.log(`npx hardhat verify --network chz-spicy ${airdropImplementation} &&`)
  console.log(`npx hardhat verify --network chz-spicy ${routerProxy} &&`)
  console.log(`npx hardhat verify --network chz-spicy ${routerImplementation} &&`)
  console.log(`npx hardhat verify --network chz-spicy ${withdrawalsProxy} &&`)
  console.log(`npx hardhat verify --network chz-spicy ${withdrawalsImplementation} &&`)
  console.log(`npx hardhat verify --network chz-spicy ${stakeTogetherProxy} &&`)
  console.log(`npx hardhat verify --network chz-spicy ${stakeTogetherImplementation} &&`)
}

deploy().catch((error) => {
  console.error(error)
  process.exitCode = 1
})