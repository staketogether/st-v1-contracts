// import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
// import { expect } from 'chai'
// import dotenv from 'dotenv'
// import { ethers } from 'hardhat'
// import { defaultFixture } from '../fixtures/defaultFixture'
// import connect from '../utils/connect'

// dotenv.config()

// describe('StakeTogether: Process Rewards', function () {
//   const blockTimeSkip = async () => {
//     for (let i = 0; i < 5760; i++) {
//       await ethers.provider.send('evm_mine')
//     }
//   }

//   it('Should stake and distribute fee', async function () {
//     const { StakeTogether, STOracle, owner, user1, user2, user3, user4, user9, nullAddress } =
//       await loadFixture(defaultFixture)

//     const initialDeposit = await StakeTogether.balanceOf(await StakeTogether.getAddress())

//     const stakeAmount = ethers.parseEther('1')

//     await connect(StakeTogether, user1).stake(user2, nullAddress, {
//       value: stakeAmount
//     })

//     let totalPooledEther = await StakeTogether.getTotalPooledEther()
//     let totalShares = await StakeTogether.totalShares()
//     let totalSupply = await StakeTogether.totalSupply()

//     let balanceUser = await StakeTogether.balanceOf(user1.address)
//     let sharesUser = await StakeTogether.sharesOf(user1.address)

//     let balanceST = await StakeTogether.balanceOf(owner.address)
//     let sharesST = await StakeTogether.sharesOf(owner.address)

//     let balanceOperator = await StakeTogether.balanceOf(user9.address)
//     let sharesOperator = await StakeTogether.sharesOf(user9.address)

//     let balanceCommunity = await StakeTogether.balanceOf(user2.address)

//     let sharesCommunity = await StakeTogether.sharesOf(user2.address)
//     let delegationSharesDelegated = await StakeTogether.delegatedSharesOf(user2.address)

//     console.log('---------------------------------------------')
//     console.log('balanceUser\t\t', balanceUser.toString())
//     console.log('balanceST\t\t', balanceST.toString())
//     console.log('balanceOperator\t\t', balanceOperator.toString())
//     console.log('balanceCommunity\t', balanceCommunity.toString())
//     console.log('totalPooledEther\t', totalPooledEther.toString())
//     console.log('totalBalances\t\t', initialDeposit + balanceUser + balanceST + balanceCommunity)
//     console.log(
//       'loss\t\t\t',
//       totalPooledEther - (initialDeposit + balanceUser + balanceST + balanceOperator + balanceCommunity)
//     )
//     console.log('---------------------------------------------\n\n')

//     expect(totalPooledEther).to.eq(initialDeposit + stakeAmount)
//     expect(totalShares).to.eq(initialDeposit + stakeAmount)
//     expect(totalSupply).to.eq(initialDeposit + stakeAmount)

//     expect(balanceUser).to.eq(stakeAmount)
//     expect(sharesUser).to.eq(stakeAmount)

//     expect(balanceST).to.eq(0n)
//     expect(sharesST).to.eq(0n)

//     expect(balanceOperator).to.eq(0n)
//     expect(sharesOperator).to.eq(0n)

//     expect(balanceCommunity).to.eq(0n)
//     expect(sharesCommunity).to.eq(0n)

//     // rebase earn

//     await blockTimeSkip()

//     const beaconBalanceEarn = ethers.parseEther('1')
//     console.log('\nEARN\t\t\t', beaconBalanceEarn.toString(), '\n')

//     let blockNumber = await ethers.provider.getBlockNumber()
//     expect(blockNumber).to.equal(5774)

//     let reportNextBlock = await STOracle.reportNextBlock()

//     await connect(STOracle, user1).report(reportNextBlock, beaconBalanceEarn)
//     await connect(STOracle, user2).report(reportNextBlock, beaconBalanceEarn)

//     const stakeAmount3 = ethers.parseEther('1')

