import '@nomicfoundation/hardhat-toolbox'
import '@openzeppelin/hardhat-upgrades'
import 'hardhat-gas-reporter'

import dotenv from 'dotenv'
import { checkVariables } from './test/utils/env'
dotenv.config()

checkVariables()

const config = {
  solidity: {
    version: '0.8.25',
    overrides: {
      '*': {
        version: '0.8.25',
      },
    },
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v6',
  },
  networks: {
    mainnet: {
      url: `https://mainnet.infura.io/v3/${process.env.MAINNET_INFURA_API_KEY}`,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
      chainId: 1,
    },
    goerli: {
      url: `https://goerli.infura.io/v3/${process.env.GOERLI_INFURA_API_KEY}`,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
      chainId: 5,
    },
    localhost: {
      url: 'http://127.0.0.1:8545',
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY as string,
  },
  sourcify: {
    enabled: false,
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 5,
    enabled: process.env.GAS_REPORTER === 'true' ? true : false,
    coinmarketcap: process.env.COINMARKETCAP_API_KEY as string,
  },
}

export default config
