import { CustomEthersSigner, SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import { ethers, network, upgrades } from 'hardhat'
import { Airdrop__factory, Airdrop } from '../../typechain'

export async function airdropFixture() {
  const provider = ethers.provider

  let owner: SignerWithAddress
  let user1: SignerWithAddress
  let user2: SignerWithAddress
  let nullAddress: string = '0x0000000000000000000000000000000000000000'

  ;[owner, user1, user2] = await ethers.getSigners()

  const Airdrop = await deployAirdrop(owner)

  return {
    provider,
    owner,
    user1,
    user2,
    nullAddress,
    Airdrop
  }
}

async function deployAirdrop(owner: CustomEthersSigner) {
  const AirdropFactory = new Airdrop__factory().connect(owner)
  const airdrop = await upgrades.deployProxy(AirdropFactory)
  await airdrop.waitForDeployment()
  const proxyAddress = await airdrop.getAddress()
  const implementationAddress = await getImplementationAddress(network.provider, proxyAddress)

  console.log(`Airdrop\t\t Proxy\t\t\t ${proxyAddress}`)
  console.log(`Airdrop\t\t Implementation\t\t ${implementationAddress}`)

  const airdropContract = airdrop as unknown as Airdrop

  await airdropContract.setMaxBatchSize(100)

  return { proxyAddress, implementationAddress, contract: airdropContract }
}
