// import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
// import { expect } from 'chai'
// import dotenv from 'dotenv'
// import { ethers } from 'hardhat'
// import { defaultFixture } from '../fixtures/defaultFixture'
// import connect from '../utils/connect'

// dotenv.config()

// describe('StakeTogether: Unstake', function () {
//   const blockTimeSkip = async () => {
//     for (let i = 0; i < 5760; i++) {
//       await ethers.provider.send('evm_mine')
//     }
//   }

//   it('Should unstake and distribute fee successfully', async function () {
//     const { StakeTogether, Router, owner, user1, user2, user3, user4, nullAddress, initialDeposit } =
//       await loadFixture(defaultFixture)

//     const stakeAmount = ethers.parseEther('1')
//     await connect(StakeTogether, user1).depositPool(user2, nullAddress, {
//       value: stakeAmount
//     })

//     await connect(StakeTogether, user3).depositPool(user4, nullAddress, {
//       value: stakeAmount
//     })

//     await blockTimeSkip()

//     const newBeaconBalance = ethers.parseEther('0.2')

//     // let blockNumber = await ethers.provider.getBlockNumber()
//     // expect(blockNumber).to.equal(5775)

//     let reportNextBlock = await Router.reportBlockNumber()

//     // await connect(Router, user1).report(reportNextBlock, newBeaconBalance)
//     // await connect(Router, user2).report(reportNextBlock, newBeaconBalance)

//     const unstakeAmount = 1000000000000000000n
//     await connect(StakeTogether, user1).withdrawPool(unstakeAmount, user2)

//     const totalPooledEther = await StakeTogether.totalPooledEther()
//     const totalShares = await StakeTogether.totalShares()
//     // const totalDelegatedShares = await StakeTogether.totalDelegatedShares()
//     const totalSupply = await StakeTogether.totalSupply()

//     const balanceUser = await StakeTogether.balanceOf(user1.address)
//     const balanceUser3 = await StakeTogether.balanceOf(user3.address)

//     const sharesUser = await StakeTogether.sharesOf(user1.address)
//     // const delegatedSharesUser = await StakeTogether.delegatedSharesOf(user1.address)
//     const sharesST = await StakeTogether.sharesOf(owner.address)

//     const sharesDelegated = await StakeTogether.sharesOf(user2.address)
//     // const delegatedSharedDelegated = await StakeTogether.delegatedSharesOf(user2.address)

//     expect(totalPooledEther).to.eq(stakeAmount + stakeAmount - unstakeAmount + initialDeposit)
//     // expect(totalShares).to.eq(1016498625114573783n)
//     // expect(totalDelegatedShares).to.eq(stakeAmount + 1n)
//     expect(totalSupply).to.eq(stakeAmount + stakeAmount - unstakeAmount + initialDeposit)

//     expect(balanceUser).to.eq(0n)
//     expect(balanceUser3).to.eq(1091002042649965438n)
//     // expect(sharesUser).to.eq(0)
//     // expect(delegatedSharesUser).to.eq(0)
//     // expect(sharesST).to.eq(5499541704857928n)

//     // expect(sharesDelegated).to.eq(2749770852428963n)
//     // expect(delegatedSharedDelegated).to.eq(0n)
//   })
// })
