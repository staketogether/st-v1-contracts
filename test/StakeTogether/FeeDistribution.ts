import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers } from 'hardhat'
import { defaultFixture } from '../fixtures/defaultFixture'
import connect from '../utils/connect'

dotenv.config()

describe('StakeTogether: Fee Distribution', function () {
  const blockTimeSkip = async () => {
    for (let i = 0; i < 5760; i++) {
      await ethers.provider.send('evm_mine')
    }
  }

  it('Should stake and distribute fee', async function () {
    const { StakeTogether, Oracle, owner, user1, user2, user9 } = await loadFixture(defaultFixture)

    const stakeAmount = ethers.parseEther('1')

    await connect(StakeTogether, user1).stake(user2, {
      value: stakeAmount
    })

    let totalPooledEther = await StakeTogether.getTotalPooledEther()
    let totalShares = await StakeTogether.getTotalShares()
    let totalSupply = await StakeTogether.totalSupply()

    let balanceUser = await StakeTogether.balanceOf(user1.address)
    let sharesUser = await StakeTogether.sharesOf(user1.address)

    let balanceST = await StakeTogether.balanceOf(owner.address)
    let sharesST = await StakeTogether.sharesOf(owner.address)

    let balanceOperator = await StakeTogether.balanceOf(user9.address)
    let sharesOperator = await StakeTogether.sharesOf(user9.address)

    let balanceDelegated = await StakeTogether.balanceOf(user2.address)
    let sharesDelegated = await StakeTogether.sharesOf(user2.address)
    let delegationSharesDelegated = await StakeTogether.delegatedSharesOf(user2.address)

    // console.log('---------------------------------------------')
    // console.log('balanceUser\t\t', balanceUser.toString())
    // console.log('balanceST\t\t', balanceST.toString())
    // console.log('balanceOperator\t\t', balanceOperator.toString())
    // console.log('balanceDelegated\t', balanceDelegated.toString())
    // console.log('totalPooledEther\t', totalPooledEther.toString())
    // console.log('totalBalances\t\t', balanceUser + balanceST + balanceDelegated)
    // console.log(
    //   'loss\t\t\t',
    //   totalPooledEther - (balanceUser + balanceST + balanceOperator + balanceDelegated)
    // )
    // console.log('---------------------------------------------')

    expect(totalPooledEther).to.eq(stakeAmount + 1n)
    expect(totalShares).to.eq(stakeAmount + 1n)
    expect(totalSupply).to.eq(stakeAmount + 1n)

    expect(balanceUser).to.eq(stakeAmount)
    expect(sharesUser).to.eq(stakeAmount)

    expect(balanceST).to.eq(0n)
    expect(sharesST).to.eq(0n)

    expect(balanceOperator).to.eq(0n)
    expect(sharesOperator).to.eq(0n)

    expect(balanceDelegated).to.eq(0n)
    expect(sharesDelegated).to.eq(0n)

    // rebase earn

    await blockTimeSkip()

    const beaconBalanceEarn = ethers.parseEther('1')

    let blockNumber = await ethers.provider.getBlockNumber()
    expect(blockNumber).to.equal(5773)

    let reportNextBlock = await Oracle.reportNextBlock()

    await connect(Oracle, user1).report(reportNextBlock, beaconBalanceEarn)
    await connect(Oracle, user2).report(reportNextBlock, beaconBalanceEarn)

    totalPooledEther = await StakeTogether.getTotalPooledEther()
    totalShares = await StakeTogether.getTotalShares()
    totalSupply = await StakeTogether.totalSupply()

    balanceUser = await StakeTogether.balanceOf(user1.address)
    sharesUser = await StakeTogether.sharesOf(user1.address)

    balanceST = await StakeTogether.balanceOf(owner.address)
    sharesST = await StakeTogether.sharesOf(owner.address)

    balanceOperator = await StakeTogether.balanceOf(user9.address)
    sharesOperator = await StakeTogether.sharesOf(user9.address)

    balanceDelegated = await StakeTogether.balanceOf(user2.address)
    sharesDelegated = await StakeTogether.sharesOf(user2.address)
    delegationSharesDelegated = await StakeTogether.delegatedSharesOf(user2.address)

    // console.log('---------------------------------------------')
    // console.log('balanceUser\t\t', balanceUser.toString())
    // console.log('balanceST\t\t', balanceST.toString())
    // console.log('balanceOperator\t\t', balanceOperator.toString())
    // console.log('balanceDelegated\t', balanceDelegated.toString())
    // console.log('totalPooledEther\t', totalPooledEther.toString())
    // console.log('totalBalances\t\t', balanceUser + balanceST + balanceDelegated)
    // console.log(
    //   'loss\t\t\t',
    //   totalPooledEther - (balanceUser + balanceST + balanceOperator + balanceDelegated)
    // )
    // console.log('---------------------------------------------')

    expect(totalPooledEther).to.eq(stakeAmount + 1n + beaconBalanceEarn)
    expect(totalShares).to.eq(1047120418848167536n)
    expect(totalSupply).to.eq(stakeAmount + 1n + beaconBalanceEarn)

    expect(balanceUser).to.eq(1910000000000000006n)
    expect(sharesUser).to.eq(stakeAmount)

    expect(balanceST).to.eq(29999999999999998n)
    expect(sharesST).to.eq(15706806282722512n)

    expect(balanceOperator).to.eq(29999999999999998n)
    expect(sharesOperator).to.eq(15706806282722512n)

    expect(balanceDelegated).to.eq(29999999999999996n)
    expect(sharesDelegated).to.eq(15706806282722511n)
    expect(delegationSharesDelegated).to.eq(stakeAmount)

    //  rebase loss

    await blockTimeSkip()

    const beaconBalanceLoss = ethers.parseEther('0.5')

    blockNumber = await ethers.provider.getBlockNumber()
    expect(blockNumber).to.equal(11535)

    reportNextBlock = await Oracle.reportNextBlock()

    await connect(Oracle, user1).report(reportNextBlock, beaconBalanceLoss)
    await connect(Oracle, user2).report(reportNextBlock, beaconBalanceLoss)

    totalPooledEther = await StakeTogether.getTotalPooledEther()
    totalShares = await StakeTogether.getTotalShares()
    totalSupply = await StakeTogether.totalSupply()

    balanceUser = await StakeTogether.balanceOf(user1.address)
    sharesUser = await StakeTogether.sharesOf(user1.address)

    balanceST = await StakeTogether.balanceOf(owner.address)
    sharesST = await StakeTogether.sharesOf(owner.address)

    balanceOperator = await StakeTogether.balanceOf(user9.address)
    sharesOperator = await StakeTogether.sharesOf(user9.address)

    balanceDelegated = await StakeTogether.balanceOf(user2.address)
    sharesDelegated = await StakeTogether.sharesOf(user2.address)
    delegationSharesDelegated = await StakeTogether.delegatedSharesOf(user2.address)

    // console.log('---------------------------------------------')
    // console.log('balanceUser\t\t', balanceUser.toString())
    // console.log('balanceST\t\t', balanceST.toString())
    // console.log('balanceOperator\t\t', balanceOperator.toString())
    // console.log('balanceDelegated\t', balanceDelegated.toString())
    // console.log('totalPooledEther\t', totalPooledEther.toString())
    // console.log('totalBalances\t\t', balanceUser + balanceST + balanceDelegated)
    // console.log(
    //   'loss\t\t\t',
    //   totalPooledEther - (balanceUser + balanceST + balanceOperator + balanceDelegated)
    // )
    // console.log('---------------------------------------------')

    expect(totalPooledEther).to.eq(stakeAmount + 1n + beaconBalanceLoss)
    expect(totalShares).to.eq(1047120418848167536n)
    expect(totalSupply).to.eq(stakeAmount + 1n + beaconBalanceLoss)

    expect(balanceUser).to.eq(1432500000000000005n)
    expect(sharesUser).to.eq(stakeAmount)

    expect(balanceST).to.eq(22499999999999998n)
    expect(sharesST).to.eq(15706806282722512n)

    expect(balanceOperator).to.eq(22499999999999998n)
    expect(sharesOperator).to.eq(15706806282722512n)

    expect(balanceDelegated).to.eq(22499999999999997n)
    expect(sharesDelegated).to.eq(15706806282722511n)
    expect(delegationSharesDelegated).to.eq(stakeAmount)

    // rebase earn2

    await blockTimeSkip()

    const beaconBalanceEarn2 = ethers.parseEther('2')

    blockNumber = await ethers.provider.getBlockNumber()
    expect(blockNumber).to.equal(17297)

    reportNextBlock = await Oracle.reportNextBlock()

    await connect(Oracle, user1).report(reportNextBlock, beaconBalanceEarn2)
    await connect(Oracle, user2).report(reportNextBlock, beaconBalanceEarn2)

    totalPooledEther = await StakeTogether.getTotalPooledEther()
    totalShares = await StakeTogether.getTotalShares()
    totalSupply = await StakeTogether.totalSupply()

    balanceUser = await StakeTogether.balanceOf(user1.address)
    sharesUser = await StakeTogether.sharesOf(user1.address)

    balanceST = await StakeTogether.balanceOf(owner.address)
    sharesST = await StakeTogether.sharesOf(owner.address)

    balanceOperator = await StakeTogether.balanceOf(user9.address)
    sharesOperator = await StakeTogether.sharesOf(user9.address)

    balanceDelegated = await StakeTogether.balanceOf(user2.address)
    sharesDelegated = await StakeTogether.sharesOf(user2.address)
    delegationSharesDelegated = await StakeTogether.delegatedSharesOf(user2.address)

    // console.log('---------------------------------------------')
    // console.log('balanceUser\t\t', balanceUser.toString())
    // console.log('balanceST\t\t', balanceST.toString())
    // console.log('balanceOperator\t\t', balanceOperator.toString())
    // console.log('balanceDelegated\t', balanceDelegated.toString())
    // console.log('totalPooledEther\t', totalPooledEther.toString())
    // console.log('totalBalances\t\t', balanceUser + balanceST + balanceDelegated)
    // console.log(
    //   'loss\t\t\t',
    //   totalPooledEther - (balanceUser + balanceST + balanceOperator + balanceDelegated)
    // )
    // console.log('---------------------------------------------')

    expect(totalPooledEther).to.eq(stakeAmount + 1n + beaconBalanceEarn2)
    expect(totalShares).to.eq(1096461171568761813n)
    expect(totalSupply).to.eq(stakeAmount + 1n + beaconBalanceEarn2)

    expect(balanceUser).to.eq(2736075000000000021n)
    expect(sharesUser).to.eq(stakeAmount)

    expect(balanceST).to.eq(87974999999999994n)
    expect(sharesST).to.eq(32153723856253938n)

    expect(balanceOperator).to.eq(87974999999999994n)
    expect(sharesOperator).to.eq(32153723856253938n)

    expect(balanceDelegated).to.eq(87974999999999988n)
    expect(sharesDelegated).to.eq(32153723856253936n)
    expect(delegationSharesDelegated).to.eq(stakeAmount)
  })
})
