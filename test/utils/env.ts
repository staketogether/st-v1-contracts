export function checkVariables() {
  const missingVariables = []
  if (!process.env.GOERLI_DEPOSIT_ADDRESS) missingVariables.push('GOERLI_DEPOSIT_ADDRESS')

  if (!process.env.GOERLI_SSV_NETWORK_ADDRESS) missingVariables.push('GOERLI_SSV_NETWORK_ADDRESS')
  if (!process.env.GOERLI_SSV_TOKEN_ADDRESS) missingVariables.push('GOERLI_SSV_TOKEN_ADDRESS')
  if (!process.env.GOERLI_SSV_TOKEN_ADDRESS) missingVariables.push('GOERLI_SSV_TOKEN_ADDRESS')
  if (!process.env.ALCHEMY_GOERLI_API_KEY) missingVariables.push('ALCHEMY_GOERLI_API_KEY')
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

  if (!process.env.GOERLI_VALIDATOR_ADDRESS) missingVariables.push('GOERLI_VALIDATOR_ADDRESS')
  if (!process.env.GOERLI_ORACLE_ADDRESS) missingVariables.push('GOERLI_ORACLE_ADDRESS')
  if (!process.env.GOERLI_STAKE_TOGETHER_ADDRESS) missingVariables.push('GOERLI_STAKE_TOGETHER_ADDRESS')

  if (missingVariables.length > 0) {
    throw new Error(`Missing environment variables: ${missingVariables.join(', ')}`)
  }
}
