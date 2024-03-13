import '@nomicfoundation/hardhat-toolbox'
import '@openzeppelin/hardhat-upgrades'
import 'hardhat-gas-reporter'
import { HardhatUserConfig } from 'hardhat/config'

import dotenv from 'dotenv'
import { checkVariables } from './test/utils/env'
dotenv.config()

checkVariables()

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.22',
    overrides: {
      '*': {
        version: '0.8.22',
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
    optimism: {
      url: `https://optimism-mainnet.infura.io/v3/${process.env.MAINNET_INFURA_API_KEY}`,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
      chainId: 10,
    },
    goerli: {
      url: `https://goerli.infura.io/v3/${process.env.GOERLI_INFURA_API_KEY}`,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
      chainId: 5,
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${process.env.SEPOLIA_INFURA_API_KEY}`,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
      chainId: 11155111,
    },
    optimismSepolia: {
      url: `https://optimism-sepolia.infura.io/v3/${process.env.OP_SEPOLIA_INFURA_API_KEY}`,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
      chainId: 11155420,
    },
    localhost: {
      url: 'http://127.0.0.1:8545',
    },
    hardhat: {
      accounts: [
        {
          privateKey: process.env.ACCOUNT_1_PRIVATE_KEY as string,
          balance: '10000000000000000000000',
        },
        {
          privateKey: process.env.ACCOUNT_2_PRIVATE_KEY as string,
          balance: '10000000000000000000000',
        },
        {
          privateKey: process.env.ACCOUNT_3_PRIVATE_KEY as string,
          balance: '10000000000000000000000',
        },
        {
          privateKey: process.env.ACCOUNT_4_PRIVATE_KEY as string,
          balance: '10000000000000000000000',
        },
        {
          privateKey: process.env.ACCOUNT_5_PRIVATE_KEY as string,
          balance: '10000000000000000000000',
        },
        {
          privateKey: process.env.ACCOUNT_6_PRIVATE_KEY as string,
          balance: '10000000000000000000000',
        },
        {
          privateKey: process.env.ACCOUNT_7_PRIVATE_KEY as string,
          balance: '10000000000000000000000',
        },
        {
          privateKey: process.env.ACCOUNT_8_PRIVATE_KEY as string,
          balance: '10000000000000000000000',
        },
        {
          privateKey: process.env.ACCOUNT_9_PRIVATE_KEY as string,
          balance: '10000000000000000000000',
        },
        {
          privateKey: process.env.ACCOUNT_10_PRIVATE_KEY as string,
          balance: '10000000000000000000000',
        },
      ],
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY as string,
    customChains: [
      {
        chainId: 10,
        network: 'optimism',
        urls: {
          apiURL: 'https://api-optimistic.etherscan.io/api',
          browserURL: 'https://optimistic.etherscan.io',
        },
      },
      {
        chainId: 11155420,
        network: 'optimismSepolia',
        urls: {
          apiURL: 'https://api-sepolia-optimistic.etherscan.io/api',
          browserURL: 'https://optimistic-sepolia.etherscan.io',
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
