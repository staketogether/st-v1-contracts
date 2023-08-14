import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers, upgrades } from 'hardhat'
import { MockStakeTogether, MockStakeTogether__factory, StakeTogether } from '../../typechain'
import connect from '../utils/connect'
import { stakeTogetherFixture } from './StakeTogether.fixture'

dotenv.config()

describe('Stake Together', function () {
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
    const fixture = await loadFixture(stakeTogetherFixture)
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
      expect(await stakeTogether.paused()).to.equal(false)

      // User without admin role tries to pause the contract - should fail
      await expect(connect(stakeTogether, user1).pause()).to.reverted

      // The owner pauses the contract
      await connect(stakeTogether, owner).pause()

      // Check if the contract is paused
      expect(await stakeTogether.paused()).to.equal(true)

      // User without admin role tries to unpause the contract - should fail
      await expect(connect(stakeTogether, user1).unpause()).to.reverted

      // The owner unpauses the contract
      await connect(stakeTogether, owner).unpause()
      // Check if the contract is not paused
      expect(await stakeTogether.paused()).to.equal(false)
    })

    it('should upgrade the contract if the user has upgrader role', async function () {
      expect(await stakeTogether.version()).to.equal(1n)

      const MockStakeTogether = new MockStakeTogether__factory(user1)

      // A user without the UPGRADER_ROLE tries to upgrade the contract - should fail
      await expect(upgrades.upgradeProxy(stakeTogetherProxy, MockStakeTogether)).to.be.reverted

      const MockWithdrawalsOwner = new MockStakeTogether__factory(owner)

      // The owner (who has the UPGRADER_ROLE) upgrades the contract - should succeed
      const upgradedFeesContract = await upgrades.upgradeProxy(stakeTogetherProxy, MockWithdrawalsOwner)

      // Upgrade version
      await upgradedFeesContract.initializeV2()

      expect(await upgradedFeesContract.version()).to.equal(2n)
    })
  })

  it('should correctly receive Ether', async function () {
    const initBalance = await ethers.provider.getBalance(stakeTogetherProxy)

    const tx = await user1.sendTransaction({
      to: stakeTogetherProxy,
      value: ethers.parseEther('1.0'),
    })

    await tx.wait()

    const finalBalance = await ethers.provider.getBalance(stakeTogetherProxy)
    expect(finalBalance).to.equal(initBalance + ethers.parseEther('1.0'))

    await expect(tx)
      .to.emit(stakeTogether, 'ReceiveEther')
      .withArgs(user1.address, ethers.parseEther('1.0'))
  })

  describe('Set Configuration', function () {
    it('should allow owner to set configuration', async function () {
      const config = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('32'),
        minDepositAmount: ethers.parseEther('0.1'), // Changing to a new value
        depositLimit: ethers.parseEther('1000'),
        withdrawalLimit: ethers.parseEther('1000'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        feature: {
          AddPool: true,
          Deposit: true,
          WithdrawPool: true,
          WithdrawValidator: true,
        },
      }

      // Set config by owner
      await connect(stakeTogether, owner).setConfig(config)

      // Verify if the configuration was changed correctly
      const updatedConfig = await stakeTogether.config()
      expect(updatedConfig.minDepositAmount).to.equal(config.minDepositAmount)
    })
    it('should not allow non-owner to set configuration', async function () {
      const config = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('32'),
        minDepositAmount: ethers.parseEther('0.1'),
        depositLimit: ethers.parseEther('1000'),
        withdrawalLimit: ethers.parseEther('1000'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        feature: {
          AddPool: true,
          Deposit: true,
          WithdrawPool: true,
          WithdrawValidator: true,
        },
      }

      // Attempt to set config by non-owner should fail
      await expect(connect(stakeTogether, user1).setConfig(config)).to.be.reverted
    })

    it('should revert if poolSize is less than validatorSize', async function () {
      const invalidConfig = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('31'),
        minDepositAmount: ethers.parseEther('0.001'),
        depositLimit: ethers.parseEther('1000'),
        withdrawalLimit: ethers.parseEther('1000'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        feature: {
          AddPool: true,
          Deposit: true,
          WithdrawPool: true,
          WithdrawValidator: true,
        },
      }

      // Attempt to set config by owner should fail
      await expect(stakeTogether.setConfig(invalidConfig)).to.be.revertedWith('IS')
    })
  })

  describe('Deposit', function () {
    it('should correctly calculate balance and beaconBalance', async function () {
      const initialContractBalance = await ethers.provider.getBalance(stakeTogetherProxy)

      const initialBeaconBalance = await stakeTogether.beaconBalance()

      const depositAmount = ethers.parseEther('1.0')
      await user1.sendTransaction({
        to: stakeTogetherProxy,
        value: depositAmount,
      })

      const expectedTotalSupply = initialContractBalance + depositAmount + initialBeaconBalance

      const totalSupply = await stakeTogether.totalSupply()

      expect(totalSupply).to.equal(expectedTotalSupply)
    })

    it('should correctly handle deposit', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee

      const user1Delegations = [{ pool: poolAddress, shares: user1Shares }]

      const tx1 = await stakeTogether
        .connect(user1)
        .depositPool(user1Delegations, user3, { value: user1DepositAmount })
      await tx1.wait()

      let eventFilter = stakeTogether.filters.UpdateDelegations(user1.address)
      let logs = await stakeTogether.queryFilter(eventFilter)

      let event = logs[0]
      const [emittedAddress1, emittedDelegations1] = event.args
      expect(emittedAddress1).to.equal(user1.address)
      expect(emittedDelegations1[0].pool).to.equal(user1Delegations[0].pool)
      expect(emittedDelegations1[0].shares).to.equal(user1Delegations[0].shares)
    })

    it('should revert due to wrong shares value (without fee)', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const user1Shares = user1DepositAmount

      const user1Delegations = [{ pool: poolAddress, shares: user1Shares }]

      await expect(
        stakeTogether.connect(user1).depositPool(user1Delegations, user3, { value: user1DepositAmount }),
      ).to.be.revertedWith('IS')
    })

    it('should revert if deposit feature is disabled', async function () {
      const config = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('32'),
        minDepositAmount: ethers.parseEther('0.001'),
        depositLimit: ethers.parseEther('1000'),
        withdrawalLimit: ethers.parseEther('1000'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        feature: {
          AddPool: true,
          Deposit: false,
          WithdrawPool: true,
          WithdrawValidator: true,
        },
      }

      await connect(stakeTogether, owner).setConfig(config)

      const user1DepositAmount = ethers.parseEther('100')
      const nonExistentPoolAddress = nullAddress
      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee

      const user1Delegations = [{ pool: nonExistentPoolAddress, shares: user1Shares }]

      await expect(
        stakeTogether
          .connect(user1)
          .depositPool(user1Delegations, user3, { value: ethers.parseEther('100') }),
      ).to.be.revertedWith('FD')
    })

    it('should revert if deposit address is zero', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const nonExistentPoolAddress = nullAddress

      await expect(
        stakeTogether
          .connect(user1)
          .depositDonationPool(nonExistentPoolAddress, user3, { value: user1DepositAmount }),
      ).to.be.revertedWith('ZA')
    })

    it('should fail when trying to delegate to a non-existent pool', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const nonExistentPoolAddress = nullAddress
      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee

      const user1Delegations = [{ pool: nonExistentPoolAddress, shares: user1Shares }]

      await expect(
        stakeTogether.connect(user1).depositPool(user1Delegations, user3, { value: user1DepositAmount }),
      ).to.be.revertedWith('NF')
    })

    it('should fail when total delegation shares do not match user shares', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)
      const fee = (user1DepositAmount * 3n) / 1000n
      const incorrectShares = user1DepositAmount - fee + 1n

      const user1Delegations = [{ pool: poolAddress, shares: incorrectShares }]

      await expect(
        stakeTogether.connect(user1).depositPool(user1Delegations, user3, { value: user1DepositAmount }),
      ).to.be.revertedWith('IS')
    })

    it('should fail when the number of delegations is greater than maxDelegations', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const maxDelegations = 64
      const user1Delegations = Array(maxDelegations + 1).fill({ pool: poolAddress, shares: 1 })

      await expect(
        stakeTogether.connect(user1).depositPool(user1Delegations, user3, { value: user1DepositAmount }),
      ).to.be.revertedWith('MD')
    })

    it('should fail when a delegation has zero shares', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const user1Delegations = [{ pool: poolAddress, shares: 0 }]

      await expect(
        stakeTogether.connect(user1).depositPool(user1Delegations, user3, { value: user1DepositAmount }),
      ).to.be.revertedWith('ZS')
    })

    it('should correctly transfer delegations to another pool', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress1 = user3.address
      const poolAddress2 = user4.address

      await stakeTogether.connect(owner).addPool(poolAddress1, true)
      await stakeTogether.connect(owner).addPool(poolAddress2, true)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee

      const user1Delegations = [{ pool: poolAddress1, shares: user1Shares }]

      await stakeTogether
        .connect(user1)
        .depositPool(user1Delegations, user3, { value: user1DepositAmount })

      const updatedDelegations = [{ pool: poolAddress2, shares: user1Shares }]
      await stakeTogether.connect(user1).updateDelegations(updatedDelegations)

      const user1Filter = stakeTogether.filters.UpdateDelegations(user1.address)

      const user1Logs = await stakeTogether.queryFilter(user1Filter)

      expect(user1Logs.length).to.equal(2)

      expect(user1Logs[1].args[1][0][0]).to.equal(poolAddress2)
    })
  })

  describe('Fees', function () {
    it('should correctly distribute the fee among roles and mint shares accordingly', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee

      const user1Delegations = [{ pool: poolAddress, shares: user1Shares }]

      await stakeTogether
        .connect(user1)
        .depositPool(user1Delegations, user3, { value: user1DepositAmount })

      const totalShares = await stakeTogether.totalShares()
      expect(totalShares).to.equal(user1DepositAmount + 1n)

      const airdropAddress = await stakeTogether.getFeeAddress(0)
      const stakeTogetherAddress = await stakeTogether.getFeeAddress(2)

      const airdropFilter = stakeTogether.filters.MintShares(airdropAddress)
      const stakeTogetherFilter = stakeTogether.filters.MintShares(stakeTogetherAddress)
      const user1Filter = stakeTogether.filters.MintShares(user1.address)

      const airdropLogs = await stakeTogether.queryFilter(airdropFilter)
      const stakeTogetherLogs = await stakeTogether.queryFilter(stakeTogetherFilter)
      const user1Logs = await stakeTogether.queryFilter(user1Filter)

      expect(airdropLogs.length).to.equal(1)
      expect(stakeTogetherLogs.length).to.equal(1)
      expect(user1Logs.length).to.equal(1)

      expect(airdropLogs[0].args[1]).to.equal((fee * 60n) / 100n)
      expect(stakeTogetherLogs[0].args[1]).to.equal((fee * 40n) / 100n)
      expect(user1Logs[0].args[1]).to.equal(user1Shares)
    })
  })
})
