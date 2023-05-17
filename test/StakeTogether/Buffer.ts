import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers } from 'hardhat'
import { defaultFixture } from '../fixtures/defaultFixture'
import connect from '../utils/connect'

dotenv.config()

describe('StakeTogether: Buffer', function () {
  it('Should deposit to withdrawals buffer successfully', async function () {
    const { StakeTogether, owner } = await loadFixture(defaultFixture)

    const depositAmount = ethers.parseEther('1')
    await connect(StakeTogether, owner).depositBuffer({ value: depositAmount })

    const bufferBalance = await StakeTogether.getBufferBalance()
    expect(bufferBalance).to.eq(depositAmount)
  })

  it('Should fail to deposit to withdrawals buffer with zero value', async function () {
    const { StakeTogether, owner } = await loadFixture(defaultFixture)

    await expect(connect(StakeTogether, owner).depositBuffer({ value: 0 })).to.be.revertedWith(
      'Value sent must be greater than 0'
    )
  })

  it('Should withdraw from withdrawals buffer successfully', async function () {
    const { StakeTogether, owner } = await loadFixture(defaultFixture)

    const depositAmount = ethers.parseEther('2')
    await connect(StakeTogether, owner).depositBuffer({ value: depositAmount })

    const withdrawAmount = ethers.parseEther('1')
    await connect(StakeTogether, owner).withdrawBuffer(withdrawAmount)

    const bufferBalance = await StakeTogether.getBufferBalance()
    expect(bufferBalance).to.eq(depositAmount - withdrawAmount)
  })

  it('Should fail to withdraw from withdrawals buffer with zero amount', async function () {
    const { StakeTogether, owner } = await loadFixture(defaultFixture)

    await expect(connect(StakeTogether, owner).withdrawBuffer(0)).to.be.revertedWith(
      'Withdrawal amount must be greater than 0'
    )
  })

  it('Should fail to withdraw from withdrawals buffer with amount exceeding buffer balance', async function () {
    const { StakeTogether, owner } = await loadFixture(defaultFixture)

    const depositAmount = ethers.parseEther('1')
    await connect(StakeTogether, owner).depositBuffer({ value: depositAmount })

    const withdrawAmount = ethers.parseEther('2')
    await expect(connect(StakeTogether, owner).withdrawBuffer(withdrawAmount)).to.be.revertedWith(
      'Withdrawal amount exceeds buffer balance'
    )
  })
})
