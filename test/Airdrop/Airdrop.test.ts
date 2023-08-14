import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { upgrades } from 'hardhat'
import { Airdrop, MockAirdrop__factory, MockStakeTogether } from '../../typechain'
import connect from '../utils/connect'
import { airdropFixture } from './Airdrop.fixture'

dotenv.config()

describe('Airdrop', function () {
  let airdrop: Airdrop
  let airdropProxy: string
  let stakeTogether: MockStakeTogether
  let stakeTogetherProxy: string
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
    const fixture = await loadFixture(airdropFixture)
    airdrop = fixture.airdrop
    airdropProxy = fixture.airdropProxy
    stakeTogether = fixture.stakeTogether
    stakeTogetherProxy = fixture.stakeTogetherProxy
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
      expect(await airdrop.paused()).to.equal(false)

      // User without admin role tries to pause the contract - should fail
      await expect(connect(airdrop, user1).pause()).to.reverted

      // The owner pauses the contract
      await connect(airdrop, owner).pause()

      // Check if the contract is paused
      expect(await airdrop.paused()).to.equal(true)

      // User without admin role tries to unpause the contract - should fail
      await expect(connect(airdrop, user1).unpause()).to.reverted

      // The owner unpauses the contract
      await connect(airdrop, owner).unpause()
      // Check if the contract is not paused
      expect(await airdrop.paused()).to.equal(false)
    })

    it('should upgrade the contract if the user has upgrader role', async function () {
      expect(await airdrop.version()).to.equal(1n)

      const MockAirdrop = new MockAirdrop__factory(user1)

      // A user without the UPGRADER_ROLE tries to upgrade the contract - should fail
      await expect(upgrades.upgradeProxy(airdropProxy, MockAirdrop)).to.be.reverted

      const MockAirdropOwner = new MockAirdrop__factory(owner)

      // The owner (who has the UPGRADER_ROLE) upgrades the contract - should succeed
      const upgradedContract = await upgrades.upgradeProxy(airdropProxy, MockAirdropOwner)

      // Upgrade version
      await upgradedContract.initializeV2()

      expect(await upgradedContract.version()).to.equal(2n)
    })
  })

  it('should correctly set the StakeTogether address', async function () {
    // User1 tries to set the StakeTogether address to zero address - should fail
    await expect(connect(airdrop, owner).setStakeTogether(nullAddress)).to.be.reverted

    // User1 tries to set the StakeTogether address to their own address - should fail
    await expect(connect(airdrop, user1).setStakeTogether(user1.address)).to.be.reverted

    // Owner sets the StakeTogether address - should succeed
    await connect(airdrop, owner).setStakeTogether(user1.address)

    // Verify that the StakeTogether address was correctly set
    expect(await airdrop.stakeTogether()).to.equal(user1.address)
  })
})
