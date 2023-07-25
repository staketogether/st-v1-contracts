import { CustomEthersSigner } from '@nomiclabs/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import * as dotenv from 'dotenv'
import { Contract } from 'ethers'
import { ethers, network, upgrades } from 'hardhat'
import { checkVariables } from '../test/utils/env'
import { Fees, Fees__factory } from '../typechain'

dotenv.config()

async function deployContract<T extends Contract>(name: string, ...args: any[]): Promise<T> {
  const factory = (await ethers.getContractFactory(name)) as any
  return (await upgrades.deployProxy(factory, args, { initializer: 'initialize' })) as T
}

export async function deploy() {
  checkVariables()

  const [owner] = await ethers.getSigners()

  const fees = await deployFees(owner)

  // Fees Contract
  // Todo: set stake together address
  // Todo: set router address
  // Todo: set liquidity address

  // const withdrawalsAddress = await deployWithdrawals(owner)
  // const airdropAddress = await deployAirdrop(owner)
  // const validatorsAddress = await deployValidators(owner)
  // const liquidityAddress = await deployLiquidity(owner)
  // const routerAddress = await deployRouter(
  //   owner,
  //   withdrawalsAddress,
  //   liquidityAddress,
  //   airdropAddress,
  //   validatorsAddress,
  //   feesAddress
  // )

  // const stakeTogether = await deployStakeTogether(
  //   owner,
  //   routerAddress,
  //   feesAddress,
  //   airdropAddress,
  //   withdrawalsAddress,
  //   liquidityAddress,
  //   validatorsAddress
  // )

  console.log('\n🔷 All contracts deployed!\n')
  verifyContracts(
    fees.proxyAddress,
    fees.implementationAddress
    //   routerAddress,
    //   airdropAddress,
    //   withdrawalsAddress,
    //   liquidityAddress,
    //   validatorsAddress,
    //   stakeTogether
  )
}

