import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { BytesLike } from 'ethers'
import { ethers, network, upgrades } from 'hardhat'
import { MockRouter__factory, Router, StakeTogether } from '../../typechain'
import connect from '../utils/connect'
import { routerFixture } from './Router.fixture'

dotenv.config()

describe('Router', function () {
  let router: Router
  let routerProxy: string
  let stakeTogether: StakeTogether
  let stakeTogetherProxy: string
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
  let ORACLE_REPORT_MANAGER_ROLE: string
  let ORACLE_SENTINEL_ROLE: string

  // Setting up the fixture before each test
  beforeEach(async function () {
    const fixture = await loadFixture(routerFixture)
    router = fixture.router
    routerProxy = fixture.routerProxy
    stakeTogether = fixture.stakeTogether
    stakeTogetherProxy = fixture.stakeTogetherProxy
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
    ORACLE_REPORT_MANAGER_ROLE = fixture.ORACLE_REPORT_MANAGER_ROLE
    ORACLE_SENTINEL_ROLE = fixture.ORACLE_SENTINEL_ROLE
  })

  describe('Upgrade', () => {
    // Test to check if pause and unpause functions work properly
    it('should pause and unpause the contract if the user has owner role', async function () {
      // Check if the contract is not paused at the beginning
      expect(await router.paused()).to.equal(false)

      // User without owner role tries to pause the contract - should fail
      await expect(connect(router, user1).pause()).to.reverted

      // The owner pauses the contract
      await connect(router, owner).pause()

      // Check if the contract is paused
      expect(await router.paused()).to.equal(true)

      // User without owner role tries to unpause the contract - should fail
      await expect(connect(router, user1).unpause()).to.reverted

      // The owner unpauses the contract
      await connect(router, owner).unpause()
      // Check if the contract is not paused
      expect(await router.paused()).to.equal(false)
    })

    it('should upgrade the contract if the user has upgrader role', async function () {
      expect(await router.version()).to.equal(1n)

      const MockRouter = new MockRouter__factory(user1)

      // A user without the UPGRADER_ROLE tries to upgrade the contract - should fail
      await expect(upgrades.upgradeProxy(routerProxy, MockRouter)).to.be.reverted

      const MockRouterOwner = new MockRouter__factory(owner)

      // The owner (who has the UPGRADER_ROLE) upgrades the contract - should succeed
      const upgradedContract = await upgrades.upgradeProxy(routerProxy, MockRouterOwner)

      // Upgrade version
      await upgradedContract.initializeV2()

      expect(await upgradedContract.version()).to.equal(2n)
    })

    it('should correctly set the StakeTogether address', async function () {
      // User1 tries to set the StakeTogether address to zero address - should fail
      await expect(connect(router, owner).setStakeTogether(nullAddress)).to.be.reverted

      // User1 tries to set the StakeTogether address to their own address - should fail
      await expect(connect(router, user1).setStakeTogether(user1.address)).to.be.reverted

      // Owner sets the StakeTogether address - should succeed
      await connect(router, owner).setStakeTogether(user1.address)

      // Verify that the StakeTogether address was correctly set
      expect(await router.stakeTogether()).to.equal(user1.address)
    })

    describe('Receive Ether', function () {
      it('should correctly receive Ether', async function () {
        const initBalance = await ethers.provider.getBalance(routerProxy)

        const tx = await user1.sendTransaction({
          to: routerProxy,
          value: ethers.parseEther('1.0'),
        })

        await tx.wait()

        const finalBalance = await ethers.provider.getBalance(routerProxy)
        expect(finalBalance).to.equal(initBalance + ethers.parseEther('1.0'))

        await expect(tx).to.emit(router, 'ReceiveEther').withArgs(ethers.parseEther('1.0'))
      })
    })

    describe('Set Configuration', function () {
      it('should allow owner to set configuration', async function () {
        const config = {
          bunkerMode: false,
          reportDelayBlocks: 600,
          minOracleQuorum: 5,
          oracleBlackListLimit: 3,
          reportFrequency: 1,
          oracleQuorum: 5,
        }

        // Set config by owner
        await connect(router, owner).setConfig(config)

        // Verify if the configuration was changed correctly
        const updatedConfig = await router.config()
        expect(updatedConfig.reportDelayBlocks).to.equal(config.reportDelayBlocks)
      })

      it('should not allow non-owner to set configuration', async function () {
        const config = {
          bunkerMode: false,
          reportDelayBlocks: 600,
          minOracleQuorum: 5,
          oracleBlackListLimit: 3,
          reportFrequency: 1,
          oracleQuorum: 5,
        }

        // Attempt to set config by non-owner should fail
        await expect(router.connect(user1).setConfig(config)).to.be.reverted
      })

      it('should enforce reportDelayBlocks to be at least 300', async function () {
        const config = {
          bunkerMode: false,
          reportDelayBlocks: 200,
          minOracleQuorum: 5,
          oracleBlackListLimit: 3,
          reportFrequency: 1,
          oracleQuorum: 5,
        }

        // Set config by owner
        await router.connect(owner).setConfig(config)

        // Verify if the configuration enforces the minimum value
        const updatedConfig = await router.config()
        expect(updatedConfig.reportDelayBlocks).to.equal(300)
      })
    })
  })

  describe('Report Oracle', async function () {
    beforeEach(async function () {
      await router.connect(owner).grantRole(ORACLE_SENTINEL_ROLE, owner.address)
      await router.connect(owner).addReportOracle(user2.address)
    })

    it('should return true oracle', async function () {
      const oracle = user2.address

      const isReportOracle = await router.isReportOracle(oracle)
      expect(isReportOracle).to.be.true
    })

    it('should return false blacklisted oracle', async function () {
      const oracleToBlacklist = user2.address
      // Adding the oracle to the blacklist with a value within the limit
      await router.connect(owner).blacklistReportOracle(user2.address)
      const isReportOracle = await router.isReportOracle(oracleToBlacklist)
      expect(isReportOracle).to.be.false
    })

    it('should revert when adding an already existing report oracle', async function () {
      const existingOracle = user2.address // The oracle added in the beforeEach block

      await expect(router.connect(owner).addReportOracle(existingOracle)).to.be.revertedWith(
        'REPORT_ORACLE_EXISTS',
      )
    })

    it('should return true for a blacklisted oracle in isReportOracleBlackListed', async function () {
      const oracleToBlacklist = user2.address
      // Adding the oracle to the blacklist with a value within the limit
      await router.connect(owner).blacklistReportOracle(user2.address)

      const isBlacklisted = await router.isReportOracleBlackListed(oracleToBlacklist)
      expect(isBlacklisted).to.be.true
    })

    it('should return false for a non-blacklisted oracle in isReportOracleBlackListed', async function () {
      const oracle = user2.address

      const isBlacklisted = await router.isReportOracleBlackListed(oracle)
      expect(isBlacklisted).to.be.false
    })

    it('should remove a report oracle when called by an oracle manager', async function () {
      const oracleToRemove = user2.address

      await router.connect(owner).removeReportOracle(oracleToRemove)

      const isReportOracle = await router.isReportOracle(oracleToRemove)
      expect(isReportOracle).to.be.false
    })

    it('should revert when called by a non-oracle manager', async function () {
      const oracleToRemove = user2.address

      await expect(router.connect(user1).removeReportOracle(oracleToRemove)).to.be.reverted
    })

    it('should revert when trying to remove a non-existing report oracle', async function () {
      const nonExistingOracle = user3.address

      await expect(router.connect(owner).removeReportOracle(nonExistingOracle)).to.be.revertedWith(
        'REPORT_ORACLE_NOT_EXISTS',
      )
    })
  })

  describe('_updateQuorum', function () {
    beforeEach(async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      await router.connect(owner).addReportOracle(user2.address)
      await router.connect(owner).addReportOracle(user3.address)
      await router.connect(owner).addReportOracle(user4.address)
      // Total active oracles: 3 (user2, user3, user4)
    })

    it('should update the quorum as expected min quorum', async function () {
      await router.connect(owner).removeReportOracle(user2.address)
      await router.connect(owner).removeReportOracle(user3.address)
      await router.connect(owner).removeReportOracle(user4.address)

      const currentQuorum = (await router.config()).oracleQuorum
      const minOracleQuorum = (await router.config()).minOracleQuorum

      expect(currentQuorum).to.equal(minOracleQuorum)
    })

    it('should update the quorum as expected when total reports increase', async function () {
      // Incrementing totalOracles by adding another oracle (user5), totalOracles becomes 4
      await router.connect(owner).addReportOracle(user5.address)

      await router.connect(owner).removeReportOracle(user2.address)

      const currentConfig = await router.config()
      const currentQuorum = currentConfig.oracleQuorum
      const expectedNewQuorum = Math.floor((4 * 3) / 5) // 60% of total active oracles (4)
      const minOracleQuorum = (await router.config()).minOracleQuorum

      // If the newQuorum is lower than minOracleQuorum, use minOracleQuorum instead
      const expectedQuorum = Math.max(expectedNewQuorum, Number(minOracleQuorum))

      expect(currentQuorum).to.equal(expectedQuorum)
    })

    it('should update the quorum as expected when adding and removing oracles', async function () {
      // Adding 5 more oracles (totalOracles becomes 8)
      await router.connect(owner).addReportOracle(user6.address)
      await router.connect(owner).addReportOracle(user7.address)
      await router.connect(owner).addReportOracle(user8.address)
      await router.connect(owner).addReportOracle(user1.address)
      await router.connect(owner).addReportOracle(owner.address)

      // Get the updated quorum after adding oracles
      const updatedQuorumAfterAdd = (await router.config()).oracleQuorum

      // Removing 3 oracles (totalOracles becomes 5)
      await router.connect(owner).removeReportOracle(user6.address)

      // Get the updated quorum after removing oracles
      const updatedQuorumAfterRemove = (await router.config()).oracleQuorum

      const currentConfig = await router.config()
      const expectedNewQuorum = Math.floor((5 * 3) / 5) // 60% of total active oracles (5)
      const minOracleQuorum = currentConfig.minOracleQuorum

      // If the newQuorum is lower than minOracleQuorum, use minOracleQuorum instead
      const expectedQuorum = Math.max(expectedNewQuorum, Number(minOracleQuorum))

      // Verify that the current quorum matches the expected quorum after adding oracles
      expect(updatedQuorumAfterAdd).to.equal(expectedQuorum)

      // Verify that the current quorum matches the expected quorum after removing oracles
      expect(updatedQuorumAfterRemove).to.equal(expectedQuorum)
    })

    it('should update the quorum to minimum threshold when total reports decrease below minimum', async function () {
      // Removing all oracles except one (user4), totalOracles becomes 1
      await router.connect(owner).removeReportOracle(user2.address)
      await router.connect(owner).removeReportOracle(user3.address)

      const currentQuorum = (await router.config()).oracleQuorum
      const expectedNewQuorum = (await router.config()).minOracleQuorum

      expect(currentQuorum).to.equal(expectedNewQuorum)
    })

    it('should update the quorum as expected when having only 1 oracle and min quorum is 1', async function () {
      await router.connect(owner).removeReportOracle(user2.address)
      await router.connect(owner).removeReportOracle(user3.address)
      await router.connect(owner).removeReportOracle(user4.address)

      const config = {
        bunkerMode: false,
        reportDelayBlocks: 600,
        minOracleQuorum: 1, // Set minOracleQuorum to 1 for this test
        oracleBlackListLimit: 3,
        reportFrequency: 1,
        oracleQuorum: 5,
      }

      // Set config by owner
      await connect(router, owner).setConfig(config)

      // Adding 1 oracle (totalOracles becomes 1)
      await router.connect(owner).addReportOracle(user1.address)

      // Get the updated quorum after adding the oracle
      const updatedQuorumAfterAdd = (await router.config()).oracleQuorum

      // Removing the oracle (totalOracles becomes 0)
      await router.connect(owner).removeReportOracle(user1.address)

      // Get the updated quorum after removing the oracle
      const updatedQuorumAfterRemove = (await router.config()).oracleQuorum

      const currentConfig = await router.config()
      const expectedNewQuorum = Math.floor((0 * 3) / 5) // 60% of total active oracles (0)
      const minOracleQuorum = currentConfig.minOracleQuorum

      // If the newQuorum is lower than minOracleQuorum, use minOracleQuorum instead
      const expectedQuorum = Math.max(expectedNewQuorum, Number(minOracleQuorum))

      // Verify that the current quorum matches the expected quorum after adding the oracle
      expect(updatedQuorumAfterAdd).to.equal(expectedQuorum)

      // Verify that the current quorum matches the expected quorum after removing the oracle
      expect(updatedQuorumAfterRemove).to.equal(expectedQuorum)
    })
  })

  describe('unBlacklistReportOracle', async function () {
    beforeEach(async function () {
      await router.connect(owner).grantRole(ORACLE_SENTINEL_ROLE, owner.address)
      await router.connect(owner).addReportOracle(user2.address)
      await router.connect(owner).blacklistReportOracle(user2.address)
    })

    it('should un-blacklist a report oracle when called by the owner', async function () {
      // Un-blacklist the oracle
      await router.connect(owner).unBlacklistReportOracle(user2.address)

      // Check if the oracle is un-blacklisted
      const isBlacklistedAfter = await router.isReportOracleBlackListed(user2.address)
      expect(isBlacklistedAfter).to.be.false
    })

    it('should revert when trying to un-blacklist a non-blacklisted oracle', async function () {
      // Un-blacklist the oracle first
      await router.connect(owner).unBlacklistReportOracle(user2.address)

      // Try to un-blacklist the oracle again (it's no longer blacklisted)
      await expect(router.connect(owner).unBlacklistReportOracle(user2.address)).to.be.revertedWith(
        'REPORT_ORACLE_NOT_BLACKLISTED',
      )
    })

    it('should revert when trying to un-blacklist a non-existing oracle', async function () {
      // Un-blacklist a non-existing oracle
      await expect(router.connect(owner).unBlacklistReportOracle(user3.address)).to.be.revertedWith(
        'REPORT_ORACLE_NOT_EXISTS',
      )
    })
  })

  describe('addSentinel', async function () {
    it('should add a sentinel when called by an admin', async function () {
      await router.connect(owner).addSentinel(user1.address)

      const hasSentinelRole = await router.hasRole(ORACLE_SENTINEL_ROLE, user1.address)
      expect(hasSentinelRole).to.be.true
    })

    it('should revert when trying to add an existing sentinel', async function () {
      // Add a sentinel first
      await router.connect(owner).addSentinel(user1.address)

      // Try to add the same sentinel again
      await expect(router.connect(owner).addSentinel(user1.address)).to.be.revertedWith('SENTINEL_EXISTS')
    })

    it('should revert when trying to add a sentinel by a non-admin', async function () {
      // Try to add a sentinel without ADMIN_ROLE
      await expect(router.connect(user1).addSentinel(user2.address)).to.be.reverted
    })

    describe('removeSentinel', async function () {
      beforeEach(async function () {
        // Grant ADMIN_ROLE to owner
        await router.connect(owner).grantRole(ADMIN_ROLE, owner.address)

        // Add a sentinel
        await router.connect(owner).addSentinel(user1.address)
      })

      it('should remove a sentinel when called by an admin', async function () {
        // Remove the sentinel
        await router.connect(owner).removeSentinel(user1.address)

        // Check if the sentinel no longer has the role
        const hasSentinelRole = await router.hasRole(ORACLE_SENTINEL_ROLE, user1.address)
        expect(hasSentinelRole).to.be.false
      })

      it('should revert when trying to remove a non-existing sentinel', async function () {
        // Try to remove a sentinel that was not added
        await expect(router.connect(owner).removeSentinel(user2.address)).to.be.revertedWith(
          'SENTINEL_NOT_EXISTS',
        )
      })

      it('should revert when trying to remove a sentinel by a non-admin', async function () {
        // Try to remove a sentinel without ADMIN_ROLE
        await expect(router.connect(user1).removeSentinel(user1.address)).to.be.reverted
      })
    })
  })

  describe('Report Submit', function () {
    type Report = {
      epoch: bigint
      merkleRoot: BytesLike
      profitAmount: bigint
      lossAmount: bigint
      withdrawAmount: bigint
      withdrawRefundAmount: bigint
      routerExtraAmount: bigint
      validatorsToRemove: BytesLike[]
    }

    let report: Report

    it('should revert if send by a non oracle', async function () {
      report = {
        epoch: 1n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        lossAmount: 500n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await expect(router.connect(user2).submitReport(report.epoch, report)).to.be.revertedWith(
        'ONLY_ACTIVE_ORACLE',
      )
    })

    it('should revert if block min quorum not achieved', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      await router.connect(owner).addReportOracle(user1.address)

      report = {
        epoch: 1n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        lossAmount: 500n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await expect(router.connect(user1).submitReport(report.epoch, report)).to.be.revertedWith(
        'MIN_ORACLE_QUORUM_NOT_REACHED',
      )
    })

    it('should revert if epoch less than last consensus', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      await router.connect(owner).addReportOracle(user1.address)
      await router.connect(owner).addReportOracle(user2.address)
      await router.connect(owner).addReportOracle(user3.address)
      await router.connect(owner).addReportOracle(user4.address)
      await router.connect(owner).addReportOracle(user5.address)

      const totalOracles = await router.totalOracles()

      const minOracleQuorum = (await router.config()).minOracleQuorum

      report = {
        epoch: 0n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        lossAmount: 500n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await expect(router.connect(user1).submitReport(report.epoch, report)).to.be.revertedWith(
        'EPOCH_NOT_GREATER_THAN_LAST_CONSENSUS',
      )
    })

    it('should execute a report', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      await router.connect(owner).addReportOracle(user1.address)
      await router.connect(owner).addReportOracle(user2.address)
      await router.connect(owner).addReportOracle(user3.address)
      await router.connect(owner).addReportOracle(user4.address)
      await router.connect(owner).addReportOracle(user5.address)

      const totalOracles = await router.totalOracles()

      const minOracleQuorum = (await router.config()).minOracleQuorum

      report = {
        epoch: 1n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        lossAmount: 500n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await expect(router.connect(user1).submitReport(report.epoch, report)).to.be.not.reverted
    })

    it('should revert oracle already voted', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      const oracles = [user1, user2, user3, user4, user5, user6]

      for (const oracle of oracles) {
        await router.connect(owner).addReportOracle(oracle.address)
      }

      report = {
        epoch: 2n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        lossAmount: 500n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      const tx1 = await router.connect(user1).submitReport(report.epoch, report)
      await expect(tx1).to.emit(router, 'SubmitReport')
      await expect(tx1).to.emit(router, 'ConsensusNotReached')

      await expect(router.connect(user1).submitReport(report.epoch, report)).to.be.revertedWith(
        'ORACLE_ALREADY_VOTED',
      )
    })

    it('should approve consensus', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      const oracles = [user1, user2, user3, user4, user5, user6]

      for (const oracle of oracles) {
        await router.connect(owner).addReportOracle(oracle.address)
      }

      report = {
        epoch: 2n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        lossAmount: 500n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      const tx1 = await router.connect(user1).submitReport(report.epoch, report)
      await expect(tx1).to.emit(router, 'SubmitReport')
      await expect(tx1).to.emit(router, 'ConsensusNotReached')

      const tx2 = await router.connect(user2).submitReport(report.epoch, report)
      await expect(tx2).to.emit(router, 'SubmitReport')
      await expect(tx2).to.emit(router, 'ConsensusNotReached')

      const tx3 = await router.connect(user3).submitReport(report.epoch, report)
      await expect(tx3).to.emit(router, 'SubmitReport')
      await expect(tx3).to.emit(router, 'ConsensusNotReached')

      const tx4 = await router.connect(user4).submitReport(report.epoch, report)
      await expect(tx4).to.emit(router, 'SubmitReport')
      await expect(tx4).to.emit(router, 'ConsensusNotReached')

      const tx5 = await router.connect(user5).submitReport(report.epoch, report)
      await expect(tx5).to.emit(router, 'SubmitReport')
      await expect(tx5).to.emit(router, 'ConsensusApprove')
    })

    it('should approve consensus', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      const oracles = [user1, user2, user3, user4, user5, user6]

      for (const oracle of oracles) {
        await router.connect(owner).addReportOracle(oracle.address)
      }

      report = {
        epoch: 2n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        lossAmount: 500n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      const tx1 = await router.connect(user1).submitReport(report.epoch, report)
      await expect(tx1).to.emit(router, 'SubmitReport')
      await expect(tx1).to.emit(router, 'ConsensusNotReached')

      const tx2 = await router.connect(user2).submitReport(report.epoch, report)
      await expect(tx2).to.emit(router, 'SubmitReport')
      await expect(tx2).to.emit(router, 'ConsensusNotReached')

      const tx3 = await router.connect(user3).submitReport(report.epoch, report)
      await expect(tx3).to.emit(router, 'SubmitReport')
      await expect(tx3).to.emit(router, 'ConsensusNotReached')

      const tx4 = await router.connect(user4).submitReport(report.epoch, report)
      await expect(tx4).to.emit(router, 'SubmitReport')
      await expect(tx4).to.emit(router, 'ConsensusNotReached')

      const tx5 = await router.connect(user5).submitReport(report.epoch, report)
      await expect(tx5).to.emit(router, 'SubmitReport')
      await expect(tx5).to.emit(router, 'ConsensusApprove')
    })

    it('should reach consensus and fail if execute early', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      const oracles = [user1, user2, user3, user4, user5]

      for (const oracle of oracles) {
        await router.connect(owner).addReportOracle(oracle.address)
      }

      report = {
        epoch: 2n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        lossAmount: 0n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      for (const oracle of oracles) {
        await router.connect(oracle).submitReport(report.epoch, report)
      }

      const delayBlocks = (await router.config()).reportDelayBlocks - 100n

      for (let i = 0; i < delayBlocks; i++) {
        await network.provider.send('evm_mine')
      }

      await expect(router.connect(user1).executeReport(report)).to.be.revertedWith('TOO_EARLY_TO_EXECUTE')
    })

    it('should fail because of eth', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      const oracles = [user1, user2, user3, user4, user5]

      for (const oracle of oracles) {
        await router.connect(owner).addReportOracle(oracle.address)
      }

      report = {
        epoch: 2n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        lossAmount: 0n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      for (const oracle of oracles) {
        await router.connect(oracle).submitReport(report.epoch, report)
      }

      const delayBlocks = (await router.config()).reportDelayBlocks

      for (let i = 0; i < delayBlocks; i++) {
        await network.provider.send('evm_mine')
      }

      await expect(router.connect(user1).executeReport(report)).to.revertedWith(
        'NOT_ENOUGH_BEACON_BALANCE',
      )
    })

    it('should reach consensus and execute the report', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      const oracles = [user1, user2, user3, user4, user5]

      for (const oracle of oracles) {
        await router.connect(owner).addReportOracle(oracle.address)
      }

      report = {
        epoch: 2n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        lossAmount: 0n,
        withdrawAmount: 100n,
        withdrawRefundAmount: 0n,
        routerExtraAmount: 55n,
        validatorsToRemove: [],
      }

      for (const oracle of oracles) {
        await router.connect(oracle).submitReport(report.epoch, report)
      }

      const delayBlocks = (await router.config()).reportDelayBlocks

      for (let i = 0; i < delayBlocks; i++) {
        await network.provider.send('evm_mine')
      }

      await owner.sendTransaction({ to: routerProxy, value: ethers.parseEther('1') })

      const executeTx = await router.connect(user1).executeReport(report)
      await expect(executeTx).to.emit(router, 'ExecuteReport')
    })

    it('should be interrupted by revoked consensus', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      await router.connect(owner).grantRole(ORACLE_SENTINEL_ROLE, owner.address)
      const oracles = [user1, user2, user3, user4, user5]

      for (const oracle of oracles) {
        await router.connect(owner).addReportOracle(oracle.address)
      }

      const report = {
        epoch: 2n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        lossAmount: 0n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      for (const oracle of oracles) {
        await router.connect(oracle).submitReport(report.epoch, report)
      }

      const _hash = await router.getReportHash(report)

      await router.connect(owner).revokeConsensusReport(report.epoch, _hash)

      await expect(router.connect(user1).executeReport(report)).to.be.revertedWith('REVOKED_REPORT')
    })
  })

  describe('Set Consensus', () => {
    it('should set the last consensus epoch', async function () {
      const newEpoch = 42

      await router.connect(owner).grantRole(ADMIN_ROLE, owner.address)

      await expect(router.connect(owner).setLastConsensusEpoch(newEpoch))
        .to.emit(router, 'SetLastConsensusEpoch')
        .withArgs(newEpoch)

      expect(await router.lastConsensusEpoch()).to.equal(newEpoch)
    })

    it('should revert if called by non-admin', async function () {
      const newEpoch = 42

      await expect(router.connect(user1).setLastConsensusEpoch(newEpoch)).to.be.reverted
    })
  })
})
