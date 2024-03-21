import { ethers, network, upgrades } from 'hardhat'
import { checkGeneralVariables } from '../../test/utils/env'
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import { Adapter } from '../../typechain/contracts/eigen-layer'
import { Adapter__factory } from '../../typechain/factories/contracts/eigen-layer'

export async function deploy() {
  checkDeployVariables()
  const [owner] = await ethers.getSigners()

  const withdrawalsCredentials = process.env.SEPOLIA_WITHDRAWAL_ADDRESS as string
  const depositAddress = process.env.SEPOLIA_DEPOSIT_ADDRESS as string
  const bridgeAddress = process.env.SEPOLIA_BRIDGE_ADDRESS as string

  const { proxyAddress, implementationAddress } = await deployEthereumAdapter(owner, depositAddress, withdrawalsCredentials, bridgeAddress)

  console.log('\n🔷 All ST Contracts Deployed!\n')

  verifyContracts(
    proxyAddress,
    implementationAddress,
  )
}

async function deployEthereumAdapter(
  owner: HardhatEthersSigner,
  depositAddress: string,
  withdrawalsCredentialsAddress: string,
  bridgeAddress: string,
) {
  function convertToWithdrawalAddress(eth1Address: string): string {
    if (!ethers.isAddress(eth1Address)) {
      throw new Error('Invalid ETH1 address format.')
    }

    const address = eth1Address.startsWith('0x') ? eth1Address.slice(2) : eth1Address
    const paddedAddress = address.padStart(62, '0')
    return '0x01' + paddedAddress
  }

  const withdrawalsCredentials = convertToWithdrawalAddress(withdrawalsCredentialsAddress)

  if (withdrawalsCredentials.length !== 66) {
    throw new Error('Withdrawals credentials are not the correct length')
  }

  const OptimismAdapterFactory = new Adapter__factory().connect(owner)

  const optimismAdapter = await upgrades.deployProxy(OptimismAdapterFactory, [
    bridgeAddress,
    depositAddress,
    withdrawalsCredentialsAddress,
  ])

  await optimismAdapter.waitForDeployment()
  const proxyAddress = await optimismAdapter.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Adapter\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Adapter\t\t Implementation\t\t ${implementationAddress}`)

  const optimismAdapterContract = optimismAdapter as unknown as Adapter

  const ST_ADMIN_ROLE = await optimismAdapterContract.ADMIN_ROLE()
  await optimismAdapterContract.connect(owner).grantRole(ST_ADMIN_ROLE, owner)

  const config = {
    validatorSize: ethers.parseEther('32'),
  }

  await optimismAdapterContract.setConfig(config)

  return { proxyAddress, implementationAddress, adapterContract: optimismAdapterContract }
}

async function verifyContracts(
  adapterProxy: string,
  adapterImplementation: string,
) {
  console.log('\nRUN COMMAND TO VERIFY ON ETHERSCAN\n')

  console.log(`npx hardhat verify --network sepolia ${adapterProxy} &&`)
  console.log(`npx hardhat verify --network sepolia ${adapterImplementation} &&`)
}

function checkDeployVariables() {
  checkGeneralVariables()
  const missingVariables = []

  if (!process.env.SEPOLIA_WITHDRAWAL_ADDRESS) missingVariables.push('SEPOLIA_WITHDRAWAL_ADDRESS')
  if (!process.env.SEPOLIA_DEPOSIT_ADDRESS) missingVariables.push('SEPOLIA_DEPOSIT_ADDRESS')
  if (!process.env.SEPOLIA_BRIDGE_ADDRESS) missingVariables.push('SEPOLIA_BRIDGE_ADDRESS')

  if (missingVariables.length > 0) {
    throw new Error(`Missing environment variables: ${missingVariables.join(', ')}`)
  }
}