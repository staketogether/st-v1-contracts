import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { ethers, network, upgrades } from 'hardhat'

import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import { Fees, Fees__factory } from '../../typechain'
import { checkVariables } from '../utils/env'

export async function feesFixture() {
  checkVariables()

  const provider = ethers.provider

  let owner: SignerWithAddress
  let user1: SignerWithAddress
  let user2: SignerWithAddress
  let user3: SignerWithAddress
  let user4: SignerWithAddress
  let user5: SignerWithAddress
  let user6: SignerWithAddress
  let user7: SignerWithAddress
  let user8: SignerWithAddress
  let user9: SignerWithAddress

  let nullAddress: string = '0x0000000000000000000000000000000000000000'

  ;[owner, user1, user2, user3, user4, user5, user6, user7, user8, user9] = await ethers.getSigners()

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
    nullAddress,
    feesContract,
    UPGRADER_ROLE,
    ADMIN_ROLE
  }
}
