// import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
// import { expect } from 'chai'
// import dotenv from 'dotenv'
// import { ethers } from 'ethers'
// import { defaultFixture } from '../fixtures/defaultFixture'
// import connect from '../utils/connect'

// dotenv.config()

// describe.only('StakeTogether: Stake', function () {
//   it('Should deposit successfuly', async function () {
//     const { StakeTogether, owner, user1, user2, nullAddress } = await loadFixture(defaultFixture)

//     const stakeAmount = ethers.parseEther('1')

//     await connect(StakeTogether, user1).depositPool(user2, nullAddress, {
//       value: stakeAmount
//     })

//     const totalPooledEther = await StakeTogether.totalPooledEther()
//     const totalShares = await StakeTogether.totalShares()
//     const totalSupply = await StakeTogether.totalSupply()

//     const balanceUser = await StakeTogether.balanceOf(user1.address)
//     const sharesUser = await StakeTogether.sharesOf(user1.address)

//     const sharesST = await StakeTogether.sharesOf(owner.address)

//     const sharesDelegated = await StakeTogether.sharesOf(user2.address)
//     const delegatedSharedDelegated = await StakeTogether.poolSharesOf(user2.address)

//     expect(totalPooledEther).to.eq(stakeAmount + 1n)
//     expect(totalShares).to.eq(stakeAmount + 1n)
//     expect(totalSupply).to.eq(stakeAmount + 1n)

//     expect(balanceUser).to.eq(stakeAmount)
//     expect(sharesUser).to.eq(stakeAmount)

//     expect(sharesST).to.eq(0n)

//     expect(sharesDelegated).to.eq(0n)
//     expect(delegatedSharedDelegated).to.eq(stakeAmount)
//   })

//   it.only('Should deposit and change shares by send ether', async function () {
//     const { StakeTogether, owner, user1, user2, user3, user4, nullAddress } = await loadFixture(
//       defaultFixture
//     )

//     const stakeAmount = ethers.parseEther('1')
//     const sendAmount = 334n

//     await connect(StakeTogether, user1).depositPool(user2, nullAddress, {
//       value: stakeAmount
//     })

//     await connect(StakeTogether, user2).depositPool(user2, nullAddress, {
//       value: stakeAmount
//     })

//     await connect(StakeTogether, user3).depositPool(user2, nullAddress, {
//       value: stakeAmount
//     })

//     await user4.sendTransaction({
//       to: await StakeTogether.getAddress(),
//       value: sendAmount
//     })

//     const totalPooledEther = await StakeTogether.totalPooledEther()
//     const totalShares = await StakeTogether.totalShares()
//     const totalSupply = await StakeTogether.totalSupply()

//     const balanceUser = await StakeTogether.balanceOf(user1.address)
//     const sharesUser = await StakeTogether.sharesOf(user1.address)

//     const sharesST = await StakeTogether.sharesOf(owner.address)

//     const sharesDelegated = await StakeTogether.sharesOf(user2.address)
//     const delegatedSharedDelegated = await StakeTogether.poolSharesOf(user2.address)

//     // expect(totalPooledEther).to.eq(stakeAmount + sendAmount)
//     // expect(totalShares).to.eq(stakeAmount + sendAmount)
//     // expect(totalSupply).to.eq(stakeAmount + sendAmount)

//     expect(balanceUser).to.eq(stakeAmount + sendAmount)
//     expect(sharesUser).to.eq(stakeAmount + sendAmount)

//     expect(sharesST).to.eq(0n)

//     expect(sharesDelegated).to.eq(0n)
//     expect(delegatedSharedDelegated).to.eq(stakeAmount)
//   })

//   it.only('Should stake successfuly in sequence', async function () {
//     const { StakeTogether, owner, user1, user2, user3, user4, nullAddress, initialDeposit } =
//       await loadFixture(defaultFixture)

//     const stakeAmount1 = ethers.parseEther('1.3')

//     await connect(StakeTogether, user1).depositPool(user2, nullAddress, {
//       value: stakeAmount1
//     })

//     const totalPooledEther1 = await StakeTogether.totalPooledEther()
//     const totalShares1 = await StakeTogether.totalShares()
//     const totalSupply1 = await StakeTogether.totalSupply()

//     const balanceUser1 = await StakeTogether.balanceOf(user1.address)
//     const sharesUser1 = await StakeTogether.sharesOf(user1.address)

//     const sharesST1 = await StakeTogether.sharesOf(owner.address)

//     const sharesDelegated1 = await StakeTogether.sharesOf(user2.address)
//     const poolShares1 = await StakeTogether.poolSharesOf(user2.address)

//     expect(totalPooledEther1).to.eq(stakeAmount1 + initialDeposit)
//     expect(totalShares1).to.eq(stakeAmount1 + initialDeposit)
//     expect(totalSupply1).to.eq(stakeAmount1 + initialDeposit)

//     expect(balanceUser1).to.eq(stakeAmount1)
//     expect(sharesUser1).to.eq(stakeAmount1)

//     expect(sharesST1).to.eq(0n)

//     expect(sharesDelegated1).to.eq(0n)
//     expect(poolShares1).to.eq(stakeAmount1)

//     const stakeAmount2 = ethers.parseEther('0.1')

