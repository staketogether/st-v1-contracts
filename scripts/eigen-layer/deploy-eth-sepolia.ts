import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import * as dotenv from 'dotenv'
import { checkVariables } from '../../test/utils/env'
import { Adapter, Adapter__factory } from '../../typechain'
import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

dotenv.config()

const deployEthSepolia = task("deploy-eth-sepolia", "Deploys and configures the Adapter's contract")
  .setAction(async (taskArgs, hre) => {
    const withdrawalsCredentials = process.env.SEPOLIA_WITHDRAWAL_ADDRESS as string
    const bridgeAddress = process.env.ETH_SEPOLIA_BRIDGE_ADDRESS as string
    const depositAddress = process.env.SEPOLIA_DEPOSIT_ADDRESS as string

    checkVariables()
    const { ethers } = hre

    const [owner] = await ethers.getSigners()

    const opAdapter = await deployEthereumAdapter(
      owner,
      depositAddress,
      bridgeAddress,
      withdrawalsCredentials,
      hre
    )

    // LOG
    console.log('\n🔷 All Ethereum Deployed!\n')
    await verifyContracts(
      opAdapter.proxyAddress,
      opAdapter.implementationAddress,
    )

    return {
      opAdapter
    }
  });

async function deployEthereumAdapter(
  owner: HardhatEthersSigner,
  depositAddress: string,
  bridgeAddress: string,
  withdrawalsCredentialsAddress: string,
  hre: HardhatRuntimeEnvironment
) {
  const { ethers, upgrades, network } = hre
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
    depositAddress,
    bridgeAddress,
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
  airdropProxy: string,
  airdropImplementation: string,
) {
  console.log('\nRUN COMMAND TO VERIFY ON ETHERSCAN\n')

  console.log(`npx hardhat verify --network sepolia ${airdropProxy} &&`)
  console.log(`npx hardhat verify --network sepolia ${airdropImplementation} &&`)
}

export default deployEthSepolia
