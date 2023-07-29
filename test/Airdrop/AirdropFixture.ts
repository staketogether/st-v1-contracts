import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import { ethers, network, upgrades } from 'hardhat'
import { Airdrop, Airdrop__factory, MockStakeTogether, MockStakeTogether__factory } from '../../typechain'
import { checkVariables } from '../utils/env'

export async function airdropFixture() {
  checkVariables()

  const provider = ethers.provider

  let owner: HardhatEthersSigner
  let user1: HardhatEthersSigner
  let user2: HardhatEthersSigner
  let user3: HardhatEthersSigner
  let user4: HardhatEthersSigner
  let user5: HardhatEthersSigner
  let user6: HardhatEthersSigner
  let user7: HardhatEthersSigner
  let user8: HardhatEthersSigner

  let nullAddress: string = '0x0000000000000000000000000000000000000000'

  ;[owner, user1, user2, user3, user4, user5, user6, user7, user8] = await ethers.getSigners()

  const AirdropFactory = new Airdrop__factory().connect(owner)
  const airdrop = await upgrades.deployProxy(AirdropFactory)
  await airdrop.waitForDeployment()
  const airdropProxy = await airdrop.getAddress()
  const airdropImplementation = await getImplementationAddress(network.provider, airdropProxy)

  const airdropContract = airdrop as unknown as Airdrop

  const MockStakeTogether = new MockStakeTogether__factory().connect(owner)
  const mockStakeTogether = await upgrades.deployProxy(MockStakeTogether)
  await mockStakeTogether.waitForDeployment()

  const stProxy = await mockStakeTogether.getAddress()
  const stImplementation = await getImplementationAddress(network.provider, stProxy)

  const stContract = mockStakeTogether as unknown as MockStakeTogether

  const UPGRADER_ROLE = await airdropContract.UPGRADER_ROLE()
  const ADMIN_ROLE = await airdropContract.ADMIN_ROLE()

  return {
    provider,
    owner,
    user1,
    user2,
    user3,
    user4,
    user5,
    user6,
    user7,
    user8,
    nullAddress,
    airdropContract,
    airdropProxy,
    stContract,
    stProxy,
    UPGRADER_ROLE,
    ADMIN_ROLE
  }
}
