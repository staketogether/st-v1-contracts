import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { getImplementationAddress } from '@openzeppelin/upgrades-core'
import { ethers, network, upgrades } from 'hardhat'
import {
  MockStakeTogether,
  MockStakeTogether__factory,
  Withdrawals,
  Withdrawals__factory,
} from '../../typechain'
import { checkVariables } from '../utils/env'

export async function withdrawalsFixture() {
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

  const WithdrawalsFactory = new Withdrawals__factory().connect(owner)

  const withdrawals = await upgrades.deployProxy(WithdrawalsFactory)
  await withdrawals.waitForDeployment()
  const withdrawalsProxy = await withdrawals.getAddress()
  const withdrawalsImplementation = await getImplementationAddress(network.provider, withdrawalsProxy)

  const withdrawalsContract = withdrawals as unknown as Withdrawals

  const MockStakeTogether = new MockStakeTogether__factory().connect(owner)
  const mockStakeTogether = await upgrades.deployProxy(MockStakeTogether)
  await mockStakeTogether.waitForDeployment()

  const stakeTogetherProxy = await mockStakeTogether.getAddress()
  const stakeTogetherImplementation = await getImplementationAddress(network.provider, stakeTogetherProxy)

  const stakeTogether = mockStakeTogether as unknown as MockStakeTogether

  const UPGRADER_ROLE = await withdrawalsContract.UPGRADER_ROLE()
  const ADMIN_ROLE = await withdrawalsContract.ADMIN_ROLE()

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
    withdrawals: withdrawalsContract,
    withdrawalsProxy,
    stakeTogether,
    stakeTogetherProxy,
    UPGRADER_ROLE,
    ADMIN_ROLE,
  }
}
