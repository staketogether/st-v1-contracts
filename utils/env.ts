export function checkGeneralVariables() {
  const missingVariables = []
  if (!process.env.DEPLOYER_PRIVATE_KEY) missingVariables.push('DEPLOYER_PRIVATE_KEY')

  if (!process.env.CS_RPC_ETH_MAINNET) missingVariables.push('CS_RPC_ETH_MAINNET')
  if (!process.env.CS_RPC_ETH_HOLESKY) missingVariables.push('CS_RPC_ETH_HOLESKY')
  if (!process.env.CS_RPC_ETH_SEPOLIA) missingVariables.push('CS_RPC_ETH_SEPOLIA')
  if (!process.env.CS_RPC_OP_MAINNET) missingVariables.push('CS_RPC_OP_MAINNET')
  if (!process.env.CS_RPC_OP_SEPOLIA) missingVariables.push('CS_RPC_OP_SEPOLIA')

  if (!process.env.ETHERSCAN_API_KEY) missingVariables.push('ETHERSCAN_API_KEY')
  if (!process.env.OP_ETHERSCAN_API_KEY) missingVariables.push('OP_ETHERSCAN_API_KEY')

  if (missingVariables.length > 0) {
    throw new Error(`Missing environment variables: ${missingVariables.join(', ')}`)
  }
}
