import { CustomEthersSigner } from '@nomiclabs/hardhat-ethers/signers'
import * as dotenv from 'dotenv'
import { ethers } from 'hardhat'
import { checkVariables } from '../test/utils/env'
import { STOracle__factory, StakeTogether__factory } from '../typechain'

dotenv.config()

export async function deployContracts() {
  checkVariables()

  const [owner] = await ethers.getSigners()

  const oracleAddress = await deployOracle(owner)

  const stakeTogether = await deployStakeTogether(owner, oracleAddress)

  console.log('\n🔷 All contracts deployed!\n')
  verifyContracts(oracleAddress, stakeTogether)
}

async function verifyContracts(oracleAddress: string, stakeTogether: string) {
  console.log('\nRUN COMMAND TO VERIFY ON ETHERSCAN\n')
  console.log(
    `\nnpx hardhat verify --network goerli ${oracleAddress} && 
      npx hardhat verify --network goerli ${stakeTogether} ${oracleAddress} ${
      process.env.GOERLI_DEPOSIT_ADDRESS as string
    }`
  )
}

async function deployOracle(owner: CustomEthersSigner) {
  const STOracle = await new STOracle__factory().connect(owner).deploy()

  const address = await STOracle.getAddress()

  console.log(`STOracle deployed:\t\t ${address}`)

  return address
}

async function deployStakeTogether(owner: CustomEthersSigner, oracleAddress: string) {
  const StakeTogether = await new StakeTogether__factory()
    .connect(owner)
    .deploy(oracleAddress, process.env.GOERLI_DEPOSIT_ADDRESS as string, {
      value: 1n
    })

  await StakeTogether.setOperatorFeeRecipient(await owner.getAddress())
  await StakeTogether.setStakeTogetherFeeRecipient(await owner.getAddress())

  const address = await StakeTogether.getAddress()

  console.log(`StakeTogether deployed:\t\t ${address}`)

  const STOracle = await ethers.getContractAt('STOracle', oracleAddress)
  await STOracle.setStakeTogether(address)

  return address
}

deployContracts().catch(error => {
  console.error(error)
  process.exitCode = 1
})
