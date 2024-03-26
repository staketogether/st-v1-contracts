import '@nomicfoundation/hardhat-toolbox'
import '@openzeppelin/hardhat-upgrades'
import 'hardhat-gas-reporter'

import dotenv from 'dotenv'
import { checkGeneralVariables } from './test/utils/env'
dotenv.config()

checkGeneralVariables()

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
    compilers: [{ version: '0.8.25' }],
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v6',
  },
  networks: {
    'eth-mainnet': {
      url: process.env.CS_RPC_ETH_MAINNET,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
    },
    'eth-holesky': {
      url: process.env.CS_RPC_ETH_HOLESKY,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
    },
    'eth-sepolia': {
      url: process.env.CS_RPC_ETH_SEPOLIA,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
    },
    'op-mainnet': {
      url: process.env.CS_RPC_OP_MAINNET,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
    },
    'op-sepolia': {
      url: process.env.CS_RPC_OP_SEPOLIA,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
    },
    localhost: {
      url: 'http://127.0.0.1:8545',
    },
  },
  etherscan: {
    apiKey: {
      'eth-mainnet': process.env.ETHERSCAN_API_KEY as string,
      'eth-holesky': process.env.ETHERSCAN_API_KEY as string,
      'op-mainnet': process.env.OP_ETHERSCAN_API_KEY as string,
      'op-sepolia': process.env.OP_ETHERSCAN_API_KEY as string,
    },
    customChains: [
      {
        network: 'eth-mainnet',
        chainId: 1,
        urls: {
          apiURL: 'https://etherscan.io/api',
          browserURL: 'https://etherscan.io',
        },
      },
      {
        network: 'eth-holesky',
        chainId: 17000,
        urls: {
          apiURL: 'https://api-holesky.etherscan.io/api',
          browserURL: 'https://holesky.etherscan.io/',
        },
      },
      {
        network: 'eth-sepolia',
        chainId: 11155111,
        urls: {
          apiURL: 'https://api-sepolia.etherscan.io/api',
          browserURL: 'https://sepolia.etherscan.io/',
        },
      },

      {
        network: 'op-mainnet',
        chainId: 10,
        urls: {
          apiURL: 'https://api-optimistic.etherscan.io/api',
          browserURL: 'https://optimistic.etherscan.io/',
        },
      },
      {
        network: 'op-sepolia',
        chainId: 11155420,
        urls: {
          apiURL: 'https://api-sepolia-optimistic.etherscan.io/api',
          browserURL: 'https://sepolia-optimism.etherscan.io/',
        },
      },
    ],
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
