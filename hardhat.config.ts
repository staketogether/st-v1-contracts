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
    version: '0.8.20',
    overrides: {
      '*': {
        version: '0.8.20',
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
    goerli: {
      url: `https://eth-goerli.g.alchemy.com/v2/${process.env.ALCHEMY_GOERLI_API_KEY}`,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
      gasPrice: 4000000000,
    },
    localhost: {
      url: 'http://127.0.0.1:8545',
    },
    hardhat: {
      // forking: {
      //   url: `https://eth-goerli.g.alchemy.com/v2/${process.env.ALCHEMY_GOERLI_API_KEY}`
      // },
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
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 5,
    enabled: process.env.GAS_REPORTER === 'true' ? true : false,
    coinmarketcap: process.env.COINMARKETCAP_API_KEY as string,
  },
}

export default config
