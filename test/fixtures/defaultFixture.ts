import { CustomEthersSigner, SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import * as dotenv from 'dotenv'
import { ethers, network, upgrades } from 'hardhat'
import {
  Airdrop,
  Airdrop__factory,
  Fees,
  Fees__factory,
  Liquidity,
  Liquidity__factory,
  Router,
  Router__factory,
  StakeTogether,
  StakeTogether__factory,
  Validators,
  Validators__factory,
  Withdrawals,
  Withdrawals__factory
} from '../../typechain'
import { checkVariables } from '../utils/env'

dotenv.config()

export async function defaultFixture() {
  checkVariables()

  const provider = ethers.provider

  let owner: SignerWithAddress
  let user1: SignerWithAddress
  let user2: SignerWithAddress
  let user3: SignerWithAddress
  let user4: SignerWithAddress
  let user5: SignerWithAddress
  let user6: SignerWithAddress
  let user7: SignerWithAddress
  let user8: SignerWithAddress
  let user9: SignerWithAddress
  let nullAddress: string = '0x0000000000000000000000000000000000000000'

  ;[owner, user1, user2, user3, user4, user5, user6, user7, user8, user9] = await ethers.getSigners()

  const depositAddress = String(process.env.GOERLI_DEPOSIT_ADDRESS)
  const initialDeposit = 1n

  const Fees = await deployFees(owner)
  const Airdrop = await deployAirdrop(owner)
  const Liquidity = await deployLiquidity(owner)
  const Validators = await deployValidators(owner, depositAddress, Fees.proxyAddress)
  const Withdrawals = await deployWithdrawals(owner)
  const Router = await deployRouter(
    owner,
    Airdrop.proxyAddress,
    Fees.proxyAddress,
    Liquidity.proxyAddress,
    Validators.proxyAddress,
    Withdrawals.proxyAddress
  )
  const StakeTogether = await deployStakeTogether(
    owner,
    Airdrop.proxyAddress,
    Fees.proxyAddress,
    Liquidity.proxyAddress,
    Router.proxyAddress,
    Validators.proxyAddress,
    Withdrawals.proxyAddress
  )

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
  }
}

async function deployFees(owner: CustomEthersSigner) {
  const FeesFactory = new Fees__factory().connect(owner)
  const fees = await upgrades.deployProxy(FeesFactory)
  await fees.waitForDeployment()
  const proxyAddress = await fees.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Fees\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Fees\t\t Implementation\t\t ${implementationAddress}`)

  const feesContract = fees as unknown as Fees

  // Set the StakeEntry fee to 0.003 ether and make it a percentage-based fee
  await feesContract.setFeeValue(0, ethers.parseEther('0.003'), 1)

  // Set the StakeRewards fee to 0.09 ether and make it a percentage-based fee
  await feesContract.setFeeValue(1, ethers.parseEther('0.09'), 1)

  // Set the StakePool fee to 1 ether and make it a fixed fee
  await feesContract.setFeeValue(2, ethers.parseEther('1'), 0)

  // Set the StakeValidator fee to 0.01 ether and make it a fixed fee
  await feesContract.setFeeValue(3, ethers.parseEther('0.01'), 0)

  // Set the LiquidityProvideEntry fee to 0.003 ether and make it a percentage-based fee
  await feesContract.setFeeValue(4, ethers.parseEther('0.003'), 1)

  // Set the LiquidityProvide fee to 0.001 ether and make it a percentage-based fee
  await feesContract.setFeeValue(5, ethers.parseEther('0.001'), 1)

  // Set the maximum fee increase to 3 ether (300%)
  await feesContract.setMaxFeeIncrease(ethers.parseEther('3'))

  // Todo: Change these addresses to the actual fee recipient addresses
  for (let i = 0; i < 7; i++) {
    await feesContract.setFeeAddress(i, owner)
  }

  // Set fee allocations: Make sure these allocations add up to 1 ether (100%) for each fee type

  // StakeEntry
  await feesContract.setFeeAllocation(0, 1, ethers.parseEther('0.2'))
  await feesContract.setFeeAllocation(0, 2, ethers.parseEther('0.4'))
  await feesContract.setFeeAllocation(0, 5, ethers.parseEther('0.4'))

  // StakeRewards
  await feesContract.setFeeAllocation(1, 2, ethers.parseEther('0.33'))
  await feesContract.setFeeAllocation(1, 3, ethers.parseEther('0.33'))
  await feesContract.setFeeAllocation(1, 5, ethers.parseEther('0.34'))

  // StakePool
  await feesContract.setFeeAllocation(2, 1, ethers.parseEther('0.2'))
  await feesContract.setFeeAllocation(2, 5, ethers.parseEther('0.6'))
  await feesContract.setFeeAllocation(2, 6, ethers.parseEther('0.02'))

  // StakeValidator
  await feesContract.setFeeAllocation(3, 3, ethers.parseEther('1'))

  // LiquidityProvideEntry
  await feesContract.setFeeAllocation(4, 1, ethers.parseEther('0.5'))
  await feesContract.setFeeAllocation(4, 5, ethers.parseEther('0.5'))

  // LiquidityProvide
  await feesContract.setFeeAllocation(5, 1, ethers.parseEther('0.1'))
  await feesContract.setFeeAllocation(5, 2, ethers.parseEther('0.1'))
  await feesContract.setFeeAllocation(5, 5, ethers.parseEther('0.1'))
  await feesContract.setFeeAllocation(5, 6, ethers.parseEther('0.7'))

  return { proxyAddress, implementationAddress, contract: feesContract }
}

async function deployAirdrop(owner: CustomEthersSigner) {
  const AirdropFactory = new Airdrop__factory().connect(owner)
  const airdrop = await upgrades.deployProxy(AirdropFactory)
  await airdrop.waitForDeployment()
  const proxyAddress = await airdrop.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Airdrop\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Airdrop\t\t Implementation\t\t ${implementationAddress}`)

  const airdropContract = airdrop as unknown as Airdrop

  await airdropContract.setMaxBatchSize(100)

  return { proxyAddress, implementationAddress, contract: airdropContract }
}

