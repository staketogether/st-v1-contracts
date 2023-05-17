import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers } from 'ethers'
import { defaultFixture } from '../fixtures/defaultFixture'
import connect from '../utils/connect'

dotenv.config()

xdescribe('StakeTogether: Create Validator', function () {
  it('Should create a validator successfully', async function () {
    const { StakeTogether, Validator, owner, user1, user2 } = await loadFixture(defaultFixture)

    const stakeAmount = ethers.parseEther('32.1')

    await connect(StakeTogether, user1).stake(user2, {
      value: stakeAmount
    })

    // await connect(StakeTogether, owner).createValidator()

    const validatorIndex = await Validator.validatorIndex()
    expect(validatorIndex).to.equal(1)
  })

  it('Should fail to create a validator due lack ether on pool balance', async function () {
    const { StakeTogether, Validator, owner, user1, user2 } = await loadFixture(defaultFixture)

    const stakeAmount = ethers.parseEther('2')

    await connect(StakeTogether, user1).stake(user2, {
      value: stakeAmount
    })

    // await expect(connect(StakeTogether, owner).createValidator()).to.be.revertedWith(
    //   'Not enough ether on poolBalance to create validator'
    // )
  })
})
