import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers, upgrades } from 'hardhat'
import {
  MockStakeTogether,
  MockStakeTogetherWrapper__factory,
  StakeTogether,
  StakeTogetherWrapper,
} from '../../typechain'
import connect from '../utils/connect'
import { stakeTogetherWrapperFixture } from './StakeTogetherWrapper.fixture'

dotenv.config()

describe('StakeTogetherWrapper', function () {
  let stakeTogetherWrapper: StakeTogetherWrapper
  let stakeTogetherWrapperProxy: string
  let stakeTogether: StakeTogether
  let stakeTogetherProxy: string
  let mockStakeTogether: MockStakeTogether
  let mockStakeTogetherProxy: string
  let owner: HardhatEthersSigner
  let user1: HardhatEthersSigner
  let user2: HardhatEthersSigner
  let user3: HardhatEthersSigner
  let user4: HardhatEthersSigner
  let user5: HardhatEthersSigner
  let user6: HardhatEthersSigner
  let user7: HardhatEthersSigner
  let user8: HardhatEthersSigner
  let nullAddress: string
  let ADMIN_ROLE: string

  // Setting up the fixture before each test
  beforeEach(async function () {
    const fixture = await loadFixture(stakeTogetherWrapperFixture)
    stakeTogetherWrapper = fixture.stakeTogetherWrapper
    stakeTogetherWrapperProxy = fixture.stakeTogetherWrapperProxy
    stakeTogether = fixture.stakeTogether
    stakeTogetherProxy = fixture.stakeTogetherProxy
    mockStakeTogether = fixture.mockStakeTogether
    mockStakeTogetherProxy = fixture.mockStakeTogetherProxy
    owner = fixture.owner
    user1 = fixture.user1
    user2 = fixture.user2
    user3 = fixture.user3
    user4 = fixture.user4
    user5 = fixture.user5
    user6 = fixture.user6
    user7 = fixture.user7
    user8 = fixture.user8
    nullAddress = fixture.nullAddress
    ADMIN_ROLE = fixture.ADMIN_ROLE
  })

  describe('Upgrade', () => {
    // Test to check if pause and unpause functions work properly
    it('should pause and unpause the contract if the user has admin role', async function () {
      // Check if the contract is not paused at the beginning
      expect(await stakeTogetherWrapper.paused()).to.equal(false)

      // User without admin role tries to pause the contract - should fail
      await expect(connect(stakeTogetherWrapper, user1).pause()).to.reverted

      // The owner pauses the contract
      await connect(stakeTogetherWrapper, owner).pause()

      // Check if the contract is paused
      expect(await stakeTogetherWrapper.paused()).to.equal(true)

      // User without admin role tries to unpause the contract - should fail
      await expect(connect(stakeTogetherWrapper, user1).unpause()).to.reverted

      // The owner unpauses the contract
      await connect(stakeTogetherWrapper, owner).unpause()
      // Check if the contract is not paused
      expect(await stakeTogetherWrapper.paused()).to.equal(false)
    })

    it('should upgrade the contract if the user has upgrader role', async function () {
      expect(await stakeTogetherWrapper.version()).to.equal(1n)

      const MockStakeTogetherWrapper = new MockStakeTogetherWrapper__factory(user1)

      // A user without the UPGRADER_ROLE tries to upgrade the contract - should fail
      await expect(upgrades.upgradeProxy(stakeTogetherWrapperProxy, MockStakeTogetherWrapper)).to.be
        .reverted

      const MockStakeTogetherWrapperOwner = new MockStakeTogetherWrapper__factory(owner)

      // The owner (who has the UPGRADER_ROLE) upgrades the contract - should succeed
      const upgradedContract = await upgrades.upgradeProxy(
        stakeTogetherWrapperProxy,
        MockStakeTogetherWrapperOwner,
      )

      // Upgrade version
      await upgradedContract.initializeV2()

      expect(await upgradedContract.version()).to.equal(2n)
    })
  })

  it('should correctly set the StakeTogether address', async function () {
    // Verify that the StakeTogether address was correctly set
    expect(await stakeTogetherWrapper.stakeTogether()).to.equal(await stakeTogether.getAddress())
  })

  describe('Receive Ether', function () {
    it('should correctly receive Ether', async function () {
      const initBalance = await ethers.provider.getBalance(stakeTogetherWrapperProxy)

      const tx = await user1.sendTransaction({
        to: stakeTogetherWrapperProxy,
        value: ethers.parseEther('1.0'),
      })

      await tx.wait()

      const finalBalance = await ethers.provider.getBalance(stakeTogetherWrapperProxy)
      expect(finalBalance).to.equal(initBalance + ethers.parseEther('1.0'))

      await expect(tx).to.emit(stakeTogetherWrapper, 'ReceiveEther').withArgs(ethers.parseEther('1.0'))
    })
  })
})
