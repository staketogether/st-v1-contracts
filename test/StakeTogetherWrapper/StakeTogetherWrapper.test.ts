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

describe.only('StakeTogetherWrapper', function () {
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

    it('should correctly set the StakeTogether address', async function () {
      // User1 tries to set the StakeTogether address to zero address - should fail
      await expect(
        connect(stakeTogetherWrapper, owner).setStakeTogether(nullAddress),
      ).to.be.revertedWithCustomError(stakeTogetherWrapper, 'StakeTogetherAlreadySet')

      // Verify that the StakeTogether address was correctly set
      expect(await stakeTogetherWrapper.stakeTogether()).to.equal(await mockStakeTogether.getAddress())
    })
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

  describe('transferExtraAmount', function () {
    it('should transfer the extra Ether to StakeTogether fee address if contract balance is greater than total supply', async function () {
      await mockStakeTogether.setFeeAddress(2, user5.address)

      const stFeeAddress = await mockStakeTogether.getFeeAddress(2)

      const stBalanceBefore = await ethers.provider.getBalance(stFeeAddress)

      await owner.sendTransaction({
        to: stakeTogetherWrapperProxy,
        value: ethers.parseEther('20.0'),
      })

      await stakeTogetherWrapper.connect(owner).transferExtraAmount()

      const wstBalanceAfter = ethers.parseEther('0')
      const wstBalance = await ethers.provider.getBalance(stakeTogetherWrapperProxy)

      const extraAmount = ethers.parseEther('20.0')
      const stBalanceAfter = await ethers.provider.getBalance(stFeeAddress)

      expect(wstBalanceAfter).to.equal(wstBalance)
      expect(stBalanceAfter).to.equal(stBalanceBefore + extraAmount)
    })

    it('should revert if there is no extra Ether in contract balance', async function () {
      await mockStakeTogether.setFeeAddress(2, user5.address)

      await expect(
        stakeTogetherWrapper.connect(owner).transferExtraAmount(),
      ).to.be.revertedWithCustomError(stakeTogetherWrapper, 'NoExtraAmountAvailable')
    })
  })

  describe('Transfer', () => {
    it('should fail transfer when sender is in anti-fraud list of StakeTogether', async function () {
      const mintAmount = ethers.parseEther('10')
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)

      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user1.address)

      const transferAmount = ethers.parseEther('5')
      await expect(
        stakeTogetherWrapper.connect(user1).transfer(user2.address, transferAmount),
      ).to.be.revertedWithCustomError(stakeTogetherWrapper, 'ListedInAntiFraud')
    })

    it('should fail transfer when recipient is in anti-fraud list of StakeTogether', async function () {
      const mintAmount = ethers.parseEther('10')
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)

      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user2.address)

      const transferAmount = ethers.parseEther('5')
      await expect(
        stakeTogetherWrapper.connect(user1).transfer(user2.address, transferAmount),
      ).to.be.revertedWithCustomError(stakeTogetherWrapper, 'ListedInAntiFraud')
    })

    it('should fail transfer when recipient is in anti-fraud list of StakeTogether', async function () {
      const mintAmount = ethers.parseEther('10')
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)

      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user2.address)

      const transferAmount = ethers.parseEther('5')
      await expect(
        stakeTogetherWrapper.connect(user1).transfer(user2.address, transferAmount),
      ).to.be.revertedWithCustomError(stakeTogetherWrapper, 'ListedInAntiFraud')
    })

    it('should successfully transfer wstpETH after wrapping stpETH', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: user1DepositAmount })

      const user1StpETH = await stakeTogether.balanceOf(user1.address)

      const transferAmount = ethers.parseEther('10')
      await stakeTogether.connect(user1).approve(stakeTogetherWrapperProxy, user1StpETH)

      const txWrap = await stakeTogetherWrapper.connect(user1).wrap(user1StpETH)
      await txWrap.wait()

      await stakeTogetherWrapper.connect(user1).approve(user2.address, transferAmount)

      const txTransfer = await stakeTogetherWrapper.connect(user1).transfer(user2.address, transferAmount)
      await txTransfer.wait()

      const user2WstpETH = await stakeTogetherWrapper.balanceOf(user2.address)
      expect(user2WstpETH).to.equal(transferAmount)
    })
  })

  describe('transferFrom', function () {
    it('should successfully execute transferFrom after wrapping stpETH', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: user1DepositAmount })

      const user1StpETH = await stakeTogether.balanceOf(user1.address)

      const transferAmount = ethers.parseEther('10')
      await stakeTogether.connect(user1).approve(stakeTogetherWrapperProxy, user1StpETH)

      const txWrap = await stakeTogetherWrapper.connect(user1).wrap(user1StpETH)
      await txWrap.wait()

      await stakeTogetherWrapper.connect(user1).approve(user2.address, transferAmount)

      // User2 transfers the wrapped token from User1 to themselves using transferFrom
      const txTransferFrom = await stakeTogetherWrapper
        .connect(user2)
        .transferFrom(user1.address, user2.address, transferAmount)
      await txTransferFrom.wait()

      const user2WstpETH = await stakeTogetherWrapper.balanceOf(user2.address)
      expect(user2WstpETH).to.equal(transferAmount)
    })

    it('should fail transferFrom when sender is in anti-fraud list', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: user1DepositAmount })

      const user1StpETH = await stakeTogether.balanceOf(user1.address)

      await stakeTogether.connect(user1).approve(stakeTogetherWrapperProxy, user1StpETH)
      const txWrap = await stakeTogetherWrapper.connect(user1).wrap(user1StpETH)
      await txWrap.wait()

      const transferAmount = ethers.parseEther('10')
      await stakeTogetherWrapper.connect(user1).approve(user2.address, transferAmount)

      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user1.address)

      await expect(
        stakeTogetherWrapper.connect(user2).transferFrom(user1.address, user2.address, transferAmount),
      ).to.be.revertedWithCustomError(stakeTogetherWrapper, 'ListedInAntiFraud')
    })

    it('should fail transferFrom when recipient is in anti-fraud list', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: user1DepositAmount })

      const user1StpETH = await stakeTogether.balanceOf(user1.address)

      await stakeTogether.connect(user1).approve(stakeTogetherWrapperProxy, user1StpETH)
      const txWrap = await stakeTogetherWrapper.connect(user1).wrap(user1StpETH)
      await txWrap.wait()

      const transferAmount = ethers.parseEther('10')
      await stakeTogetherWrapper.connect(user1).approve(user2.address, transferAmount)

      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user2.address)

      await expect(
        stakeTogetherWrapper.connect(user1).transferFrom(user1.address, user2.address, transferAmount),
      ).to.be.revertedWithCustomError(stakeTogetherWrapper, 'ListedInAntiFraud')
    })
  })

  describe('Wrap', () => {
    it('should successfully wrap stpETH to wstpETH', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: user1DepositAmount })

      const user1StpETH = await stakeTogether.balanceOf(user1.address)
      await stakeTogether.connect(user1).approve(stakeTogetherWrapperProxy, user1StpETH)

      const tx = await stakeTogetherWrapper.connect(user1).wrap(user1StpETH)
      await tx.wait()

      const user1WstpETH = await stakeTogetherWrapper.balanceOf(user1.address)
      expect(user1WstpETH).to.equal(user1StpETH) // Checks if wstpETH balance is equal to the stpETH balance
    })

    it('should fail to wrap when sender is in anti-fraud list', async function () {
      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: user1DepositAmount })

      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user1.address)

      const user1StpETH = await stakeTogether.balanceOf(user1.address)
      await expect(stakeTogetherWrapper.connect(user1).wrap(user1StpETH)).to.be.revertedWithCustomError(
        stakeTogetherWrapper,
        'ListedInAntiFraud',
      )
    })

    it('should fail to wrap when _stpETH amount is zero', async function () {
      await expect(stakeTogetherWrapper.connect(user1).wrap(0)).to.be.revertedWithCustomError(
        stakeTogetherWrapper,
        'ZeroStpETHAmount',
      )
    })
  })

  describe('Unwrap', () => {
    it('should successfully unwrap wstpETH to stpETH', async function () {
      const depositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: depositAmount })
      const user1StpETH = await stakeTogether.balanceOf(user1.address)
      await stakeTogether.connect(user1).approve(stakeTogetherWrapperProxy, user1StpETH)

      await stakeTogetherWrapper.connect(user1).wrap(user1StpETH)

      const unwrapAmount = ethers.parseEther('10')
      const tx = await stakeTogetherWrapper.connect(user1).unwrap(unwrapAmount)
      await tx.wait()

      const user1FinalStpETH = await stakeTogether.balanceOf(user1.address)
      expect(user1FinalStpETH).to.be.gte(unwrapAmount)
    })

    it('should fail to unwrap when wstpETH amount is zero', async function () {
      await expect(stakeTogetherWrapper.connect(user1).unwrap(0)).to.be.revertedWithCustomError(
        stakeTogetherWrapper,
        'ZeroWstpETHAmount',
      )
    })

    it('should fail to unwrap when user is in anti-fraud list', async function () {
      const depositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      await stakeTogether.connect(user1).depositPool(poolAddress, referral, { value: depositAmount })
      const user1StpETH = await stakeTogether.balanceOf(user1.address)
      await stakeTogether.connect(user1).approve(stakeTogetherWrapperProxy, user1StpETH)

      await stakeTogetherWrapper.connect(user1).wrap(user1StpETH)

      // Add user to anti-fraud list
      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await stakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await stakeTogether.connect(owner).addToAntiFraud(user1.address)

      const unwrapAmount = ethers.parseEther('10')
      await expect(
        stakeTogetherWrapper.connect(user1).unwrap(unwrapAmount),
      ).to.be.revertedWithCustomError(stakeTogetherWrapper, 'ListedInAntiFraud')
    })
  })
})
