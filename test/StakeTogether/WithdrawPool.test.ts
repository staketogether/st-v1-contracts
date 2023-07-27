// import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
// import { expect } from 'chai'
// import dotenv from 'dotenv'
// import { ethers } from 'ethers'
// import { defaultFixture } from '../fixtures/defaultFixture'
// import { mockedRewardsFixture } from '../fixtures/mockedRewardsFixture'
// import connect from '../utils/connect'

// dotenv.config()

// describe('StakeTogether: WithdrawPool', function () {
//   it.skip('Should withdraw from pool successfully after making a deposit', async function () {
//     const { StakeTogether, Fees, owner, user1, user2, user3, user4, nullAddress } = await loadFixture(
//       defaultFixture
//     )

//     const stakeAmount = ethers.parseEther('1')

//     const STAKE_ENTRY_FEE = 1n
//     const SENDER_ROLE = 7
//     const { shares, amounts } = await Fees.contract.estimateFeePercentage(STAKE_ENTRY_FEE, stakeAmount)

//     await connect(StakeTogether.contract, user1).depositPool(user2, nullAddress, {
//       value: stakeAmount
//     })

//     await connect(StakeTogether.contract, user3).depositPool(user2, nullAddress, {
//       value: stakeAmount
//     })

//     const withdrawAmount = ethers.parseEther('0.7')
//     const withdrawAmountShares = await StakeTogether.contract.sharesByPooledEth(withdrawAmount)
//     const totalSharesBeforeWithdraw = await StakeTogether.contract.totalShares()
//     const totalPooledEtherBeforeWithdraw = await StakeTogether.contract.totalPooledEther()
//     const sharesUser3BeforeWithdraw = await StakeTogether.contract.shares(user3.address)
//     const balanceUser3BeforeWithdraw = await StakeTogether.contract.balanceOf(user3.address)
//     await connect(StakeTogether.contract, user1).withdrawPool(withdrawAmount, user2)

//     expect(await StakeTogether.contract.shares(user1.address)).to.eq(
//       shares[SENDER_ROLE] - withdrawAmountShares
//     )
//     expect(await StakeTogether.contract.balanceOf(user1.address)).to.eq(
//       amounts[SENDER_ROLE] - withdrawAmount
//     )
//     expect(await StakeTogether.contract.shares(user3.address)).to.eq(sharesUser3BeforeWithdraw)
//     expect(await StakeTogether.contract.balanceOf(user3.address)).to.eq(balanceUser3BeforeWithdraw)
//     expect(await StakeTogether.contract.totalPooledEther()).to.eq(
//       totalSharesBeforeWithdraw - withdrawAmountShares
//     )
//     expect(await StakeTogether.contract.totalShares()).to.eq(
//       totalPooledEtherBeforeWithdraw - withdrawAmount
//     )
//   })
//   it.skip('Should not allow withdraw if the Stake Together does not have sufficient amount', async function () {
//     const { StakeTogether, Fees, owner, user1, user2, user3, user4, nullAddress } = await loadFixture(
//       defaultFixture
//     )

//     const stakeAmount = ethers.parseEther('1')

//     await expect(
//       connect(StakeTogether.contract, user1).withdrawPool(stakeAmount, user4)
//     ).to.be.revertedWith('NOT_ENOUGH_POOL_BALANCE')
//   })
//   it.skip('Should not allow withdraw if the pool does not exists', async function () {
//     const { StakeTogether, Fees, owner, user1, user2, user3, user4, nullAddress } = await loadFixture(
//       defaultFixture
//     )

//     const stakeAmount = ethers.parseEther('1')

//     await connect(StakeTogether.contract, user1).depositPool(user2, nullAddress, {
//       value: stakeAmount
//     })

//     await expect(
//       connect(StakeTogether.contract, user1).withdrawPool(stakeAmount, nullAddress)
//     ).to.be.revertedWith('POOL_NOT_FOUND')
//   })
//   it.skip('Should not allow withdraw of insufficient amount', async function () {
//     const { StakeTogether, Fees, owner, user1, user2, user3, user4, nullAddress } = await loadFixture(
//       defaultFixture
//     )

//     const stakeAmount = ethers.parseEther('1')

//     await connect(StakeTogether.contract, user1).depositPool(user2, nullAddress, {
//       value: stakeAmount
//     })

//     await expect(
//       connect(StakeTogether.contract, user1).withdrawPool(stakeAmount, user2)
//     ).to.be.revertedWith('AMOUNT_EXCEEDS_BALANCE')
//   })
//   it.skip('Should withdraw from pool successfully after making a deposit and receiving rewards', async function () {
//     const { StakeTogether, Fees, owner, user1, user2, user3, user4, nullAddress } = await loadFixture(
//       mockedRewardsFixture
//     )
//     // TODO: Add test for rewards
//   })
// })
