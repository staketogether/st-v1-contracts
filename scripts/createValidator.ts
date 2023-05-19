import * as dotenv from 'dotenv'
import { ethers } from 'hardhat'
import { checkVariables } from '../test/utils/env'
import { StakeTogether__factory } from '../typechain'

dotenv.config()

export async function executeTxs() {
  checkVariables()
  await createValidator()
}

async function createValidator() {
  const [owner] = await ethers.getSigners()

  const StakeTogether = StakeTogether__factory.connect(
    process.env.GOERLI_STAKE_TOGETHER_ADDRESS as string,
    owner
  )

  const ethValidator = {
    pubkey:
      '8c4420559d2b5ec5020960ba71acfef35a4537b620f1007fd6378d8a6f45d58abc076ef0785029f7aa40951859bedf46',
    signature:
      '985a4b1c409ee5d6830489b7b84968c258fb97e408dbab00b15215b05ea3394d281545c8100a73ae8f6473986d58a5ff0f2e9eb834d7d8d61ec2384937ff363a37a2abcca1ac1df03e763b1b7de31e3aedf0cbf2aa6dde3271161c9ef2d3e2c7',
    deposit_data_root: '12612727fdc785c81aa29e0b388c06d10b10348eca0276f0a2e85bd1d57a45bb'
  }

  const tx = await StakeTogether.createValidator(
    `0x${ethValidator.pubkey}`,
    `0x${ethValidator.signature}`,
    `0x${ethValidator.deposit_data_root}`
  )

  console.log('TX Create STValidator', tx.hash)
}

executeTxs().catch(error => {
  console.error(error)
  process.exitCode = 1
})