//     await connect(StakeTogether, user3).stake(user4, nullAddress, {
//       value: stakeAmount3
//     })

//     totalPooledEther = await StakeTogether.getTotalPooledEther()
//     totalShares = await StakeTogether.totalShares()
//     totalSupply = await StakeTogether.totalSupply()

//     balanceUser = await StakeTogether.balanceOf(user1.address)
//     sharesUser = await StakeTogether.sharesOf(user1.address)

//     let balanceUser3 = await StakeTogether.balanceOf(user3.address)
//     let sharesUser3 = await StakeTogether.sharesOf(user3.address)

//     balanceST = await StakeTogether.balanceOf(owner.address)
//     sharesST = await StakeTogether.sharesOf(owner.address)

//     balanceOperator = await StakeTogether.balanceOf(user9.address)
//     sharesOperator = await StakeTogether.sharesOf(user9.address)

//     balanceCommunity = await StakeTogether.balanceOf(user2.address)
//     let balanceCommunity4 = await StakeTogether.balanceOf(user4.address)

//     sharesCommunity = await StakeTogether.sharesOf(user2.address)
//     delegationSharesDelegated = await StakeTogether.delegatedSharesOf(user2.address)
//     let delegationSharesDelegated4 = await StakeTogether.delegatedSharesOf(user4.address)

//     console.log('---------------------------------------------')
//     console.log('balanceUser\t\t', balanceUser.toString())
//     console.log('balanceUser3\t\t', balanceUser3.toString())
//     console.log('balanceST\t\t', balanceST.toString())
//     console.log('balanceOperator\t\t', balanceOperator.toString())
//     console.log('balanceCommunity\t', balanceCommunity.toString())
//     console.log('balanceCommunity4\t', balanceCommunity4.toString())
//     console.log('totalPooledEther\t', totalPooledEther.toString())
//     console.log(
//       'totalBalances\t\t',
//       initialDeposit +
//         balanceUser +
//         balanceUser3 +
//         balanceST +
//         balanceOperator +
//         balanceCommunity +
//         balanceCommunity4
//     )
//     console.log(
//       'loss\t\t\t',
//       totalPooledEther -
//         (initialDeposit +
//           balanceUser +
//           balanceUser3 +
//           balanceST +
//           balanceOperator +
//           balanceCommunity +
//           balanceCommunity4)
//     )
//     console.log('---------------------------------------------\n\n')

//     expect(totalPooledEther).to.eq(initialDeposit + stakeAmount + beaconBalanceEarn + stakeAmount3)
//     // expect(totalShares).to.eq(1634999999999999999n)
//     expect(totalSupply).to.eq(initialDeposit + stakeAmount + beaconBalanceEarn + stakeAmount3)

//     expect(balanceUser).to.eq(1910000000000000007n)
//     // expect(sharesUser).to.eq(stakeAmount)

//     expect(balanceUser3).to.eq(999999999999999999n)
//     // expect(sharesUser3).to.eq(544999999999999999n)

//     expect(balanceST).to.eq(29999999999999998n)
//     // expect(sharesST).to.eq(30000000000000000n)

//     expect(balanceOperator).to.eq(29999999999999998n)
//     // expect(sharesOperator).to.eq(30000000000000000n)

//     expect(balanceCommunity).to.eq(29999999999999996n)
//     expect(balanceCommunity4).to.eq(0n)

//     // expect(sharesCommunity).to.eq(29999999999999999n)
//     // expect(delegationSharesDelegated).to.eq(1029999999999999999n)
//     // expect(delegationSharesDelegated4).to.eq(544999999999999999n)

//     //  rebase loss

//     await blockTimeSkip()

//     const beaconBalanceLoss = 1n
//     console.log('\nLOSS\t\t\t', beaconBalanceLoss.toString(), '\n')

//     blockNumber = await ethers.provider.getBlockNumber()
//     expect(blockNumber).to.equal(11537)