async function deployLiquidity(owner: CustomEthersSigner) {
  const LiquidityFactory = new Liquidity__factory().connect(owner)

  const liquidity = await upgrades.deployProxy(LiquidityFactory)
  await liquidity.waitForDeployment()
  const proxyAddress = await liquidity.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Liquidity\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Liquidity\t Implementation\t\t ${implementationAddress}`)

  const liquidityContract = liquidity as unknown as Liquidity

  const config = {
    depositLimit: ethers.parseEther('1000'),
    withdrawalLimit: ethers.parseEther('1000'),
    withdrawalLiquidityLimit: ethers.parseEther('1000'),
    minDepositAmount: ethers.parseEther('0.001'),
    blocksInterval: 6500,
    feature: {
      Deposit: true,
      Withdraw: true,
      Liquidity: true
    }
  }

  await liquidityContract.setConfig(config)

  await liquidityContract.initializeShares({ value: 1n })

  return { proxyAddress, implementationAddress, contract: liquidityContract }
}

async function deployValidators(owner: CustomEthersSigner, depositAddress: string, feesAddress: string) {
  const ValidatorsFactory = new Validators__factory().connect(owner)

  const validators = await upgrades.deployProxy(ValidatorsFactory, [depositAddress, feesAddress])
  await validators.waitForDeployment()
  const proxyAddress = await validators.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Validators\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Validators\t Implementation\t\t ${implementationAddress}`)

  const validatorsContract = validators as unknown as Validators

  return { proxyAddress, implementationAddress, contract: validatorsContract }
}

async function deployWithdrawals(owner: CustomEthersSigner) {
  const WithdrawalsFactory = new Withdrawals__factory().connect(owner)

  const withdrawals = await upgrades.deployProxy(WithdrawalsFactory)
  await withdrawals.waitForDeployment()
  const proxyAddress = await withdrawals.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Withdrawals\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Withdrawals\t Implementation\t\t ${implementationAddress}`)

  const withdrawalsContract = withdrawals as unknown as Withdrawals

  return { proxyAddress, implementationAddress, contract: withdrawalsContract }
}

async function deployRouter(
  owner: CustomEthersSigner,
  airdropContract: string,
  feesContract: string,
  liquidityContract: string,
  validatorsContract: string,
  withdrawalsContract: string
) {
  const RouterFactory = new Router__factory().connect(owner)

  const router = await upgrades.deployProxy(RouterFactory, [
    airdropContract,
    feesContract,
    liquidityContract,
    validatorsContract,
    withdrawalsContract
  ])

  await router.waitForDeployment()
  const proxyAddress = await router.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Router\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Router\t\t Implementation\t\t ${implementationAddress}`)

  // Create the configuration
  const config = {
    bunkerMode: false,
    maxValidatorsToExit: 100,
    minBlocksBeforeExecution: 600,
    minReportOracleQuorum: 5,
    reportOracleQuorum: 5,
    oracleBlackListLimit: 3,
    reportBlockFrequency: 1
  }

  // Cast the contract to the correct type
  const routerContract = router as unknown as Router

  // Set the configuration
  await routerContract.setConfig(config)

  return { proxyAddress, implementationAddress, contract: routerContract }
}

async function deployStakeTogether(
  owner: CustomEthersSigner,
  airdropContract: string,
  feesContract: string,
  liquidityContract: string,
  routerContract: string,
  validatorsContract: string,
  withdrawalsContract: string
) {
  const StakeTogetherFactory = new StakeTogether__factory().connect(owner)

  const stakeTogether = await upgrades.deployProxy(StakeTogetherFactory, [
    airdropContract,
    feesContract,
    liquidityContract,
    routerContract,
    validatorsContract,
    withdrawalsContract
  ])

  await stakeTogether.waitForDeployment()
  const proxyAddress = await stakeTogether.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`StakeTogether\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`StakeTogether\t Implementation\t\t ${implementationAddress}`)

  const stakeTogetherContract = stakeTogether as unknown as StakeTogether

  function convertToWithdrawalAddress(eth1Address: string): string {
    const address = eth1Address.startsWith('0x') ? eth1Address.slice(2) : eth1Address
    const paddedAddress = address.padStart(64, '0')
    const withdrawalAddress = '0x01' + paddedAddress
    return withdrawalAddress
  }

  await stakeTogetherContract.setWithdrawalsCredentials(convertToWithdrawalAddress(proxyAddress))

  const config = {
    poolSize: ethers.parseEther('32'),
    minDepositAmount: ethers.parseEther('0.001'),
    minLockDays: 30n,
    maxLockDays: 365n,
    depositLimit: ethers.parseEther('1000'),
    withdrawalLimit: ethers.parseEther('1000'),
    blocksPerDay: 7200n,
    maxDelegations: 64n,
    feature: {
      AddPool: true,
      Deposit: true,
      Lock: true,
      WithdrawPool: true,
      WithdrawLiquidity: true,
      WithdrawValidator: true
    }
  }

  await stakeTogetherContract.setConfig(config)

  await stakeTogetherContract.initializeShares({ value: 1n })

  return { proxyAddress, implementationAddress, contract: stakeTogetherContract }
}
