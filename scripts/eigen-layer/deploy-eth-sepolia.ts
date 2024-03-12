import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import * as dotenv from 'dotenv'
import { ethers, network, upgrades } from 'hardhat'
import { checkVariables } from '../../test/utils/env'
import { OptimismAdapter, OptimismAdapter__factory } from '../../typechain'

dotenv.config()

const depositAddress = String(process.env.SEPOLIA_DEPOSIT_ADDRESS)

export async function deploy() {
  checkVariables()

  const [owner] = await ethers.getSigners()

  const l2StakeTogetherAdapter = ''
  const withdrawalsCredentials = ''
  const bridgeAddress = ''
  const opAdapter = await deployOptimismAdapter(
    owner,
    l2StakeTogetherAdapter,
    depositAddress,
    bridgeAddress,
    withdrawalsCredentials,
  )

  // LOG
  console.log('\n🔷 All ST Contracts Deployed!\n')

  verifyContracts(
    opAdapter.proxyAddress,
    opAdapter.implementationAddress,
  )
}

export async function deployOptimismAdapter(
  owner: HardhatEthersSigner,
  l2StakeTogetherAddress: string,
  depositAddress: string,
  bridgeAddress: string,
  withdrawalsCredentialsAddress: string,
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

  const OptimismAdapterFactory = new OptimismAdapter__factory().connect(owner)

  const optimismAdapter = await upgrades.deployProxy(OptimismAdapterFactory, [
    l2StakeTogetherAddress,
    depositAddress,
    bridgeAddress,
    withdrawalsCredentialsAddress,
  ])

  await optimismAdapter.waitForDeployment()
  const proxyAddress = await optimismAdapter.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`StakeTogether\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`StakeTogether\t\t Implementation\t\t ${implementationAddress}`)

  const optimismAdapterContract = optimismAdapter as unknown as OptimismAdapter

  const ST_ADMIN_ROLE = await optimismAdapterContract.ADMIN_ROLE()
  await optimismAdapterContract.connect(owner).grantRole(ST_ADMIN_ROLE, owner)

  const config = {
    validatorSize: ethers.parseEther('32'),
  }

  await optimismAdapterContract.setConfig(config)

  return { proxyAddress, implementationAddress, stakeTogetherContract: optimismAdapterContract }
}

async function verifyContracts(
  airdropProxy: string,
  airdropImplementation: string,
) {
  console.log('\nRUN COMMAND TO VERIFY ON ETHERSCAN\n')

  console.log(`npx hardhat verify --network goerli ${airdropProxy} &&`)
  console.log(`npx hardhat verify --network goerli ${airdropImplementation} &&`)
}

deploy().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
