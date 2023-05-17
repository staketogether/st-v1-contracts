import * as dotenv from 'dotenv'
import { ethers } from 'hardhat'
import connect from '../test/utils/connect'
import { checkVariables } from '../test/utils/env'
import { StakeTogether__factory } from '../typechain'

dotenv.config()

export async function executeTxs() {
  checkVariables()

  await unstakeEth()
}

async function unstakeEth() {
  const [owner] = await ethers.getSigners()

  const StakeTogether = StakeTogether__factory.connect(
    process.env.GOERLI_STAKE_TOGETHER_ADDRESS as string,
    owner
  )

  const delegations = [
    {
      account: owner,
      percentage: ethers.parseEther('1')
    }
  ]

  const tx = await connect(StakeTogether, owner).unstake(delegations, ethers.parseEther('32.1'))

  console.log('TX Unstake', tx.hash)
}

executeTxs().catch(error => {
  console.error(error)
  process.exitCode = 1
})
