import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers, network, upgrades } from 'hardhat'
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
  let VALIDATOR_ORACLE_MANAGER_ROLE: string
  let VALIDATOR_ORACLE_ROLE: string

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
    VALIDATOR_ORACLE_MANAGER_ROLE = fixture.VALIDATOR_ORACLE_MANAGER_ROLE
    VALIDATOR_ORACLE_ROLE = fixture.VALIDATOR_ORACLE_ROLE
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

  describe('Rewards', () => {
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

    it('should distribute profit equally among three depositors', async function () {
      const depositAmount = ethers.parseEther('1')
      const poolAddress = user3.address // Example pool address

      // Adding the pool
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      // Three users depositing 1 Ether each
      const users = [user1, user2, user3]
      let totalFees = 0n
      const userBalancesBefore = []
      for (const user of users) {
        const fee = (depositAmount * 3n) / 1000n
        totalFees += fee
        const shares = depositAmount - fee
        userBalancesBefore.push(shares)
        const delegations = [{ pool: poolAddress, shares: shares }]
        await stakeTogether.connect(user).depositPool(delegations, nullAddress, { value: depositAmount })
      }

      const prevContractBalance = await ethers.provider.getBalance(stakeTogetherProxy)
      expect(prevContractBalance).to.equal(ethers.parseEther('3') + 1n) // contract init with 1n

      // Sending 1 Ether profit to the contract
      await owner.sendTransaction({ to: stakeTogetherProxy, value: ethers.parseEther('1') })

      // Simulating how the profit should be distributed
      const totalProfit = ethers.parseEther('1') - totalFees / 3n
      const profitPerUserBase = totalProfit / BigInt(users.length)
      const hasRemainder = totalProfit % BigInt(users.length) > 0n
      const profitPerUser = hasRemainder ? profitPerUserBase + 1n : profitPerUserBase

      // Checking the balance of each user
      for (let i = 0; i < users.length; i++) {
        const expectedBalance = userBalancesBefore[i] + profitPerUser
        const actualBalance = await stakeTogether.balanceOf(users[i].address)
        expect(actualBalance).to.be.equal(expectedBalance)
      }

      // Total balance in the contract should be 4 Ether + total fees
      const totalContractBalance = await ethers.provider.getBalance(stakeTogetherProxy)
      expect(totalContractBalance).to.equal(ethers.parseEther('4') + 1n) // contract init with 1n
    })

    it('should distribute profit equally among two depositors', async function () {
      const depositAmount = ethers.parseEther('1')
      const poolAddress = user3.address // Example pool address

      // Adding the pool
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      // Two users depositing 1 Ether each
      const users = [user1, user2]
      let totalFees = 0n
      const userBalancesBefore = []
      for (const user of users) {
        const fee = (depositAmount * 3n) / 1000n
        totalFees += fee
        const shares = depositAmount - fee
        userBalancesBefore.push(shares)
        const delegations = [{ pool: poolAddress, shares: shares }]
        await stakeTogether.connect(user).depositPool(delegations, nullAddress, { value: depositAmount })
      }

      const prevContractBalance = await ethers.provider.getBalance(stakeTogetherProxy)
      expect(prevContractBalance).to.equal(ethers.parseEther('2') + 1n) // contract init with 1n

      // Sending 1 Ether profit to the contract
      await owner.sendTransaction({ to: stakeTogetherProxy, value: ethers.parseEther('1') })

      // Simulating how the profit should be distributed
      const totalProfit = ethers.parseEther('1') - totalFees / 2n
      const profitPerUserBase = totalProfit / BigInt(users.length)
      const hasRemainder = totalProfit % BigInt(users.length) > 0n
      const profitPerUser = hasRemainder ? profitPerUserBase + 1n : profitPerUserBase

      // Checking the balance of each user
      for (let i = 0; i < users.length; i++) {
        const expectedBalance = userBalancesBefore[i] + profitPerUser
        const actualBalance = await stakeTogether.balanceOf(users[i].address)
        expect(actualBalance).to.be.equal(expectedBalance)
      }

      // Total balance in the contract should be 3 Ether + total fees
      const totalContractBalance = await ethers.provider.getBalance(stakeTogetherProxy)
      expect(totalContractBalance).to.equal(ethers.parseEther('3') + 1n) // contract init with 1n
    })
  })

  describe('Set Configuration', function () {
    it('should allow owner to set configuration', async function () {
      const config = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('32'),
        minDepositAmount: ethers.parseEther('0.1'), // Changing to a new value
        minWithdrawAmount: ethers.parseEther('0.0001'),
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
        minWithdrawAmount: ethers.parseEther('0.0001'),
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
        minWithdrawAmount: ethers.parseEther('0.0001'),
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
    it('should correctly handle deposit and update delegations for Pool type', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee

      const user1Delegations = [{ pool: poolAddress, shares: user1Shares }]

      const tx1 = await stakeTogether
        .connect(user1)
        .depositPool(user1Delegations, referral, { value: user1DepositAmount })
      await tx1.wait()

      let eventFilter = stakeTogether.filters.UpdateDelegations(user1.address)
      let logs = await stakeTogether.queryFilter(eventFilter)

      let event = logs[0]
      const [emittedAddress1, emittedDelegations1] = event.args

      expect(emittedAddress1).to.equal(user1.address)
      expect(emittedDelegations1[0].pool).to.equal(user1Delegations[0].pool)
      expect(emittedDelegations1[0].shares).to.equal(user1Delegations[0].shares)

      eventFilter = stakeTogether.filters.DepositBase(user1.address, undefined, undefined)
      logs = await stakeTogether.queryFilter(eventFilter)

      event = logs[0]
      const [_to, _value, _type, _referral] = event.args
      expect(_to).to.equal(user1.address)
      expect(_value).to.equal(user1DepositAmount)
      expect(_type).to.equal(1)
      expect(_referral).to.equal(referral)

      const expectedBalance = await stakeTogether.weiByShares(user1Shares)
      const actualBalance = await stakeTogether.balanceOf(user1.address)
      expect(actualBalance).to.equal(expectedBalance)

      const calculatedShares = await stakeTogether.sharesByWei(user1DepositAmount - fee)
      expect(calculatedShares).to.equal(user1Shares)
    })

    it('should correctly handle deposit donation', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const toAddress = user2.address
      const referral = user4.address

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee

      const tx = await stakeTogether
        .connect(user1)
        .depositDonation(toAddress, referral, { value: user1DepositAmount })
      await tx.wait()

      let eventFilter = stakeTogether.filters.DepositBase(toAddress, undefined, undefined, undefined)
      let logs = await stakeTogether.queryFilter(eventFilter)

      let event = logs[0]
      const [_to, _value, _type, _referral] = event.args
      expect(_to).to.equal(toAddress)
      expect(_value).to.equal(user1DepositAmount)
      expect(_type).to.equal(0)
      expect(_referral).to.equal(referral)

      const expectedBalance = await stakeTogether.weiByShares(user1Shares)
      const actualBalance = await stakeTogether.balanceOf(toAddress)
      expect(actualBalance).to.equal(expectedBalance)

      const calculatedShares = await stakeTogether.sharesByWei(user1DepositAmount - fee)
      expect(calculatedShares).to.equal(user1Shares)
    })

    it('should correctly handle deposit with fractional values (round up)', async function () {
      const user1DepositAmount = ethers.parseEther('10') / 3n
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const fee = (user1DepositAmount * 3n) / 1000n

      const user1Shares = 1n + user1DepositAmount - fee // In this case we have to round up

      const user1Delegations = [{ pool: poolAddress, shares: user1Shares }]

      const tx1 = await stakeTogether
        .connect(user1)
        .depositPool(user1Delegations, referral, { value: user1DepositAmount })
      await tx1.wait()

      let eventFilter = stakeTogether.filters.UpdateDelegations(user1.address)
      let logs = await stakeTogether.queryFilter(eventFilter)

      let event = logs[0]
      const [emittedAddress1, emittedDelegations1] = event.args
      expect(emittedAddress1).to.equal(user1.address)
      expect(emittedDelegations1[0].pool).to.equal(user1Delegations[0].pool)
      expect(emittedDelegations1[0].shares).to.equal(user1Delegations[0].shares)

      eventFilter = stakeTogether.filters.DepositBase(user1.address, undefined, undefined)
      logs = await stakeTogether.queryFilter(eventFilter)

      event = logs[0]
      const [_to, _value, _type, _referral] = event.args
      expect(_to).to.equal(user1.address)
      expect(_value).to.equal(user1DepositAmount)
      expect(_type).to.equal(1)
      expect(_referral).to.equal(referral)

      const expectedBalance = await stakeTogether.weiByShares(user1Shares)
      const actualBalance = await stakeTogether.balanceOf(user1.address)
      expect(actualBalance).to.equal(expectedBalance)

      const calculatedShares = await stakeTogether.sharesByWei(user1DepositAmount - fee)
      expect(calculatedShares).to.equal(user1Shares - 1n)
      // PS: Shares by wei it's a pure function and have no round up
    })

    it('should correctly handle deposit and fail if daily deposit limit is reached', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const user2DepositAmount = ethers.parseEther('901')
      const poolAddress = user3.address
      const referral = user4.address

      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee
      const user1Delegations = [{ pool: poolAddress, shares: user1Shares }]

      const tx1 = await stakeTogether
        .connect(user1)
        .depositPool(user1Delegations, referral, { value: user1DepositAmount })
      await tx1.wait()

      let eventFilter = stakeTogether.filters.DepositBase(user1.address, undefined, undefined)
      let logs = await stakeTogether.queryFilter(eventFilter)

      let event = logs[0]
      const [_to1, _value1, _type1, _referral1] = event.args
      expect(_to1).to.equal(user1.address)
      expect(_value1).to.equal(user1DepositAmount)
      expect(_type1).to.equal(1)
      expect(_referral1).to.equal(referral)

      const fee2 = (user2DepositAmount * 3n) / 1000n
      const user2Shares = user2DepositAmount - fee2
      const user2Delegations = [{ pool: poolAddress, shares: user2Shares }]

      await expect(
        stakeTogether
          .connect(user2)
          .depositPool(user2Delegations, referral, { value: user2DepositAmount }),
      ).to.be.revertedWith('DLR')
    })

    it('should correctly handle deposit and reset deposit limit after a day', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const user2DepositAmount = ethers.parseEther('901')
      const user3DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      const blocksPerDay = 7200

      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const fee1 = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee1
      const user1Delegations = [{ pool: poolAddress, shares: user1Shares }]

      const tx1 = await stakeTogether
        .connect(user1)
        .depositPool(user1Delegations, referral, { value: user1DepositAmount })
      await tx1.wait()

      let eventFilter = stakeTogether.filters.DepositBase(user1.address, undefined, undefined)
      let logs = await stakeTogether.queryFilter(eventFilter)

      let event = logs[0]
      const [_to1, _value1, _type1, _referral1] = event.args
      expect(_to1).to.equal(user1.address)
      expect(_value1).to.equal(user1DepositAmount)
      expect(_type1).to.equal(1)
      expect(_referral1).to.equal(referral)

      const fee2 = (user2DepositAmount * 3n) / 1000n
      const user2Shares = user2DepositAmount - fee2
      const user2Delegations = [{ pool: poolAddress, shares: user2Shares }]

      await expect(
        stakeTogether
          .connect(user2)
          .depositPool(user2Delegations, referral, { value: user2DepositAmount }),
      ).to.be.revertedWith('DLR')

      for (let i = 0; i < 100; i++) {
        await network.provider.send('evm_mine')
      }

      await expect(
        stakeTogether
          .connect(user2)
          .depositPool(user2Delegations, referral, { value: user2DepositAmount }),
      ).to.be.revertedWith('DLR')

      for (let i = 0; i < blocksPerDay; i++) {
        await network.provider.send('evm_mine')
      }

      const fee3 = (user3DepositAmount * 3n) / 1000n
      const user3Shares = user3DepositAmount - fee3
      const user3Delegations = [{ pool: poolAddress, shares: user3Shares }]

      const tx3 = await stakeTogether
        .connect(user3)
        .depositPool(user3Delegations, referral, { value: user3DepositAmount })
      await tx3.wait()

      eventFilter = stakeTogether.filters.DepositBase(user3.address, undefined, undefined)
      logs = await stakeTogether.queryFilter(eventFilter)

      event = logs[0]
      const [_to3, _value3, _type3, _referral3] = event.args
      expect(_to3).to.equal(user3.address)
      expect(_value3).to.equal(user3DepositAmount)
      expect(_type3).to.equal(1)
      expect(_referral3).to.equal(referral)
    })

    it('should fail if deposit amount is less than minDepositAmount', async function () {
      const user1DepositAmount = ethers.parseEther('0.0005')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      await expect(
        stakeTogether.connect(user1).depositPool([], referral, { value: user1DepositAmount }),
      ).to.be.revertedWith('MD')
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
        minWithdrawAmount: ethers.parseEther('0.0001'),
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

    it('should fail when trying to delegate to a non-existent pool', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const nonExistentPoolAddress = nullAddress
      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee

      const user1Delegations = [{ pool: nonExistentPoolAddress, shares: user1Shares }]

      await expect(
        stakeTogether.connect(user1).depositPool(user1Delegations, user3, { value: user1DepositAmount }),
      ).to.be.revertedWith('PNF')
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

  describe('Withdrawals', function () {
    it('should correctly handle deposit and withdraw from pool', async function () {
      // Deposit
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee
      const user1Delegations = [{ pool: poolAddress, shares: user1Shares }]

      await stakeTogether
        .connect(user1)
        .depositPool(user1Delegations, referral, { value: user1DepositAmount })

      let expectedBalanceAfterDeposit = await stakeTogether.balanceOf(user1.address)
      expect(expectedBalanceAfterDeposit).to.equal(user1DepositAmount - fee)

      // Withdraw
      const withdrawAmount = ethers.parseEther('40')
      const sharesForWithdrawAmount = await stakeTogether.sharesByWei(withdrawAmount)

      user1Delegations[0].shares -= sharesForWithdrawAmount

      await stakeTogether.connect(user1).withdrawPool(withdrawAmount, user1Delegations)

      let expectedBalanceAfterWithdraw = await stakeTogether.balanceOf(user1.address)
      expect(expectedBalanceAfterWithdraw).to.equal(user1DepositAmount - fee - withdrawAmount)

      let eventFilter = stakeTogether.filters.WithdrawBase(user1.address, undefined, undefined)
      let logs = await stakeTogether.queryFilter(eventFilter)
      let event = logs[0]
      const [_from, _value, _withdrawType] = event.args

      expect(_from).to.equal(user1.address)
      expect(_value).to.equal(withdrawAmount)
      expect(_withdrawType).to.equal(0)
    })

    it('should correctly handle withdraw from pool with fractional values (round up)', async function () {
      // Deposit
      const user1DepositAmount = ethers.parseEther('100') / 3n
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const fee = (user1DepositAmount * 3n) / 1000n

      const user1Shares = 1n + user1DepositAmount - fee // In this case we have to round up

      const user1Delegations = [{ pool: poolAddress, shares: user1Shares }]

      await stakeTogether
        .connect(user1)
        .depositPool(user1Delegations, referral, { value: user1DepositAmount })

      let expectedBalanceAfterDeposit = await stakeTogether.balanceOf(user1.address)
      expect(expectedBalanceAfterDeposit).to.equal(user1DepositAmount - fee + 1n) // round up

      // Withdraw
      const withdrawAmount = ethers.parseEther('40') / 3n
      const sharesForWithdrawAmount = await stakeTogether.sharesByWei(withdrawAmount)

      user1Delegations[0].shares -= sharesForWithdrawAmount

      await stakeTogether.connect(user1).withdrawPool(withdrawAmount, user1Delegations)

      let expectedBalanceAfterWithdraw = await stakeTogether.balanceOf(user1.address)
      expect(expectedBalanceAfterWithdraw).to.equal(user1DepositAmount - fee - withdrawAmount + 1n)

      let eventFilter = stakeTogether.filters.WithdrawBase(user1.address, undefined, undefined)
      let logs = await stakeTogether.queryFilter(eventFilter)
      let event = logs[0]
      const [_from, _value, _withdrawType] = event.args

      expect(_from).to.equal(user1.address)
      expect(_value).to.equal(withdrawAmount)
      expect(_withdrawType).to.equal(0)
    })

    it('should revert when trying to withdraw amount of 0', async function () {
      // Deposit
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee
      const user1Delegations = [{ pool: poolAddress, shares: user1Shares }]

      await stakeTogether
        .connect(user1)
        .depositPool(user1Delegations, referral, { value: user1DepositAmount })

      // Withdraw
      const withdrawAmount = ethers.parseEther('0') // Attempting to withdraw 0

      // Expect a revert with the specific error message
      await expect(
        stakeTogether.connect(user1).withdrawPool(withdrawAmount, user1Delegations),
      ).to.be.revertedWith('ZA')
    })

    it('should revert when trying to withdraw an amount greater than the balance', async function () {
      // Deposit
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee
      const user1Delegations = [{ pool: poolAddress, shares: user1Shares }]

      await stakeTogether
        .connect(user1)
        .depositPool(user1Delegations, referral, { value: user1DepositAmount })

      // Withdraw an amount greater than the balance
      const withdrawAmount = ethers.parseEther('101')

      // Expect a revert with the specific error message
      await expect(
        stakeTogether.connect(user1).withdrawPool(withdrawAmount, user1Delegations),
      ).to.be.revertedWith('IB')
    })

    it('should revert when trying to withdraw an amount less than the minimum ', async function () {
      // Deposit
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee
      const user1Delegations = [{ pool: poolAddress, shares: user1Shares }]

      await stakeTogether
        .connect(user1)
        .depositPool(user1Delegations, referral, { value: user1DepositAmount })

      const withdrawAmount = ethers.parseEther('0.000001')

      const sharesForWithdrawAmount = await stakeTogether.sharesByWei(withdrawAmount)

      user1Delegations[0].shares -= sharesForWithdrawAmount + 1n // round up

      await expect(
        stakeTogether.connect(user1).withdrawPool(withdrawAmount, user1Delegations),
      ).to.be.revertedWith('MW')
    })

    it('should revert when trying to withdraw an amount that exceeds the limit', async function () {
      const config = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('32'),
        minDepositAmount: ethers.parseEther('0.1'),
        minWithdrawAmount: ethers.parseEther('0.0001'),
        depositLimit: ethers.parseEther('10000'),
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
      await stakeTogether.connect(owner).setConfig(config)

      // Deposits
      const depositAmount = ethers.parseEther('1000')
      const poolAddress = user3.address
      const referral = user4.address

      // Deposit from user1 and user2
      await stakeTogether.connect(owner).addPool(poolAddress, true)
      const fee = (depositAmount * 3n) / 1000n
      const user1Shares = depositAmount - fee
      const user2Shares = depositAmount - fee
      const user1Delegations = [{ pool: poolAddress, shares: user1Shares }]
      const user2Delegations = [{ pool: poolAddress, shares: user2Shares }]

      await stakeTogether.connect(user1).depositPool(user1Delegations, referral, { value: depositAmount })
      await stakeTogether.connect(user2).depositPool(user2Delegations, referral, { value: depositAmount })

      // Calculate shares for the first withdrawal
      const withdrawAmount = ethers.parseEther('900')
      const sharesForWithdrawAmount1 = await stakeTogether.sharesByWei(withdrawAmount)

      const user1Delegations1 = [{ pool: poolAddress, shares: user1Shares - sharesForWithdrawAmount1 }]
      await stakeTogether.connect(user1).withdrawPool(withdrawAmount, user1Delegations1)

      const withdrawAmount2 = ethers.parseEther('900')
      const sharesForWithdrawAmount2 = await stakeTogether.sharesByWei(withdrawAmount2)

      const user2Delegations1 = [{ pool: poolAddress, shares: user2Shares - sharesForWithdrawAmount2 }]

      // Expect a revert with the specific error message
      await expect(
        stakeTogether.connect(user2).withdrawPool(withdrawAmount, user2Delegations1),
      ).to.be.revertedWith('WLR')

      const blocksPerDay = 7200n
      for (let i = 0; i < blocksPerDay; i++) {
        await network.provider.send('evm_mine')
      }

      await stakeTogether.connect(user2).withdrawPool(withdrawAmount, user2Delegations1)
    })

    it('should revert when trying to withdraw an amount greater than the balance', async function () {
      // Deposit by user1
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee

      const user1Delegations = [{ pool: poolAddress, shares: user1Shares }]

      await stakeTogether
        .connect(user1)
        .depositPool(user1Delegations, referral, { value: user1DepositAmount })

      await stakeTogether
        .connect(user2)
        .depositPool(user1Delegations, referral, { value: user1DepositAmount })

      const withdrawAmount = ethers.parseEther('150')

      await expect(stakeTogether.connect(user1).withdrawPool(withdrawAmount, [])).to.be.revertedWith(
        'IAB',
      )
    })

    it('should revert when trying to withdraw from the pool disabled', async function () {
      // Setting the WithdrawPool feature to false
      const config = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('32'),
        minDepositAmount: ethers.parseEther('0.1'), // Changing to a new value
        minWithdrawAmount: ethers.parseEther('0.0001'),
        depositLimit: ethers.parseEther('1000'),
        withdrawalLimit: ethers.parseEther('1000'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        feature: {
          AddPool: true,
          Deposit: true,
          WithdrawPool: false,
          WithdrawValidator: false,
        },
      }

      // Set config by owner
      await connect(stakeTogether, owner).setConfig(config)

      // Attempt to withdraw
      const withdrawAmount = ethers.parseEther('1')

      // Expect a revert with the specific error message 'FD'
      await expect(stakeTogether.connect(user1).withdrawPool(withdrawAmount, [])).to.be.revertedWith('FD')
    })

    it('should revert when trying to withdraw from the validator disabled', async function () {
      // Setting the WithdrawPool feature to false
      const config = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('32'),
        minDepositAmount: ethers.parseEther('0.1'), // Changing to a new value
        minWithdrawAmount: ethers.parseEther('0.0001'),
        depositLimit: ethers.parseEther('1000'),
        withdrawalLimit: ethers.parseEther('1000'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        feature: {
          AddPool: true,
          Deposit: true,
          WithdrawPool: false,
          WithdrawValidator: false,
        },
      }

      // Set config by owner
      await connect(stakeTogether, owner).setConfig(config)
      const withdrawAmount = ethers.parseEther('1')

      await expect(stakeTogether.connect(user1).withdrawValidator(withdrawAmount, [])).to.be.revertedWith(
        'FD',
      )
    })

    // I Need to create a test on create validator to increase beacon balance
    it.skip('should correctly handle withdrawal as a validator', async function () {
      // Deposit
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee
      const user1Delegations = [{ pool: poolAddress, shares: user1Shares }]

      await stakeTogether
        .connect(user1)
        .depositPool(user1Delegations, referral, { value: user1DepositAmount })

      // Increase beacon balance
      const airdropAddress = await stakeTogether.getFeeAddress(0)

      const airdropSigner = ethers.provider.getSigner(airdropAddress)

      await connect(stakeTogether, airdropSigner as unknown as HardhatEthersSigner).setBeaconBalance(
        ethers.parseEther('50'),
      )

      // Withdraw as Validator
      const withdrawAmount = ethers.parseEther('40')
      await stakeTogether.connect(user1).withdrawValidator(withdrawAmount, user1Delegations)

      // Check the balance after withdraw
      let expectedBalanceAfterWithdraw = await stakeTogether.balanceOf(user1.address)
      expect(expectedBalanceAfterWithdraw).to.equal(user1DepositAmount - fee - withdrawAmount)

      // Check the WithdrawBase event
      let eventFilter = stakeTogether.filters.WithdrawBase(user1.address, undefined, undefined)
      let logs = await stakeTogether.queryFilter(eventFilter)
      let event = logs[0]
      const [_from, _value, _withdrawType] = event.args

      expect(_from).to.equal(user1.address)
      expect(_value).to.equal(withdrawAmount)
      expect(_withdrawType).to.equal(1) // Assuming the correct enum value is used
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

  describe('Pool Creation', function () {
    // Test for a user with POOL_MANAGER_ROLE (the owner in this case)
    it('should correctly add pool by the owner', async function () {
      // Connect with an address that has the POOL_MANAGER_ROLE (the owner)
      const poolAddress = user3.address
      const isListed = true

      // Add the pool
      await stakeTogether.connect(owner).addPool(poolAddress, isListed)

      // Verify the pool has been added
      expect(await stakeTogether.pools(poolAddress)).to.be.true

      // Verify the AddPool event
      const eventFilter = stakeTogether.filters.AddPool(poolAddress, undefined, undefined)
      const logs = await stakeTogether.queryFilter(eventFilter)
      const event = logs[0]
      expect(event.args.pool).to.equal(poolAddress)
      expect(event.args.listed).to.equal(isListed)
    })

    // Test for a user without POOL_MANAGER_ROLE
    it('should correctly add pool by a user without POOL_MANAGER_ROLE and handle fees', async function () {
      // Use an address that does not have the POOL_MANAGER_ROLE
      const userSigner = user1

      const poolAddress = user3.address
      const isListed = true
      const paymentAmount = ethers.parseEther('1') // Set the appropriate value to pay the fees

      // Add the pool
      await stakeTogether.connect(userSigner).addPool(poolAddress, isListed, { value: paymentAmount })

      // Verify the pool has been added
      expect(await stakeTogether.pools(poolAddress)).to.be.true

      // Verify the AddPool event and rewards (add necessary checks for fees/rewards)
      const eventFilter = stakeTogether.filters.AddPool(poolAddress, undefined, undefined)
      const logs = await stakeTogether.queryFilter(eventFilter)
      const event = logs[0]
      expect(event.args.pool).to.equal(poolAddress)
      expect(event.args.listed).to.equal(isListed)
      // Add additional checks for fees/rewards as needed
    })

    it('should reject adding a pool with zero address', async function () {
      // Attempt to add the pool with a zero address and expect failure
      await expect(stakeTogether.connect(owner).addPool(nullAddress, true)).to.be.revertedWith('ZA')
    })

    it('should reject adding a pool with an existing address', async function () {
      const poolAddress = user3.address
      const isListed = true

      // Owner adds the pool
      await stakeTogether.connect(owner).addPool(poolAddress, isListed)

      // Attempt to add the pool again and expect failure
      await expect(stakeTogether.connect(owner).addPool(poolAddress, isListed)).to.be.revertedWith('PE')
    })

    it('should reject adding a pool when AddPool feature is disabled', async function () {
      // Setting the WithdrawPool feature to false
      const config = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('32'),
        minDepositAmount: ethers.parseEther('0.1'), // Changing to a new value
        minWithdrawAmount: ethers.parseEther('0.0001'),
        depositLimit: ethers.parseEther('1000'),
        withdrawalLimit: ethers.parseEther('1000'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        feature: {
          AddPool: false,
          Deposit: false,
          WithdrawPool: false,
          WithdrawValidator: false,
        },
      }

      // Set config by owner
      await connect(stakeTogether, owner).setConfig(config)
      // Attempt to add the pool and expect failure
      const poolAddress = user3.address
      await expect(
        stakeTogether.connect(user1).addPool(poolAddress, true, { value: ethers.parseEther('1') }),
      ).to.be.revertedWith('FD')
    })

    it('should correctly add pool with a specific value and mark as unlisted', async function () {
      const poolAddress = user3.address
      const isListed = false // Mark as unlisted
      const paymentAmount = ethers.parseEther('1') // The value to pass

      // Add the pool
      await stakeTogether.connect(owner).addPool(poolAddress, isListed, { value: paymentAmount })

      // Verify the pool has been added
      expect(await stakeTogether.pools(poolAddress)).to.be.true

      // Verify the AddPool event
      const eventFilter = stakeTogether.filters.AddPool(poolAddress, undefined, undefined)
      const logs = await stakeTogether.queryFilter(eventFilter)
      const event = logs[0]
      expect(event.args.pool).to.equal(poolAddress)
      expect(event.args.listed).to.equal(isListed)
      expect(event.args.amount).to.equal(paymentAmount)
    })

    it('should correctly add pool by a non-owner user when any user can create a pool', async function () {
      const poolAddress = user3.address
      const isListed = true
      const paymentAmount = ethers.parseEther('1') // The value to pay the fees

      // Add the pool by a non-owner user
      await stakeTogether.connect(user1).addPool(poolAddress, isListed, { value: paymentAmount })

      // Verify the pool has been added
      expect(await stakeTogether.pools(poolAddress)).to.be.true
    })

    it('should correctly remove a pool by an account with POOL_MANAGER_ROLE', async function () {
      // Add a pool first
      const poolAddress = user3.address
      const isListed = true
      await stakeTogether.connect(owner).addPool(poolAddress, isListed)

      // Verify the pool has been added
      expect(await stakeTogether.pools(poolAddress)).to.be.true

      // Remove the pool
      await stakeTogether.connect(owner).removePool(poolAddress)

      // Verify the pool has been removed
      expect(await stakeTogether.pools(poolAddress)).to.be.false

      // Verify the RemovePool event
      const eventFilter = stakeTogether.filters.RemovePool(poolAddress)
      const logs = await stakeTogether.queryFilter(eventFilter)
      const event = logs[0]
      expect(event.args.pool).to.equal(poolAddress)
    })

    it('should fail to remove a non-existing pool', async function () {
      // Address of a non-existing pool
      const nonExistingPoolAddress = user3.address

      // Verify the pool does not exist
      expect(await stakeTogether.pools(nonExistingPoolAddress)).to.be.false

      // Attempt to remove the non-existing pool and expect a revert with 'PNF'
      await expect(stakeTogether.connect(owner).removePool(nonExistingPoolAddress)).to.be.revertedWith(
        'PNF',
      )
    })

    it('should handle the scenario where shares are equal to zero', async function () {
      // Add pools
      const poolAddress1 = user3.address
      const poolAddress2 = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress1, true)
      await stakeTogether.connect(owner).addPool(poolAddress2, true)

      // Verify that shares are initially zero for user1
      expect(await stakeTogether.shares(user1.address)).to.equal(0)

      // Create delegations without deposit (shares remain zero)
      const user1Delegations = [
        { pool: poolAddress1, shares: 0n },
        { pool: poolAddress2, shares: 0n },
      ]

      // Try to update delegations
      await expect(stakeTogether.connect(user1).updateDelegations(user1Delegations)).to.not.be.reverted // No error expected since shares are zero

      // Confirm that no changes were made (since shares were zero, no validation is done)
      for (const delegation of user1Delegations) {
        expect(await stakeTogether.pools(delegation.pool)).to.be.true
        expect(delegation.shares).to.equal(0)
      }
    })
  })

  describe('VALIDATORS', function () {
    it('should grant the VALIDATOR_ORACLE_MANAGER_ROLE to admin, add an oracle', async function () {
      // Verify that admin doesn't have the VALIDATOR_ORACLE_MANAGER_ROLE
      expect(await stakeTogether.hasRole(VALIDATOR_ORACLE_MANAGER_ROLE, user6)).to.be.false

      // Grant the VALIDATOR_ORACLE_MANAGER_ROLE to admin (owner) using ADMIN_ROLE
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, user6)

      // Verify that admin now has the VALIDATOR_ORACLE_MANAGER_ROLE
      expect(await stakeTogether.hasRole(VALIDATOR_ORACLE_MANAGER_ROLE, user6)).to.be.true

      const newOracleAddress = user3.address

      // Connect with an address that has the VALIDATOR_ORACLE_MANAGER_ROLE (now admin)
      await connect(stakeTogether, user6).addValidatorOracle(newOracleAddress)

      // Verify that the oracle address has been granted the VALIDATOR_ORACLE_ROLE
      expect(await stakeTogether.hasRole(VALIDATOR_ORACLE_ROLE, newOracleAddress)).to.be.true

      // Verify that the oracle address has been added
      const oracles = await stakeTogether.getValidatorsOracle()
      expect(oracles.includes(newOracleAddress)).to.be.true

      // Verify the AddValidatorOracle event
      const eventFilter = stakeTogether.filters.AddValidatorOracle(newOracleAddress)
      const logs = await stakeTogether.queryFilter(eventFilter)
      const event = logs[0]
      expect(event.args.account).to.equal(newOracleAddress)
    })

    it('should revert if called by an address without VALIDATOR_ORACLE_MANAGER_ROLE', async function () {
      const newOracleAddress = user3.address

      // Use an address that does not have the VALIDATOR_ORACLE_MANAGER_ROLE
      await expect(stakeTogether.connect(user1).addValidatorOracle(newOracleAddress)).to.be.reverted
    })
  })
})