//     reportNextBlock = await STOracle.reportNextBlock()

//     await connect(STOracle, user1).report(reportNextBlock, beaconBalanceLoss)
//     await connect(STOracle, user2).report(reportNextBlock, beaconBalanceLoss)

//     totalPooledEther = await StakeTogether.getTotalPooledEther()
//     // totalShares = await StakeTogether.totalShares()
//     totalSupply = await StakeTogether.totalSupply()

//     balanceUser = await StakeTogether.balanceOf(user1.address)
//     // sharesUser = await StakeTogether.sharesOf(user1.address)

//     balanceUser3 = await StakeTogether.balanceOf(user3.address)
//     // sharesUser3 = await StakeTogether.sharesOf(user3.address)

//     balanceST = await StakeTogether.balanceOf(owner.address)
//     // sharesST = await StakeTogether.sharesOf(owner.address)

//     balanceOperator = await StakeTogether.balanceOf(user9.address)
//     // sharesOperator = await StakeTogether.sharesOf(user9.address)

//     balanceCommunity = await StakeTogether.balanceOf(user2.address)
//     balanceCommunity4 = await StakeTogether.balanceOf(user4.address)

//     // sharesCommunity = await StakeTogether.sharesOf(user2.address)
//     // delegationSharesDelegated = await StakeTogether.delegatedSharesOf(user2.address)
//     // delegationSharesDelegated4 = await StakeTogether.delegatedSharesOf(user4.address)

//     console.log('---------------------------------------------')
//     console.log('balanceUser\t\t', balanceUser.toString())
//     console.log('balanceUser3\t\t', balanceUser3.toString())
//     console.log('balanceST\t\t', balanceST.toString())
//     console.log('balanceOperator\t\t', balanceOperator.toString())
//     console.log('balanceCommunity\t', balanceCommunity.toString())
//     console.log('balanceCommunity4\t', balanceCommunity4.toString())
//     console.log('totalPooledEther\t', totalPooledEther.toString())
//     console.log(
//       'totalBalances\t\t',
//       initialDeposit +
//         balanceUser +
//         balanceUser3 +
//         balanceST +
//         balanceOperator +
//         balanceCommunity +
//         balanceCommunity4
//     )
//     console.log(
//       'loss\t\t\t',
//       totalPooledEther -
//         (initialDeposit +
//           balanceUser +
//           balanceUser3 +
//           balanceST +
//           balanceOperator +
//           balanceCommunity +
//           balanceCommunity4)
//     )
//     console.log('---------------------------------------------\n\n')

//     expect(totalPooledEther).to.eq(initialDeposit + stakeAmount + stakeAmount3 + beaconBalanceLoss)
//     // expect(totalShares).to.eq(1634999999999999999n)
//     expect(totalSupply).to.eq(initialDeposit + stakeAmount + stakeAmount3 + beaconBalanceLoss)

//     expect(balanceUser).to.eq(1273333333333333339n)
//     // expect(sharesUser).to.eq(stakeAmount)

//     expect(balanceUser3).to.eq(666666666666666666n)
//     // expect(sharesUser3).to.eq(544999999999999999n)

//     expect(balanceST).to.eq(19999999999999998n)
//     // expect(sharesST).to.eq(30000000000000000n)

//     expect(balanceOperator).to.eq(19999999999999998n)
//     // expect(sharesOperator).to.eq(30000000000000000n)

//     expect(balanceCommunity).to.eq(19999999999999997n)
//     expect(balanceCommunity4).to.eq(0n)

//     // expect(sharesCommunity).to.eq(29999999999999999n)
//     // expect(delegationSharesDelegated).to.eq(1029999999999999999n)
//     // expect(delegationSharesDelegated4).to.eq(544999999999999999n)

//     // rebase earn2

//     await blockTimeSkip()

//     const beaconBalanceEarn2 = ethers.parseEther('2')
//     console.log('\nEARN\t\t\t', beaconBalanceEarn2.toString(), '\n')

