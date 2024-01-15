import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import { ethers, network, upgrades } from 'hardhat'
import { StakeTogetherV3__factory } from '../typechain'

const proxyAddress = '0xBD1C6935eaA5B6EaA8b88154b64acf081D2a2599'

async function upgrade() {
  const [owner] = await ethers.getSigners()

  const StakeTogether = new StakeTogetherV3__factory(owner)

  console.log(`Upgrading StakeTogetherV3...`)

  const upgradedContract = await upgrades.upgradeProxy(proxyAddress, StakeTogether, {
    redeployImplementation: 'always',
  })
  console.log(`Upgraded To StakeTogetherV3`)

  console.log('Initializing V3...')
  await upgradedContract.initializeV3()
  console.log('Initialized V3')

  console.log('Waiting Abi Propagate...')
  await new Promise((resolve) => setTimeout(resolve, 30000))

  console.log('Get Implementation for Verify... Double Check')
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`npx hardhat verify --network ${network.name} ${implementationAddress}`)
}

upgrade()
