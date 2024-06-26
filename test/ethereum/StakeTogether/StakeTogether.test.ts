import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { StandardMerkleTree } from '@openzeppelin/merkle-tree'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers, network, upgrades } from 'hardhat'
import { Airdrop, StakeTogether, Withdrawals } from '../../../typechain/contracts/ethereum'
import { MockFlashLoan, MockRouter } from '../../../typechain/contracts/ethereum/mocks'
import { MockStakeTogether__factory } from '../../../typechain/factories/contracts/ethereum/mocks'
import { stakeTogetherFixture } from './StakeTogether.fixture'

dotenv.config()

describe('Stake Together', function () {
  let stakeTogether: StakeTogether
  let stakeTogetherProxy: string

  let mockRouter: MockRouter
  let mockRouterProxy: string
  let withdrawals: Withdrawals
  let withdrawalsProxy: string
  let mockFlashLoan: MockFlashLoan
  let airdrop: Airdrop
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
  let VALIDATOR_ORACLE_SENTINEL_ROLE: string
  let initialBalance: bigint

  // Setting up the fixture before each test
  beforeEach(async function () {
    const fixture = await loadFixture(stakeTogetherFixture)
    stakeTogether = fixture.stakeTogether
    stakeTogetherProxy = fixture.stakeTogetherProxy
    mockRouter = fixture.mockRouter as unknown as MockRouter
    mockRouterProxy = fixture.mockRouterProxy
    withdrawals = fixture.withdrawals
    withdrawalsProxy = fixture.withdrawalsProxy
    mockFlashLoan = fixture.mockFlashLoan
    airdrop = fixture.airdrop
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
    VALIDATOR_ORACLE_SENTINEL_ROLE = fixture.VALIDATOR_ORACLE_SENTINEL_ROLE
    initialBalance = await ethers.provider.getBalance(stakeTogetherProxy)
  })

  describe('Upgrade', () => {
    // Test to check if pause and unpause functions work properly
    it('should pause and unpause the contract if the user has admin role', async function () {
      // Check if the contract is not paused at the beginning
      expect(await stakeTogether.paused()).to.equal(false)

      // User without admin role tries to pause the contract - should fail
      await expect(stakeTogether.connect(user1).pause()).to.reverted

      // The owner pauses the contract
      await stakeTogether.connect(owner).pause()

      // Check if the contract is paused
      expect(await stakeTogether.paused()).to.equal(true)

      // User without admin role tries to unpause the contract - should fail
      await expect(stakeTogether.connect(user1).unpause()).to.reverted

      // The owner unpauses the contract
      await stakeTogether.connect(owner).unpause()
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

      await expect(tx).to.emit(stakeTogether, 'ReceiveEther').withArgs(ethers.parseEther('1.0'))
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
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      // Three users depositing 1 Ether each
      const users = [user1, user2, user3]
      let totalFees = 0n
      const userBalancesBefore = []
      for (const user of users) {
        const fee = (depositAmount * 3n) / 1000n
        totalFees += fee
        const shares = depositAmount - fee
        userBalancesBefore.push(shares)
        await stakeTogether.connect(user).depositPool(poolAddress, nullAddress, { value: depositAmount })
      }

      const prevContractBalance = await ethers.provider.getBalance(stakeTogetherProxy)
      expect(prevContractBalance).to.equal(ethers.parseEther('3') + initialBalance) // contract init with 1n

      // Sending 1 Ether profit to the contract
      await owner.sendTransaction({ to: stakeTogetherProxy, value: ethers.parseEther('1') })

      // Simulating how the profit should be distributed
      const totalProfit = ethers.parseEther('1') - totalFees / 3n
      const profitPerUserBase = totalProfit / 4n
      const hasRemainder = totalProfit % 4n > 0n
      const profitPerUser = hasRemainder ? profitPerUserBase + 1n : profitPerUserBase

      // Checking the balance of each user
      for (let i = 0; i < users.length; i++) {
        const expectedBalance = userBalancesBefore[i] + profitPerUser
        const actualBalance = await stakeTogether.balanceOf(users[i].address)
        expect(actualBalance).to.be.equal(expectedBalance)
      }

      // Total balance in the contract should be 4 Ether + total fees
      const totalContractBalance = await ethers.provider.getBalance(stakeTogetherProxy)
      expect(totalContractBalance).to.equal(ethers.parseEther('4') + initialBalance) // contract init with 1n
    })

    it('should distribute profit equally among three depositors', async function () {
      const depositAmount = ethers.parseEther('1')
      const poolAddress = user3.address

      // Adding the pool
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      await expect(
        mockFlashLoan.depositAndWithdraw(poolAddress, poolAddress, { value: depositAmount }),
      ).to.revertedWithCustomError(stakeTogether, 'FlashLoan')
    })

    it('should distribute profit equally among two depositors by Stake Entry', async function () {
      const depositAmount = ethers.parseEther('1')
      const poolAddress = user3.address // Example pool address

      // Adding the pool
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      // Two users depositing 1 Ether each
      const users = [user1, user2]
      let totalFees = 0n
      const userBalancesBefore = []
      for (const user of users) {
        const fee = (depositAmount * 3n) / 1000n
        totalFees += fee
        const shares = depositAmount - fee
        userBalancesBefore.push(shares)
        await stakeTogether.connect(user).depositPool(poolAddress, nullAddress, { value: depositAmount })
      }

      const prevContractBalance = await ethers.provider.getBalance(stakeTogetherProxy)
      expect(prevContractBalance).to.equal(ethers.parseEther('2') + initialBalance) // contract init with 1n

      // Checking the balance of each user
      // for (let i = 0; i < users.length; i++) {
      //   const actualBalance = await stakeTogether.balanceOf(users[i].address)
      //   console.log('User Balance Pre', actualBalance.toString())
      // }

      // Sending 1 Ether profit to the contract
      await owner.sendTransaction({ to: stakeTogetherProxy, value: ethers.parseEther('1') })

      // Simulating how the profit should be distributed
      const userShares = ethers.parseEther('1') - totalFees / 2n
      const profitPerUserBase = userShares / 3n
      const hasRemainder = userShares % 3n > 0n
      const profitPerUser = hasRemainder ? profitPerUserBase + 1n : profitPerUserBase

      // Checking the balance of each user
      for (let i = 0; i < users.length; i++) {
        const expectedBalance = userBalancesBefore[i] + profitPerUser
        const actualBalance = await stakeTogether.balanceOf(users[i].address)
        // console.log('User Balance Pos', actualBalance.toString())
        expect(actualBalance).to.be.equal(expectedBalance)
      }

      // Total balance in the contract should be 3 Ether + total fees
      const totalContractBalance = await ethers.provider.getBalance(stakeTogetherProxy)
      expect(totalContractBalance).to.equal(ethers.parseEther('3') + initialBalance)
    })

    it('should fail to mint rewards if called directly on stakeTogether', async function () {
      const rewardAmount = ethers.parseEther('5')
      const rewardShares = ethers.parseEther('5')

      await expect(
        stakeTogether.connect(user1).processFeeRewards(rewardShares, { value: rewardAmount }),
      ).to.be.revertedWithCustomError(stakeTogether, 'OnlyRouter')
    })

    it('should fail to claim rewards if caller is not airdrop fee address', async function () {
      const sharesAmount = ethers.parseEther('10')

      await expect(
        stakeTogether.connect(user2).claimAirdrop(user1.address, sharesAmount),
      ).to.be.revertedWithCustomError(stakeTogether, 'OnlyAirdrop')
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
        withdrawalPoolLimit: ethers.parseEther('1000'),
        withdrawalValidatorLimit: ethers.parseEther('1000'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        withdrawDelay: 10n,
        withdrawBeaconDelay: 10n,
        feature: {
          AddPool: true,
          Deposit: true,
          WithdrawPool: true,
          WithdrawBeacon: true,
        },
      }

      // Set config by owner
      await stakeTogether.connect(owner).setConfig(config)

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
        withdrawalPoolLimit: ethers.parseEther('1000'),
        withdrawalValidatorLimit: ethers.parseEther('1000'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        withdrawDelay: 10n,
        withdrawBeaconDelay: 10n,
        feature: {
          AddPool: true,
          Deposit: true,
          WithdrawPool: true,
          WithdrawBeacon: true,
        },
      }

      // Attempt to set config by non-owner should fail
      await expect(stakeTogether.connect(user1).setConfig(config)).to.be.reverted
    })

    it('should revert if poolSize is less than validatorSize', async function () {
      const invalidConfig = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('31'),
        minDepositAmount: ethers.parseEther('0.001'),
        minWithdrawAmount: ethers.parseEther('0.0001'),
        depositLimit: ethers.parseEther('1000'),
        withdrawalPoolLimit: ethers.parseEther('1000'),
        withdrawalValidatorLimit: ethers.parseEther('1000'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        withdrawDelay: 10n,
        withdrawBeaconDelay: 10n,
        feature: {
          AddPool: true,
          Deposit: true,
          WithdrawPool: true,
          WithdrawBeacon: true,
        },
      }

      // Attempt to set config by owner should fail
      await expect(stakeTogether.setConfig(invalidConfig)).to.be.revertedWithCustomError(
        stakeTogether,
        'InvalidSize',
      )
    })
  })

  describe('Deposit', function () {
    it('should correctly handle deposit and update delegations for Pool type', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee

      const tx1 = await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, referral, { value: user1DepositAmount })
      await tx1.wait()

      let eventFilter = stakeTogether.filters.DepositBase(user1.address, undefined, undefined, undefined)
      let logs = await stakeTogether.queryFilter(eventFilter)

      let event = logs[0]
      const [_to, _value, _type, _pool] = event.args
      expect(_to).to.equal(user1.address)
      expect(_value).to.equal(user1DepositAmount)
      expect(_type).to.equal(1)
      expect(_pool).to.equal(poolAddress)

      const expectedBalance = await stakeTogether.weiByShares(user1Shares)
      const actualBalance = await stakeTogether.balanceOf(user1.address)
      expect(actualBalance).to.equal(expectedBalance)

      const calculatedShares = await stakeTogether.sharesByWei(user1DepositAmount - fee)
      expect(calculatedShares).to.equal(user1Shares)
    })

    it('should correctly handle deposit and maintain the same withdraw', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const user1WithdrawAmount = ethers.parseEther('1')
      const poolAddress = user3.address
      const referral = user4.address

      // Add pool before testing deposit
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      // Check withdraw block before deposit
      const withdrawBlockBefore = await stakeTogether.getWithdrawBlock(user1.address)
      expect(withdrawBlockBefore).to.equal(0n)

      // Perform deposit
      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: user1DepositAmount })

      // Check withdraw block after deposit
      const withdrawBlockAfter = await stakeTogether.getWithdrawBlock(user1.address)
      expect(withdrawBlockAfter).to.equal(132n)

      await expect(
        stakeTogether.connect(user1).withdrawPool(user1WithdrawAmount, poolAddress),
      ).revertedWithCustomError(stakeTogether, 'EarlyTransfer')

      for (let i = 0; i < 100; i++) {
        await network.provider.send('evm_mine')
      }

      const accountBalanceBefore = await stakeTogether.balanceOf(user1.address)

      await stakeTogether.connect(user1).withdrawPool(user1WithdrawAmount, poolAddress)

      const accountBalanceAfter = await stakeTogether.balanceOf(user1.address)

      expect(accountBalanceAfter).to.equal(accountBalanceBefore - user1WithdrawAmount)
    })

    it('should correctly handle deposit with minimum deposit amount', async function () {
      const user1DepositAmount = ethers.parseEther('0.001')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      const config = await stakeTogether.config()
      expect(config.minDepositAmount).to.equal(user1DepositAmount)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee

      const tx1 = await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, referral, { value: user1DepositAmount })
      await tx1.wait()

      const expectedBalance = await stakeTogether.weiByShares(user1Shares)
      const actualBalance = await stakeTogether.balanceOf(user1.address)
      expect(actualBalance).to.equal(expectedBalance)

      const calculatedShares = await stakeTogether.sharesByWei(user1DepositAmount - fee)
      expect(calculatedShares).to.equal(user1Shares)
    })

    it('should correctly handle deposit donation', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const toAddress = user2.address
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee

      const tx = await stakeTogether
        .connect(user1)
        .depositDonation(toAddress, poolAddress, referral, { value: user1DepositAmount })
      await tx.wait()

      let eventFilter = stakeTogether.filters.DepositBase(
        toAddress,
        undefined,
        undefined,
        undefined,
        undefined,
      )
      let logs = await stakeTogether.queryFilter(eventFilter)

      let event = logs[0]
      const [_to, _value, _type, _pool] = event.args
      expect(_to).to.equal(toAddress)
      expect(_value).to.equal(user1DepositAmount)
      expect(_type).to.equal(0)
      expect(_pool).to.equal(poolAddress)

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
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      const fee = (user1DepositAmount * 3n) / 1000n

      const user1Shares = 1n + user1DepositAmount - fee // In this case we have to round up

      const tx1 = await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, referral, { value: user1DepositAmount })
      await tx1.wait()

      let eventFilter = stakeTogether.filters.DepositBase(user1.address, undefined, undefined)
      let logs = await stakeTogether.queryFilter(eventFilter)

      let event = logs[0]
      const [_to, _value, _type, _pool] = event.args
      expect(_to).to.equal(user1.address)
      expect(_value).to.equal(user1DepositAmount)
      expect(_type).to.equal(1)
      expect(_pool).to.equal(poolAddress)

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

      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      const fee = (user1DepositAmount * 3n) / 1000n

      const tx1 = await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, referral, { value: user1DepositAmount })
      await tx1.wait()

      let eventFilter = stakeTogether.filters.DepositBase(user1.address, undefined, undefined)
      let logs = await stakeTogether.queryFilter(eventFilter)

      let event = logs[0]
      const [_to1, _value1, _type1, _pool] = event.args
      expect(_to1).to.equal(user1.address)
      expect(_value1).to.equal(user1DepositAmount)
      expect(_type1).to.equal(1)
      expect(_pool).to.equal(poolAddress)

      const fee2 = (user2DepositAmount * 3n) / 1000n

      await expect(
        stakeTogether.connect(user2).depositPool(poolAddress, referral, { value: user2DepositAmount }),
      ).to.be.revertedWithCustomError(stakeTogether, 'DepositLimitReached')
    })

    it('should correctly handle deposit and reset deposit limit after a day', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const user2DepositAmount = ethers.parseEther('901')
      const user3DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      const blocksPerDay = 7200

      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      const fee1 = (user1DepositAmount * 3n) / 1000n

      const tx1 = await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, referral, { value: user1DepositAmount })
      await tx1.wait()

      let eventFilter = stakeTogether.filters.DepositBase(user1.address, undefined, undefined)
      let logs = await stakeTogether.queryFilter(eventFilter)

      let event = logs[0]
      const [_to1, _value1, _type1, _pool] = event.args
      expect(_to1).to.equal(user1.address)
      expect(_value1).to.equal(user1DepositAmount)
      expect(_type1).to.equal(1)
      expect(_pool).to.equal(poolAddress)

      const fee2 = (user2DepositAmount * 3n) / 1000n

      await expect(
        stakeTogether.connect(user2).depositPool(poolAddress, referral, { value: user2DepositAmount }),
      ).to.be.revertedWithCustomError(stakeTogether, 'DepositLimitReached')

      for (let i = 0; i < 100; i++) {
        await network.provider.send('evm_mine')
      }

      await expect(
        stakeTogether.connect(user2).depositPool(poolAddress, referral, { value: user2DepositAmount }),
      ).to.be.revertedWithCustomError(stakeTogether, 'DepositLimitReached')

      for (let i = 0; i < blocksPerDay; i++) {
        await network.provider.send('evm_mine')
      }

      const fee3 = (user3DepositAmount * 3n) / 1000n

      const tx3 = await stakeTogether
        .connect(user3)
        .depositPool(poolAddress, referral, { value: user3DepositAmount })
      await tx3.wait()

      eventFilter = stakeTogether.filters.DepositBase(user3.address, undefined, undefined)
      logs = await stakeTogether.queryFilter(eventFilter)

      event = logs[0]
      const [_to3, _value3, _type3, _pool3] = event.args
      expect(_to3).to.equal(user3.address)
      expect(_value3).to.equal(user3DepositAmount)
      expect(_type3).to.equal(1)
      expect(_pool3).to.equal(poolAddress)
    })

    it('should fail if deposit amount is less than minDepositAmount', async function () {
      const user1DepositAmount = ethers.parseEther('0.0005')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      await expect(
        stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: user1DepositAmount }),
      ).to.be.revertedWithCustomError(stakeTogether, 'LessThanMinimumDeposit')
    })

    it('should revert if deposit feature is disabled', async function () {
      const config = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('32'),
        minDepositAmount: ethers.parseEther('0.001'),
        minWithdrawAmount: ethers.parseEther('0.0001'),
        depositLimit: ethers.parseEther('1000'),
        withdrawalPoolLimit: ethers.parseEther('1000'),
        withdrawalValidatorLimit: ethers.parseEther('1000'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        withdrawDelay: 10n,
        withdrawBeaconDelay: 10n,
        feature: {
          AddPool: true,
          Deposit: false,
          WithdrawPool: true,
          WithdrawBeacon: true,
        },
      }

      await stakeTogether.connect(owner).setConfig(config)

      const user1DepositAmount = ethers.parseEther('100')
      const nonExistentPoolAddress = nullAddress
      const fee = (user1DepositAmount * 3n) / 1000n

      await expect(
        stakeTogether
          .connect(user1)
          .depositPool(nonExistentPoolAddress, ethers.toUtf8Bytes(await user3.getAddress()), {
            value: ethers.parseEther('100'),
          }),
      ).to.be.revertedWithCustomError(stakeTogether, 'FeatureDisabled')
    })

    it('should fail when trying to delegate to a non-existent pool', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const nonExistentPoolAddress = nullAddress
      const fee = (user1DepositAmount * 3n) / 1000n

      await expect(
        stakeTogether
          .connect(user1)
          .depositPool(nonExistentPoolAddress, ethers.toUtf8Bytes(await user3.getAddress()), {
            value: user1DepositAmount,
          }),
      ).to.be.revertedWithCustomError(stakeTogether, 'PoolNotFound')
    })

    it('should correctly transfer delegations to another pool', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress1 = user3.address
      const poolAddress2 = user4.address

      await stakeTogether.connect(owner).addPool(poolAddress1, true, false, false)
      await stakeTogether.connect(owner).addPool(poolAddress2, true, false, false)

      const poolAddress = user3.address

      await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, ethers.toUtf8Bytes(await user3.getAddress()), {
          value: user1DepositAmount,
        })

      const updatedDelegations = [
        { pool: poolAddress1, percentage: ethers.parseEther('0.5') },
        { pool: poolAddress2, percentage: ethers.parseEther('0.5') },
      ]
      await stakeTogether.connect(user1).updateDelegations(updatedDelegations)

      const user1Filter = stakeTogether.filters.UpdateDelegations(user1.address)

      const user1Logs = await stakeTogether.queryFilter(user1Filter)

      expect(user1Logs.length).to.equal(1)

      expect(user1Logs[0].args[1][0][0]).to.equal(poolAddress1)
    })
  })

  describe('Withdrawals', function () {
    it('should correctly handle deposit and withdraw from pool', async function () {
      // Deposit
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee
      const user1Delegations = [{ pool: poolAddress, percentage: ethers.parseEther('1') }]

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: user1DepositAmount })

      let expectedBalanceAfterDeposit = await stakeTogether.balanceOf(user1.address)
      expect(expectedBalanceAfterDeposit).to.equal(user1DepositAmount - fee)

      // Withdraw
      const withdrawAmount = ethers.parseEther('40')
      const sharesForWithdrawAmount = await stakeTogether.sharesByWei(withdrawAmount)

      const blocksPerDay = 7200n
      for (let i = 0; i < blocksPerDay; i++) {
        await network.provider.send('evm_mine')
      }

      await stakeTogether.connect(user1).withdrawPool(withdrawAmount, poolAddress)

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
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      const fee = (user1DepositAmount * 3n) / 1000n

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: user1DepositAmount })

      let expectedBalanceAfterDeposit = await stakeTogether.balanceOf(user1.address)
      expect(expectedBalanceAfterDeposit).to.equal(user1DepositAmount - fee + 1n) // round up

      // Withdraw
      const withdrawAmount = ethers.parseEther('40') / 3n
      const sharesForWithdrawAmount = await stakeTogether.sharesByWei(withdrawAmount)

      const blocksPerDay = 7200n
      for (let i = 0; i < blocksPerDay; i++) {
        await network.provider.send('evm_mine')
      }

      await stakeTogether.connect(user1).withdrawPool(withdrawAmount, poolAddress)

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
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      const fee = (user1DepositAmount * 3n) / 1000n

      const user1Delegations = [{ pool: poolAddress, percentage: ethers.parseEther('1') }]

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: user1DepositAmount })

      // Withdraw
      const withdrawAmount = ethers.parseEther('0') // Attempting to withdraw 0

      // Expect a revert with the specific error message
      await expect(
        stakeTogether.connect(user1).withdrawPool(withdrawAmount, poolAddress),
      ).to.be.revertedWithCustomError(stakeTogether, 'ZeroAmount')
    })

    it('should revert when trying to withdraw an amount greater than the balance', async function () {
      // Deposit
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee
      const user1Delegations = [{ pool: poolAddress, percentage: ethers.parseEther('1') }]

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: user1DepositAmount })

      // Withdraw an amount greater than the balance
      const withdrawAmount = ethers.parseEther('101')

      // Expect a revert with the specific error message
      await expect(
        stakeTogether.connect(user1).withdrawPool(withdrawAmount, poolAddress),
      ).to.be.revertedWithCustomError(stakeTogether, 'InsufficientAccountBalance')
    })

    it('should revert when trying to withdraw an amount less than the minimum ', async function () {
      // Deposit
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee
      const user1Delegations = [{ pool: poolAddress, percentage: ethers.parseEther('1') }]

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: user1DepositAmount })

      const withdrawAmount = ethers.parseEther('0.000001')

      const sharesForWithdrawAmount = await stakeTogether.sharesByWei(withdrawAmount)

      user1Delegations[0].percentage -= sharesForWithdrawAmount + 1n // round up

      await expect(
        stakeTogether.connect(user1).withdrawPool(withdrawAmount, poolAddress),
      ).to.be.revertedWithCustomError(stakeTogether, 'LessThanMinimumWithdraw')
    })

    it('should revert when trying to withdraw pool amount that exceeds the limit', async function () {
      const config = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('32'),
        minDepositAmount: ethers.parseEther('0.1'),
        minWithdrawAmount: ethers.parseEther('0.0001'),
        depositLimit: ethers.parseEther('10000'),
        withdrawalPoolLimit: ethers.parseEther('1000'),
        withdrawalValidatorLimit: ethers.parseEther('1000'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        withdrawDelay: 10n,
        withdrawBeaconDelay: 10n,
        feature: {
          AddPool: true,
          Deposit: true,
          WithdrawPool: true,
          WithdrawBeacon: true,
        },
      }

      // Set config by owner
      await stakeTogether.connect(owner).setConfig(config)

      // Deposits
      const depositAmount = ethers.parseEther('1000')
      const poolAddress = user3.address
      const referral = user4.address

      // Deposit from user1 and user2
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: depositAmount })
      await stakeTogether.connect(user2).depositPool(poolAddress, referral, { value: depositAmount })

      // Calculate shares for the first withdrawal
      const withdrawAmount = ethers.parseEther('900')

      for (let i = 0; i < 7200n; i++) {
        await network.provider.send('evm_mine')
      }

      await stakeTogether.connect(user1).withdrawPool(withdrawAmount, poolAddress)

      // Expect a revert with the specific error message
      await expect(
        stakeTogether.connect(user2).withdrawPool(withdrawAmount, poolAddress),
      ).to.be.revertedWithCustomError(stakeTogether, 'WithdrawalsPoolLimitReached')

      const blocksPerDay = 7200n
      for (let i = 0; i < blocksPerDay; i++) {
        await network.provider.send('evm_mine')
      }

      await stakeTogether.connect(user2).withdrawPool(withdrawAmount, poolAddress)
    })

    it('should revert when trying to withdraw beacon amount that exceeds the limit', async function () {
      const config = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('32'),
        minDepositAmount: ethers.parseEther('0.1'),
        minWithdrawAmount: ethers.parseEther('0.0001'),
        depositLimit: ethers.parseEther('10000'),
        withdrawalPoolLimit: ethers.parseEther('1000'),
        withdrawalValidatorLimit: ethers.parseEther('40'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        withdrawDelay: 10n,
        withdrawBeaconDelay: 10n,
        feature: {
          AddPool: true,
          Deposit: true,
          WithdrawPool: true,
          WithdrawBeacon: true,
        },
      }

      // Set config by owner
      await stakeTogether.connect(owner).setConfig(config)

      // Deposits
      const depositAmount = ethers.parseEther('40')
      const poolAddress = user3.address
      const referral = user4.address

      // Deposit from user1 and user2
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: depositAmount })
      await stakeTogether.connect(user2).depositPool(poolAddress, referral, { value: depositAmount })

      // Calculate shares for the first withdrawal
      const withdrawAmount = ethers.parseEther('38')

      const publicKey =
        '0x954c931791b73c03c5e699eb8da1222b221b098f6038282ff7e32a4382d9e683f0335be39b974302e42462aee077cf93'
      const publicKey2 =
        '0x954c931791b73c03c5e699eb8da1222b221b098f6038282ff7e32a4382d9e683f0335be39b974302e42462aee077cf94'
      const publicKey3 =
        '0x954c931791b73c03c5e699eb8da1222b221b098f6038282ff7e32a4382d9e683f0335be39b974302e42462aee077cf95'
      const signature =
        '0x967d1b93d655752e303b43905ac92321c048823e078cadcfee50eb35ede0beae1501a382a7c599d6e9b8a6fd177ab3d711c44b2115ac90ea1dc7accda6d0352093eaa5f2bc9f1271e1725b43b3a74476b9e749fc011de4a63d9e72cf033978ed'
      const depositDataRoot = '0x4ef3924ceb993cbc51320f44cb28ffb50071deefd455ce61feabb7b6b2f1d0e8'

      const poolSize = ethers.parseEther('32.1')
      const validatorSize = ethers.parseEther('32')

      const oracle = user1
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, owner)
      await stakeTogether.connect(owner).addValidatorOracle(oracle)

      await owner.sendTransaction({ to: stakeTogetherProxy, value: ethers.parseEther('40') })

      await stakeTogether.connect(oracle).addValidator(publicKey, signature, depositDataRoot)
      await stakeTogether.connect(oracle).addValidator(publicKey2, signature, depositDataRoot)
      await stakeTogether.connect(oracle).addValidator(publicKey3, signature, depositDataRoot)

      const beaconBalance = await stakeTogether.beaconBalance()
      expect(beaconBalance).to.equal(validatorSize * 3n)

      for (let i = 0; i < 7200n; i++) {
        await network.provider.send('evm_mine')
      }

      const withdrawBeaconBlock = await stakeTogether.getWithdrawBeaconBlock(user1.address)
      expect(withdrawBeaconBlock).to.equal(0n)

      await stakeTogether.connect(user1).withdrawBeacon(withdrawAmount, poolAddress)

      // Expect a revert with the specific error message
      await expect(
        stakeTogether.connect(user2).withdrawBeacon(withdrawAmount, poolAddress),
      ).to.be.revertedWithCustomError(stakeTogether, 'WithdrawalsValidatorLimitWasReached')

      const blocksPerDay = 7200n
      for (let i = 0; i < blocksPerDay; i++) {
        await network.provider.send('evm_mine')
      }

      await expect(stakeTogether.connect(user2).withdrawBeacon(withdrawAmount, poolAddress)).to.not
        .reverted

      const withdrawBeaconBlockAfter = await stakeTogether.getWithdrawBeaconBlock(user1.address)
      expect(withdrawBeaconBlockAfter).to.equal(7341n)
    })

    it('should revert when trying to withdraw an amount greater than the balance', async function () {
      // Deposit by user1
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee

      const user1Delegations = [{ pool: poolAddress, percentage: ethers.parseEther('1') }]

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: user1DepositAmount })

      await stakeTogether.connect(user2).depositPool(poolAddress, referral, { value: user1DepositAmount })

      const withdrawAmount = ethers.parseEther('150')

      await expect(
        stakeTogether.connect(user1).withdrawPool(withdrawAmount, poolAddress),
      ).to.be.revertedWithCustomError(stakeTogether, 'InsufficientAccountBalance')
    })

    it('should revert when trying to withdraw from the pool disabled', async function () {
      // Setting the WithdrawPool feature to false
      const config = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('32'),
        minDepositAmount: ethers.parseEther('0.1'), // Changing to a new value
        minWithdrawAmount: ethers.parseEther('0.0001'),
        depositLimit: ethers.parseEther('1000'),
        withdrawalPoolLimit: ethers.parseEther('1000'),
        withdrawalValidatorLimit: ethers.parseEther('1000'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        withdrawDelay: 10n,
        withdrawBeaconDelay: 10n,
        feature: {
          AddPool: true,
          Deposit: true,
          WithdrawPool: false,
          WithdrawBeacon: false,
        },
      }

      // Set config by owner
      await stakeTogether.connect(owner).setConfig(config)

      // Attempt to withdraw
      const withdrawAmount = ethers.parseEther('1')
      const poolAddress = user3.address

      // Expect a revert with the specific error message 'FD'
      await expect(
        stakeTogether.connect(user1).withdrawPool(withdrawAmount, poolAddress),
      ).to.be.revertedWithCustomError(stakeTogether, 'FeatureDisabled')
    })

    it('should revert when trying to withdraw from the validator disabled', async function () {
      // Setting the WithdrawPool feature to false
      const config = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('32'),
        minDepositAmount: ethers.parseEther('0.1'), // Changing to a new value
        minWithdrawAmount: ethers.parseEther('0.0001'),
        depositLimit: ethers.parseEther('1000'),
        withdrawalPoolLimit: ethers.parseEther('1000'),
        withdrawalValidatorLimit: ethers.parseEther('1000'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        withdrawDelay: 10n,
        withdrawBeaconDelay: 10n,
        feature: {
          AddPool: true,
          Deposit: true,
          WithdrawPool: false,
          WithdrawBeacon: false,
        },
      }

      // Set config by owner
      await stakeTogether.connect(owner).setConfig(config)
      const withdrawAmount = ethers.parseEther('1')
      const poolAddress = user3.address

      await expect(
        stakeTogether.connect(user1).withdrawBeacon(withdrawAmount, poolAddress),
      ).to.be.revertedWithCustomError(stakeTogether, 'FeatureDisabled')
    })

    it('should not allow withdrawal greater than beacon balance', async function () {
      const publicKey =
        '0x954c931791b73c03c5e699eb8da1222b221b098f6038282ff7e32a4382d9e683f0335be39b974302e42462aee077cf93'
      const signature =
        '0x967d1b93d655752e303b43905ac92321c048823e078cadcfee50eb35ede0beae1501a382a7c599d6e9b8a6fd177ab3d711c44b2115ac90ea1dc7accda6d0352093eaa5f2bc9f1271e1725b43b3a74476b9e749fc011de4a63d9e72cf033978ed'
      const depositDataRoot = '0x4ef3924ceb993cbc51320f44cb28ffb50071deefd455ce61feabb7b6b2f1d0e8'

      const oracle = user1
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, owner)
      await stakeTogether.connect(owner).addValidatorOracle(oracle)

      // Sending sufficient funds for pool size and validator size
      await owner.sendTransaction({ to: stakeTogetherProxy, value: ethers.parseEther('30.1') })

      // Deposit

      const depositAmount = ethers.parseEther('2')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      const delegations = [{ pool: poolAddress, percentage: ethers.parseEther('1') }]

      const tx1 = await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, referral, { value: depositAmount })
      await tx1.wait()

      // Creating the validator
      const tx = await stakeTogether.connect(oracle).addValidator(publicKey, signature, depositDataRoot)

      const beaconBalanceBefore = ethers.parseEther('50')
      await mockRouter.connect(owner).setBeaconBalance(beaconBalanceBefore)

      const withdrawAmount = ethers.parseEther('60')

      await expect(
        stakeTogether.connect(user1).withdrawBeacon(withdrawAmount, poolAddress),
      ).to.be.revertedWithCustomError(stakeTogether, 'InsufficientBeaconBalance')
    })

    it('should allow the router to withdraw a refund', async function () {
      const beaconBalance = ethers.parseEther('10')
      await mockRouter.connect(owner).setBeaconBalance(beaconBalance)

      const reduceAmount = ethers.parseEther('1')
      const updatedBalance = beaconBalance - reduceAmount
      const initialBeaconBalance = await stakeTogether.beaconBalance()

      expect(initialBeaconBalance).to.equal(beaconBalance)

      await expect(mockRouter.connect(user1).setBeaconBalance(updatedBalance, { value: updatedBalance }))
        .to.emit(stakeTogether, 'SetBeaconBalance')
        .withArgs(updatedBalance)

      expect(await stakeTogether.beaconBalance()).to.equal(updatedBalance)
    })

    it('should reject withdrawal from addresses other than the router', async function () {
      const refundValue = ethers.parseEther('1')

      await expect(
        stakeTogether.connect(user2).setBeaconBalance(refundValue, { value: refundValue }),
      ).to.be.revertedWithCustomError(stakeTogether, 'OnlyRouter')
    })
  })

  describe('Pool Creation', function () {
    // Test for a user with POOL_MANAGER_ROLE (the owner in this case)
    it('should correctly add pool by the owner', async function () {
      // Connect with an address that has the POOL_MANAGER_ROLE (the owner)
      const poolAddress = user3.address
      const isListed = true

      // Add the pool
      await stakeTogether.connect(owner).addPool(poolAddress, isListed, false, false)

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
      await stakeTogether
        .connect(userSigner)
        .addPool(poolAddress, isListed, false, false, { value: paymentAmount })

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
      await expect(
        stakeTogether.connect(owner).addPool(nullAddress, true, false, false),
      ).to.be.revertedWithCustomError(stakeTogether, 'ZeroAddress')
    })

    it('should reject adding a pool with an existing address', async function () {
      const poolAddress = user3.address
      const isListed = true

      // Owner adds the pool
      await stakeTogether.connect(owner).addPool(poolAddress, isListed, false, false)

      // Attempt to add the pool again and expect failure
      await expect(
        stakeTogether.connect(owner).addPool(poolAddress, isListed, false, false),
      ).to.be.revertedWithCustomError(stakeTogether, 'PoolExists')
    })

    it('should reject adding a pool when AddPool feature is disabled', async function () {
      // Setting the WithdrawPool feature to false
      const config = {
        validatorSize: ethers.parseEther('32'),
        poolSize: ethers.parseEther('32'),
        minDepositAmount: ethers.parseEther('0.1'), // Changing to a new value
        minWithdrawAmount: ethers.parseEther('0.0001'),
        depositLimit: ethers.parseEther('1000'),
        withdrawalPoolLimit: ethers.parseEther('1000'),
        withdrawalValidatorLimit: ethers.parseEther('1000'),
        blocksPerDay: 7200n,
        maxDelegations: 64n,
        withdrawDelay: 10n,
        withdrawBeaconDelay: 10n,
        feature: {
          AddPool: false,
          Deposit: false,
          WithdrawPool: false,
          WithdrawBeacon: false,
        },
      }

      // Set config by owner
      await stakeTogether.connect(owner).setConfig(config)
      // Attempt to add the pool and expect failure
      const poolAddress = user3.address
      await expect(
        stakeTogether
          .connect(user1)
          .addPool(poolAddress, true, false, false, { value: ethers.parseEther('1') }),
      ).to.be.revertedWithCustomError(stakeTogether, 'FeatureDisabled')
    })

    it('should correctly add pool with a specific value and mark as unlisted', async function () {
      const poolAddress = user3.address
      const isListed = false // Mark as unlisted
      const paymentAmount = ethers.parseEther('1') // The value to pass

      // Add the pool
      await stakeTogether
        .connect(owner)
        .addPool(poolAddress, isListed, false, false, { value: paymentAmount })

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
      await stakeTogether
        .connect(user1)
        .addPool(poolAddress, isListed, false, false, { value: paymentAmount })

      // Verify the pool has been added
      expect(await stakeTogether.pools(poolAddress)).to.be.true
    })

    it('should correctly remove a pool by an account with POOL_MANAGER_ROLE', async function () {
      // Add a pool first
      const poolAddress = user3.address
      const isListed = true
      await stakeTogether.connect(owner).addPool(poolAddress, isListed, false, false)

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
      await expect(
        stakeTogether.connect(owner).removePool(nonExistingPoolAddress),
      ).to.be.revertedWithCustomError(stakeTogether, 'PoolNotFound')
    })

    it('should handle the scenario where shares are equal to zero', async function () {
      // Add pools
      const poolAddress1 = user3.address
      const poolAddress2 = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress1, true, false, false)
      await stakeTogether.connect(owner).addPool(poolAddress2, true, false, false)

      // Verify that shares are initially zero for user1
      expect(await stakeTogether.shares(user1.address)).to.equal(0)

      // Create delegations without deposit (shares remain zero)
      const user1Delegations: {
        pool: string
        percentage: bigint
      }[] = []

      // Try to update delegations
      await expect(stakeTogether.connect(user1).updateDelegations(user1Delegations)).to.not.be.reverted // No error expected since shares are zero

      // Confirm that no changes were made (since shares were zero, no validation is done)
      for (const delegation of user1Delegations) {
        expect(await stakeTogether.pools(delegation.pool)).to.be.true
        expect(delegation.percentage).to.equal(0)
      }
    })
  })

  describe('Validators Oracle', function () {
    it('should grant the VALIDATOR_ORACLE_MANAGER_ROLE to admin, add an oracle', async function () {
      // Verify that admin doesn't have the VALIDATOR_ORACLE_MANAGER_ROLE
      expect(await stakeTogether.hasRole(VALIDATOR_ORACLE_MANAGER_ROLE, user6)).to.be.false

      // Grant the VALIDATOR_ORACLE_MANAGER_ROLE to admin (owner) using ADMIN_ROLE
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, user6)

      // Verify that admin now has the VALIDATOR_ORACLE_MANAGER_ROLE
      expect(await stakeTogether.hasRole(VALIDATOR_ORACLE_MANAGER_ROLE, user6)).to.be.true

      const newOracleAddress = user3.address

      // Connect with an address that has the VALIDATOR_ORACLE_MANAGER_ROLE (now admin)
      await stakeTogether.connect(user6).addValidatorOracle(newOracleAddress)

      // Verify that the oracle address has been granted the VALIDATOR_ORACLE_ROLE
      expect(await stakeTogether.hasRole(VALIDATOR_ORACLE_ROLE, newOracleAddress)).to.be.true

      // Verify that the oracle address has been added
      expect(await stakeTogether.isValidatorOracle(newOracleAddress)).to.be.true

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

    it('should add three oracle validators and they should be present', async function () {
      const newOracleAddress1 = user3.address
      const newOracleAddress2 = user4.address
      const newOracleAddress3 = user5.address

      // Grant the VALIDATOR_ORACLE_MANAGER_ROLE to admin
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, owner.address)

      // Add the oracle addresses
      await stakeTogether.connect(owner).addValidatorOracle(newOracleAddress1)
      await stakeTogether.connect(owner).addValidatorOracle(newOracleAddress2)
      await stakeTogether.connect(owner).addValidatorOracle(newOracleAddress3)

      // Verify that the oracle addresses were added
      expect(await stakeTogether.isValidatorOracle(newOracleAddress1)).to.be.true
      expect(await stakeTogether.isValidatorOracle(newOracleAddress2)).to.be.true
      expect(await stakeTogether.isValidatorOracle(newOracleAddress3)).to.be.true

      // Optionally, you can also check the total number of oracle validators if that's something your contract keeps track of
    })

    it('should remove an oracle address when called by manager ', async function () {
      const newOracleAddress1 = user3.address
      const newOracleAddress2 = user4.address

      // Grant the VALIDATOR_ORACLE_MANAGER_ROLE to admin
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, owner.address)

      // Add the oracle addresses (ensure they exist first)
      await stakeTogether.connect(owner).addValidatorOracle(newOracleAddress1)
      await stakeTogether.connect(owner).addValidatorOracle(newOracleAddress2)

      expect(await stakeTogether.isValidatorOracle(newOracleAddress1)).to.be.true
      expect(await stakeTogether.isValidatorOracle(newOracleAddress2)).to.be.true

      // Now, remove the first oracle address
      await stakeTogether.connect(owner).removeValidatorOracle(newOracleAddress1)

      expect(await stakeTogether.isValidatorOracle(newOracleAddress1)).to.be.false
      expect(await stakeTogether.isValidatorOracle(newOracleAddress2)).to.be.true

      // Verify that the oracle address has been revoked the VALIDATOR_ORACLE_ROLE
      expect(await stakeTogether.hasRole(VALIDATOR_ORACLE_ROLE, newOracleAddress1)).to.be.false

      // Verify the RemoveValidatorOracle event
      const eventFilter = stakeTogether.filters.RemoveValidatorOracle(newOracleAddress1)
      const logs = await stakeTogether.queryFilter(eventFilter)
      const event = logs[0]
      expect(event.args.account).to.equal(newOracleAddress1)
    })

    it('should revert if trying to remove a non-existing oracle address', async function () {
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, owner.address)

      const nonExistingOracleAddress = user5.address

      await expect(
        stakeTogether.connect(owner).removeValidatorOracle(nonExistingOracleAddress),
      ).to.be.revertedWithCustomError(stakeTogether, 'ValidatorOracleNotFound')
    })

    it('should correctly remove an oracle address that is not the last in the list', async function () {
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, owner.address)

      const oracleAddress1 = user3.address
      const oracleAddress2 = user4.address
      const oracleAddress3 = user5.address

      await stakeTogether.connect(owner).addValidatorOracle(oracleAddress1)
      await stakeTogether.connect(owner).addValidatorOracle(oracleAddress2)
      await stakeTogether.connect(owner).addValidatorOracle(oracleAddress3)

      await stakeTogether.connect(owner).removeValidatorOracle(oracleAddress2)

      expect(await stakeTogether.isValidatorOracle(oracleAddress1)).to.be.true
      expect(await stakeTogether.isValidatorOracle(oracleAddress2)).to.be.false
      expect(await stakeTogether.isValidatorOracle(oracleAddress3)).to.be.true

      await stakeTogether.connect(owner).removeValidatorOracle(oracleAddress3)

      expect(await stakeTogether.isValidatorOracle(oracleAddress1)).to.be.true
      expect(await stakeTogether.isValidatorOracle(oracleAddress2)).to.be.false
      expect(await stakeTogether.isValidatorOracle(oracleAddress3)).to.be.false
    })

    it('should return false if the address is not a validator oracle', async function () {
      const nonOracleAddress = user4.address

      // Verify that the address is not a validator oracle
      expect(await stakeTogether.isValidatorOracle(nonOracleAddress)).to.be.false
    })

    it('should return true if the address is validator oracle', async function () {
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, owner.address)

      const newOracleAddress1 = user3.address

      // Grant the VALIDATOR_ORACLE_MANAGER_ROLE to admin
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, owner.address)

      // Add the oracle addresses (ensure they exist first)
      await stakeTogether.connect(owner).addValidatorOracle(newOracleAddress1)

      // Verify that the address is not a validator oracle
      expect(await stakeTogether.isValidatorOracle(newOracleAddress1)).to.be.true
    })

    it('should advance the current oracle index when called by sentinel or manager', async function () {
      const sentinel = user5
      const newOracleAddress1 = user3.address
      const newOracleAddress2 = user4.address

      // Grant the VALIDATOR_ORACLE_MANAGER_ROLE to admin
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, owner)

      // Grant the VALIDATOR_ORACLE_SENTINEL_ROLE to sentinel
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_SENTINEL_ROLE, sentinel)

      // Add the oracle addresses
      await stakeTogether.connect(owner).addValidatorOracle(newOracleAddress1)
      await stakeTogether.connect(owner).addValidatorOracle(newOracleAddress2)

      // Check the initial current oracle index
      expect(await stakeTogether.isValidatorOracle(newOracleAddress1)).to.be.true

      // Force the next validator oracle using the sentinel role
      const tx1 = await stakeTogether.connect(sentinel).forceNextValidatorOracle()

      // Check that the current oracle index has advanced
      expect(await stakeTogether.isValidatorOracle(newOracleAddress2)).to.be.true

      // Check the NextValidatorOracle event
      await expect(tx1).to.emit(stakeTogether, 'NextValidatorOracle').withArgs(1, newOracleAddress2)

      // Force the next validator oracle using the sentinel role
      const tx2 = await stakeTogether.connect(owner).forceNextValidatorOracle()

      // Check that the current oracle index has advanced
      expect(await stakeTogether.isValidatorOracle(newOracleAddress1)).to.be.true

      // Check the NextValidatorOracle event
      await expect(tx2).to.emit(stakeTogether, 'NextValidatorOracle').withArgs(0, newOracleAddress1)
    })

    it('should revert if called by an address without role ', async function () {
      const unauthorizedAddress = user1

      // Attempt to force the next validator oracle using an unauthorized address
      await expect(stakeTogether.connect(unauthorizedAddress).forceNextValidatorOracle()).to.be.reverted
    })
  })

  describe('Validators', () => {
    const publicKey =
      '0x954c931791b73c03c5e699eb8da1222b221b098f6038282ff7e32a4382d9e683f0335be39b974302e42462aee077cf93'
    const signature =
      '0x967d1b93d655752e303b43905ac92321c048823e078cadcfee50eb35ede0beae1501a382a7c599d6e9b8a6fd177ab3d711c44b2115ac90ea1dc7accda6d0352093eaa5f2bc9f1271e1725b43b3a74476b9e749fc011de4a63d9e72cf033978ed'
    const depositDataRoot = '0x4ef3924ceb993cbc51320f44cb28ffb50071deefd455ce61feabb7b6b2f1d0e8'

    it('should create a new validator', async function () {
      const poolSize = ethers.parseEther('32.1')
      const validatorSize = ethers.parseEther('32')

      const oracle = user1
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, owner)
      await stakeTogether.connect(owner).addValidatorOracle(oracle)

      await owner.sendTransaction({ to: stakeTogetherProxy, value: poolSize })

      const tx = await stakeTogether.connect(oracle).addValidator(publicKey, signature, depositDataRoot)

      const withdrawalCredentials = await stakeTogether.withdrawalCredentials()

      await expect(tx)
        .to.emit(stakeTogether, 'AddValidator')
        .withArgs(
          oracle.address,
          validatorSize,
          publicKey,
          withdrawalCredentials,
          signature,
          depositDataRoot,
        )

      const beaconBalance = await stakeTogether.beaconBalance()
      expect(beaconBalance).to.equal(validatorSize)

      expect(await stakeTogether.validators(publicKey)).to.be.true
    })

    it('should cycle through oracles and ensure order of validator creation', async function () {
      const oracle1 = user1
      const oracle2 = user2
      const oracle3 = user3
      const oracle4 = user4
      const oracle5 = user5

      let incremented = BigInt(publicKey) + 1n
      function incrementPublicKey() {
        incremented = BigInt(incremented) + 1n
        return '0x' + incremented.toString(16).padStart(64, '0')
      }

      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, owner)
      await stakeTogether.connect(owner).addValidatorOracle(oracle1)
      await stakeTogether.connect(owner).addValidatorOracle(oracle2)
      await stakeTogether.connect(owner).addValidatorOracle(oracle3)
      await stakeTogether.connect(owner).addValidatorOracle(oracle4)
      await stakeTogether.connect(owner).addValidatorOracle(oracle5)

      const validatorSize = ethers.parseEther('32')
      const poolSize = ethers.parseEther('32.1') * 6n

      await owner.sendTransaction({ to: stakeTogetherProxy, value: poolSize })

      await stakeTogether.connect(oracle1).addValidator(publicKey, signature, depositDataRoot)
      let nextPublicKey = incrementPublicKey()

      await expect(
        stakeTogether.connect(oracle3).addValidator(nextPublicKey, signature, depositDataRoot),
      ).to.be.revertedWithCustomError(stakeTogether, 'NotIsCurrentValidatorOracle')

      nextPublicKey = incrementPublicKey()
      await stakeTogether.connect(oracle2).addValidator(nextPublicKey, signature, depositDataRoot)

      await expect(
        stakeTogether.connect(oracle1).addValidator(nextPublicKey, signature, depositDataRoot),
      ).to.be.revertedWithCustomError(stakeTogether, 'NotIsCurrentValidatorOracle')

      nextPublicKey = incrementPublicKey()
      await stakeTogether.connect(oracle3).addValidator(nextPublicKey, signature, depositDataRoot)

      await expect(
        stakeTogether.connect(oracle5).addValidator(nextPublicKey, signature, depositDataRoot),
      ).to.be.revertedWithCustomError(stakeTogether, 'NotIsCurrentValidatorOracle')

      nextPublicKey = incrementPublicKey()
      await stakeTogether.connect(oracle4).addValidator(nextPublicKey, signature, depositDataRoot)

      nextPublicKey = incrementPublicKey()
      await stakeTogether.connect(oracle5).addValidator(nextPublicKey, signature, depositDataRoot)

      nextPublicKey = incrementPublicKey()
      const tx = await stakeTogether
        .connect(oracle1)
        .addValidator(nextPublicKey, signature, depositDataRoot)

      const withdrawalCredentials = await stakeTogether.withdrawalCredentials()
      await expect(tx)
        .to.emit(stakeTogether, 'AddValidator')
        .withArgs(
          oracle1.address,
          validatorSize,
          nextPublicKey,
          withdrawalCredentials,
          signature,
          depositDataRoot,
        )

      const beaconBalance = await stakeTogether.beaconBalance()
      expect(beaconBalance).to.equal(validatorSize * 6n)

      expect(await stakeTogether.validators(nextPublicKey)).to.be.true
    })

    it('should fail to create a validator by an invalid oracle', async function () {
      const invalidOracle = user2

      await expect(
        stakeTogether.connect(invalidOracle).addValidator(publicKey, signature, depositDataRoot),
      ).to.be.revertedWithCustomError(stakeTogether, 'OnlyValidatorOracle')
    })

    it('should fail to create a validator when the contract balance is less than pool size', async function () {
      const oracle = user1
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, owner)
      await stakeTogether.connect(owner).addValidatorOracle(oracle)

      const insufficientFunds = ethers.parseEther('30') // Insufficient value
      await owner.sendTransaction({ to: stakeTogetherProxy, value: insufficientFunds })

      await expect(
        stakeTogether.connect(oracle).addValidator(publicKey, signature, depositDataRoot),
      ).to.be.revertedWithCustomError(stakeTogether, 'NotEnoughBalanceOnPool')
    })

    it('should fail to create a validator with an existing public key', async function () {
      const poolSize = ethers.parseEther('32.1')

      const oracle = user1
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, owner)
      await stakeTogether.connect(owner).addValidatorOracle(oracle)

      // Sending sufficient funds for pool size and validator size
      await owner.sendTransaction({ to: stakeTogetherProxy, value: poolSize * 2n })

      // Creating the first validator
      await stakeTogether.connect(oracle).addValidator(publicKey, signature, depositDataRoot)

      // Attempting to create a second validator with the same public key
      await expect(
        stakeTogether.connect(oracle).addValidator(publicKey, signature, depositDataRoot),
      ).to.be.revertedWithCustomError(stakeTogether, 'ValidatorExists')
    })

    it('should create a new validator ', async function () {
      const poolSize = ethers.parseEther('32.1')

      const oracle = user1
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, owner)
      await stakeTogether.connect(owner).addValidatorOracle(oracle)

      // Sending sufficient funds for pool size and validator size
      await owner.sendTransaction({ to: stakeTogetherProxy, value: poolSize })

      // Creating the validator
      const tx = await stakeTogether.connect(oracle).addValidator(publicKey, signature, depositDataRoot)
    })

    it('should set the beacon balance through the router', async function () {
      const beaconBalance = ethers.parseEther('10')
      await mockRouter.connect(owner).setBeaconBalance(beaconBalance)
      expect(await stakeTogether.beaconBalance()).to.equal(beaconBalance)
    })

    it('should fail to set the beacon balance by non-router address', async function () {
      const beaconBalance = ethers.parseEther('10')
      await expect(
        stakeTogether.connect(user1).setBeaconBalance(beaconBalance),
      ).to.be.revertedWithCustomError(stakeTogether, 'OnlyRouter')
    })
  })

  describe('Fees', function () {
    it('should correctly distribute the fee among roles and mint shares accordingly', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee

      const user1Delegations = [{ pool: poolAddress, percentage: ethers.parseEther('1') }]

      await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, ethers.toUtf8Bytes(await user3.getAddress()), {
          value: user1DepositAmount,
        })

      const totalShares = await stakeTogether.totalShares()
      expect(totalShares).to.equal(user1DepositAmount + initialBalance)

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

      const feeValue = ethers.parseEther('0.003')
      expect(await stakeTogether.getFee(0)).to.equal(feeValue)
    })

    it('should only allow admin to set fee', async function () {
      const feeValue = ethers.parseEther('0.05')
      const allocations = [250000, 250000, 250000, 250000]
      await expect(stakeTogether.connect(user1).setFee(0, feeValue, allocations)).to.be.reverted
    })

    it('should require allocations length to be 4', async function () {
      const feeValue = ethers.parseEther('0.05')
      const allocations = [250000, 250000, 250000, 250000]
      await expect(
        stakeTogether.connect(owner).setFee(1, feeValue, [250000]),
      ).to.be.revertedWithCustomError(stakeTogether, 'InvalidLength')
    })

    it('should require sum of allocations to be 1 ether', async function () {
      const feeValue = ethers.parseEther('0.05')
      const allocations = [250000, 250000, 250000, 250000]
      await expect(
        stakeTogether.connect(owner).setFee(2, feeValue, [250000, 250000, 250000, 300000]),
      ).to.be.revertedWithCustomError(stakeTogether, 'InvalidSum')
    })

    it('should successfully set fee for ProcessStakeValidator (index 3)', async function () {
      const feeValue = ethers.parseEther('0.1')
      const allocations = [
        ethers.parseEther('0.25'),
        ethers.parseEther('0.25'),
        ethers.parseEther('0.25'),
        ethers.parseEther('0.25'),
      ]

      const feeType = 3

      const tx = await stakeTogether.connect(owner).setFee(feeType, feeValue, allocations)

      await expect(tx).to.emit(stakeTogether, 'SetFee').withArgs(feeType, feeValue, allocations)
    })

    describe('Revert', function () {
      beforeEach(async function () {
        await stakeTogether.setFee(0n, ethers.parseEther('0.003'), [
          ethers.parseEther('0.6'),
          0n,
          ethers.parseEther('0.4'),
          0n,
        ])
        await stakeTogether.setFee(1n, ethers.parseEther('0.09'), [
          ethers.parseEther('0.33'),
          ethers.parseEther('0.33'),
          ethers.parseEther('0.34'),
          0n,
        ])
        await stakeTogether.setFee(2n, ethers.parseEther('1'), [
          ethers.parseEther('0.4'),
          0n,
          ethers.parseEther('0.6'),
          0n,
        ])
        await stakeTogether.setFee(3n, ethers.parseEther('0.01'), [0n, 0n, ethers.parseEther('1'), 0n])
      })
    })
  })

  describe('Transfer', function () {
    it('should successfully transfer amount and emit Transfer event', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const fee = (user1DepositAmount * 3n) / 1000n
      const user1SharesAfterDeposit = user1DepositAmount - fee

      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)
      await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, ethers.toUtf8Bytes(await user3.getAddress()), {
          value: user1DepositAmount,
        })

      for (let i = 0; i < 100; i++) {
        await network.provider.send('evm_mine')
      }

      const amountToTransfer = ethers.parseEther('2')
      const tx = await stakeTogether.connect(user1).transfer(user2.address, amountToTransfer)

      await expect(tx)
        .to.emit(stakeTogether, 'Transfer')
        .withArgs(user1.address, user2.address, amountToTransfer)

      const user1BalanceAfterTransfer = await stakeTogether.balanceOf(user1.address)
      const user2BalanceAfterTransfer = await stakeTogether.balanceOf(user2.address)

      expect(user1BalanceAfterTransfer).to.equal(user1DepositAmount - amountToTransfer - fee)
      expect(user2BalanceAfterTransfer).to.equal(amountToTransfer)
    })

    it('should fail if _to address is zero', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const fee = (user1DepositAmount * 3n) / 1000n
      const user1SharesAfterDeposit = user1DepositAmount - fee

      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)
      await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, ethers.toUtf8Bytes(await user3.getAddress()), {
          value: user1DepositAmount,
        })

      await expect(stakeTogether.connect(user1).transfer(nullAddress, ethers.parseEther('2'))).to.be
        .reverted
    })

    it('should fail if _amount is greater than balance owned by _from', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const fee = (user1DepositAmount * 3n) / 1000n
      const user1SharesAfterDeposit = user1DepositAmount - fee

      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)
      await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, ethers.toUtf8Bytes(await user3.getAddress()), {
          value: user1DepositAmount,
        })

      for (let i = 0; i < 100; i++) {
        await network.provider.send('evm_mine')
      }

      const user1Balance = await stakeTogether.balanceOf(user1.address)
      await expect(
        stakeTogether.connect(user1).transfer(user2.address, user1Balance + 1n),
      ).to.be.revertedWithCustomError(stakeTogether, 'InsufficientShares')
    })

    it('should transfer from one address to another using an approved spender and emit Transfer event', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const fee = (user1DepositAmount * 3n) / 1000n
      const user1SharesAfterDeposit = user1DepositAmount - fee

      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)
      await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, ethers.toUtf8Bytes(await user3.getAddress()), {
          value: user1DepositAmount,
        })

      const amountToApprove = ethers.parseEther('50')
      const amountToTransfer = ethers.parseEther('20')
      const initialUser1Balance = user1SharesAfterDeposit

      await stakeTogether.connect(user1).approve(user2.address, amountToApprove)

      const tx = await stakeTogether
        .connect(user2)
        .transferFrom(user1.address, user3.address, amountToTransfer)

      await expect(tx)
        .to.emit(stakeTogether, 'Transfer')
        .withArgs(user1.address, user3.address, amountToTransfer)

      const remainingAllowance = await stakeTogether.allowance(user1.address, user2.address)
      expect(remainingAllowance).to.equal(amountToApprove - amountToTransfer)

      const user1Balance = await stakeTogether.shares(user1.address)
      const user3Balance = await stakeTogether.shares(user3.address)
      expect(user1Balance).to.equal(initialUser1Balance - amountToTransfer)
      expect(user3Balance).to.equal(amountToTransfer)
    })

    it('should permit a spender and allow them to transfer funds', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const fee = (user1DepositAmount * 3n) / 1000n
      const user1SharesAfterDeposit = user1DepositAmount - fee

      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)
      await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, ethers.toUtf8Bytes(await user3.getAddress()), {
          value: user1DepositAmount,
        })

      const amountToApprove = ethers.parseEther('50')
      const nonce = await stakeTogether.nonces(user1.address)
      const deadline = ethers.MaxUint256
      const domain = {
        name: 'Stake Together Protocol',
        version: '1',
        chainId: await network.provider.send('eth_chainId'),
        verifyingContract: stakeTogetherProxy,
      }
      const types = {
        Permit: [
          { name: 'owner', type: 'address' },
          { name: 'spender', type: 'address' },
          { name: 'value', type: 'uint256' },
          { name: 'nonce', type: 'uint256' },
          { name: 'deadline', type: 'uint256' },
        ],
      }
      const value = {
        owner: user1.address,
        spender: user2.address,
        value: amountToApprove.toString(),
        nonce: nonce.toString(),
        deadline: deadline.toString(),
      }
      const signature = await user1.signTypedData(domain, types, value)
      const sig = ethers.getBytes(signature)
      const r = ethers.hexlify(sig.slice(0, 32))
      const s = ethers.hexlify(sig.slice(32, 64))
      const v = sig[64] < 27 ? sig[64] + 27 : sig[64]

      await stakeTogether
        .connect(user2)
        .permit(user1.address, user2.address, amountToApprove, deadline, v, r, s)

      const newAllowance = await stakeTogether.allowance(user1.address, user2.address)
      expect(newAllowance).to.equal(amountToApprove)

      await stakeTogether.connect(user2).transferFrom(user1.address, user3.address, amountToApprove)

      const newUser1Balance = await stakeTogether.balanceOf(user1.address)
      expect(newUser1Balance).to.equal(user1SharesAfterDeposit - amountToApprove)

      const newUser2Balance = await stakeTogether.balanceOf(user3.address)
      expect(newUser2Balance).to.equal(amountToApprove)
    })

    it('should successfully transfer when neither sender nor receiver is in anti-fraud list', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const transferAmount = ethers.parseEther('10')
      const poolAddress = user3.address
      const fee = (user1DepositAmount * 3n) / 1000n

      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)
      await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, ethers.toUtf8Bytes(await user3.getAddress()), {
          value: user1DepositAmount,
        })

      for (let i = 0; i < 100; i++) {
        await network.provider.send('evm_mine')
      }

      const tx = await stakeTogether.connect(user1).transfer(user2.address, transferAmount)

      await expect(tx)
        .to.emit(stakeTogether, 'Transfer')
        .withArgs(user1.address, user2.address, transferAmount)

      const user1BalanceAfterTransfer = await stakeTogether.balanceOf(user1.address)
      const user2BalanceAfterTransfer = await stakeTogether.balanceOf(user2.address)

      expect(user1BalanceAfterTransfer).to.equal(user1DepositAmount - transferAmount - fee)
      expect(user2BalanceAfterTransfer).to.equal(transferAmount)
    })

    it('should fail transfer when sender is in anti-fraud list', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const transferAmount = ethers.parseEther('10')
      const poolAddress = user3.address
      const fee = (user1DepositAmount * 3n) / 1000n

      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)
      await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, ethers.toUtf8Bytes(await user3.getAddress()), {
          value: user1DepositAmount,
        })

      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await stakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)

      await stakeTogether.connect(owner).addToAntiFraud(user1.address)

      await expect(
        stakeTogether.connect(user1).transfer(user2.address, transferAmount),
      ).to.be.revertedWithCustomError(stakeTogether, 'ListedInAntiFraud')
    })

    it('should fail transfer when receiver is in anti-fraud list', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const transferAmount = ethers.parseEther('10')
      const poolAddress = user3.address

      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)
      await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, ethers.toUtf8Bytes(await user3.getAddress()), {
          value: user1DepositAmount,
        })

      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await stakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)

      await stakeTogether.connect(owner).addToAntiFraud(user2.address)

      await expect(
        stakeTogether.connect(user1).transfer(user2.address, transferAmount),
      ).to.be.revertedWithCustomError(stakeTogether, 'ListedInAntiFraud')
    })

    it('should fail transferFrom when the _from address is in the anti-fraud list', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const transferAmount = ethers.parseEther('10')
      const poolAddress = user3.address

      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)
      await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, ethers.toUtf8Bytes(await user3.getAddress()), {
          value: user1DepositAmount,
        })

      await stakeTogether.connect(user1).approve(owner.address, transferAmount)

      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await stakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)

      await stakeTogether.connect(owner).addToAntiFraud(user1.address)

      await expect(
        stakeTogether.connect(owner).transferFrom(user1.address, user2.address, transferAmount),
      ).to.be.revertedWithCustomError(stakeTogether, 'ListedInAntiFraud')
    })

    it('should fail transferFrom when the _to address is in the anti-fraud list', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const transferAmount = ethers.parseEther('10')
      const poolAddress = user3.address

      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)
      await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, ethers.toUtf8Bytes(await user3.getAddress()), {
          value: user1DepositAmount,
        })

      await stakeTogether.connect(user1).approve(owner.address, transferAmount)

      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await stakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)

      await stakeTogether.connect(owner).addToAntiFraud(user2.address)

      await expect(
        stakeTogether.connect(owner).transferFrom(user1.address, user2.address, transferAmount),
      ).to.be.revertedWithCustomError(stakeTogether, 'ListedInAntiFraud')
    })

    it('should successfully transferFrom when neither _from nor _to is in the anti-fraud list', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const transferAmount = ethers.parseEther('10')
      const poolAddress = user3.address

      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)
      await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, ethers.toUtf8Bytes(await user3.getAddress()), {
          value: user1DepositAmount,
        })

      await stakeTogether.connect(user1).approve(owner.address, transferAmount)

      const tx = await stakeTogether
        .connect(owner)
        .transferFrom(user1.address, user2.address, transferAmount)

      await expect(tx)
        .to.emit(stakeTogether, 'Transfer')
        .withArgs(user1.address, user2.address, transferAmount)
    })
  })

  describe('Shares', function () {
    it('should approve an amount for a spender and emit Approval event', async function () {
      const amountToApprove = ethers.parseEther('50')

      const tx = await stakeTogether.connect(user1).approve(user2.address, amountToApprove)

      await expect(tx)
        .to.emit(stakeTogether, 'Approval')
        .withArgs(user1.address, user2.address, amountToApprove)

      const allowanceAfterApprove = await stakeTogether.allowance(user1.address, user2.address)
      expect(allowanceAfterApprove).to.equal(amountToApprove)
    })

    it('should fail to approve if _spender address is zero', async function () {
      const amountToApprove = ethers.parseEther('50')

      await expect(
        stakeTogether.connect(user1).approve(nullAddress, amountToApprove),
      ).to.be.revertedWithCustomError(stakeTogether, 'ZeroAddress')
    })

    it('should return correct allowance', async function () {
      const amountToApprove = ethers.parseEther('50')

      await stakeTogether.connect(user1).approve(user2.address, amountToApprove)

      const allowance = await stakeTogether.allowance(user1.address, user2.address)

      expect(allowance).to.equal(amountToApprove)
    })
  })

  describe('Accounting', () => {
    let poolAddress: string
    let initialBalance = ethers.parseEther('1')
    let initialShares = ethers.parseEther('1')

    beforeEach(async function () {
      poolAddress = user3.address
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)
    })

    it('Stake Entry', async function () {
      const users = [user1, user2]
      const referral = user4.address
      const depositAmount = ethers.parseEther('1')
      const poolPercentage = ethers.parseEther('1')
      const delegations = [{ pool: poolAddress, percentage: poolPercentage }]

      let totalSharesFee = 0n
      let totalUserShares = 0n
      let totalShares = initialShares

      for (const user of users) {
        const stakeEntryFee = (depositAmount * 3n) / 1000n
        const liquidDepositAmount = depositAmount - stakeEntryFee

        totalSharesFee += stakeEntryFee
        totalUserShares += liquidDepositAmount
        totalShares += liquidDepositAmount

        await stakeTogether.connect(user).depositPool(poolAddress, referral, { value: depositAmount })

        const userBalance = await stakeTogether.balanceOf(user.address)
        expect(userBalance).to.equal(liquidDepositAmount)
      }

      const expectedTotalShares = await stakeTogether.totalShares()
      const expectedTotalBalance = await ethers.provider.getBalance(stakeTogether)
      const expectedInitialRatio = initialBalance / initialShares

      expect(expectedTotalShares).to.equal(initialShares + totalUserShares + totalSharesFee)
      expect(expectedTotalBalance).to.equal(initialBalance + totalUserShares + totalSharesFee)
      expect(expectedInitialRatio).to.equal(1n)

      // Send 3 Ether to the contract
      const sentEtherAmount = ethers.parseEther('3')
      await owner.sendTransaction({ to: stakeTogetherProxy, value: sentEtherAmount })

      // User 1
      const totalShares1 = await stakeTogether.totalShares()
      const userShares1 = await stakeTogether.shares(user1.address)
      const userParticipation1 = (userShares1 * ethers.parseEther('1')) / totalShares1
      const userRewards1 = (sentEtherAmount * userParticipation1) / ethers.parseEther('1')
      const newUserShares1 = userShares1 / 2n
      const newTotalUserShares1 = userShares1 + newUserShares1

      // User 2
      const totalShares2 = await stakeTogether.totalShares()
      const userShares2 = await stakeTogether.shares(user2.address)
      const userParticipation2 = (userShares2 * ethers.parseEther('1')) / totalShares2
      const userRewards2 = (sentEtherAmount * userParticipation2) / ethers.parseEther('1')
      const newUserShares2 = userShares2 / 2n
      const newTotalUserShares2 = userShares2 + newUserShares2

      // Deposits

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: depositAmount })
      await stakeTogether.connect(user2).depositPool(poolAddress, referral, { value: depositAmount })

      const stakeEntryFee = (depositAmount * 3n) / 1000n
      const liquidDepositAmount = depositAmount - stakeEntryFee

      totalSharesFee += stakeEntryFee
      totalUserShares += newUserShares1 + newUserShares2

      // Accounting User 1

      const userFinalBalance1 = await stakeTogether.balanceOf(user1.address)
      const userFinalShares1 = await stakeTogether.shares(user1.address)

      expect(userFinalBalance1).to.equal(liquidDepositAmount * 2n + (userRewards1 + 1n)) // round up
      expect(userFinalShares1).to.equal(newTotalUserShares1)

      // Accounting User 2

      // console.log('user')

      const userFinalBalance2 = await stakeTogether.balanceOf(user2.address)
      const userFinalShares2 = await stakeTogether.shares(user2.address)

      expect(userFinalBalance2).to.equal(liquidDepositAmount * 2n + (userRewards2 + 1n)) // round up
      expect(userFinalShares2).to.equal(newTotalUserShares2)

      // console.log('User 2 Final Balance:', userFinalBalance2.toString())
      // console.log('User 2 Final Shares:', userFinalShares2.toString())

      // Total Balances

      const finalTotalBalance = await ethers.provider.getBalance(stakeTogether)
      const finalTotalShares = await stakeTogether.totalShares()

      expect(finalTotalBalance).to.equal(depositAmount * 4n + sentEtherAmount + initialBalance)
      expect(finalTotalShares).to.equal(totalSharesFee + totalUserShares + initialShares)

      // console.log('Final Total Balance:', finalTotalBalance.toString())
      // console.log('Final Total Shares:', finalTotalShares.toString())
    })

    it('Stake Rewards', async function () {
      const users = [user1, user2]
      const referral = user4.address
      const depositAmount = ethers.parseEther('1')
      const poolPercentage = ethers.parseEther('1')

      const poolAddress = user3.address

      let totalSharesFee = 0n
      let totalUserShares = 0n
      let totalShares = initialShares

      for (const user of users) {
        const stakeEntryFee = (depositAmount * 3n) / 1000n
        const liquidDepositAmount = depositAmount - stakeEntryFee

        totalSharesFee += stakeEntryFee
        totalUserShares += liquidDepositAmount
        totalShares += liquidDepositAmount

        await stakeTogether.connect(user).depositPool(poolAddress, referral, { value: depositAmount })

        const userBalance = await stakeTogether.balanceOf(user.address)

        // console.log('userBalance Before', userBalance.toString())
        expect(userBalance).to.equal(liquidDepositAmount)
      }

      const expectedTotalShares = await stakeTogether.totalShares()
      const expectedTotalBalance = await ethers.provider.getBalance(stakeTogether)
      const expectedInitialRatio = initialBalance / initialShares

      expect(expectedTotalShares).to.equal(initialShares + totalUserShares + totalSharesFee)
      expect(expectedTotalBalance).to.equal(initialBalance + totalUserShares + totalSharesFee)
      expect(expectedInitialRatio).to.equal(1n)

      // Process Stake Rewards

      const rewardsAmount = ethers.parseEther('3')
      const rewardsSharesAmount = (totalShares * ethers.parseEther('0.588')) / ethers.parseEther('1')
      // Calculated Off-Chain by Oracle with function to calculate the closest share amount

      // During de processFeeRewards, the distribute fee will apply the fee to the rewards, tha will reduce the amount of shares
      const tx1 = await mockRouter.connect(user1).processFeeRewards(rewardsSharesAmount, {
        value: rewardsAmount,
      })

      await tx1.wait()

      const events = await stakeTogether.queryFilter(stakeTogether.filters.MintFeeShares())

      const specificFeeType = 1n

      let totalNewShares = 0n

      events.forEach((event) => {
        const args = event.args
        if (args && args.feeType === specificFeeType) {
          totalNewShares += args[1]

          // console.log(args[1])
        }
      })

      const valuationNewShares = await stakeTogether.weiByShares(totalNewShares)

      // Oracle = TotalProfitShares (considering the fee reduction)
      // Distribute Fee will reduce the amount of shares by fee amount

      const epsilon = 1000000000000000n
      const expectedValue = ethers.parseEther('0.3')

      const difference =
        valuationNewShares > expectedValue
          ? valuationNewShares - expectedValue
          : expectedValue - valuationNewShares

      const isApproxEqual = difference < epsilon

      expect(isApproxEqual).to.be.true

      const updatedTotalBalance = await ethers.provider.getBalance(stakeTogether)
      expect(updatedTotalBalance).to.equal(
        initialBalance + totalUserShares + totalSharesFee + rewardsAmount,
      )

      expect(updatedTotalBalance).to.equal(ethers.parseEther('6'))
    })
  })

  describe('Accounting', () => {
    let initialBalance = ethers.parseEther('1')
    let initialShares = ethers.parseEther('1')

    it('Stake Pool', async function () {
      const depositAmount = ethers.parseEther('1')

      await stakeTogether
        .connect(owner)
        .addPool(user3.address, true, false, false, { value: depositAmount })

      const balance = await ethers.provider.getBalance(stakeTogether)
      expect(balance).to.equal(initialBalance + depositAmount)

      const totalShares = await stakeTogether.totalShares()

      expect(totalShares).to.equal(initialShares + depositAmount)

      const sentEtherAmount = ethers.parseEther('1')
      await owner.sendTransaction({ to: stakeTogetherProxy, value: sentEtherAmount })

      const balance2 = await ethers.provider.getBalance(stakeTogether)
      expect(balance2).to.equal(initialBalance + depositAmount + depositAmount)

      const totalShares2 = await stakeTogether.totalShares()
      expect(totalShares2).to.equal(initialShares + depositAmount)

      await stakeTogether
        .connect(owner)
        .addPool(user4.address, true, false, false, { value: depositAmount })

      const balance3 = await ethers.provider.getBalance(stakeTogether)
      expect(balance3).to.equal(initialBalance + depositAmount + depositAmount + depositAmount)

      const totalShares3 = await stakeTogether.totalShares()
      expect(totalShares3).to.equal(initialShares + depositAmount + (depositAmount / 3n) * 2n - 1n)
    })
  })

  describe('Anti-Fraud', () => {
    it('should fail to add an address to anti-fraud list without the necessary role', async function () {
      const addressToAdd = user2.address

      await expect(
        stakeTogether.connect(user2).addToAntiFraud(addressToAdd),
      ).to.be.revertedWithCustomError(stakeTogether, 'NotAuthorized')
    })

    it('should fail to add zero address to anti-fraud list', async function () {
      const zeroAddress = nullAddress
      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()

      await stakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)

      await expect(
        stakeTogether.connect(owner).addToAntiFraud(zeroAddress),
      ).to.be.revertedWithCustomError(stakeTogether, 'ZeroAddress')
    })

    it('should successfully add an address to anti-fraud list', async function () {
      const addressToAdd = user2.address
      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()

      await stakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)

      await expect(stakeTogether.connect(owner).addToAntiFraud(addressToAdd))
        .to.emit(stakeTogether, 'SetAntiFraudStatus')
        .withArgs(owner.address, addressToAdd, true)

      const isListed = await stakeTogether.isListedInAntiFraud(addressToAdd)
      expect(isListed).to.equal(true)
    })

    it('should fail to remove an address from anti-fraud list without the necessary role', async function () {
      const addressToRemove = user2.address

      await expect(
        stakeTogether.connect(user1).removeFromAntiFraud(addressToRemove),
      ).to.be.revertedWithCustomError(stakeTogether, 'NotAuthorized')
    })

    it('should fail to remove zero address from anti-fraud list', async function () {
      const zeroAddress = nullAddress
      const ANTI_FRAUD_MANAGER_ROLE = await stakeTogether.ANTI_FRAUD_MANAGER_ROLE()

      await stakeTogether.connect(owner).grantRole(ANTI_FRAUD_MANAGER_ROLE, owner.address)

      await expect(
        stakeTogether.connect(owner).removeFromAntiFraud(zeroAddress),
      ).to.be.revertedWithCustomError(stakeTogether, 'ZeroAddress')
    })

    it('should successfully remove an address from anti-fraud list', async function () {
      const addressToRemove = user2.address
      const ANTI_FRAUD_MANAGER_ROLE = await stakeTogether.ANTI_FRAUD_MANAGER_ROLE()
      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()

      await stakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await stakeTogether.connect(owner).grantRole(ANTI_FRAUD_MANAGER_ROLE, owner.address)

      await stakeTogether.connect(owner).addToAntiFraud(addressToRemove)

      await expect(stakeTogether.connect(owner).removeFromAntiFraud(addressToRemove))
        .to.emit(stakeTogether, 'SetAntiFraudStatus')
        .withArgs(owner.address, addressToRemove, false)

      const isListed = await stakeTogether.isListedInAntiFraud(addressToRemove)
      expect(isListed).to.equal(false)
    })

    it('should fail if the address is not in the anti-fraud list', async function () {
      const innocentAddress = user3.address
      const ANTI_FRAUD_MANAGER_ROLE = await stakeTogether.ANTI_FRAUD_MANAGER_ROLE()
      await stakeTogether.connect(owner).grantRole(ANTI_FRAUD_MANAGER_ROLE, owner.address)

      await expect(
        stakeTogether.connect(owner).removeFromAntiFraud(innocentAddress),
      ).to.be.revertedWithCustomError(stakeTogether, 'NotInAntiFraudList')
    })

    it('should return true if an address is in the anti-fraud list', async function () {
      const suspectAddress = user2.address
      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await stakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)

      await stakeTogether.connect(owner).addToAntiFraud(suspectAddress)

      const isListed = await stakeTogether.isListedInAntiFraud(suspectAddress)
      expect(isListed).to.equal(true)
    })

    it('should return false if an address is not in the anti-fraud list', async function () {
      const innocentAddress = user3.address

      const isNotListed = await stakeTogether.isListedInAntiFraud(innocentAddress)
      expect(isNotListed).to.equal(false)
    })

    it('should return false after an address is removed from the anti-fraud list', async function () {
      const suspectAddress = user2.address
      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      const ANTI_FRAUD_MANAGER_ROLE = await stakeTogether.ANTI_FRAUD_MANAGER_ROLE()

      await stakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await stakeTogether.connect(owner).grantRole(ANTI_FRAUD_MANAGER_ROLE, owner.address)

      await stakeTogether.connect(owner).addToAntiFraud(suspectAddress)
      await stakeTogether.connect(owner).removeFromAntiFraud(suspectAddress)

      const isListed = await stakeTogether.isListedInAntiFraud(suspectAddress)
      expect(isListed).to.equal(false)
    })
  })

  describe('Rewards', () => {
    it('should claim', async function () {
      const user5Balance = await stakeTogether.balanceOf(user5.address)
      expect(user5Balance).to.equal(0n)

      const user2Balance = await stakeTogether.balanceOf(user2.address)
      expect(user2Balance).to.equal(0n)

      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true, false, false)

      const fee = (user1DepositAmount * 3n) / 1000n

      await stakeTogether.connect(owner).setFeeAddress(0, await airdrop.getAddress())

      const tx1 = await stakeTogether
        .connect(user1)
        .depositPool(poolAddress, referral, { value: user1DepositAmount })
      await tx1.wait()

      const reportBlock = 1n
      const index0 = 0n
      const index1 = 1n

      // 1
      const values: [bigint, bigint, string, bigint][] = [
        [index0, reportBlock, user5.address, 50000000000000n],
        [index1, reportBlock, user2.address, 25000000000000n],
      ]

      // 2
      const tree = StandardMerkleTree.of(values, ['uint256', 'uint256', 'address', 'uint256'])
      const proof1 = tree.getProof([index0, reportBlock, user5.address, 50000000000000n])
      const proof2 = tree.getProof([index1, reportBlock, user2.address, 25000000000000n])

      // 3
      await mockRouter.connect(owner).addMerkleRoot(reportBlock, tree.root)

      // 4
      await expect(
        airdrop.connect(user1).claim(reportBlock, index0, user5.address, 50000000000000n, proof1),
      )
        .to.emit(airdrop, 'Claim')
        .withArgs(reportBlock, index0, user5.address, 50000000000000n, proof1)

      await expect(
        airdrop.connect(user1).claim(reportBlock, index0, user5.address, 50000000000000n, proof1),
      ).to.be.revertedWithCustomError(airdrop, 'AlreadyClaimed')

      expect(await airdrop.isClaimed(reportBlock, index0)).to.equal(true)
      expect(await airdrop.isClaimed(reportBlock, index1)).to.equal(false)

      await airdrop.connect(user1).claim(reportBlock, index1, user2.address, 25000000000000n, proof2)

      expect(await airdrop.isClaimed(reportBlock, index1)).to.equal(true)

      const user5BalanceUpdated = await stakeTogether.balanceOf(user5.address)
      expect(user5BalanceUpdated).to.equal(50000000000000n)

      const user2BalanceUpdated = await stakeTogether.balanceOf(user2.address)
      expect(user2BalanceUpdated).to.equal(25000000000000n)
    })
  })
})
