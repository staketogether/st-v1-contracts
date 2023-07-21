import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers } from 'ethers'
import { defaultFixture } from '../fixtures/defaultFixture'
import connect from '../utils/connect'

dotenv.config()

describe.only('StakeTogether: Deposit', function () {
  it('Should deposit successfuly', async function () {
    const { StakeTogether, Fees, owner, user1, user2, user4, nullAddress } = await loadFixture(
      defaultFixture
    )

    const beforeTotalPooledEther = await StakeTogether.totalPooledEther()
    const beforeTotalShares = await StakeTogether.totalShares()
    const beforeTotalSupply = await StakeTogether.totalSupply()

    expect(beforeTotalPooledEther).to.eq(1n)
    expect(beforeTotalShares).to.eq(1n)
    expect(beforeTotalSupply).to.eq(1n)

    const stakeAmount = ethers.parseEther('1')
    const stakeShares = await StakeTogether.sharesByPooledEth(stakeAmount)
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

    const { shares, amounts } = await Fees.estimateFeePercentage(STAKE_ENTRY_FEE, stakeAmount)
    const expectedStFeeAddressShares = shares
      .filter((_, roleIndex) => stRolesToBeChecked.includes(roleIndex))
      .reduce((share, total) => share + total, 0n)

    const expectedSenderShares = shares[SENDER_ROLE]
    const expectedSenderAmount = amounts[SENDER_ROLE]
    const expectedPoolShares = shares[POOL_ROLE]

    await connect(StakeTogether, user1).depositPool(user2, nullAddress, {
      value: stakeAmount
    })

    const totalPooledEther = await StakeTogether.totalPooledEther()
    const totalShares = await StakeTogether.totalShares()

    const sharesUser = await StakeTogether.sharesOf(user1.address)
    const balanceUser = await StakeTogether.balanceOf(user1.address)

    const sharesSt = await StakeTogether.sharesOf(owner.address)
    const sharesStFee = await StakeTogether.sharesOf(user4.address)

    const userDelegatedShares = await StakeTogether.sharesOf(user2.address)
    const poolShares = await StakeTogether.poolSharesOf(user2.address)

    expect(totalPooledEther).to.eq(stakeAmount + 1n)
    expect(totalShares).to.eq(stakeShares + 1n)

    expect(sharesUser).to.eq(expectedSenderShares)
    expect(balanceUser).to.eq(expectedSenderAmount)

    expect(sharesSt).to.eq(0n)

    expect(userDelegatedShares).to.eq(expectedPoolShares)
    expect(poolShares).to.eq(expectedSenderShares + expectedPoolShares)
    expect(sharesStFee).to.eq(expectedStFeeAddressShares)
  })
})
