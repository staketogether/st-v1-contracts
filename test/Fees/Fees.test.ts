import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { feesFixture } from './FeesFixture'

dotenv.config()

describe('Fees', function () {
  it('should start with no fees', async function () {
    const { feesContract } = await loadFixture(feesFixture)

    const [feeTypes, feeValues, feeMathTypes, allocations] = await feesContract.getFees()

    expect(feeTypes.length).to.eq(6)
    expect(feeValues.length).to.eq(6)
    expect(feeMathTypes.length).to.eq(6)
    expect(allocations.length).to.eq(6)
  })
})
