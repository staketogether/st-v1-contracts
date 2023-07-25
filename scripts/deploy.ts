import { CustomEthersSigner } from '@nomiclabs/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import * as dotenv from 'dotenv'
import { ethers, network, upgrades } from 'hardhat'
import { checkVariables } from '../test/utils/env'
import {
  Airdrop,
  Airdrop__factory,
  Fees,
  Fees__factory,
  Liquidity,
  Liquidity__factory,
  Router,
  Router__factory,
  Validators__factory,
  Withdrawals__factory
} from '../typechain'

dotenv.config()

const depositAddress = String(process.env.GOERLI_DEPOSIT_ADDRESS)

export async function deploy() {
  checkVariables()

  const [owner] = await ethers.getSigners()

  const fees = await deployFees(owner)
  const airdrop = await deployAirdrop(owner)
  const liquidity = await deployLiquidity(owner)
  const validators = await deployValidators(owner, depositAddress, fees.proxyAddress)
  const withdrawals = await deployWithdrawals(owner)
  const router = await deployRouter(
    owner,
    withdrawals.proxyAddress,
    liquidity.proxyAddress,
    airdrop.proxyAddress,
    validators.proxyAddress,
    fees.proxyAddress
  )

  // Fees Contract
  // Todo: set stake together address
  // Todo: set liquidity address

  // Airdrop Contract
  // Todo: set stake together address
  // Todo: set router address

  // Liquidity Contract
  // Todo: set stake together address
  // Todo: set router address

  // Validators Contract
  // Todo: set router address
  // Todo: set stake together address

  // Withdrawals Contract
  // Todo: set stake together address

  // Router Contract
  // Todo: set stake together address

  console.log('\n🔷 All contracts deployed!\n')
  verifyContracts(
    fees.proxyAddress,
    fees.implementationAddress,
    airdrop.proxyAddress,
    airdrop.implementationAddress,
    liquidity.proxyAddress,
    liquidity.implementationAddress,
    validators.proxyAddress,
    validators.implementationAddress,
    withdrawals.proxyAddress,
    withdrawals.implementationAddress,
    router.proxyAddress,
    router.implementationAddress
  )
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

  return { proxyAddress, implementationAddress }
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

  return { proxyAddress, implementationAddress }
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

  await liquidityContract.initializeShares({ value: 1n })

  const config = {
    enableLiquidity: true,
    enableDeposit: true,
    depositLimit: ethers.parseEther('1000'),
    withdrawalLimit: ethers.parseEther('1000'),
    withdrawalLiquidityLimit: ethers.parseEther('1000'),
    minDepositAmount: ethers.parseEther('0.001'),
    blocksInterval: 6500
  }

  await liquidityContract.setConfig(config)

  return { proxyAddress, implementationAddress }
}

async function deployValidators(owner: CustomEthersSigner, depositAddress: string, feesAddress: string) {
  const ValidatorsFactory = new Validators__factory().connect(owner)

  const validators = await upgrades.deployProxy(ValidatorsFactory, [depositAddress, feesAddress])
  await validators.waitForDeployment()
  const proxyAddress = await validators.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Validators\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Validators\t Implementation\t\t ${implementationAddress}`)

  return { proxyAddress, implementationAddress }
}

async function deployWithdrawals(owner: CustomEthersSigner) {
  const WithdrawalsFactory = new Withdrawals__factory().connect(owner)

  const withdrawals = await upgrades.deployProxy(WithdrawalsFactory)
  await withdrawals.waitForDeployment()
  const proxyAddress = await withdrawals.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Withdrawals\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Withdrawals\t Implementation\t\t ${implementationAddress}`)

  return { proxyAddress, implementationAddress }
}

async function deployRouter(
  owner: CustomEthersSigner,
  withdrawalsContract: string,
  liquidityContract: string,
  airdropContract: string,
  validatorsContract: string,
  feesContract: string
) {
  const RouterFactory = new Router__factory().connect(owner)

  const router = await upgrades.deployProxy(RouterFactory, [
    withdrawalsContract,
    liquidityContract,
    airdropContract,
    validatorsContract,
    feesContract
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

  return { proxyAddress, implementationAddress }
}

async function verifyContracts(
  feesProxy: string,
  feesImplementation: string,
  airdropProxy: string,
  airdropImplementation: string,
  liquidityProxy: string,
  liquidityImplementation: string,
  validatorsProxy: string,
  validatorsImplementation: string,
  withdrawalsProxy: string,
  withdrawalsImplementation: string,
  routerAddress: string,
  routerImplementation: string
) {
  console.log('\nRUN COMMAND TO VERIFY ON ETHERSCAN\n')

  console.log(`npx hardhat verify --network goerli ${feesProxy} &&`)
  console.log(`npx hardhat verify --network goerli ${feesImplementation} &&`)
  console.log(`npx hardhat verify --network goerli ${airdropProxy} &&`)
  console.log(`npx hardhat verify --network goerli ${airdropImplementation} &&`)
  console.log(`npx hardhat verify --network goerli ${liquidityProxy} &&`)
  console.log(`npx hardhat verify --network goerli ${liquidityImplementation} &&`)
  console.log(`npx hardhat verify --network goerli ${validatorsProxy} ${depositAddress} ${feesProxy} &&`)
  console.log(`npx hardhat verify --network goerli ${validatorsImplementation} &&`)
  console.log(`npx hardhat verify --network goerli ${withdrawalsProxy} &&`)
  console.log(`npx hardhat verify --network goerli ${withdrawalsImplementation} &&`)
  console.log(
    `npx hardhat verify --network goerli ${routerAddress} ${withdrawalsProxy} ${liquidityProxy} ${airdropProxy} ${validatorsProxy} ${feesProxy} &&`
  )
  console.log(`npx hardhat verify --network goerli ${routerImplementation}`)
}

deploy().catch(error => {
  console.error(error)
  process.exitCode = 1
})
