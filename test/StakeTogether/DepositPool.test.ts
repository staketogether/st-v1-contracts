import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers } from 'ethers'
import { defaultFixture } from '../fixtures/defaultFixture'
import connect from '../utils/connect'

dotenv.config()

xdescribe('StakeTogether: Deposit', function () {
  it('Should deposit successfuly', async function () {
    const { StakeTogether, Fees, owner, user1, user2, user4, nullAddress } = await loadFixture(
      defaultFixture
    )

    const beforeTotalPooledEther = await StakeTogether.contract.totalPooledEther()
    const beforeTotalShares = await StakeTogether.contract.totalShares()
    const beforeTotalSupply = await StakeTogether.contract.totalSupply()

    expect(beforeTotalPooledEther).to.eq(1n)
    expect(beforeTotalShares).to.eq(1n)
    expect(beforeTotalSupply).to.eq(1n)

    const stakeAmount = ethers.parseEther('1')
    const stakeShares = await StakeTogether.contract.sharesByPooledEth(stakeAmount)
    const STAKE_ENTRY_FEE = 0n
    const STAKE_ACCOUNTS_ROLE = 0
    const LOCK_ACCOUNTS_ROLE = 1
    const POOL_ROLE = 2
    const OPERATORS_ROLE = 3
    const ORACLES_ROLE = 4
    const STAKE_TOGETHER_ROLE = 5
    const LIQUIDITY_PROVIDERS_ROLE = 6
    const SENDER_ROLE = 7

    const stRolesToBeChecked = [
      STAKE_ACCOUNTS_ROLE,
      LOCK_ACCOUNTS_ROLE,
      OPERATORS_ROLE,
      ORACLES_ROLE,
      STAKE_TOGETHER_ROLE,
      LIQUIDITY_PROVIDERS_ROLE
    ]

    const expectedStFeeAddressShares = ethers.parseEther('0.007')

    const expectedSenderShares = ethers.parseEther('0.99')
    const expectedSenderAmount = ethers.parseEther('0.99')
    const expectedPoolShares = ethers.parseEther('0.003')

    await connect(StakeTogether.contract, user1).depositPool(user2, nullAddress, {
      value: stakeAmount
    })

    const totalPooledEther = await StakeTogether.contract.totalPooledEther()
    const totalShares = await StakeTogether.contract.totalShares()

    const sharesUser = await StakeTogether.contract.shares(user1.address)
    const balanceUser = await StakeTogether.contract.balanceOf(user1.address)

    const sharesSt = await StakeTogether.contract.shares(owner.address)
    const sharesStFee = await StakeTogether.contract.shares(user4.address)

    const userDelegatedShares = await StakeTogether.contract.shares(user2.address)
    // const poolShares = await StakeTogether.stakeTogetherContract.poolSharesOf(user2.address)
    const userDelegationShares = await StakeTogether.contract.delegationSharesOf(
      user1.address,
      user2.address
    )

    expect(totalPooledEther).to.eq(stakeAmount + 1n)
    expect(totalShares).to.eq(stakeShares + 1n)

    expect(sharesUser).to.eq(expectedSenderShares)
    expect(balanceUser).to.eq(expectedSenderAmount)

    expect(sharesSt).to.eq(0n)

    expect(userDelegatedShares).to.eq(expectedPoolShares)
    // expect(poolShares).to.eq(expectedSenderShares + expectedPoolShares)
    expect(sharesStFee).to.eq(expectedStFeeAddressShares)
    expect(userDelegationShares).to.eq(expectedSenderShares)
  })
  it('Should not allow deposit over the limit', async function () {
    const { StakeTogether, user1, user2, nullAddress } = await loadFixture(defaultFixture)

    const stakeAmount = ethers.parseEther('1000')
    const connectedStakeTogether = await connect(StakeTogether.contract, user1)

    expect(
      connectedStakeTogether.depositPool(user2, nullAddress, {
        value: stakeAmount
      })
    ).to.be.revertedWith('WALLET_DEPOSIT_LIMIT_REACHED')
  })
  it('Should not allow deposit if not enough balance', async function () {
    const { StakeTogether, user1, user2, nullAddress } = await loadFixture(defaultFixture)

    await user1.sendTransaction({
      to: nullAddress,
      value: ethers.parseEther('9999')
    })

    const stakeAmount = ethers.parseEther('10')
    const connectedStakeTogether = await connect(StakeTogether.contract, user1)

    expect(
      connectedStakeTogether.depositPool(user2, nullAddress, {
        value: stakeAmount
      })
    ).to.be.revertedWith('AMOUNT_EXCEEDS_BALANCE')
  })
  it("Should not allow deposit if it's below the minimum amount", async function () {
    const { StakeTogether, user1, user2, nullAddress } = await loadFixture(defaultFixture)

    const stakeAmount = ethers.parseEther('0.000000000000000001')
    const connectedStakeTogether = await connect(StakeTogether.contract, user1)

    expect(
      connectedStakeTogether.depositPool(user2, nullAddress, {
        value: stakeAmount
      })
    ).to.be.revertedWith('AMOUNT_BELOW_MIN_DEPOSIT')
  })
  it('Should not allow deposit if StakeTogether is paused', async function () {
    const { StakeTogether, user1, user2, nullAddress } = await loadFixture(defaultFixture)

    await StakeTogether.contract.pause()

    const stakeAmount = ethers.parseEther('1')
    const connectedStakeTogether = await connect(StakeTogether.contract, user1)

    expect(
      connectedStakeTogether.depositPool(user2, nullAddress, {
        value: stakeAmount
      })
    ).to.be.revertedWith('Pausable: paused')
  })
  it('Should not allow deposit if pool does not exists', async function () {
    const { StakeTogether, user1, user2, nullAddress } = await loadFixture(defaultFixture)

    const stakeAmount = ethers.parseEther('1')
    const connectedStakeTogether = await connect(StakeTogether.contract, user2)

    expect(
      connectedStakeTogether.depositPool(user1, nullAddress, {
        value: stakeAmount
      })
    ).to.be.revertedWith('POOL_NOT_FOUND')
  })
  it('Should not allow deposit to null address', async function () {
    const { StakeTogether, user1, user2, nullAddress } = await loadFixture(defaultFixture)

    const stakeAmount = ethers.parseEther('1')
    const connectedStakeTogether = await connect(StakeTogether.contract, user2)

    expect(
      connectedStakeTogether.depositPool(nullAddress, nullAddress, {
        value: stakeAmount
      })
    ).to.be.revertedWith('POOL_NOT_FOUND')
  })
  it('Should not allow deposit that leads to overflow', async function () {
    const { StakeTogether, user1, user2, nullAddress } = await loadFixture(defaultFixture)

    const stakeAmount = ethers.MaxUint256
    const connectedStakeTogether = await connect(StakeTogether.contract, user2)

    expect(
      connectedStakeTogether.depositPool(user1, nullAddress, {
        value: stakeAmount
      })
    ).to.be.revertedWith('SafeMath: addition overflow')
  })
  it.skip('Should distribute fees correctly according to the _depositBase function', async function () {
    const { StakeTogether, Fees, owner, user1, user2, user4, nullAddress } = await loadFixture(
      defaultFixture
    )

    const beforeTotalPooledEther = await StakeTogether.contract.totalPooledEther()
    const beforeTotalShares = await StakeTogether.contract.totalShares()
    const beforeTotalSupply = await StakeTogether.contract.totalSupply()

    expect(beforeTotalPooledEther).to.eq(1n)
    expect(beforeTotalShares).to.eq(1n)
    expect(beforeTotalSupply).to.eq(1n)

    const stakeAmount = ethers.parseEther('1')
    const stakeShares = await StakeTogether.contract.sharesByPooledEth(stakeAmount)
    const STAKE_ENTRY_FEE = 1n
    const STAKE_ACCOUNTS_ROLE = 0
    const LOCK_ACCOUNTS_ROLE = 1
    const POOL_ROLE = 2
    const OPERATORS_ROLE = 3
    const ORACLES_ROLE = 4
    const STAKE_TOGETHER_ROLE = 5
    const LIQUIDITY_PROVIDERS_ROLE = 6
    const SENDER_ROLE = 7

    const stRolesToBeChecked = [
      STAKE_ACCOUNTS_ROLE,
      LOCK_ACCOUNTS_ROLE,
      OPERATORS_ROLE,
      ORACLES_ROLE,
      STAKE_TOGETHER_ROLE,
      LIQUIDITY_PROVIDERS_ROLE
    ]

    const { shares, amounts } = await Fees.contract.estimateFeePercentage(STAKE_ENTRY_FEE, stakeAmount)
    const expectedStFeeAddressShares = shares
      .filter((_, roleIndex) => stRolesToBeChecked.includes(roleIndex))
      .reduce((share, total) => share + total, 0n)
    const expectedStFeeAddressBalance = amounts
      .filter((_, roleIndex) => stRolesToBeChecked.includes(roleIndex))
      .reduce((share, total) => share + total, 0n)
    const expectedPoolAddressShares = shares
      .filter((_, roleIndex) => [POOL_ROLE, SENDER_ROLE].includes(roleIndex))
      .reduce((share, total) => share + total, 0n)

    const expectedSenderShares = shares[SENDER_ROLE]
    const expectedSenderAmount = amounts[SENDER_ROLE]
    const expectedPoolShares = shares[POOL_ROLE]

    await connect(StakeTogether.contract, user1).depositPool(user2, nullAddress, {
      value: stakeAmount
    })

    const totalPooledEther = await StakeTogether.contract.totalPooledEther()
    const totalShares = await StakeTogether.contract.totalShares()

    const sharesUser = await StakeTogether.contract.shares(user1.address)
    const balanceUser = await StakeTogether.contract.balanceOf(user1.address)

    const sharesSt = await StakeTogether.contract.shares(owner.address)
    const sharesStFee = await StakeTogether.contract.shares(user4.address)
    const userDelegatedShares = await StakeTogether.contract.shares(user2.address)
    // const poolShares = await StakeTogether.stakeTogetherContract.poolSharesOf(user2.address)
    const userDelegationShares = await StakeTogether.contract.delegationSharesOf(
      user1.address,
      user2.address
    )

    expect(totalPooledEther).to.eq(stakeAmount + 1n)
    expect(totalShares).to.eq(stakeShares + 1n)

    expect(sharesUser).to.eq(expectedSenderShares)
    expect(balanceUser).to.eq(expectedSenderAmount)

    expect(sharesSt).to.eq(0n)

    expect(userDelegatedShares).to.eq(expectedPoolShares)
    // expect(poolShares).to.eq(expectedSenderShares + expectedPoolShares)
    expect(sharesStFee).to.eq(expectedStFeeAddressShares)
    expect(userDelegationShares).to.eq(expectedSenderShares)

    const stFeeAddress = await Fees.contract.getFeeRolesAddresses()
    const stFeeAddressShares = await StakeTogether.contract.shares(stFeeAddress[0])
    const stFeeAddressBalance = await StakeTogether.contract.balanceOf(stFeeAddress[0])

    expect(stFeeAddressShares).to.eq(expectedStFeeAddressShares)
    expect(stFeeAddressBalance).to.eq(expectedStFeeAddressBalance)

    // const poolSharesSt = await StakeTogether.stakeTogetherContract.poolSharesOf(owner.address)
    // const poolSharesStFee = await StakeTogether.stakeTogetherContract.poolSharesOf(user4.address)

    /*  expect(poolSharesSt).to.eq(0n)
    expect(poolSharesStFee).to.eq(expectedStFeeAddressShares)

    const poolSharesUser = await StakeTogether.stakeTogetherContract.poolSharesOf(user1.address)
    const poolSharesUser2 = await StakeTogether.stakeTogetherContract.poolSharesOf(user2.address)

    expect(poolSharesUser).to.eq(0n)
    expect(poolSharesUser2).to.eq(expectedPoolAddressShares) */
  })
  it.skip('Should distribute delegation shares correctly after 2 deposits', async function () {
    const { StakeTogether, Fees, owner, user1, user2, user4, nullAddress } = await loadFixture(
      defaultFixture
    )

    const beforeTotalPooledEther = await StakeTogether.contract.totalPooledEther()
    const beforeTotalShares = await StakeTogether.contract.totalShares()
    const beforeTotalSupply = await StakeTogether.contract.totalSupply()

    expect(beforeTotalPooledEther).to.eq(1n)
    expect(beforeTotalShares).to.eq(1n)
    expect(beforeTotalSupply).to.eq(1n)

    const stakeAmount = ethers.parseEther('1')
    const stakeShares = await StakeTogether.contract.sharesByPooledEth(stakeAmount)
    const STAKE_ENTRY_FEE = 1n
    const STAKE_ACCOUNTS_ROLE = 0
    const LOCK_ACCOUNTS_ROLE = 1
    const POOL_ROLE = 2
    const OPERATORS_ROLE = 3
    const ORACLES_ROLE = 4
    const STAKE_TOGETHER_ROLE = 5
    const LIQUIDITY_PROVIDERS_ROLE = 6
    const SENDER_ROLE = 7

    const stRolesToBeChecked = [
      STAKE_ACCOUNTS_ROLE,
      LOCK_ACCOUNTS_ROLE,
      OPERATORS_ROLE,
      ORACLES_ROLE,
      STAKE_TOGETHER_ROLE,
      LIQUIDITY_PROVIDERS_ROLE
    ]

    const { shares, amounts } = await Fees.contract.estimateFeePercentage(STAKE_ENTRY_FEE, stakeAmount)
    const expectedStFeeAddressShares = shares
      .filter((_, roleIndex) => stRolesToBeChecked.includes(roleIndex))
      .reduce((share, total) => share + total, 0n)
    const expectedStFeeAddressBalance = amounts
      .filter((_, roleIndex) => stRolesToBeChecked.includes(roleIndex))
      .reduce((share, total) => share + total, 0n)
    const expectedPoolAddressShares = shares
      .filter((_, roleIndex) => [POOL_ROLE, SENDER_ROLE].includes(roleIndex))
      .reduce((share, total) => share + total, 0n)

    const expectedSenderShares = shares[SENDER_ROLE]
    const expectedSenderAmount = amounts[SENDER_ROLE]
    const expectedPoolShares = shares[POOL_ROLE]

    await connect(StakeTogether.contract, user1).depositPool(user2, nullAddress, {
      value: stakeAmount
    })

    const totalPooledEther = await StakeTogether.contract.totalPooledEther()
    const totalShares = await StakeTogether.contract.totalShares()

    const sharesUser = await StakeTogether.contract.shares(user1.address)
    const balanceUser = await StakeTogether.contract.balanceOf(user1.address)

    const sharesSt = await StakeTogether.contract.shares(owner.address)
    const sharesStFee = await StakeTogether.contract.shares(user4.address)

    const userDelegatedShares = await StakeTogether.contract.shares(user2.address)
    // const poolShares = await StakeTogether.stakeTogetherContract.poolSharesOf(user2.address)
    const userDelegationShares = await StakeTogether.contract.delegationSharesOf(
      user1.address,
      user2.address
    )

    expect(totalPooledEther).to.eq(stakeAmount + 1n)
    expect(totalShares).to.eq(stakeShares + 1n)

    expect(sharesUser).to.eq(expectedSenderShares)
    expect(balanceUser).to.eq(expectedSenderAmount)

    expect(sharesSt).to.eq(0n)

    expect(userDelegatedShares).to.eq(expectedPoolShares)
    // expect(poolShares).to.eq(expectedSenderShares + expectedPoolShares)
    expect(sharesStFee).to.eq(expectedStFeeAddressShares)
    expect(userDelegationShares).to.eq(expectedSenderShares)

    const stFeeAddress = await Fees.contract.getFeeRolesAddresses()
    const stFeeAddressShares = await StakeTogether.contract.shares(stFeeAddress[0])
    const stFeeAddressBalance = await StakeTogether.contract.balanceOf(stFeeAddress[0])

    expect(stFeeAddressShares).to.eq(expectedStFeeAddressShares)
    expect(stFeeAddressBalance).to.eq(expectedStFeeAddressBalance)

    /* const poolSharesSt = await StakeTogether.stakeTogetherContract.poolSharesOf(owner.address)
    const poolSharesStFee = await StakeTogether.stakeTogetherContract.poolSharesOf(user4.address)

    expect(poolSharesSt).to.eq(0n)
    expect(poolSharesStFee).to.eq(expectedStFeeAddressShares) */
  })

  it.skip('Should verify the wei loss after transfer ether to contract and depositing afterwards', async function () {
    const { StakeTogether, user1, user2, user3, nullAddress } = await loadFixture(defaultFixture)

    const beforeTransfer1TotalPooledEther = await StakeTogether.contract.totalPooledEther()
    const beforeTransfer1TotalShares = await StakeTogether.contract.totalShares()
    const transfer1Amount = ethers.parseEther('1.3')

    await user1.sendTransaction({
      to: await StakeTogether.contract.getAddress(),
      value: transfer1Amount
    })

    expect(await StakeTogether.contract.totalPooledEther()).to.eq(
      beforeTransfer1TotalPooledEther + transfer1Amount
    )
    expect(await StakeTogether.contract.totalShares()).to.eq(beforeTransfer1TotalShares)

    const beforeDeposit1TotalPooledEther = await StakeTogether.contract.totalPooledEther()
    const beforeDepositTotalShares = await StakeTogether.contract.totalShares()
    const deposit1Amount = ethers.parseEther('0.3')
    const deposit1Shares = await StakeTogether.contract.sharesByPooledEth(deposit1Amount)

    await connect(StakeTogether.contract, user1).depositPool(user2, nullAddress, {
      value: deposit1Amount
    })

    expect(await StakeTogether.contract.totalPooledEther()).to.eq(
      beforeDeposit1TotalPooledEther + deposit1Amount
    )
    expect(await StakeTogether.contract.totalShares()).to.eq(beforeDepositTotalShares + deposit1Shares)

    const beforeTransfer2TotalPooledEther = await StakeTogether.contract.totalPooledEther()
    const beforeTransfer2TotalShares = await StakeTogether.contract.totalShares()
    const transfer2Amount = ethers.parseEther('0.337')

    await user2.sendTransaction({
      to: await StakeTogether.contract.getAddress(),
      value: transfer2Amount
    })

    expect(await StakeTogether.contract.totalPooledEther()).to.eq(
      beforeTransfer2TotalPooledEther + transfer2Amount
    )
    expect(await StakeTogether.contract.totalShares()).to.eq(beforeTransfer2TotalShares)

    const beforeDeposit2TotalPooledEther = await StakeTogether.contract.totalPooledEther()
    const beforeDeposit2TotalShares = await StakeTogether.contract.totalShares()
    const deposit2Amount = ethers.parseEther('0.6723')

    await connect(StakeTogether.contract, user2).depositPool(user3, user1, {
      value: deposit2Amount
    })

    expect(await StakeTogether.contract.totalPooledEther()).to.eq(
      beforeDeposit2TotalPooledEther + deposit2Amount
    )
    expect(await StakeTogether.contract.totalShares()).to.eq(beforeDeposit2TotalShares)
  })
})
