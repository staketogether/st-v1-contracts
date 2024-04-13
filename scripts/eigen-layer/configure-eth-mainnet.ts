import { ethers } from 'hardhat'
import { checkGeneralVariables } from '../../utils/env'

export default async function configureL1() {
  checkConfigVariables()
  await configureL1Adapter()
  console.log('\n🔷 All ST Eigen Layer Contracts on L1 Configured!\n')
}

async function configureL1Adapter() {
  console.log('Configuring L1 Adapter...\n')

  const ethAdapter = await ethers.getContractAt(
    'ELAdapter',
    process.env.OP_MAINNET_L1_ADAPTER_ADDRESS as string,
  )

  const tx = await ethAdapter.setL2Router(process.env.OP_MAINNET_L2_ROUTER_ADDRESS as string)
  await tx.wait()
}

function checkConfigVariables() {
  checkGeneralVariables()
  const missingVariables = []

  if (!process.env.OP_MAINNET_L1_ADAPTER_ADDRESS) missingVariables.push('OP_MAINNET_L1_ADAPTER_ADDRESS')
  if (!process.env.OP_MAINNET_L2_ROUTER_ADDRESS) missingVariables.push('OP_MAINNET_L2_ROUTER_ADDRESS')

  if (missingVariables.length > 0) {
    throw new Error(`Missing environment variables: ${missingVariables.join(', ')}`)
  }
}

configureL1().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
