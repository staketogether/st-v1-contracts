import { ethers } from 'hardhat'
import { checkGeneralVariables } from '../../utils/env'

export default async function configureEthSepolia() {
  checkConfigVariables()

  await configureL1Adapter()
  console.log('\n🔷 All ST Eigen Layer Contracts on L1 Configured!\n')
}

async function configureL1Adapter() {
  const ethAdapter = await ethers.getContractAt(
    'Adapter',
    process.env.OP_HOLESKY_L1_ADAPTER_ADDRESS as string,
  )

  const tx = await ethAdapter.setL2Router(process.env.OP_SEPOLIA_L2_ROUTER_ADDRESS as string)
  await tx.wait()

  console.log('\n🔷 All ST Eigen Layer Contracts on L1 Configured!\n')
}

function checkConfigVariables() {
  checkGeneralVariables()
  const missingVariables = []

  if (!process.env.OP_HOLESKY_L1_ADAPTER_ADDRESS) missingVariables.push('OP_HOLESKY_L1_ADAPTER_ADDRESS')
  if (!process.env.OP_SEPOLIA_L2_ROUTER_ADDRESS) missingVariables.push('OP_SEPOLIA_L2_ROUTER_ADDRESS')

  if (missingVariables.length > 0) {
    throw new Error(`Missing environment variables: ${missingVariables.join(', ')}`)
  }
}
