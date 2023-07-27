import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers, upgrades } from 'hardhat'
import { Fees, FeesV2__factory } from '../../typechain'
import connect from '../utils/connect'
import { feesFixture } from './FeesFixture'

dotenv.config()

describe('Fees', function () {
  let feesContract: Fees
  let feesProxy: string
  let owner: HardhatEthersSigner
  let user1: HardhatEthersSigner
  let user2: HardhatEthersSigner
  let user3: HardhatEthersSigner
  let user4: HardhatEthersSigner
  let user5: HardhatEthersSigner
  let user6: HardhatEthersSigner
  let user7: HardhatEthersSigner
  let user8: HardhatEthersSigner
  let nullAddress: string
  let ADMIN_ROLE: string

  // Setting up the fixture before each test
  beforeEach(async function () {
    const fixture = await loadFixture(feesFixture)
    feesContract = fixture.feesContract
    feesProxy = fixture.feesProxy
    owner = fixture.owner
    user1 = fixture.user1
    user2 = fixture.user2
    user3 = fixture.user3
    user4 = fixture.user4
    user5 = fixture.user5
    user6 = fixture.user6
    user7 = fixture.user7
    user8 = fixture.user8
    nullAddress = fixture.nullAddress
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
    await expect(upgrades.upgradeProxy(feesProxy, FeesV2Factory)).to.be.reverted

    const FeesV2FactoryOwner = new FeesV2__factory(owner)

    // The owner (who has the UPGRADER_ROLE) upgrades the contract - should succeed
    const upgradedFeesContract = await upgrades.upgradeProxy(feesProxy, FeesV2FactoryOwner)

    // Upgrade version
    await upgradedFeesContract.initializeV2()

    expect(await upgradedFeesContract.version()).to.equal(2n)
  })

  it('should correctly set the StakeTogether address', async function () {
    // User1 tries to set the StakeTogether address to zero address - should fail
    await expect(connect(feesContract, owner).setStakeTogether(nullAddress)).to.be.reverted

    // User1 tries to set the StakeTogether address to their own address - should fail
    await expect(connect(feesContract, user1).setStakeTogether(user1.address)).to.be.reverted

    // Owner sets the StakeTogether address - should succeed
    await connect(feesContract, owner).setStakeTogether(user1.address)

    // Verify that the StakeTogether address was correctly set
    expect(await feesContract.stakeTogether()).to.equal(user1.address)
  })

  it('should correctly receive Ether and transfer to StakeTogether via receive', async function () {
    // Set the StakeTogether address to user1
    await connect(feesContract, owner).setStakeTogether(user1.address)

    const initBalance = await ethers.provider.getBalance(user1.address)

    // User2 sends 1 Ether to the contract's receive function
    const tx = await user2.sendTransaction({
      to: feesProxy,
      value: ethers.parseEther('1.0')
    })

    // Simulate confirmation of the transaction
    await tx.wait()

    // Verify that the Ether was correctly transferred to user1 (StakeTogether)
    const finalBalance = await ethers.provider.getBalance(user1.address)
    expect(finalBalance).to.equal(initBalance + ethers.parseEther('1.0'))

    // Verify that the ReceiveEther event was emitted
    await expect(tx)
      .to.emit(feesContract, 'ReceiveEther')
      .withArgs(user2.address, ethers.parseEther('1.0'))
  })

  it('should correctly set the Liquidity address', async function () {
    // User1 tries to set the Liquidity address to zero address - should fail
    await expect(connect(feesContract, owner).setLiquidity(nullAddress)).to.be.reverted

    // User1 tries to set the Liquidity address to their own address - should fail
    await expect(connect(feesContract, user1).setLiquidity(user1.address)).to.be.reverted

    // Owner sets the Liquidity address - should succeed
    await connect(feesContract, owner).setLiquidity(user2.address)

    // Verify that the Liquidity address was correctly set
    expect(await feesContract.liquidity()).to.equal(user2.address)
  })

  it('should return the correct roles from getFeesRoles', async function () {
    const roles = await feesContract.getFeesRoles()

    // Check if the returned roles match the expected values
    expect(roles[0]).to.equal(0) // FeeRoles.StakeAccounts
    expect(roles[1]).to.equal(1) // FeeRoles.LockAccounts
    expect(roles[2]).to.equal(2) // FeeRoles.Pools
    expect(roles[3]).to.equal(3) // FeeRoles.Operators
    expect(roles[4]).to.equal(4) // FeeRoles.Oracles
    expect(roles[5]).to.equal(5) // FeeRoles.StakeTogether
    expect(roles[6]).to.equal(6) // FeeRoles.LiquidityProviders
    expect(roles[7]).to.equal(7) // FeeRoles.Sender
  })

  it('should correctly set the Fee Address', async function () {
    const role = 0 // FeeRoles.StakeAccounts
    const newAddress = user1.address

    // Owner sets the Fee Address for the specified role
    await connect(feesContract, owner).setFeeAddress(role, newAddress)

    // Verify that the Fee Address was correctly set
    expect(await feesContract.getFeeAddress(role)).to.equal(newAddress)
  })

  it('should correctly get the Fee Address', async function () {
    const role = 1 // FeeRoles.LockAccounts
    const newAddress = user2.address

    // Owner sets the Fee Address for the specified role
    await connect(feesContract, owner).setFeeAddress(role, newAddress)

    // Verify that the Fee Address can be retrieved correctly
    expect(await feesContract.getFeeAddress(role)).to.equal(newAddress)
  })

  it('should correctly get the Fee Addresses for all roles', async function () {
    // Set Fee Addresses for different roles
    await connect(feesContract, owner).setFeeAddress(0, user1.address) // FeeRoles.StakeAccounts
    await connect(feesContract, owner).setFeeAddress(1, user2.address) // FeeRoles.LockAccounts
    await connect(feesContract, owner).setFeeAddress(2, user3.address) // FeeRoles.Pools
    await connect(feesContract, owner).setFeeAddress(3, user4.address) // FeeRoles.Operators
    await connect(feesContract, owner).setFeeAddress(4, user5.address) // FeeRoles.Oracles
    await connect(feesContract, owner).setFeeAddress(5, user6.address) // FeeRoles.StakeTogether
    await connect(feesContract, owner).setFeeAddress(6, user7.address) // FeeRoles.LiquidityProviders
    await connect(feesContract, owner).setFeeAddress(7, user8.address) // FeeRoles.Sender

    // Get Fee Addresses for all roles
    const addresses = await feesContract.getFeeRolesAddresses()

    // Verify that the Fee Addresses are correct for each role
    expect(addresses[0]).to.equal(user1.address)
    expect(addresses[1]).to.equal(user2.address)
    expect(addresses[2]).to.equal(user3.address)
    expect(addresses[3]).to.equal(user4.address)
    expect(addresses[4]).to.equal(user5.address)
    expect(addresses[5]).to.equal(user6.address)
    expect(addresses[6]).to.equal(user7.address)
    expect(addresses[7]).to.equal(user8.address)
  })

  it('should revert if allocations array length is not 8', async function () {
    const feeType = 0 // FeeType.StakeEntry
    const value = ethers.parseEther('0.01')
    const mathType = 1 // FeeMathType.PERCENTAGE
    const allocations = [ethers.parseEther('0.1'), ethers.parseEther('0.1')]

    await expect(connect(feesContract, owner).setFee(feeType, value, mathType, allocations)).to.be
      .reverted
  })

  it('should revert if the sum of allocations is not 1 ether', async function () {
    const feeType = 0 // FeeType.StakeEntry
    const value = ethers.parseEther('0.01')
    const mathType = 1 // FeeMathType.PERCENTAGE
    const allocations = new Array(8).fill(ethers.parseEther('0.1'))

    await expect(connect(feesContract, owner).setFee(feeType, value, mathType, allocations)).to.be
      .reverted
  })

  it('should set the fee correctly if the user has admin role and inputs are valid', async function () {
    const feeType = 0 // FeeType.StakeEntry
    const value = ethers.parseEther('0.01')
    const mathType = 1 // FeeMathType.PERCENTAGE
    const allocations = new Array(8).fill(ethers.parseEther('0.125'))

    await connect(feesContract, owner).setFee(feeType, value, mathType, allocations)

    const [returnedFeeType, returnedValue, returnedMathType, returnedAllocations] =
      await feesContract.getFee(feeType)

    expect(returnedFeeType).to.equal(feeType)
    expect(returnedValue).to.equal(value)
    expect(returnedMathType).to.equal(mathType)
    for (let i = 0; i < returnedAllocations.length; i++) {
      expect(returnedAllocations[i]).to.equal(allocations[i])
    }
  })

  it('should revert if a user without admin role tries to set the fee', async function () {
    const feeType = 0 // FeeType.StakeEntry
    const value = ethers.parseEther('0.01')
    const mathType = 1 // FeeMathType.PERCENTAGE
    const allocations = new Array(8).fill(ethers.parseEther('0.125'))

    await expect(connect(feesContract, user1).setFee(feeType, value, mathType, allocations)).to.be
      .reverted
  })

  it('should set the fixed fee correctly if the user has admin role and inputs are valid', async function () {
    const feeType = 0 // FeeType.StakeEntry
    const value = ethers.parseEther('0.01') // This will be the fixed fee
    const mathType = 0 // FeeMathType.FIXED
    const allocations = new Array(8).fill(ethers.parseEther('0.125')) // The allocations still need to sum to 1 ether

    await connect(feesContract, owner).setFee(feeType, value, mathType, allocations)

    const [returnedFeeType, returnedValue, returnedMathType, returnedAllocations] =
      await feesContract.getFee(feeType)

    expect(returnedFeeType).to.equal(feeType)
    expect(returnedValue).to.equal(value)
    expect(returnedMathType).to.equal(mathType)
    for (let i = 0; i < returnedAllocations.length; i++) {
      expect(returnedAllocations[i]).to.equal(allocations[i])
    }
  })

  it('should correctly get all the fees', async function () {
    // We will set up 6 different fees for testing
    const feeCount = 6
    const fixedValue = ethers.parseEther('0.01') // This will be the fixed fee
    const percentageValue = ethers.parseEther('0.02') // This will be the percentage fee
    const fixedMathType = 0 // FeeMathType.FIXED
    const percentageMathType = 1 // FeeMathType.PERCENTAGE
    const allocations = new Array(8).fill(ethers.parseEther('0.125'))

    for (let i = 0; i < feeCount; i++) {
      if (i % 2 === 0) {
        // Set fixed fee for even indexed fees
        await connect(feesContract, owner).setFee(i, fixedValue, fixedMathType, allocations)
      } else {
        // Set percentage fee for odd indexed fees
        await connect(feesContract, owner).setFee(i, percentageValue, percentageMathType, allocations)
      }
    }

    const [feeTypes, feeValues, feeMathTypes, feeAllocations] = await feesContract.getFees()

    expect(feeTypes.length).to.equal(feeCount)
    expect(feeValues.length).to.equal(feeCount)
    expect(feeMathTypes.length).to.equal(feeCount)
    expect(feeAllocations.length).to.equal(feeCount)

    for (let i = 0; i < feeCount; i++) {
      expect(feeTypes[i]).to.equal(i)
      if (i % 2 === 0) {
        expect(feeValues[i]).to.equal(fixedValue)
        expect(feeMathTypes[i]).to.equal(fixedMathType)
      } else {
        expect(feeValues[i]).to.equal(percentageValue)
        expect(feeMathTypes[i]).to.equal(percentageMathType)
      }
      for (let j = 0; j < feeAllocations[i].length; j++) {
        expect(feeAllocations[i][j]).to.equal(allocations[j])
      }
    }
  })

  it('should set the max fee increase correctly if the user has admin role', async function () {
    const newMaxFeeIncrease = ethers.parseEther('0.1')

    await connect(feesContract, owner).setMaxFeeIncrease(newMaxFeeIncrease)

    expect(await feesContract.maxFeeIncrease()).to.equal(newMaxFeeIncrease)
    await expect(connect(feesContract, owner).setMaxFeeIncrease(newMaxFeeIncrease))
      .to.emit(feesContract, 'SetMaxFeeIncrease')
      .withArgs(newMaxFeeIncrease)
  })

  it('should not set the max fee increase if the user does not have admin role', async function () {
    const newMaxFeeIncrease = ethers.parseEther('0.1')

    await expect(connect(feesContract, user1).setMaxFeeIncrease(newMaxFeeIncrease)).to.be.reverted
  })
})
