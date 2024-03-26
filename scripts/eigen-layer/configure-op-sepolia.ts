import { ethers } from 'hardhat'
import { checkGeneralVariables } from '../../utils/env'

export default async function configureOpSepolia() {
  checkConfigVariables()
  const stakeTogether = await ethers.getContractAt(
    'StakeTogether',
    process.env.OP_SEPOLIA_L2_STAKE_TOGETHER_ADDRESS as string,
  )

  const tx = await stakeTogether.setL1Adapter(process.env.OP_SEPOLIA_L1_ADAPTER_ADDRESS as string)
  await tx.wait()

  console.log('\n🔷 All ST Eigen Layer Contracts on L2 Configured!\n')
}

function checkConfigVariables() {
  checkGeneralVariables()
  const missingVariables = []

  if (!process.env.OP_SEPOLIA_L1_ADAPTER_ADDRESS) missingVariables.push('OP_SEPOLIA_L1_ADAPTER_ADDRESS')
  if (!process.env.OP_SEPOLIA_L2_STAKE_TOGETHER_ADDRESS)
    missingVariables.push('OP_SEPOLIA_L2_STAKE_TOGETHER_ADDRESS')

  if (missingVariables.length > 0) {
    throw new Error(`Missing environment variables: ${missingVariables.join(', ')}`)
  }
}
