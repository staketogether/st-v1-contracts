import { CustomEthersSigner } from '@nomiclabs/hardhat-ethers/signers'
import * as dotenv from 'dotenv'
import { ethers } from 'hardhat'
import { checkVariables } from '../test/utils/env'
import { Rewards__factory, StakeTogether__factory } from '../typechain'

dotenv.config()

export async function deployContracts() {
  checkVariables()

  const [owner] = await ethers.getSigners()

  const rewardsAddress = await deployRewards(owner)

  const stakeTogether = await deployStakeTogether(owner, rewardsAddress)

  console.log('\n🔷 All contracts deployed!\n')
  verifyContracts(rewardsAddress, stakeTogether)
}

async function deployRewards(owner: CustomEthersSigner) {
  const Rewards = await new Rewards__factory().connect(owner).deploy()

  const address = await Rewards.getAddress()

  console.log(`Rewards deployed:\t\t ${address}`)

  return address
}

async function deployStakeTogether(owner: CustomEthersSigner, rewardsAddress: string) {
  const StakeTogether = await new StakeTogether__factory()
    .connect(owner)
    .deploy(rewardsAddress, process.env.GOERLI_DEPOSIT_ADDRESS as string, {
      value: 1n
    })

  const address = await StakeTogether.getAddress()

  console.log(`StakeTogether deployed:\t\t ${address}`)

  const Rewards = await ethers.getContractAt('Rewards', rewardsAddress)
  await Rewards.setStakeTogether(address)

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
