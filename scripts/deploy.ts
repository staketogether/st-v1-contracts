import { CustomEthersSigner } from '@nomiclabs/hardhat-ethers/signers'
import * as dotenv from 'dotenv'
import { ethers } from 'hardhat'
import { checkVariables } from '../test/utils/env'
import {
  Airdrop__factory,
  Fees__factory,
  Liquidity__factory,
  Loan__factory,
  Router__factory,
  StakeTogether__factory,
  Validators__factory,
  Withdrawals__factory
} from '../typechain'

dotenv.config()

export async function deployContracts() {
  checkVariables()

  const [owner] = await ethers.getSigners()

  const feesAddress = await deployFees(owner)
  const withdrawalsAddress = await deployWithdrawals(owner)
  const airdropAddress = await deployAirdrop(owner)
  const loanAddress = await deployLoan(owner)
  const validatorsAddress = await deployValidators(owner)
  const liquidityAddress = await deployLiquidity(owner)
  const routerAddress = await deployRouter(
    owner,
    withdrawalsAddress,
    liquidityAddress,
    airdropAddress,
    validatorsAddress,
    feesAddress
  )

  const stakeTogether = await deployStakeTogether(
    owner,
    routerAddress,
    feesAddress,
    airdropAddress,
    withdrawalsAddress,
    liquidityAddress,
    validatorsAddress,
    loanAddress
  )

  console.log('\n🔷 All contracts deployed!\n')
  verifyContracts(
    routerAddress,
    feesAddress,
    airdropAddress,
    withdrawalsAddress,
    liquidityAddress,
    validatorsAddress,
    loanAddress,
    stakeTogether
  )
}

async function deployFees(owner: CustomEthersSigner) {
  const Fees = await new Fees__factory().connect(owner).deploy()

  const address = await Fees.getAddress()

  console.log(`Fees deployed:\t\t\t ${address}`)

  return address
}

async function deployWithdrawals(owner: CustomEthersSigner) {
  const Withdrawal = await new Withdrawals__factory().connect(owner).deploy()

  const address = await Withdrawal.getAddress()

  console.log(`Withdrawal deployed:\t\t ${address}`)

  return address
}

async function deployAirdrop(owner: CustomEthersSigner) {
  const Airdrop = await new Airdrop__factory().connect(owner).deploy()

  const address = await Airdrop.getAddress()

  console.log(`Airdrop deployed:\t\t ${address}`)

  return address
}

async function deployLoan(owner: CustomEthersSigner) {
  const Loan = await new Loan__factory().connect(owner).deploy()

  const address = await Loan.getAddress()

  console.log(`Loan deployed:\t\t\t ${address}`)

  return address
}

async function deployValidators(owner: CustomEthersSigner) {
  const Validators = await new Validators__factory()
    .connect(owner)
    .deploy(process.env.GOERLI_DEPOSIT_ADDRESS as string)

  const address = await Validators.getAddress()

  console.log(`Validators deployed:\t\t ${address}`)

  return address
}

async function deployLiquidity(owner: CustomEthersSigner) {
  const Liquidity = await new Liquidity__factory().connect(owner).deploy()

  const address = await Liquidity.getAddress()

  console.log(`Liquidity deployed:\t ${address}`)

  return address
}

async function deployStakeTogether(
  owner: CustomEthersSigner,
  routerAddress: string,
  feesAddress: string,
  airdropAddress: string,
  withdrawalsAddress: string,
  liquidityAddress: string,
  validatorsAddress: string,
  loanAddress: string
) {
  const StakeTogether = await new StakeTogether__factory()
    .connect(owner)
    .deploy(
      routerAddress,
      feesAddress,
      airdropAddress,
      withdrawalsAddress,
      liquidityAddress,
      validatorsAddress,
      loanAddress,
      {
        value: 1n
      }
    )

  const address = await StakeTogether.getAddress()

  console.log(`StakeTogether deployed:\t\t ${address}`)

  const Router = await ethers.getContractAt('Router', routerAddress)
  await Router.setStakeTogether(address)

  const Airdrop = await ethers.getContractAt('Airdrop', airdropAddress)
  await Airdrop.setStakeTogether(address)

  const Fees = await ethers.getContractAt('Fees', feesAddress)
  await Fees.setStakeTogether(address)

  const Validators = await ethers.getContractAt('Validators', validatorsAddress)
  await Validators.setStakeTogether(address)

  const Withdrawals = await ethers.getContractAt('Withdrawals', withdrawalsAddress)
  await Withdrawals.setStakeTogether(address)

  const Liquidity = await ethers.getContractAt('Liquidity', liquidityAddress)
  await Liquidity.setStakeTogether(address)

  // Configure Loan here because it's not a part of the Router dependencies
  const Loan = await ethers.getContractAt('Loan', loanAddress)
  await Loan.setStakeTogether(address)
  await Loan.setFees(feesAddress)
  await Loan.setRouter(routerAddress)

  StakeTogether.bootstrap()

  console.log(`\n\n\tStakeTogether address set in all contracts\n\n`)

  return address
}

async function deployRouter(
  owner: CustomEthersSigner,
  withdrawalsAddress: string,
  liquidityAddress: string,
  airdropAddress: string,
  validatorsAddress: string,
  feesAddress: string
) {
  const Router = await new Router__factory()
    .connect(owner)
    .deploy(withdrawalsAddress, liquidityAddress, airdropAddress, validatorsAddress, feesAddress)

  const address = await Router.getAddress()

  console.log(`Router deployed:\t\t ${address}`)

  const Airdrop = await ethers.getContractAt('Airdrop', airdropAddress)
  await Airdrop.setRouter(address)

  const Validators = await ethers.getContractAt('Validators', validatorsAddress)
  await Validators.setRouter(address)

  const Liquidity = await ethers.getContractAt('Liquidity', liquidityAddress)
  await Liquidity.setRouter(address)
  await Liquidity.setFees(feesAddress)

  console.log(`\n\n\tRouter address and fee address set in all contracts\n\n`)

  return address
}

async function verifyContracts(
  routerAddress: string,
  feesAddress: string,
  airdropAddress: string,
  withdrawalsAddress: string,
  liquidityAddress: string,
  validatorsAddress: string,
  loanAddress: string,
  stakeTogether: string
) {
  console.log('\nRUN COMMAND TO VERIFY ON ETHERSCAN\n')
  console.log(
    `\nnpx hardhat verify --network goerli ${routerAddress} ${withdrawalsAddress} ${liquidityAddress} ${airdropAddress} ${validatorsAddress} ${feesAddress} && npx hardhat verify --network goerli ${feesAddress} && npx hardhat verify --network goerli ${airdropAddress} && npx hardhat verify --network goerli ${withdrawalsAddress} && npx hardhat verify --network goerli ${liquidityAddress} && npx hardhat verify --network goerli ${validatorsAddress} ${
      process.env.GOERLI_DEPOSIT_ADDRESS as string
    } && npx hardhat verify --network goerli ${loanAddress} && npx hardhat verify --network goerli ${stakeTogether} ${routerAddress} ${feesAddress} ${airdropAddress} ${withdrawalsAddress} ${liquidityAddress} ${validatorsAddress} ${loanAddress}`
  )
}

deployContracts().catch(error => {
  console.error(error)
  process.exitCode = 1
})
