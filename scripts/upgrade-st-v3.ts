import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import { ethers, network, upgrades } from 'hardhat'
import { StakeTogetherV3__factory } from '../typechain'

const proxyAddress = '0x218dE5E6324c5351C3a2bf0c40d76f585B8dE04d'

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
