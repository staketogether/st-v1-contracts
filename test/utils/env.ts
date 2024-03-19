export function checkVariables() {
  const missingVariables = []
  if (!process.env.MAINNET_DEPOSIT_ADDRESS) missingVariables.push('MAINNET_DEPOSIT_ADDRESS')
  if (!process.env.MAINNET_INFURA_API_KEY) missingVariables.push('MAINNET_INFURA_API_KEY')
  if (!process.env.GOERLI_DEPOSIT_ADDRESS) missingVariables.push('GOERLI_DEPOSIT_ADDRESS')
  if (!process.env.GOERLI_INFURA_API_KEY) missingVariables.push('GOERLI_INFURA_API_KEY')
  if (!process.env.DEPLOYER_PRIVATE_KEY) missingVariables.push('DEPLOYER_PRIVATE_KEY')
  if (!process.env.ETHERSCAN_API_KEY) missingVariables.push('ETHERSCAN_API_KEY')
  if (missingVariables.length > 0) {
    throw new Error(`Missing environment variables: ${missingVariables.join(', ')}`)
  }
}
