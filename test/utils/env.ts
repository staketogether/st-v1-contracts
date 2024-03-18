export function checkVariables() {
  const missingVariables = []
  if (!process.env.MAINNET_DEPOSIT_ADDRESS) missingVariables.push('MAINNET_DEPOSIT_ADDRESS')
  if (!process.env.MAINNET_INFURA_API_KEY) missingVariables.push('MAINNET_INFURA_API_KEY')
  if (!process.env.HOLESKY_DEPOSIT_ADDRESS) missingVariables.push('HOLESKY_DEPOSIT_ADDRESS')
  if (!process.env.HOLESKY_RPC_URL) missingVariables.push('HOLESKY_RPC_URL')
  if (!process.env.DEPLOYER_PRIVATE_KEY) missingVariables.push('DEPLOYER_PRIVATE_KEY')
  if (!process.env.ETHERSCAN_API_KEY) missingVariables.push('ETHERSCAN_API_KEY')
  if (!process.env.ACCOUNT_1_PRIVATE_KEY) missingVariables.push('ACCOUNT_1_PRIVATE_KEY')
  if (!process.env.ACCOUNT_2_PRIVATE_KEY) missingVariables.push('ACCOUNT_2_PRIVATE_KEY')
  if (!process.env.ACCOUNT_3_PRIVATE_KEY) missingVariables.push('ACCOUNT_3_PRIVATE_KEY')
  if (!process.env.ACCOUNT_4_PRIVATE_KEY) missingVariables.push('ACCOUNT_4_PRIVATE_KEY')
  if (!process.env.ACCOUNT_5_PRIVATE_KEY) missingVariables.push('ACCOUNT_5_PRIVATE_KEY')
  if (!process.env.ACCOUNT_6_PRIVATE_KEY) missingVariables.push('ACCOUNT_6_PRIVATE_KEY')
  if (!process.env.ACCOUNT_7_PRIVATE_KEY) missingVariables.push('ACCOUNT_7_PRIVATE_KEY')
  if (!process.env.ACCOUNT_8_PRIVATE_KEY) missingVariables.push('ACCOUNT_8_PRIVATE_KEY')
  if (!process.env.ACCOUNT_9_PRIVATE_KEY) missingVariables.push('ACCOUNT_9_PRIVATE_KEY')
  if (!process.env.ACCOUNT_10_PRIVATE_KEY) missingVariables.push('ACCOUNT_10_PRIVATE_KEY')

  if (missingVariables.length > 0) {
    throw new Error(`Missing environment variables: ${missingVariables.join(', ')}`)
  }
}
