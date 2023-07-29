import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers, upgrades } from 'hardhat'
import { MockStakeTogether, MockWithdrawals__factory, Withdrawals } from '../../typechain'
import connect from '../utils/connect'
import { withdrawalsFixture } from './WithdrawalsFixture'

dotenv.config()

describe.only('Withdrawals', function () {
  let withdrawalsContract: Withdrawals
  let withdrawalsProxy: string
  let stContract: MockStakeTogether
  let stProxy: string
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
  let feeAddresses: string[]

  // Setting up the fixture before each test
  beforeEach(async function () {
    const fixture = await loadFixture(withdrawalsFixture)
    withdrawalsContract = fixture.withdrawalsContract
    withdrawalsProxy = fixture.withdrawalsProxy
    stContract = fixture.stContract
    stProxy = fixture.stProxy
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

    feeAddresses = [
      user1.address, // StakeAccounts
      user2.address, // LockAccounts
      user3.address, // Pools
      user4.address, // Operators
      user5.address, // Oracles
      user6.address, // StakeTogether
      user7.address, // LiquidityProviders
      owner.address // Sender
    ]
  })

  // Test to check if pause and unpause functions work properly
  it('should pause and unpause the contract if the user has admin role', async function () {
    // Check if the contract is not paused at the beginning
    expect(await withdrawalsContract.paused()).to.equal(false)

    // User without admin role tries to pause the contract - should fail
    await expect(connect(withdrawalsContract, user1).pause()).to.reverted

    // The owner pauses the contract
    await connect(withdrawalsContract, owner).pause()

    // Check if the contract is paused
    expect(await withdrawalsContract.paused()).to.equal(true)

    // User without admin role tries to unpause the contract - should fail
    await expect(connect(withdrawalsContract, user1).unpause()).to.reverted

    // The owner unpauses the contract
    await connect(withdrawalsContract, owner).unpause()
    // Check if the contract is not paused
    expect(await withdrawalsContract.paused()).to.equal(false)
  })

  it('should upgrade the contract if the user has upgrader role', async function () {
    expect(await withdrawalsContract.version()).to.equal(1n)

    const MockWithdrawals = new MockWithdrawals__factory(user1)

    // A user without the UPGRADER_ROLE tries to upgrade the contract - should fail
    await expect(upgrades.upgradeProxy(withdrawalsProxy, MockWithdrawals)).to.be.reverted

    const MockFeesOwner = new MockWithdrawals__factory(owner)

    // The owner (who has the UPGRADER_ROLE) upgrades the contract - should succeed
    const upgradedFeesContract = await upgrades.upgradeProxy(withdrawalsProxy, MockFeesOwner)

    // Upgrade version
    await upgradedFeesContract.initializeV2()

    expect(await upgradedFeesContract.version()).to.equal(2n)
  })

  it('should correctly set the StakeTogether address', async function () {
    // User1 tries to set the StakeTogether address to zero address - should fail
    await expect(connect(withdrawalsContract, owner).setStakeTogether(nullAddress)).to.be.reverted

    // User1 tries to set the StakeTogether address to their own address - should fail
    await expect(connect(withdrawalsContract, user1).setStakeTogether(user1.address)).to.be.reverted

    // Owner sets the StakeTogether address - should succeed
    await connect(withdrawalsContract, owner).setStakeTogether(user1.address)

    // Verify that the StakeTogether address was correctly set
    expect(await withdrawalsContract.stakeTogether()).to.equal(user1.address)
  })

  it('should correctly receive Ether and transfer to StakeTogether via receive', async function () {
    // Set the StakeTogether address to user1
    await connect(withdrawalsContract, owner).setStakeTogether(user1.address)

    const initBalance = await ethers.provider.getBalance(user1.address)

    // User2 sends 1 Ether to the contract's receive function
    const tx = await user2.sendTransaction({
      to: withdrawalsProxy,
      value: ethers.parseEther('1.0')
    })

    // Simulate confirmation of the transaction
    await tx.wait()

    // Verify that the Ether was correctly transferred to user1 (StakeTogether)
    const finalBalance = await ethers.provider.getBalance(user1.address)
    expect(finalBalance).to.equal(initBalance + ethers.parseEther('1.0'))

    // Verify that the ReceiveEther event was emitted
    await expect(tx)
      .to.emit(withdrawalsContract, 'ReceiveEther')
      .withArgs(user2.address, ethers.parseEther('1.0'))
  })
})
