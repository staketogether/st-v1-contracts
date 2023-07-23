import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import dotenv from 'dotenv'
import { defaultFixture } from '../fixtures/defaultFixture'
import { ethers } from 'ethers'
import connect from '../utils/connect'
import { expect } from 'chai'

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

    const withdrawAmount = ethers.parseEther('0.3')
    await connect(StakeTogether, user1).withdrawPool(withdrawAmount, user2)

    expect(await StakeTogether.sharesOf(user1.address)).to.eq(shares[SENDER_ROLE])
    expect(await StakeTogether.balanceOf(user1.address)).to.eq(amounts[SENDER_ROLE])
    expect(await StakeTogether.totalPooledEther()).to.eq(ethers.parseEther('1.7'))
    expect(await StakeTogether.totalShares()).to.eq(ethers.parseEther('1.7'))
  })
})
