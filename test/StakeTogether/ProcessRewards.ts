import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers } from 'hardhat'
import { defaultFixture } from '../fixtures/defaultFixture'
import connect from '../utils/connect'

dotenv.config()

describe('StakeTogether: Process Rewards', function () {
  const blockTimeSkip = async () => {
    for (let i = 0; i < 5760; i++) {
      await ethers.provider.send('evm_mine')
    }
  }

  it('Should stake and distribute fee', async function () {
    const { StakeTogether, STOracle, owner, user1, user2, user3, user4, user9, nullAddress } =
      await loadFixture(defaultFixture)

    const initialDeposit = await StakeTogether.balanceOf(await StakeTogether.getAddress())

    const stakeAmount = ethers.parseEther('1')

    await connect(StakeTogether, user1).stake(user2, nullAddress, {
      value: stakeAmount
    })

    let totalPooledEther = await StakeTogether.getTotalPooledEther()
    let totalShares = await StakeTogether.totalShares()
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

    // expect(totalPooledEther).to.eq(stakeAmount + 1n)
    // expect(totalShares).to.eq(stakeAmount + 1n)
    // expect(totalSupply).to.eq(stakeAmount + 1n)

    // expect(balanceUser).to.eq(stakeAmount)
    // expect(sharesUser).to.eq(stakeAmount)

    // expect(balanceST).to.eq(0n)
    // expect(sharesST).to.eq(0n)

    // expect(balanceOperator).to.eq(0n)
    // expect(sharesOperator).to.eq(0n)

    // expect(balanceDelegated).to.eq(0n)
    // expect(sharesDelegated).to.eq(0n)

    // rebase earn

    await blockTimeSkip()

    const beaconBalanceEarn = ethers.parseEther('1')

    let blockNumber = await ethers.provider.getBlockNumber()
    expect(blockNumber).to.equal(5774)

    let reportNextBlock = await STOracle.reportNextBlock()

    await connect(STOracle, user1).report(reportNextBlock, beaconBalanceEarn)
    await connect(STOracle, user2).report(reportNextBlock, beaconBalanceEarn)

    const stakeAmount2 = ethers.parseEther('1')

    await connect(StakeTogether, user3).stake(user4, nullAddress, {
      value: stakeAmount2
    })

    totalPooledEther = await StakeTogether.getTotalPooledEther()
    totalShares = await StakeTogether.totalShares()
    totalSupply = await StakeTogether.totalSupply()

    balanceUser = await StakeTogether.balanceOf(user1.address)
    sharesUser = await StakeTogether.sharesOf(user1.address)

    let balanceUser3 = await StakeTogether.balanceOf(user3.address)
    let sharesUser3 = await StakeTogether.sharesOf(user3.address)

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

    expect(totalPooledEther).to.eq(initialDeposit + stakeAmount + beaconBalanceEarn + stakeAmount2)
    // expect(totalShares).to.eq(1047120418848167536n)
    expect(totalSupply).to.eq(initialDeposit + stakeAmount + beaconBalanceEarn + stakeAmount2)

    expect(balanceUser).to.eq(1499999999999995501n)
    expect(sharesUser).to.eq(stakeAmount)

    // expect(balanceST).to.eq(29999999999999998n)
    // expect(sharesST).to.eq(15706806282722512n)

    // expect(balanceOperator).to.eq(29999999999999998n)
    // expect(sharesOperator).to.eq(15706806282722512n)

    // expect(balanceDelegated).to.eq(29999999999999996n)
    // expect(sharesDelegated).to.eq(15706806282722511n)
    // expect(delegationSharesDelegated).to.eq(stakeAmount)

    expect(balanceUser3).to.eq(stakeAmount)
    expect(sharesUser3).to.eq(666666666666668666n)

    //  rebase loss

    await blockTimeSkip()

    const beaconBalanceLoss = 1n

    blockNumber = await ethers.provider.getBlockNumber()
    expect(blockNumber).to.equal(11537)

    reportNextBlock = await STOracle.reportNextBlock()

    await connect(STOracle, user1).report(reportNextBlock, beaconBalanceLoss)
    await connect(STOracle, user2).report(reportNextBlock, beaconBalanceLoss)

    totalPooledEther = await StakeTogether.getTotalPooledEther()
    totalShares = await StakeTogether.totalShares()
    totalSupply = await StakeTogether.totalSupply()

    balanceUser = await StakeTogether.balanceOf(user1.address)
    sharesUser = await StakeTogether.sharesOf(user1.address)

    balanceUser3 = await StakeTogether.balanceOf(user3.address)
    sharesUser3 = await StakeTogether.sharesOf(user3.address)

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

    expect(totalPooledEther).to.eq(initialDeposit + stakeAmount + stakeAmount2 + beaconBalanceLoss)
    // expect(totalShares).to.eq(1047120418848167536n)
    expect(totalSupply).to.eq(initialDeposit + stakeAmount + stakeAmount2 + beaconBalanceLoss)

    expect(balanceUser).to.eq(1124999999999996626n)
    expect(sharesUser).to.eq(stakeAmount)

    expect(balanceUser3).to.eq(ethers.parseEther('0.75'))
    // expect(sharesUser3).to.eq(stakeAmount)

    // expect(balanceST).to.eq(22499999999999998n)
    // expect(sharesST).to.eq(15706806282722512n)

    // expect(balanceOperator).to.eq(22499999999999998n)
    // expect(sharesOperator).to.eq(15706806282722512n)

    // expect(balanceDelegated).to.eq(22499999999999997n)
    // expect(sharesDelegated).to.eq(15706806282722511n)
    // expect(delegationSharesDelegated).to.eq(stakeAmount)

    // rebase earn2

    await blockTimeSkip()

    const beaconBalanceEarn2 = ethers.parseEther('2')

    blockNumber = await ethers.provider.getBlockNumber()
    expect(blockNumber).to.equal(17299)

    reportNextBlock = await STOracle.reportNextBlock()

    await connect(STOracle, user1).report(reportNextBlock, beaconBalanceEarn2)
    await connect(STOracle, user2).report(reportNextBlock, beaconBalanceEarn2)

    totalPooledEther = await StakeTogether.getTotalPooledEther()
    totalShares = await StakeTogether.totalShares()
    totalSupply = await StakeTogether.totalSupply()

    balanceUser = await StakeTogether.balanceOf(user1.address)
    sharesUser = await StakeTogether.sharesOf(user1.address)

    balanceUser3 = await StakeTogether.balanceOf(user3.address)
    sharesUser3 = await StakeTogether.sharesOf(user3.address)

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

    expect(totalPooledEther).to.eq(stakeAmount + initialDeposit + beaconBalanceEarn + beaconBalanceEarn2)
    // expect(totalShares).to.eq(1096461171568761813n)
    expect(totalSupply).to.eq(stakeAmount + initialDeposit + beaconBalanceEarn + beaconBalanceEarn2)

    expect(balanceUser).to.eq(1874999999999987628n)
    expect(sharesUser).to.eq(stakeAmount)

    expect(balanceUser3).to.eq(1249999999999995501n)
    // expect(sharesUser3).to.eq(stakeAmount)

    // expect(balanceST).to.eq(87974999999999994n)
    // expect(sharesST).to.eq(32153723856253938n)

    // expect(balanceOperator).to.eq(87974999999999994n)
    // expect(sharesOperator).to.eq(32153723856253938n)

    // expect(balanceDelegated).to.eq(87974999999999988n)
    // expect(sharesDelegated).to.eq(32153723856253936n)
    // expect(delegationSharesDelegated).to.eq(stakeAmount)
  })
})
