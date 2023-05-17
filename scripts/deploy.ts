import { CustomEthersSigner } from '@nomiclabs/hardhat-ethers/signers'
import * as dotenv from 'dotenv'
import { ethers } from 'hardhat'
import { checkVariables } from '../test/utils/env'
import { formatAddressToWithdrawalCredentials } from '../test/utils/formatWithdrawal'
import { Oracle__factory, StakeTogether__factory, Validator__factory } from '../typechain'

dotenv.config()

export async function deployContracts() {
  checkVariables()

  const [owner] = await ethers.getSigners()

  const oracleAddress = await deployOracle(owner)
  const validatorAddress = await deployValidator(owner)

  const stakeTogether = await deployStakeTogether(owner, oracleAddress, validatorAddress)

  console.log('\n🔷 All contracts deployed!\n')
  verifyContracts(oracleAddress, validatorAddress, stakeTogether)
}

async function verifyContracts(oracleAddress: string, validatorAddress: string, stakeTogether: string) {
  console.log('\nRUN COMMAND TO VERIFY ON ETHERSCAN\n')
  console.log(
    `\nnpx hardhat verify --network goerli ${oracleAddress} && npx hardhat verify --network goerli ${validatorAddress} ${
      process.env.GOERLI_DEPOSIT_ADDRESS as string
    } ${process.env.GOERLI_SSV_NETWORK_ADDRESS as string} ${
      process.env.GOERLI_SSV_TOKEN_ADDRESS as string
    } && npx hardhat verify --network goerli ${stakeTogether} ${oracleAddress} ${validatorAddress}`
  )
}

async function deployOracle(owner: CustomEthersSigner) {
  const Oracle = await new Oracle__factory().connect(owner).deploy()

  const address = await Oracle.getAddress()

  console.log(`Oracle deployed:\t\t ${address}`)

  return address
}

async function deployValidator(owner: CustomEthersSigner) {
  checkVariables()

  const Validator = await new Validator__factory()
    .connect(owner)
    .deploy(
      process.env.GOERLI_DEPOSIT_ADDRESS as string,
      process.env.GOERLI_SSV_NETWORK_ADDRESS as string,
      process.env.GOERLI_SSV_TOKEN_ADDRESS as string
    )

  const address = await Validator.getAddress()

  console.log(`Validator deployed:\t\t ${address}`)

  return address
}

async function deployStakeTogether(
  owner: CustomEthersSigner,
  oracleAddress: string,
  validatorAddress: string
) {
  const StakeTogether = await new StakeTogether__factory()
    .connect(owner)
    .deploy(oracleAddress, validatorAddress, {
      value: 1n
    })

  await StakeTogether.setOperatorFeeRecipient(await owner.getAddress())
  await StakeTogether.setStakeTogetherFeeRecipient(await owner.getAddress())

  const address = await StakeTogether.getAddress()

  console.log(`StakeTogether deployed:\t\t ${address}`)

  const Validator = await ethers.getContractAt('Validator', validatorAddress)
  await Validator.setStakeTogether(address)
  await Validator.setWithdrawalCredentials(formatAddressToWithdrawalCredentials(address))

  const Oracle = await ethers.getContractAt('Oracle', oracleAddress)
  await Oracle.setStakeTogether(address)

  return address
}

deployContracts().catch(error => {
  console.error(error)
  process.exitCode = 1
})