//     await connect(StakeTogether, user1).depositPool(user3, nullAddress, {
//       value: stakeAmount2
//     })

//     const totalPooledEther2 = await StakeTogether.totalPooledEther()
//     const totalShares2 = await StakeTogether.totalShares()
//     const totalSupply2 = await StakeTogether.totalSupply()

//     const balanceUser2 = await StakeTogether.balanceOf(user1.address)
//     const sharesUser2 = await StakeTogether.sharesOf(user1.address)

//     const sharesST2 = await StakeTogether.sharesOf(owner.address)

//     const sharesDelegated2 = await StakeTogether.sharesOf(user3.address)
//     const delegationSharesDelegated2 = await StakeTogether.poolSharesOf(user3.address)

//     expect(totalPooledEther2).to.eq(stakeAmount1 + stakeAmount2 + 1n)
//     expect(totalShares2).to.eq(stakeAmount1 + stakeAmount2 + 1n)
//     expect(totalSupply2).to.eq(stakeAmount1 + stakeAmount2 + 1n)

//     expect(balanceUser2).to.eq(stakeAmount1 + stakeAmount2)
//     expect(sharesUser2).to.eq(stakeAmount1 + stakeAmount2)

//     expect(sharesST2).to.eq(0n)

//     expect(sharesDelegated2).to.eq(0n)
//     expect(delegationSharesDelegated2).to.eq(stakeAmount2)
//   })

//   // it('Should correctly return delegation addresses and shares for an address', async function () {
//   //   const { StakeTogether, user1, user2, user3, user4, nullAddress } = await loadFixture(defaultFixture)

//   //   const stakeAmountUser4 = ethers.parseEther('1')
//   //   const stakeAmountUser2 = ethers.parseEther('2')

//   //   await connect(StakeTogether, user1).stake(user4, nullAddress, {
//   //     value: stakeAmountUser4
//   //   })

//   //   await connect(StakeTogether, user1).stake(user2, nullAddress, {
//   //     value: stakeAmountUser4
//   //   })

//   //   await connect(StakeTogether, user1).stake(user3, nullAddress, {
//   //     value: stakeAmountUser2
//   //   })

//   //   const [delegatedAddresses, delegatedShares] = await StakeTogether.getDelegationsOf(user1.address)

//   //   expect(delegatedAddresses).to.have.lengthOf(3)
//   //   expect(delegatedAddresses).to.include(user4.address)
//   //   expect(delegatedAddresses).to.include(user2.address)
//   //   expect(delegatedAddresses).to.include(user3.address)

//   //   const indexUser4 = delegatedAddresses.indexOf(user4.address)
//   //   const indexUser2 = delegatedAddresses.indexOf(user2.address)
//   //   const indexUser3 = delegatedAddresses.indexOf(user3.address)

//   //   expect(delegatedShares[indexUser4]).to.eq(stakeAmountUser4)
//   //   expect(delegatedShares[indexUser2]).to.eq(stakeAmountUser4)
//   //   expect(delegatedShares[indexUser3]).to.eq(stakeAmountUser2)

//   //   expect(delegatedShares.reduce((share, total) => share + total, 0n)).to.eq(
//   //     stakeAmountUser4 + stakeAmountUser4 + stakeAmountUser2
//   //   )
//   // })

//   // it('Should correctly return delegation addresses and shares for an address', async function () {
//   //   const { StakeTogether, user1, user2, user3, user4, nullAddress } = await loadFixture(defaultFixture)

//   //   const stakeAmountUser1 = ethers.parseEther('1')
//   //   const stakeAmountUser2 = ethers.parseEther('2')

//   //   await connect(StakeTogether, user1).stake(user4, nullAddress, {
//   //     value: stakeAmountUser1
//   //   })

//   //   await connect(StakeTogether, user1).stake(user4, nullAddress, {
//   //     value: stakeAmountUser1
//   //   })

//   //   await connect(StakeTogether, user2).stake(user4, nullAddress, {
//   //     value: stakeAmountUser1
//   //   })

//   //   await connect(StakeTogether, user3).stake(user4, nullAddress, {
//   //     value: stakeAmountUser2
//   //   })

//   //   const [delegatedAddresses, delegatedShares] = await StakeTogether.getDelegatesOf(user4.address)

//   //   expect(delegatedAddresses).to.have.lengthOf(3)

//   //   expect(delegatedAddresses).to.include(user1.address)
//   //   expect(delegatedAddresses).to.include(user2.address)
//   //   expect(delegatedAddresses).to.include(user3.address)

//   //   const indexUser1 = delegatedAddresses.indexOf(user1.address)
//   //   const indexUser2 = delegatedAddresses.indexOf(user2.address)
//   //   const indexUser3 = delegatedAddresses.indexOf(user3.address)

//   //   expect(delegatedShares[indexUser1]).to.eq(stakeAmountUser1 + stakeAmountUser1)
//   //   expect(delegatedShares[indexUser2]).to.eq(stakeAmountUser1)
//   //   expect(delegatedShares[indexUser3]).to.eq(stakeAmountUser2)

//   //   expect(delegatedShares.reduce((share, total) => share + total, 0n)).to.eq(
//   //     stakeAmountUser1 + stakeAmountUser1 + stakeAmountUser1 + stakeAmountUser2
//   //   )
//   // })
// })
