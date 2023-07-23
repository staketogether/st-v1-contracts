import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import dotenv from 'dotenv'
import { defaultFixture } from '../fixtures/defaultFixture'
import { ethers } from 'ethers'
import connect from '../utils/connect'
import { expect } from 'chai'
import { mockedRewardsFixture } from '../fixtures/mockedRewardsFixture'

dotenv.config()

describe.only('StakeTogether: WithdrawPool', function () {
  it('Should withdraw from pool successfully after making a deposit', async function () {
    const { StakeTogether, Fees, owner, user1, user2, user3, user4, nullAddress } = await loadFixture(
      defaultFixture
    )

    const stakeAmount = ethers.parseEther('1')

    const STAKE_ENTRY_FEE = 1n
    const SENDER_ROLE = 7
    const { shares, amounts } = await Fees.estimateFeePercentage(STAKE_ENTRY_FEE, stakeAmount)

    await connect(StakeTogether, user1).depositPool(user2, nullAddress, {
      value: stakeAmount
    })

    await connect(StakeTogether, user3).depositPool(user2, nullAddress, {
      value: stakeAmount
    })

    const withdrawAmount = ethers.parseEther('0.7')
    const withdrawAmountShares = await StakeTogether.sharesByPooledEth(withdrawAmount)
    const totalSharesBeforeWithdraw = await StakeTogether.totalShares()
    const totalPooledEtherBeforeWithdraw = await StakeTogether.totalPooledEther()
    const sharesUser3BeforeWithdraw = await StakeTogether.sharesOf(user3.address)
    const balanceUser3BeforeWithdraw = await StakeTogether.balanceOf(user3.address)
    await connect(StakeTogether, user1).withdrawPool(withdrawAmount, user2)

    expect(await StakeTogether.sharesOf(user1.address)).to.eq(shares[SENDER_ROLE] - withdrawAmountShares)
    expect(await StakeTogether.balanceOf(user1.address)).to.eq(amounts[SENDER_ROLE] - withdrawAmount)
    expect(await StakeTogether.sharesOf(user3.address)).to.eq(sharesUser3BeforeWithdraw)
    expect(await StakeTogether.balanceOf(user3.address)).to.eq(balanceUser3BeforeWithdraw)
    expect(await StakeTogether.totalPooledEther()).to.eq(totalSharesBeforeWithdraw - withdrawAmountShares)
    expect(await StakeTogether.totalShares()).to.eq(totalPooledEtherBeforeWithdraw - withdrawAmount)
  })
  it('Should not allow withdraw if the Stake Together does not have sufficient amount', async function () {
    const { StakeTogether, Fees, owner, user1, user2, user3, user4, nullAddress } = await loadFixture(
      defaultFixture
    )

    const stakeAmount = ethers.parseEther('1')

    await expect(connect(StakeTogether, user1).withdrawPool(stakeAmount, user4)).to.be.revertedWith(
      'NOT_ENOUGH_POOL_BALANCE'
    )
  })
  it('Should not allow withdraw if the pool does not exists', async function () {
    const { StakeTogether, Fees, owner, user1, user2, user3, user4, nullAddress } = await loadFixture(
      defaultFixture
    )

    const stakeAmount = ethers.parseEther('1')

    await connect(StakeTogether, user1).depositPool(user2, nullAddress, {
      value: stakeAmount
    })

    await expect(connect(StakeTogether, user1).withdrawPool(stakeAmount, nullAddress)).to.be.revertedWith(
      'POOL_NOT_FOUND'
    )
  })
  it('Should not allow withdraw of insufficient amount', async function () {
    const { StakeTogether, Fees, owner, user1, user2, user3, user4, nullAddress } = await loadFixture(
      defaultFixture
    )

    const stakeAmount = ethers.parseEther('1')

    await connect(StakeTogether, user1).depositPool(user2, nullAddress, {
      value: stakeAmount
    })

    await expect(connect(StakeTogether, user1).withdrawPool(stakeAmount, user2)).to.be.revertedWith(
      'AMOUNT_EXCEEDS_BALANCE'
    )
  })
  it.only('Should withdraw from pool successfully after making a deposit and receiving rewards', async function () {
    const { StakeTogether, Fees, owner, user1, user2, user3, user4, nullAddress } = await loadFixture(
      mockedRewardsFixture
    )
    // TODO: Add test for rewards
  })
})