async function deployFees(owner: CustomEthersSigner) {
  const Fees = new Fees__factory().connect(owner)
  const fees = await upgrades.deployProxy(Fees)
  await fees.waitForDeployment()
  const proxyAddress = await fees.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Fees Proxy\t\t\t ${proxyAddress}`)
  console.log(`Fees Implementation\t\t ${implementationAddress}`)

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

  //
  // Set fee allocations: Make sure these allocations add up to 1 ether (100%) for each fee type
  await feesContract.setFeeAllocation(0, 1, ethers.parseEther('0.2'))
  await feesContract.setFeeAllocation(0, 2, ethers.parseEther('0.4'))
  await feesContract.setFeeAllocation(0, 5, ethers.parseEther('0.4'))

  await feesContract.setFeeAllocation(1, 2, ethers.parseEther('0.33'))
  await feesContract.setFeeAllocation(1, 3, ethers.parseEther('0.33'))
  await feesContract.setFeeAllocation(1, 5, ethers.parseEther('0.34'))

  await feesContract.setFeeAllocation(2, 1, ethers.parseEther('0.2'))
  await feesContract.setFeeAllocation(2, 5, ethers.parseEther('0.6'))
  await feesContract.setFeeAllocation(2, 6, ethers.parseEther('0.02'))

  await feesContract.setFeeAllocation(3, 3, ethers.parseEther('1'))

  await feesContract.setFeeAllocation(4, 1, ethers.parseEther('0.5'))
  await feesContract.setFeeAllocation(4, 5, ethers.parseEther('0.5'))

  await feesContract.setFeeAllocation(5, 1, ethers.parseEther('0.1'))
  await feesContract.setFeeAllocation(5, 2, ethers.parseEther('0.1'))
  await feesContract.setFeeAllocation(5, 5, ethers.parseEther('0.1'))
  await feesContract.setFeeAllocation(5, 6, ethers.parseEther('0.7'))

  return { proxyAddress, implementationAddress }
}

// async function deployWithdrawals(owner: CustomEthersSigner) {
//   const Withdrawal = await new Withdrawals__factory().connect(owner).deploy()

//   const address = await Withdrawal.getAddress()

//   console.log(`Withdrawal deployed:\t\t ${address}`)

//   return address
// }

// async function deployAirdrop(owner: CustomEthersSigner) {
//   const Airdrop = await new Airdrop__factory().connect(owner).deploy()

//   const address = await Airdrop.getAddress()

//   console.log(`Airdrop deployed:\t\t ${address}`)

//   return address
// }

// async function deployValidators(owner: CustomEthersSigner) {
//   const Validators = await new Validators__factory()
//     .connect(owner)
//     .deploy(process.env.GOERLI_DEPOSIT_ADDRESS as string)

//   const address = await Validators.getAddress()

//   console.log(`Validators deployed:\t\t ${address}`)

//   return address
// }

// async function deployLiquidity(owner: CustomEthersSigner) {
//   const Liquidity = await new Liquidity__factory().connect(owner).deploy()

//   const address = await Liquidity.getAddress()

//   console.log(`Liquidity deployed:\t ${address}`)

//   return address
// }

// async function deployStakeTogether(
//   owner: CustomEthersSigner,
//   routerAddress: string,
//   feesAddress: string,
//   airdropAddress: string,
//   withdrawalsAddress: string,
//   liquidityAddress: string,
//   validatorsAddress: string,
//   loanAddress: string
// ) {
//   const StakeTogether = await new StakeTogether__factory()
//     .connect(owner)
//     .deploy(
//       routerAddress,
//       feesAddress,
//       airdropAddress,
//       withdrawalsAddress,
//       liquidityAddress,
//       validatorsAddress
//       {
//         value: 1n
//       }
//     )

//   const address = await StakeTogether.getAddress()

//   console.log(`StakeTogether deployed:\t\t ${address}`)

//   const Router = await ethers.getContractAt('Router', routerAddress)
//   await Router.setStakeTogether(address)

//   const Airdrop = await ethers.getContractAt('Airdrop', airdropAddress)
//   await Airdrop.setStakeTogether(address)

//   const Fees = await ethers.getContractAt('Fees', feesAddress)
//   await Fees.setStakeTogether(address)

//   const Validators = await ethers.getContractAt('Validators', validatorsAddress)
//   await Validators.setStakeTogether(address)

//   const Withdrawals = await ethers.getContractAt('Withdrawals', withdrawalsAddress)
//   await Withdrawals.setStakeTogether(address)

//   const Liquidity = await ethers.getContractAt('Liquidity', liquidityAddress)
//   await Liquidity.setStakeTogether(address)

//   // Configure Loan here because it's not a part of the Router dependencies
//   const Loan = await ethers.getContractAt('Loan', loanAddress)
//   await Loan.setStakeTogether(address)
//   await Loan.setFees(feesAddress)
//   await Loan.setRouterContract(routerAddress)

//   console.log(`\n\n\tStakeTogether address set in all contracts\n\n`)

//   return address
// }

// async function deployRouter(
//   owner: CustomEthersSigner,
//   withdrawalsAddress: string,
//   liquidityAddress: string,
//   airdropAddress: string,
//   validatorsAddress: string,
//   feesAddress: string
// ) {
//   const Router = await new Router__factory()
//     .connect(owner)
//     .deploy(withdrawalsAddress, liquidityAddress, airdropAddress, validatorsAddress, feesAddress)

//   const address = await Router.getAddress()

//   console.log(`Router deployed:\t\t ${address}`)

//   const Airdrop = await ethers.getContractAt('Airdrop', airdropAddress)
//   await Airdrop.setRouterContract(address)

//   const Validators = await ethers.getContractAt('Validators', validatorsAddress)
//   await Validators.setRouterContract(address)

//   const Liquidity = await ethers.getContractAt('Liquidity', liquidityAddress)
//   await Liquidity.setRouterContract(address)
//   await Liquidity.setFees(feesAddress)

//   console.log(`\n\n\tRouter address and fee address set in all contracts\n\n`)

//   return address
// }

async function verifyContracts(
  feeProxy: string,
  feeImplementation: string
  // routerAddress: string,
  // airdropAddress: string,
  // withdrawalsAddress: string,
  // liquidityAddress: string,
  // validatorsAddress: string,
  // loanAddress: string,
  // stakeTogether: string
) {
  console.log('\nRUN COMMAND TO VERIFY ON ETHERSCAN\n')

  console.log(`npx hardhat verify --network goerli ${feeProxy} &&`)
  console.log(`npx hardhat verify --network goerli ${feeImplementation}`)

  // console.log(
  //   `\nnpx hardhat verify --network goerli ${routerAddress} ${withdrawalsAddress} ${liquidityAddress} ${airdropAddress} ${validatorsAddress} ${feesAddress} &&  && npx hardhat verify --network goerli ${airdropAddress} && npx hardhat verify --network goerli ${withdrawalsAddress} && npx hardhat verify --network goerli ${liquidityAddress} && npx hardhat verify --network goerli ${validatorsAddress} ${
  //     process.env.GOERLI_DEPOSIT_ADDRESS as string
  //   } && npx hardhat verify --network goerli ${loanAddress} && npx hardhat verify --network goerli ${stakeTogether} ${routerAddress} ${feesAddress} ${airdropAddress} ${withdrawalsAddress} ${liquidityAddress} ${validatorsAddress} ${loanAddress}`
  // )
}

deploy().catch(error => {
  console.error(error)
  process.exitCode = 1
})
