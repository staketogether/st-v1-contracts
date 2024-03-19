import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers, upgrades } from 'hardhat'
import {
  MockFlashLoan,
  MockStakeTogether,
  MockWithdrawals__factory,
  StakeTogether,
  Withdrawals,
  Withdrawals__factory,
} from '../../../typechain'
import { withdrawalsFixture } from './Withdrawals.fixture'

dotenv.config()

describe('Withdrawals', function () {
  let withdrawals: Withdrawals
  let withdrawalsProxy: string
  let stakeTogether: StakeTogether
  let stakeTogetherProxy: string
  let mockStakeTogether: MockStakeTogether
  let mockFlashLoan: MockFlashLoan
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
    const fixture = await loadFixture(withdrawalsFixture)
    withdrawals = fixture.withdrawals
    withdrawalsProxy = fixture.withdrawalsProxy
    stakeTogether = fixture.stakeTogether
    stakeTogetherProxy = fixture.stakeTogetherProxy
    mockStakeTogether = fixture.mockStakeTogether
    mockStakeTogetherProxy = fixture.mockStakeTogetherProxy
    mockFlashLoan = fixture.mockFlashLoan
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
      await expect(withdrawals.connect(user1).pause()).to.reverted

      // The owner pauses the contract
      await withdrawals.connect(owner).pause()

      // Check if the contract is paused
      expect(await withdrawals.paused()).to.equal(true)

      // User without admin role tries to unpause the contract - should fail
      await expect(withdrawals.connect(user1).unpause()).to.reverted

      // The owner unpauses the contract
      await withdrawals.connect(owner).unpause()
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
    // Verify that the StakeTogether address was correctly set
    expect(await withdrawals.stakeTogether()).to.equal(await stakeTogether.getAddress())
  })

  it('should correctly set the StakeTogether address', async function () {
    // User1 tries to set the StakeTogether address to zero address - should fail
    await expect(withdrawals.connect(owner).setStakeTogether(nullAddress)).to.be.revertedWithCustomError(
      withdrawals,
      'StakeTogetherAlreadySet',
    )

    // Verify that the StakeTogether address was correctly set
    expect(await withdrawals.stakeTogether()).to.equal(await mockStakeTogether.getAddress())
  })

  it('should correctly set the Router address', async function () {
    await expect(withdrawals.connect(owner).setRouter(nullAddress)).to.be.revertedWithCustomError(
      withdrawals,
      'RouterAlreadySet',
    )
  })

  describe('Receive Ether', function () {
    it('should correctly receive Ether', async function () {
      const initBalance = await ethers.provider.getBalance(withdrawalsProxy)

      const tx = await user1.sendTransaction({
        to: withdrawalsProxy,
        value: ethers.parseEther('1.0'),
      })

      await tx.wait()

      const finalBalance = await ethers.provider.getBalance(withdrawalsProxy)
      expect(finalBalance).to.equal(initBalance + ethers.parseEther('1.0'))

      await expect(tx).to.emit(withdrawals, 'ReceiveEther').withArgs(ethers.parseEther('1.0'))
    })
  })

  describe('Mint and Transfer Tokens', function () {
    it('should mint tokens to user1 and then transfer to user2', async function () {
      const mintAmount = ethers.parseEther('10.0')
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)

      expect(await withdrawals.balanceOf(user1.address)).to.equal(mintAmount)

      const transferAmount = ethers.parseEther('5.0')
      await withdrawals.connect(user1).transfer(user2.address, transferAmount)

      expect(await withdrawals.balanceOf(user2.address)).to.equal(transferAmount)
      expect(await withdrawals.balanceOf(user1.address)).to.equal(mintAmount - transferAmount)
    })

    it('should only allow minting from the stakeTogether contract', async function () {
      const WithdrawalsFactory2 = new Withdrawals__factory().connect(owner)
      const withdrawals2 = await upgrades.deployProxy(WithdrawalsFactory2)
      await withdrawals2.waitForDeployment()
      const withdrawalsContract2 = withdrawals2 as unknown as Withdrawals
      const WITHDRAW_ADMIN_ROLE = await withdrawalsContract2.ADMIN_ROLE()
      await withdrawalsContract2.connect(owner).grantRole(WITHDRAW_ADMIN_ROLE, owner)

      const mintAmount = ethers.parseEther('10.0')
      await expect(
        withdrawalsContract2.connect(user1).mint(user1.address, mintAmount),
      ).to.be.revertedWithCustomError(withdrawalsContract2, 'OnlyStakeTogether')
      await withdrawalsContract2.connect(owner).setStakeTogether(user1.address)
      await withdrawalsContract2.connect(user1).mint(user1.address, mintAmount)
      // expect(await withdrawalsContract2.balanceOf(user1.address)).to.equal(mintAmount)
    })

    it('should fail transfer when sender is in anti-fraud list of StakeTogether', async function () {
      const mintAmount = ethers.parseEther('10')
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)

      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user1.address)

      const transferAmount = ethers.parseEther('5')
      await expect(
        withdrawals.connect(user1).transfer(user2.address, transferAmount),
      ).to.be.revertedWithCustomError(withdrawals, 'ListedInAntiFraud')
    })

    it('should fail transfer when recipient is in anti-fraud list of StakeTogether', async function () {
      const mintAmount = ethers.parseEther('10')
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)

      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user2.address)

      const transferAmount = ethers.parseEther('5')
      await expect(
        withdrawals.connect(user1).transfer(user2.address, transferAmount),
      ).to.be.revertedWithCustomError(withdrawals, 'ListedInAntiFraud')
    })

    it('should fail transferFrom when sender is in anti-fraud list of StakeTogether', async function () {
      const mintAmount = ethers.parseEther('10')
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)

      // Approve the transfer amount
      const transferAmount = ethers.parseEther('5')
      await withdrawals.connect(user1).approve(user2.address, transferAmount)

      // Add user1 to the anti-fraud list
      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user1.address)

      // Expect transferFrom to fail
      await expect(
        withdrawals.connect(user2).transferFrom(user1.address, user3.address, transferAmount),
      ).to.be.revertedWithCustomError(withdrawals, 'ListedInAntiFraud')
    })

    it('should fail transferFrom when recipient is in anti-fraud list of StakeTogether', async function () {
      const mintAmount = ethers.parseEther('10')
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)

      // Approve the transfer amount
      const transferAmount = ethers.parseEther('5')
      await withdrawals.connect(user1).approve(user2.address, transferAmount)

      // Add user3 to the anti-fraud list
      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user3.address)

      // Expect transferFrom to fail
      await expect(
        withdrawals.connect(user2).transferFrom(user1.address, user3.address, transferAmount),
      ).to.be.revertedWithCustomError(withdrawals, 'ListedInAntiFraud')
    })

    it('should fail transferFrom and not spend allowance when sender is in anti-fraud list of StakeTogether', async function () {
      const mintAmount = ethers.parseEther('10')
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)

      // Approve the transfer amount
      const transferAmount = ethers.parseEther('5')
      await withdrawals.connect(user1).approve(user2.address, transferAmount)

      // Add user1 to the anti-fraud list
      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user1.address)

      // Record the initial allowance and balance
      const initialAllowance = await withdrawals.allowance(user1.address, user2.address)
      const initialBalance = await withdrawals.balanceOf(user3.address)

      // Expect transferFrom to fail
      await expect(
        withdrawals.connect(user2).transferFrom(user1.address, user3.address, transferAmount),
      ).to.be.revertedWithCustomError(withdrawals, 'ListedInAntiFraud')

      // Check that the allowance and balance remain unchanged
      const finalAllowance = await withdrawals.allowance(user1.address, user2.address)
      const finalBalance = await withdrawals.balanceOf(user3.address)

      expect(initialAllowance).to.equal(finalAllowance)
      expect(initialBalance).to.equal(finalBalance)
    })

    it('should fail transferFrom and not spend allowance when recipient is in anti-fraud list of StakeTogether', async function () {
      const mintAmount = ethers.parseEther('10')
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)

      // Approve the transfer amount
      const transferAmount = ethers.parseEther('5')
      await withdrawals.connect(user1).approve(user2.address, transferAmount)

      // Add user3 to the anti-fraud list
      const ANTI_FRAUD_SENTINEL_ROLE = await stakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user3.address)

      // Record the initial allowance and balance
      const initialAllowance = await withdrawals.allowance(user1.address, user2.address)
      const initialBalance = await withdrawals.balanceOf(user3.address)

      // Expect transferFrom to fail
      await expect(
        withdrawals.connect(user2).transferFrom(user1.address, user3.address, transferAmount),
      ).to.be.revertedWithCustomError(withdrawals, 'ListedInAntiFraud')

      // Check that the allowance and balance remain unchanged
      const finalAllowance = await withdrawals.allowance(user1.address, user2.address)
      const finalBalance = await withdrawals.balanceOf(user3.address)

      expect(initialAllowance).to.equal(finalAllowance)
      expect(initialBalance).to.equal(finalBalance)
    })

    it('should successfully execute transferFrom, spend allowance when neither sender nor recipient are in anti-fraud list of StakeTogether', async function () {
      const mintAmount = ethers.parseEther('10')
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)

      // Approve the transfer amount
      const transferAmount = ethers.parseEther('5')
      await withdrawals.connect(user1).approve(user2.address, transferAmount)

      // Record the initial allowance and balance
      const initialAllowance = await withdrawals.allowance(user1.address, user2.address)
      const initialBalanceUser3 = await withdrawals.balanceOf(user3.address)

      // Execute transferFrom
      await withdrawals.connect(user2).transferFrom(user1.address, user3.address, transferAmount)

      // Check the final allowance and balance
      const finalAllowance = await withdrawals.allowance(user1.address, user2.address)
      const finalBalanceUser3 = await withdrawals.balanceOf(user3.address)

      expect(initialAllowance - transferAmount).to.equal(finalAllowance)
      expect(initialBalanceUser3 + transferAmount).to.equal(finalBalanceUser3)
    })

    it('should successfully execute transferFrom, spend allowance after user is removed from anti-fraud list of StakeTogether', async function () {
      const mintAmount = ethers.parseEther('10')
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)

      const ANTI_FRAUD_SENTINEL_ROLE = await mockStakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user1.address)

      // Ensure that owner has ANTI_FRAUD_MANAGER_ROLE before calling removeFromAntiFraud
      const ANTI_FRAUD_MANAGER_ROLE = await mockStakeTogether.ANTI_FRAUD_MANAGER_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_MANAGER_ROLE, owner.address)

      // Now it should be possible to remove user1 from the anti-fraud list without the NotAuthorized error
      await mockStakeTogether.connect(owner).removeFromAntiFraud(user1.address)

      // Mint tokens to user2 and approve the transfer for user1
      await mockStakeTogether.connect(owner).mintWithdrawals(user2.address, mintAmount)
      await withdrawals.connect(user2).approve(user1.address, mintAmount)

      // Now user1 should be able to transfer tokens from user2 to user3 using transferFrom
      const transferAmount = ethers.parseEther('5')
      await expect(withdrawals.connect(user1).transferFrom(user2.address, user3.address, transferAmount))
        .to.emit(withdrawals, 'Transfer')
        .withArgs(user2.address, user3.address, transferAmount)

      expect(await withdrawals.balanceOf(user3.address)).to.equal(transferAmount)
    })

    it('should successfully execute transferFrom, spend allowance after user is removed from anti-fraud list of MockStakeTogether', async function () {
      const mintAmount = ethers.parseEther('10')

      // Mint to the user1 address to ensure there's a balance.
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)

      const ANTI_FRAUD_SENTINEL_ROLE = await mockStakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user1.address)

      const ANTI_FRAUD_MANAGER_ROLE = await mockStakeTogether.ANTI_FRAUD_MANAGER_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_MANAGER_ROLE, owner.address)

      // Remove user1 from the anti-fraud list.
      await mockStakeTogether.connect(owner).removeFromAntiFraud(user1.address)

      // Mint tokens to user2 to ensure there's a balance, then approve the transfer for user1.
      await mockStakeTogether.connect(owner).mintWithdrawals(user2.address, mintAmount)
      await withdrawals.connect(user2).approve(user1.address, mintAmount)

      // Now user1 should be able to transfer tokens from user2 to user3 using transferFrom.
      const transferAmount = ethers.parseEther('5')
      const tx = await withdrawals
        .connect(user1)
        .transferFrom(user2.address, user3.address, transferAmount)

      expect(tx).to.emit(withdrawals, 'Transfer').withArgs(user2.address, user3.address, transferAmount)

      expect(await withdrawals.balanceOf(user3.address)).to.equal(transferAmount)

      // Ensure the allowance is spent.
      const remainingAllowance = await withdrawals.allowance(user2.address, user1.address)
      expect(remainingAllowance).to.equal(mintAmount - transferAmount)
    })
  })

  describe('Withdraw', function () {
    it('should revert withdrawal if the contract balance is insufficient', async function () {
      const mintAmount = ethers.parseEther('10.0')
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)
      expect(await withdrawals.balanceOf(user1.address)).to.equal(mintAmount)

      const withdrawAmount = ethers.parseEther('10.0')
      await expect(withdrawals.connect(user1).withdraw(withdrawAmount)).to.be.revertedWithCustomError(
        withdrawals,
        'InsufficientEthBalance',
      )
    })

    it('should revert withdrawal if the user balance is insufficient', async function () {
      await owner.sendTransaction({
        to: withdrawalsProxy,
        value: ethers.parseEther('20.0'),
      })

      const withdrawAmount = ethers.parseEther('15.0')
      await expect(withdrawals.connect(user1).withdraw(withdrawAmount)).to.be.revertedWithCustomError(
        withdrawals,
        'InsufficientStwBalance',
      )
    })

    it('should revert withdrawal if the amount is zero', async function () {
      await expect(withdrawals.connect(user1).withdraw(0)).to.be.revertedWithCustomError(
        withdrawals,
        'ZeroAmount',
      )
    })

    it('should allow a valid withdrawal', async function () {
      await owner.sendTransaction({
        to: withdrawalsProxy,
        value: ethers.parseEther('20.0'),
      })

      const mintAmount = ethers.parseEther('5.0')
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)
      expect(await withdrawals.balanceOf(user1.address)).to.equal(mintAmount)

      const userBalanceBefore = await withdrawals.balanceOf(user1.address)
      expect(userBalanceBefore).to.equal(ethers.parseEther('5.0'))

      const withdrawAmount = ethers.parseEther('2.0')
      const tx = await withdrawals.connect(user1).withdraw(withdrawAmount)
      await expect(tx).to.emit(withdrawals, 'Withdraw').withArgs(user1.address, withdrawAmount) // Verifying the Withdraw event

      const userBalanceAfter = await withdrawals.balanceOf(user1.address)

      expect(await withdrawals.totalSupply()).to.equal(ethers.parseEther('3.0'))
      expect(await withdrawals.balanceOf(user1.address)).to.equal(ethers.parseEther('3.0'))
      expect(userBalanceAfter).to.equal(userBalanceBefore - withdrawAmount)
    })

    it('should return true if contract balance is greater than or equal to the amount', async function () {
      await owner.sendTransaction({
        to: withdrawalsProxy,
        value: ethers.parseEther('10.0'),
      })

      const amount = ethers.parseEther('5.0')
      const isReady = await withdrawals.isWithdrawReady(amount)
      expect(isReady).to.equal(true)
    })

    it('should return false if contract balance is less than the amount', async function () {
      const amount = ethers.parseEther('15.0')
      const isReady = await withdrawals.isWithdrawReady(amount)
      expect(isReady).to.equal(false)
    })

    it('should revert withdrawal if the user is in the anti-fraud list of StakeTogether', async function () {
      await owner.sendTransaction({
        to: withdrawalsProxy,
        value: ethers.parseEther('20.0'),
      })

      const mintAmount = ethers.parseEther('5.0')
      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, mintAmount)

      const userBalanceBefore = await withdrawals.balanceOf(user1.address)
      expect(userBalanceBefore).to.equal(mintAmount)

      const ANTI_FRAUD_SENTINEL_ROLE = await mockStakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user1.address)

      const withdrawAmount = ethers.parseEther('2.0')
      await expect(withdrawals.connect(user1).withdraw(withdrawAmount)).to.be.revertedWithCustomError(
        withdrawals,
        'ListedInAntiFraud',
      )

      const ANTI_FRAUD_MANAGER_ROLE = await mockStakeTogether.ANTI_FRAUD_MANAGER_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_MANAGER_ROLE, owner.address)
      await mockStakeTogether.connect(owner).removeFromAntiFraud(user1.address)

      const tx = await withdrawals.connect(user1).withdraw(withdrawAmount)
      expect(tx).to.emit(withdrawals, 'Withdraw').withArgs(user1.address, withdrawAmount)

      const userBalanceAfter = await withdrawals.balanceOf(user1.address)
      expect(userBalanceAfter).to.equal(userBalanceBefore - withdrawAmount)
    })

    it('should return false if the user is in the anti-fraud list of StakeTogether', async function () {
      const ANTI_FRAUD_SENTINEL_ROLE = await mockStakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user1.address)

      const isReady = await withdrawals.connect(user1).isWithdrawReady(ethers.parseEther('1.0'))
      expect(isReady).to.equal(false)
    })

    it('should return true if the user is not in the anti-fraud list of StakeTogether and contract has sufficient balance', async function () {
      await owner.sendTransaction({
        to: withdrawalsProxy,
        value: ethers.parseEther('20.0'),
      })

      const ANTI_FRAUD_SENTINEL_ROLE = await mockStakeTogether.ANTI_FRAUD_SENTINEL_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_SENTINEL_ROLE, owner.address)
      await mockStakeTogether.connect(owner).addToAntiFraud(user1.address)

      const ANTI_FRAUD_MANAGER_ROLE = await mockStakeTogether.ANTI_FRAUD_MANAGER_ROLE()
      await mockStakeTogether.connect(owner).grantRole(ANTI_FRAUD_MANAGER_ROLE, owner.address)
      await mockStakeTogether.connect(owner).removeFromAntiFraud(user1.address)

      const isReady = await withdrawals.connect(user1).isWithdrawReady(ethers.parseEther('1.0'))
      expect(isReady).to.equal(true)
    })
  })

  describe('transferExtraAmount', function () {
    it('should transfer the extra Ether to StakeTogether fee address if contract balance is greater than total supply', async function () {
      await mockStakeTogether.setFeeAddress(2, user5.address)

      const stFeeAddress = await mockStakeTogether.getFeeAddress(2)

      const stBalanceBefore = await ethers.provider.getBalance(stFeeAddress)

      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, ethers.parseEther('12.0'))

      await owner.sendTransaction({
        to: withdrawalsProxy,
        value: ethers.parseEther('20.0'),
      })

      await withdrawals.connect(owner).transferExtraAmount()

      const withdrawalsBalanceAfter = ethers.parseEther('12.0')
      const withdrawalsBalance = await ethers.provider.getBalance(withdrawals)

      const extraAmount = ethers.parseEther('8.0')
      const stBalanceAfter = await ethers.provider.getBalance(stFeeAddress)

      expect(withdrawalsBalanceAfter).to.equal(withdrawalsBalance)
      expect(stBalanceAfter).to.equal(stBalanceBefore + extraAmount)
    })

    it('should revert if there is no extra Ether in contract balance', async function () {
      await mockStakeTogether.setFeeAddress(2, user5.address)

      await mockStakeTogether.connect(owner).mintWithdrawals(user1.address, ethers.parseEther('12.0'))

      await owner.sendTransaction({
        to: withdrawalsProxy,
        value: ethers.parseEther('12.0'), // Same as total supply, no extra Ether
      })

      await expect(withdrawals.connect(owner).transferExtraAmount()).to.be.revertedWithCustomError(
        withdrawals,
        'NoExtraAmountAvailable',
      )
    })
  })

  describe('Flash Loan', function () {
    it('should allow a valid withdrawal', async function () {
      await owner.sendTransaction({
        to: withdrawalsProxy,
        value: ethers.parseEther('20.0'),
      })

      const mintAmount = ethers.parseEther('5.0')
      await mockStakeTogether.connect(owner).mintWithdrawals(mockFlashLoan, mintAmount)
      expect(await withdrawals.balanceOf(mockFlashLoan)).to.equal(mintAmount)

      await expect(mockFlashLoan.connect(user1).doubleWithdraw()).to.be.revertedWithCustomError(
        withdrawals,
        'FlashLoan',
      )
    })
  })
})
