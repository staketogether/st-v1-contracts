import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers } from 'hardhat'
import { defaultFixture } from '../fixtures/defaultFixture'
import connect from '../utils/connect'

dotenv.config()

describe('StakeTogether: Unstake', function () {
  const blockTimeSkip = async () => {
    for (let i = 0; i < 5760; i++) {
      await ethers.provider.send('evm_mine')
    }
  }

  it('Should unstake and distribute fee successfully', async function () {
    const { StakeTogether, STOracle, owner, user1, user2, user3, user4 } = await loadFixture(
      defaultFixture
    )

    const stakeAmount = ethers.parseEther('1')
    await connect(StakeTogether, user1).stake(user2, {
      value: stakeAmount
    })

    await connect(StakeTogether, user3).stake(user4, {
      value: stakeAmount
    })

    await blockTimeSkip()

    const newBeaconBalance = ethers.parseEther('0.2')

    let blockNumber = await ethers.provider.getBlockNumber()
    expect(blockNumber).to.equal(5774)

    let reportNextBlock = await STOracle.reportNextBlock()

    await connect(STOracle, user1).report(reportNextBlock, newBeaconBalance)
    await connect(STOracle, user2).report(reportNextBlock, newBeaconBalance)

    const unstakeAmount = ethers.parseEther('1.091') + 1n
    await connect(StakeTogether, user1).unstake(unstakeAmount, user2)

    const totalPooledEther = await StakeTogether.getTotalPooledEther()
    const totalShares = await StakeTogether.getTotalShares()
    const totalDelegatedShares = await StakeTogether.getTotalDelegatedShares()
    const totalSupply = await StakeTogether.totalSupply()

    const balanceUser = await StakeTogether.balanceOf(user1.address)
    const sharesUser = await StakeTogether.sharesOf(user1.address)
    const delegatedSharesUser = await StakeTogether.delegatedSharesOf(user1.address)
    const sharesST = await StakeTogether.sharesOf(owner.address)

    const sharesDelegated = await StakeTogether.sharesOf(user2.address)
    const delegatedSharedDelegated = await StakeTogether.delegatedSharesOf(user2.address)

    expect(totalPooledEther).to.eq(stakeAmount + stakeAmount + newBeaconBalance - unstakeAmount + 1n)
    expect(totalShares).to.eq(1016498625114573783n)
    expect(totalDelegatedShares).to.eq(stakeAmount + 1n)
    expect(totalSupply).to.eq(stakeAmount + stakeAmount + newBeaconBalance - unstakeAmount + 1n)

    expect(balanceUser).to.eq(0)
    expect(sharesUser).to.eq(0)
    expect(delegatedSharesUser).to.eq(0)
    expect(sharesST).to.eq(5499541704857928n)

    expect(sharesDelegated).to.eq(2749770852428963n)
    expect(delegatedSharedDelegated).to.eq(0n)
  })
})
