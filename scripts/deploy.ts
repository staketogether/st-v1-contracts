import { CustomEthersSigner } from '@nomiclabs/hardhat-ethers/signers'
import * as dotenv from 'dotenv'
import { ethers } from 'hardhat'
import { checkVariables } from '../test/utils/env'
import { formatAddressToWithdrawalCredentials } from '../test/utils/formatWithdrawal'
import { STOracle__factory, STValidator__factory, StakeTogether__factory } from '../typechain'

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
  const STOracle = await new STOracle__factory().connect(owner).deploy()

  const address = await STOracle.getAddress()

  console.log(`STOracle deployed:\t\t ${address}`)

  return address
}

async function deployValidator(owner: CustomEthersSigner) {
  checkVariables()

  const STValidator = await new STValidator__factory()
    .connect(owner)
    .deploy(
      process.env.GOERLI_DEPOSIT_ADDRESS as string,
      process.env.GOERLI_SSV_NETWORK_ADDRESS as string,
      process.env.GOERLI_SSV_TOKEN_ADDRESS as string
    )

  const address = await STValidator.getAddress()

  console.log(`STValidator deployed:\t\t ${address}`)

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

  const STValidator = await ethers.getContractAt('STValidator', validatorAddress)
  await STValidator.setStakeTogether(address)
  await STValidator.setWithdrawalCredentials(formatAddressToWithdrawalCredentials(address))

  const STOracle = await ethers.getContractAt('STOracle', oracleAddress)
  await STOracle.setStakeTogether(address)

  return address
}

deployContracts().catch(error => {
  console.error(error)
  process.exitCode = 1
})
