import { ethers } from 'hardhat'
import { checkGeneralVariables } from '../../utils/env'

function checkConfigVariables() {
  checkGeneralVariables()
  const missingVariables = []

  if (!process.env.OP_MAINNET_L2_STAKE_TOGETHER_ADDRESS)
    missingVariables.push('OP_MAINNET_L2_STAKE_TOGETHER_ADDRESS')

  if (!process.env.OP_MAINNET_L1_ADAPTER_ADDRESS) missingVariables.push('OP_MAINNET_L1_ADAPTER_ADDRESS')

  if (missingVariables.length > 0) {
    throw new Error(`Missing environment variables: ${missingVariables.join(', ')}`)
  }
}

export default async function configureL2() {
  checkConfigVariables()
  const stakeTogether = await ethers.getContractAt(
    'ELStakeTogether',
    process.env.OP_MAINNET_L2_STAKE_TOGETHER_ADDRESS as string,
  )

  const tx = await stakeTogether.setL1Adapter(process.env.OP_MAINNET_L1_ADAPTER_ADDRESS as string, {
    gasLimit: 1000000,
  })
  await tx.wait()

  console.log('\n🔷 All ST Eigen Layer Contracts on L2 Configured!\n')
}

configureL2().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