//     blockNumber = await ethers.provider.getBlockNumber()
//     expect(blockNumber).to.equal(17299)

//     reportNextBlock = await STOracle.reportNextBlock()

//     await connect(STOracle, user1).report(reportNextBlock, beaconBalanceEarn2)
//     await connect(STOracle, user2).report(reportNextBlock, beaconBalanceEarn2)

//     totalPooledEther = await StakeTogether.getTotalPooledEther()
//     totalShares = await StakeTogether.totalShares()
//     totalSupply = await StakeTogether.totalSupply()

//     balanceUser = await StakeTogether.balanceOf(user1.address)
//     sharesUser = await StakeTogether.sharesOf(user1.address)

//     balanceUser3 = await StakeTogether.balanceOf(user3.address)
//     sharesUser3 = await StakeTogether.sharesOf(user3.address)

//     balanceST = await StakeTogether.balanceOf(owner.address)
//     sharesST = await StakeTogether.sharesOf(owner.address)

//     balanceOperator = await StakeTogether.balanceOf(user9.address)
//     sharesOperator = await StakeTogether.sharesOf(user9.address)

//     balanceCommunity = await StakeTogether.balanceOf(user2.address)
//     balanceCommunity4 = await StakeTogether.balanceOf(user4.address)

//     sharesCommunity = await StakeTogether.sharesOf(user2.address)

//     delegationSharesDelegated = await StakeTogether.delegatedSharesOf(user2.address)
//     delegationSharesDelegated4 = await StakeTogether.delegatedSharesOf(user4.address)

//     console.log('---------------------------------------------')
//     console.log('balanceUser\t\t', balanceUser.toString())
//     console.log('balanceUser3\t\t', balanceUser3.toString())
//     console.log('balanceST\t\t', balanceST.toString())
//     console.log('balanceOperator\t\t', balanceOperator.toString())
//     console.log('balanceCommunity\t', balanceCommunity.toString())
//     console.log('balanceCommunity4\t', balanceCommunity4.toString())
//     console.log('totalPooledEther\t', totalPooledEther.toString())
//     console.log(
//       'totalBalances\t\t',
//       initialDeposit +
//         balanceUser +
//         balanceUser3 +
//         balanceST +
//         balanceOperator +
//         balanceCommunity +
//         balanceCommunity4
//     )
//     console.log(
//       'loss\t\t\t',
//       totalPooledEther -
//         (initialDeposit +
//           balanceUser +
//           balanceUser3 +
//           balanceST +
//           balanceOperator +
//           balanceCommunity +
//           balanceCommunity4)
//     )
//     console.log('---------------------------------------------\n\n')

//     expect(totalPooledEther).to.eq(stakeAmount + initialDeposit + beaconBalanceEarn + beaconBalanceEarn2)
//     // expect(totalShares).to.eq(1781811223006197836n)
//     expect(totalSupply).to.eq(stakeAmount + initialDeposit + beaconBalanceEarn + beaconBalanceEarn2)

//     expect(balanceUser).to.eq(2432196530996702639n)
//     // expect(sharesUser).to.eq(stakeAmount)

//     expect(balanceUser3).to.eq(1273401325129163678n)
//     // expect(sharesUser3).to.eq(544999999999999999n)

//     expect(balanceST).to.eq(98205243555772670n)
//     // expect(sharesST).to.eq(79049999999999999n)

//     expect(balanceOperator).to.eq(98205243555772670n)
//     // expect(sharesOperator).to.eq(79049999999999999n)

//     expect(balanceCommunity).to.eq(77795990561929889n)
//     expect(balanceCommunity4).to.eq(20195666200658449n)

//     // expect(sharesCommunity).to.eq(62077142857142855n)
//     // expect(delegationSharesDelegated).to.eq(1062077142857142855n)
//     // expect(delegationSharesDelegated4).to.eq(561634080149054982n)
//   })
// })
