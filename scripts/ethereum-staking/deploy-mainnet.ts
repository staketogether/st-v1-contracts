import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import * as dotenv from 'dotenv'
import { ethers, network, upgrades } from 'hardhat'
import { checkVariables } from '../../test/utils/env'
import {
  Airdrop,
  Airdrop__factory,
  Router,
  Router__factory,
  StakeTogether,
  StakeTogetherWrapper,
  StakeTogetherWrapper__factory,
  StakeTogether__factory,
  Withdrawals,
  Withdrawals__factory,
} from '../../typechain'

dotenv.config()

const depositAddress = String(process.env.MAINNET_DEPOSIT_ADDRESS)

export async function deploy() {
  checkVariables()

  const [owner] = await ethers.getSigners()

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
  const stakeTogetherWrapper = await deployStakeTogetherWrapper(owner)

  await configContracts(owner, airdrop, stakeTogether, stakeTogetherWrapper, withdrawals, router)

  console.log('\n🔷 All ST Contracts Deployed!\n')

  verifyContracts(
    airdrop.proxyAddress,
    airdrop.implementationAddress,
    router.proxyAddress,
    router.implementationAddress,
    stakeTogether.proxyAddress,
    stakeTogether.implementationAddress,
    stakeTogetherWrapper.proxyAddress,
    stakeTogetherWrapper.implementationAddress,
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
  await airdropContract.connect(owner).grantRole(AIR_ADMIN_ROLE, owner)

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
  await withdrawalsContract.connect(owner).grantRole(WITHDRAW_ADMIN_ROLE, owner)

  return { proxyAddress, implementationAddress, withdrawalsContract }
}

export async function deployRouter(
  owner: HardhatEthersSigner,
  airdropContract: string,
  withdrawalsContract: string,
) {
  const RouterFactory = new Router__factory().connect(owner)

  const router = await upgrades.deployProxy(RouterFactory, [airdropContract, withdrawalsContract])

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
    oracleQuorum: 2n,
  }

  const routerContract = router as unknown as Router

  const ROUTER_ADMIN_ROLE = await routerContract.ADMIN_ROLE()
  await routerContract.connect(owner).grantRole(ROUTER_ADMIN_ROLE, owner)

  await routerContract.setConfig(config)

  return { proxyAddress, implementationAddress, routerContract }
}

export async function deployStakeTogether(
  owner: HardhatEthersSigner,
  airdropContract: string,
  routerContract: string,
  withdrawalsContract: string,
) {
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

  console.log(`StakeTogether\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`StakeTogether\t\t Implementation\t\t ${implementationAddress}`)

  const stakeTogetherContract = stakeTogether as unknown as StakeTogether

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

  // Airdrop,
  // Operator,
  // StakeTogether,
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

  // await owner.sendTransaction({ to: proxyAddress, value: ethers.parseEther('1') })

  return { proxyAddress, implementationAddress, stakeTogetherContract }
}

async function deployStakeTogetherWrapper(owner: HardhatEthersSigner) {
  const STWrapperFactory = new StakeTogetherWrapper__factory().connect(owner)

  const stWrapper = await upgrades.deployProxy(STWrapperFactory)
  await stWrapper.waitForDeployment()
  const proxyAddress = await stWrapper.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`StakeTogetherWrapper\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`StakeTogetherWrapper\t Implementation\t\t ${implementationAddress}`)

  const stWrapperContract = stWrapper as unknown as StakeTogetherWrapper

  const ST_WRAPPER_ADMIN_ROLE = await stWrapperContract.ADMIN_ROLE()
  await stWrapperContract.connect(owner).grantRole(ST_WRAPPER_ADMIN_ROLE, owner)

  return { proxyAddress, implementationAddress, stakeTogetherWrapperContract: stWrapperContract }
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
  stakeTogetherWrapper: {
    proxyAddress: string
    implementationAddress: string
    stakeTogetherWrapperContract: StakeTogetherWrapper
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

  await stakeTogetherWrapper.stakeTogetherWrapperContract.setStakeTogether(stakeTogether.proxyAddress)
}

async function verifyContracts(
  airdropProxy: string,
  airdropImplementation: string,
  routerProxy: string,
  routerImplementation: string,
  stakeTogetherProxy: string,
  stakeTogetherImplementation: string,
  stakeTogetherWrapperProxy: string,
  stakeTogetherWrapperImplementation: string,
  withdrawalsProxy: string,
  withdrawalsImplementation: string,
) {
  console.log('\nRUN COMMAND TO VERIFY ON ETHERSCAN\n')

  console.log(`npx hardhat verify --network mainnet ${airdropProxy} &&`)
  console.log(`npx hardhat verify --network mainnet ${airdropImplementation} &&`)
  console.log(`npx hardhat verify --network mainnet ${routerProxy} &&`)
  console.log(`npx hardhat verify --network mainnet ${routerImplementation} &&`)
  console.log(`npx hardhat verify --network mainnet ${withdrawalsProxy} &&`)
  console.log(`npx hardhat verify --network mainnet ${withdrawalsImplementation} &&`)
  console.log(`npx hardhat verify --network mainnet ${stakeTogetherProxy} &&`)
  console.log(`npx hardhat verify --network mainnet ${stakeTogetherImplementation} &&`)
  console.log(`npx hardhat verify --network mainnet ${stakeTogetherWrapperProxy} &&`)
  console.log(`npx hardhat verify --network mainnet ${stakeTogetherWrapperImplementation}`)
}

deploy().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
