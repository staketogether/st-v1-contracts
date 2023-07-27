import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { upgrades } from 'hardhat'
import { Fees, FeesV2__factory } from '../../typechain'
import connect from '../utils/connect'
import { feesFixture } from './FeesFixture'

dotenv.config()

describe('Fees', function () {
  let feesContract: Fees
  let owner: SignerWithAddress
  let user1: SignerWithAddress
  let ADMIN_ROLE: string

  // Setting up the fixture before each test
  beforeEach(async function () {
    const fixture = await loadFixture(feesFixture)
    feesContract = fixture.feesContract
    owner = fixture.owner
    user1 = fixture.user1
    ADMIN_ROLE = fixture.ADMIN_ROLE
  })

  // Test to check if pause and unpause functions work properly
  it('should pause and unpause the contract if the user has admin role', async function () {
    // Check if the contract is not paused at the beginning
    expect(await feesContract.paused()).to.equal(false)

    // User without admin role tries to pause the contract - should fail
    await expect(connect(feesContract, user1).pause()).to.reverted

    // The owner pauses the contract
    await connect(feesContract, owner).pause()

    // Check if the contract is paused
    expect(await feesContract.paused()).to.equal(true)

    // User without admin role tries to unpause the contract - should fail
    await expect(connect(feesContract, user1).unpause()).to.reverted

    // The owner unpauses the contract
    await connect(feesContract, owner).unpause()
    // Check if the contract is not paused
    expect(await feesContract.paused()).to.equal(false)
  })

  it('should upgrade the contract if the user has upgrader role', async function () {
    expect(await feesContract.version()).to.equal(1n)

    const FeesV2Factory = new FeesV2__factory(user1)

    // A user without the UPGRADER_ROLE tries to upgrade the contract - should fail
    await expect(upgrades.upgradeProxy(await feesContract.getAddress(), FeesV2Factory)).to.be.reverted

    const FeesV2FactoryOwner = new FeesV2__factory(owner)

    // The owner (who has the UPGRADER_ROLE) upgrades the contract - should succeed
    const upgradedFeesContract = await upgrades.upgradeProxy(
      await feesContract.getAddress(),
      FeesV2FactoryOwner
    )

    // Upgrade version
    await upgradedFeesContract.initializeV2()

    expect(await upgradedFeesContract.version()).to.equal(2n)
  })
})
