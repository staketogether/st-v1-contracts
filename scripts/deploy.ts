import { CustomEthersSigner } from '@nomiclabs/hardhat-ethers/signers'
import * as dotenv from 'dotenv'
import { ethers } from 'hardhat'
import { checkVariables } from '../test/utils/env'
import {
  Airdrop__factory,
  Fees__factory,
  RewardsLoan__factory,
  Router__factory,
  StakeTogether__factory,
  Validators__factory,
  WithdrawalsLoan__factory,
  Withdrawals__factory
} from '../typechain'

dotenv.config()

export async function deployContracts() {
  checkVariables()

  const [owner] = await ethers.getSigners()

  const feesAddress = await deployFees(owner)
  const withdrawalsAddress = await deployWithdrawals(owner)
  const airdropAddress = await deployAirdrop(owner)
  const rewardsLoanAddress = await deployRewardsLoan(owner)
  const validatorsAddress = await deployValidators(owner)
  const withdrawalsLoanAddress = await deployWithdrawalsLoan(owner)
  const routerAddress = await deployRouter(
    owner,
    withdrawalsAddress,
    withdrawalsLoanAddress,
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
    withdrawalsLoanAddress,
    validatorsAddress
  )

  console.log('\n🔷 All contracts deployed!\n')
  // verifyContracts(rewardsAddress, stakeTogether)
}

async function deployFees(owner: CustomEthersSigner) {
  const Fees = await new Fees__factory().connect(owner).deploy()

  const address = await Fees.getAddress()

  console.log(`Fees deployed:\t\t ${address}`)

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

async function deployRewardsLoan(owner: CustomEthersSigner) {
  const RewardsLoan = await new RewardsLoan__factory().connect(owner).deploy()

  const address = await RewardsLoan.getAddress()

  console.log(`Rewards Loan deployed:\t\t ${address}`)

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

async function deployWithdrawalsLoan(owner: CustomEthersSigner) {
  const WithdrawalsLoan = await new WithdrawalsLoan__factory().connect(owner).deploy()

  const address = await WithdrawalsLoan.getAddress()

  console.log(`Withdrawals Loan deployed:\t\t ${address}`)

  return address
}

async function deployStakeTogether(
  owner: CustomEthersSigner,
  routerAddress: string,
  feesAddress: string,
  airdropAddress: string,
  withdrawalsAddress: string,
  withdrawalsLoanAddress: string,
  validatorsAddress: string
) {
  const StakeTogether = await new StakeTogether__factory()
    .connect(owner)
    .deploy(
      routerAddress,
      feesAddress,
      airdropAddress,
      withdrawalsAddress,
      withdrawalsLoanAddress,
      validatorsAddress,
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

  const WithdrawalsLoan = await ethers.getContractAt('WithdrawalsLoan', withdrawalsLoanAddress)
  await WithdrawalsLoan.setStakeTogether(address)

  const StakeTogetherOwner = await ethers.getContractAt('StakeTogether', address, owner)
  StakeTogetherOwner.bootstrap()

  console.log(`StakeTogether address set in all contracts`)

  return address
}

async function deployRouter(
  owner: CustomEthersSigner,
  withdrawalsAddress: string,
  withdrawalsLoanAddress: string,
  airdropAddress: string,
  validatorsAddress: string,
  feesAddress: string
) {
  const Router = await new Router__factory()
    .connect(owner)
    .deploy(withdrawalsAddress, withdrawalsLoanAddress, airdropAddress, validatorsAddress, feesAddress)

  const address = await Router.getAddress()

  console.log(`Router deployed:\t\t ${address}`)

  const Airdrop = await ethers.getContractAt('Airdrop', airdropAddress)
  await Airdrop.setRouter(address)

  const Validators = await ethers.getContractAt('Validators', validatorsAddress)
  await Validators.setRouter(address)

  const WithdrawalsLoan = await ethers.getContractAt('WithdrawalsLoan', withdrawalsLoanAddress)
  await WithdrawalsLoan.setRouter(address)
  await WithdrawalsLoan.setFees(feesAddress)

  console.log(`Router address and fee address set in all contracts`)

  return address
}

async function verifyContracts(rewardsAddress: string, stakeTogether: string) {
  console.log('\nRUN COMMAND TO VERIFY ON ETHERSCAN\n')
  console.log(
    `\nnpx hardhat verify --network goerli ${rewardsAddress} && npx hardhat verify --network goerli ${stakeTogether} ${rewardsAddress} ${
      process.env.GOERLI_DEPOSIT_ADDRESS as string
    }`
  )
}

deployContracts().catch(error => {
  console.error(error)
  process.exitCode = 1
})
