import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import { ethers, network, upgrades } from 'hardhat'
import { ELAdapter, ELAdapter__factory } from '../../typechain'
import { checkGeneralVariables } from '../../utils/env'

export async function deploy() {
  checkGeneralVariables()
  const [owner] = await ethers.getSigners()

  const withdrawalsCredentials = process.env.ETH_SEPOLIA_WITHDRAWAL_ADDRESS as string
  const depositAddress = process.env.ETH_SEPOLIA_DEPOSIT_ADDRESS as string
  const bridgeAddress = process.env.ETH_SEPOLIA_BRIDGE_ADDRESS as string

  const { proxyAddress, implementationAddress } = await deployAdapter(
    owner,
    depositAddress,
    withdrawalsCredentials,
    bridgeAddress,
  )

  console.log('\n🔷EL Adapter Contracts Deployed!\n')

  verifyContracts(proxyAddress, implementationAddress)
}

async function deployAdapter(
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

  const adapterFactory = new ELAdapter__factory().connect(owner)

  const adapter = await upgrades.deployProxy(adapterFactory, [
    bridgeAddress,
    depositAddress,
    withdrawalsCredentialsAddress,
  ])

  await adapter.waitForDeployment()
  const proxyAddress = await adapter.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Adapter\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Adapter\t\t Implementation\t\t ${implementationAddress}`)

  const adapterContract = adapter as unknown as ELAdapter

  const ST_ADMIN_ROLE = await adapterContract.ADMIN_ROLE()
  await adapterContract.connect(owner).grantRole(ST_ADMIN_ROLE, owner)

  const ADA_ADMIN_ROLE = await adapterContract.ADMIN_ROLE()

  await adapterContract.connect(owner).grantRole(ADA_ADMIN_ROLE, owner)

  const config = {
    validatorSize: '32000000000000000000',
  }

  await adapterContract.connect(owner).setConfig(config, { gasLimit: 1000000 })

  return { proxyAddress, implementationAddress, adapterContract }
}

async function verifyContracts(adapterProxy: string, adapterImplementation: string) {
  console.log('\nRUN COMMAND TO VERIFY ON ETHERSCAN\n')

  console.log(`npx hardhat verify --network eth-sepolia ${adapterProxy} &&`)
  console.log(`npx hardhat verify --network eth-sepolia ${adapterImplementation}`)
}

deploy().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
