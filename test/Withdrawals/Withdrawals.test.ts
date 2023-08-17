import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers, upgrades } from 'hardhat'
import { MockStakeTogether, MockWithdrawals__factory, Withdrawals } from '../../typechain'
import connect from '../utils/connect'
import { withdrawalsFixture } from './Withdrawals.fixture'

dotenv.config()

describe('Withdrawals', function () {
  let withdrawals: Withdrawals
  let withdrawalsProxy: string
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
    const fixture = await loadFixture(withdrawalsFixture)
    withdrawals = fixture.withdrawals
    withdrawalsProxy = fixture.withdrawalsProxy
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
      expect(await withdrawals.paused()).to.equal(false)

      // User without admin role tries to pause the contract - should fail
      await expect(connect(withdrawals, user1).pause()).to.reverted

      // The owner pauses the contract
      await connect(withdrawals, owner).pause()

      // Check if the contract is paused
      expect(await withdrawals.paused()).to.equal(true)

      // User without admin role tries to unpause the contract - should fail
      await expect(connect(withdrawals, user1).unpause()).to.reverted

      // The owner unpauses the contract
      await connect(withdrawals, owner).unpause()
      // Check if the contract is not paused
      expect(await withdrawals.paused()).to.equal(false)
    })

    it('should upgrade the contract if the user has upgrader role', async function () {
      expect(await withdrawals.version()).to.equal(1n)

      const MockWithdrawals = new MockWithdrawals__factory(user1)

      // A user without the UPGRADER_ROLE tries to upgrade the contract - should fail
      await expect(upgrades.upgradeProxy(withdrawalsProxy, MockWithdrawals)).to.be.reverted

      const MockWithdrawalsOwner = new MockWithdrawals__factory(owner)

      // The owner (who has the UPGRADER_ROLE) upgrades the contract - should succeed
      const upgradedContract = await upgrades.upgradeProxy(withdrawalsProxy, MockWithdrawalsOwner)

      // Upgrade version
      await upgradedContract.initializeV2()

      expect(await upgradedContract.version()).to.equal(2n)
    })
  })

  it('should correctly set the StakeTogether address', async function () {
    // User1 tries to set the StakeTogether address to zero address - should fail
    await expect(connect(withdrawals, owner).setStakeTogether(nullAddress)).to.be.reverted

    // User1 tries to set the StakeTogether address to their own address - should fail
    await expect(connect(withdrawals, user1).setStakeTogether(user1.address)).to.be.reverted

    // Owner sets the StakeTogether address - should succeed
    await connect(withdrawals, owner).setStakeTogether(user1.address)

    // Verify that the StakeTogether address was correctly set
    expect(await withdrawals.stakeTogether()).to.equal(user1.address)
  })

  it.skip('should correctly receive Ether and transfer to StakeTogether via receive', async function () {
    // Set the StakeTogether address to user1
    await connect(withdrawals, owner).setStakeTogether(user1.address)

    const initBalance = await ethers.provider.getBalance(user1.address)

    // User2 sends 1 Ether to the contract's receive function
    const tx = await user2.sendTransaction({
      to: withdrawalsProxy,
      value: ethers.parseEther('1.0'),
    })

    // Simulate confirmation of the transaction
    await tx.wait()

    // Verify that the Ether was correctly transferred to user1 (StakeTogether)
    const finalBalance = await ethers.provider.getBalance(user1.address)
    expect(finalBalance).to.equal(initBalance + ethers.parseEther('1.0'))

    // Verify that the ReceiveEther event was emitted
    await expect(tx)
      .to.emit(withdrawals, 'ReceiveEther')
      .withArgs(user2.address, ethers.parseEther('1.0'))
  })
})
