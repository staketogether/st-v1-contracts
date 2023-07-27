import { ethers, network, upgrades } from 'hardhat'

import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import { Fees, Fees__factory } from '../../typechain'
import { checkVariables } from '../utils/env'

export async function feesFixture() {
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

  const FeesFactory = new Fees__factory().connect(owner)
  const fees = await upgrades.deployProxy(FeesFactory)
  await fees.waitForDeployment()

  const feesProxy = await fees.getAddress()
  const feesImplementation = await getImplementationAddress(network.provider, feesProxy)

  const feesContract = fees as unknown as Fees

  const UPGRADER_ROLE = await feesContract.UPGRADER_ROLE()
  const ADMIN_ROLE = await feesContract.ADMIN_ROLE()

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
    feesContract,
    feesProxy,
    UPGRADER_ROLE,
    ADMIN_ROLE
  }
}
