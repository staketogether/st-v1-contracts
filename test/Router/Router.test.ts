import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { BytesLike } from 'ethers'
import { ethers, network, upgrades } from 'hardhat'
import { Airdrop, MockRouter__factory, Router, StakeTogether, Withdrawals } from '../../typechain'
import connect from '../utils/connect'
import { routerFixture } from './Router.fixture'

dotenv.config()

async function advanceBlocks(blocks: number) {
  for (let i = 0; i < blocks; i++) {
    await ethers.provider.send('evm_mine')
  }
}

describe('Router', function () {
  let router: Router
  let routerProxy: string
  let stakeTogether: StakeTogether
  let stakeTogetherProxy: string
  let airdrop: Airdrop
  let airdropProxy: string
  let withdrawals: Withdrawals
  let withdrawalsProxy: string
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
  let VALIDATOR_ORACLE_MANAGER_ROLE: string

  // Setting up the fixture before each test
  beforeEach(async function () {
    const fixture = await loadFixture(routerFixture)
    router = fixture.router
    routerProxy = fixture.routerProxy
    stakeTogether = fixture.stakeTogether
    stakeTogetherProxy = fixture.stakeTogetherProxy
    airdrop = fixture.airdrop
    airdropProxy = fixture.airdropProxy
    withdrawals = fixture.withdrawals
    withdrawalsProxy = fixture.withdrawalsProxy
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
    VALIDATOR_ORACLE_MANAGER_ROLE = fixture.VALIDATOR_ORACLE_MANAGER_ROLE
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
          reportDelayBlock: 300,

          oracleBlackListLimit: 3,
          reportFrequency: 1000,
          oracleQuorum: 5,
        }

        // Set config by owner
        await connect(router, owner).setConfig(config)

        // Verify if the configuration was changed correctly
        const updatedConfig = await router.config()
        expect(updatedConfig.reportDelayBlock).to.equal(config.reportDelayBlock)
      })

      it('should not allow non-owner to set configuration', async function () {
        const config = {
          bunkerMode: false,
          reportDelayBlock: 60,

          oracleBlackListLimit: 3,
          reportFrequency: 1000,
          oracleQuorum: 5,
        }

        // Attempt to set config by non-owner should fail
        await expect(router.connect(user1).setConfig(config)).to.be.reverted
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
      profitShares: bigint
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
        profitShares: 100n,
        lossAmount: 500n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await expect(router.connect(user2).submitReport(report)).to.be.revertedWith('ONLY_ACTIVE_ORACLE')
    })

    it('should revert if block min quorum not achieved', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      await router.connect(owner).addReportOracle(user1.address)
      await router.connect(owner).addReportOracle(user2.address)
      await router.connect(owner).addReportOracle(user3.address)
      await router.connect(owner).addReportOracle(user4.address)
      await router.connect(owner).addReportOracle(user5.address)

      report = {
        epoch: 1n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        profitShares: 100n,
        lossAmount: 500n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await advanceBlocks(1000)

      await expect(router.connect(user1).submitReport(report)).to.be.revertedWith(
        'EPOCH_SHOULD_BE_GREATER',
      )
    })

    it('should revert if epoch less than last consensus', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      await router.connect(owner).addReportOracle(user1.address)
      await router.connect(owner).addReportOracle(user2.address)
      await router.connect(owner).addReportOracle(user3.address)
      await router.connect(owner).addReportOracle(user4.address)
      await router.connect(owner).addReportOracle(user5.address)

      report = {
        epoch: 1n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        profitShares: 100n,
        lossAmount: 500n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await advanceBlocks(1000)

      await expect(router.connect(user1).submitReport(report)).to.be.revertedWith(
        'EPOCH_SHOULD_BE_GREATER',
      )
    })

    it('should execute a report', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      await router.connect(owner).addReportOracle(user1.address)
      await router.connect(owner).addReportOracle(user2.address)
      await router.connect(owner).addReportOracle(user3.address)
      await router.connect(owner).addReportOracle(user4.address)
      await router.connect(owner).addReportOracle(user5.address)

      report = {
        epoch: 2n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        profitShares: 100n,
        lossAmount: 0n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await advanceBlocks(1000)

      await expect(router.connect(user1).submitReport(report)).to.be.not.reverted
    })

    it('should revert oracle already voted on epoch', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      const oracles = [user1, user2, user3, user4, user5, user6]

      for (const oracle of oracles) {
        await router.connect(owner).addReportOracle(oracle.address)
      }

      report = {
        epoch: 2n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        profitShares: 100n,
        lossAmount: 0n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await advanceBlocks(1000)

      const tx1 = await router.connect(user1).submitReport(report)
      await expect(tx1).to.emit(router, 'SubmitReport')

      await expect(router.connect(user1).submitReport(report)).to.be.revertedWith(
        'ORACLE_ALREADY_REPORTED',
      )
    })

    it('should revert oracle already voted on nextBlock report', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      const oracles = [user1, user2, user3, user4, user5, user6]

      for (const oracle of oracles) {
        await router.connect(owner).addReportOracle(oracle.address)
      }

      report = {
        epoch: 2n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        profitShares: 100n,
        lossAmount: 0n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await advanceBlocks(1000)

      const tx1 = await router.connect(user1).submitReport(report)
      await expect(tx1).to.emit(router, 'SubmitReport')

      report = {
        epoch: 4n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        profitShares: 100n,
        lossAmount: 500n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await expect(router.connect(user1).submitReport(report)).to.be.revertedWith(
        'ORACLE_ALREADY_REPORTED',
      )

      await advanceBlocks(500)

      await expect(router.connect(user1).submitReport(report)).to.be.revertedWith(
        'ORACLE_ALREADY_REPORTED',
      )

      await advanceBlocks(500)

      await expect(router.connect(user1).submitReport(report)).to.be.revertedWith(
        'ORACLE_ALREADY_REPORTED',
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
        profitAmount: 0n,
        profitShares: 0n,
        lossAmount: 500n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await advanceBlocks(1000)

      const tx1 = await router.connect(user1).submitReport(report)
      await expect(tx1).to.emit(router, 'SubmitReport')

      const tx2 = await router.connect(user2).submitReport(report)
      await expect(tx2).to.emit(router, 'SubmitReport')

      const tx3 = await router.connect(user3).submitReport(report)
      await expect(tx3).to.emit(router, 'SubmitReport')
      await expect(tx3).to.not.emit(router, 'ConsensusFail')

      const tx4 = await router.connect(user4).submitReport(report)
      await expect(tx4).to.not.emit(router, 'ConsensusFail')
      await expect(tx4).to.emit(router, 'SubmitReport')

      const tx5 = await router.connect(user5).submitReport(report)
      await expect(tx5).to.emit(router, 'SubmitReport')

      const tempReport = {
        epoch: 3n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        profitShares: 100n,
        lossAmount: 500n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await expect(router.connect(user1).submitReport(tempReport)).to.be.revertedWith(
        'ORACLE_ALREADY_REPORTED',
      )

      const currentBlockReport = await router.reportBlock()

      await expect(router.connect(user1).executeReport(report)).to.be.revertedWith('TOO_EARLY_TO_EXECUTE')

      expect(currentBlockReport).to.equal(49n)
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
        profitShares: 100n,
        lossAmount: 0n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await advanceBlocks(1000)

      for (const oracle of oracles) {
        await router.connect(oracle).submitReport(report)
      }

      const delayBlocks = (await router.config()).reportDelayBlock - 100n

      for (let i = 0; i < delayBlocks; i++) {
        await network.provider.send('evm_mine')
      }

      await expect(router.connect(user1).executeReport(report)).to.be.revertedWith('TOO_EARLY_TO_EXECUTE')
    })

    it('should skip if consensus not achieved', async function () {
      const config = {
        bunkerMode: false,
        reportDelayBlock: 300,

        oracleBlackListLimit: 3,
        reportFrequency: 1000,
        oracleQuorum: 5,
      }

      // Set config by owner
      await connect(router, owner).setConfig(config)

      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      const oracles = [user1, user2, user3, user4, user5, user6]

      for (const oracle of oracles) {
        await router.connect(owner).addReportOracle(oracle.address)
      }

      const currentBlockReport = await router.reportBlock()
      expect(currentBlockReport).to.equal(49n)

      report = {
        epoch: 2n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        profitShares: 100n,
        lossAmount: 0n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await advanceBlocks(1100)

      await router.connect(user1).submitReport(report)
      await router.connect(user2).submitReport(report)
      await router.connect(user3).submitReport(report)

      report = {
        epoch: 2n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 10010n,
        profitShares: 100n,
        lossAmount: 0n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      const failTx = await router.connect(user4).submitReport(report)
      await failTx.wait()

      await expect(failTx).to.emit(router, 'ConsensusFail')

      await expect(router.connect(user5).submitReport(report)).to.be.revertedWith(
        'BLOCK_NUMBER_NOT_REACHED',
      )

      await advanceBlocks(1000)

      await router.connect(user1).submitReport(report)
      await router.connect(user2).submitReport(report)
      await router.connect(user3).submitReport(report)
      await router.connect(user4).submitReport(report)
      const txSuccess = await router.connect(user5).submitReport(report)
      await txSuccess.wait()

      expect(txSuccess).to.emit(router, 'ConsensusApproved')
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
        profitShares: 100n,
        lossAmount: 0n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await advanceBlocks(1000)

      for (const oracle of oracles) {
        await router.connect(oracle).submitReport(report)
      }

      await advanceBlocks(300)

      await expect(router.connect(user1).executeReport(report)).to.revertedWith(
        'NOT_ENOUGH_BEACON_BALANCE',
      )
    })

    it('should be interrupted by revoked consensus', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      await router.connect(owner).grantRole(ORACLE_SENTINEL_ROLE, owner.address)
      const oracles = [user1, user2, user3, user4, user5]

      const reportBlock = await router.reportBlock()

      for (const oracle of oracles) {
        await router.connect(owner).addReportOracle(oracle.address)
      }

      const report = {
        epoch: 2n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        profitShares: 100n,
        lossAmount: 0n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      await advanceBlocks(1000)

      for (const oracle of oracles) {
        await router.connect(oracle).submitReport(report)
      }

      const tx = await router.connect(owner).revokeConsensusReport(reportBlock)
      await tx.wait()
      expect(tx).to.emit(router, 'RevokeConsensusReport')

      await expect(router.connect(user1).executeReport(report)).to.be.revertedWith('NOT_ACTIVE_CONSENSUS')

      await advanceBlocks(1000)

      const report2 = {
        epoch: 3n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 0n,
        profitShares: 0n,
        lossAmount: 0n,
        withdrawAmount: 0n,
        withdrawRefundAmount: 0n,
        routerExtraAmount: 0n,
        validatorsToRemove: [],
      }

      await router.connect(user1).submitReport(report2)
      await router.connect(user2).submitReport(report2)
      await router.connect(user3).submitReport(report2)
      await router.connect(user4).submitReport(report2)
      await router.connect(user5).submitReport(report2)

      await advanceBlocks(300)

      const tx2 = await router.connect(user1).executeReport(report2)
      await tx.wait()

      expect(tx2).to.emit(router, 'ExecuteReport')
    })

    it('should reach consensus and execute five reports sequentially', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      const oracles = [user1, user2, user3, user4, user5]

      for (const oracle of oracles) {
        await router.connect(owner).addReportOracle(oracle.address)
      }

      const reports = [
        {
          epoch: 2n,
          merkleRoot: ethers.hexlify(new Uint8Array(32)),
          profitAmount: 1000n,
          profitShares: 100n,
          lossAmount: 0n,
          withdrawAmount: 0n,
          withdrawRefundAmount: 0n,
          routerExtraAmount: 55n,
          validatorsToRemove: [],
        },
        {
          epoch: 3n,
          merkleRoot: ethers.hexlify(new Uint8Array(32)),
          profitAmount: 1500n,
          profitShares: 100n,
          lossAmount: 0n,
          withdrawAmount: 0n,
          withdrawRefundAmount: 0n,
          routerExtraAmount: 30n,
          validatorsToRemove: [],
        },
        {
          epoch: 4n,
          merkleRoot: ethers.hexlify(new Uint8Array(32)),
          profitAmount: 800n,
          profitShares: 100n,
          lossAmount: 0n,
          withdrawAmount: 0n,
          withdrawRefundAmount: 0n,
          routerExtraAmount: 40n,
          validatorsToRemove: [],
        },
        {
          epoch: 5n,
          merkleRoot: ethers.hexlify(new Uint8Array(32)),
          profitAmount: 800n,
          profitShares: 100n,
          lossAmount: 0n,
          withdrawAmount: 0n,
          withdrawRefundAmount: 0n,
          routerExtraAmount: 40n,
          validatorsToRemove: [],
        },
        {
          epoch: 6n,
          merkleRoot: ethers.hexlify(new Uint8Array(32)),
          profitAmount: 800n,
          profitShares: 100n,
          lossAmount: 0n,
          withdrawAmount: 0n,
          withdrawRefundAmount: 0n,
          routerExtraAmount: 40n,
          validatorsToRemove: [],
        },
      ]

      for (const report of reports) {
        await advanceBlocks(900)

        for (const oracle of oracles) {
          await router.connect(oracle).submitReport(report)
        }

        await advanceBlocks(300)

        await owner.sendTransaction({ to: routerProxy, value: ethers.parseEther('1') })

        const executeTx = await router.connect(user1).executeReport(report)
        await expect(executeTx).to.emit(router, 'ExecuteReport')
      }
    })

    it('should emit ValidatorsToRemove event if 100 validators are to be removed', async function () {
      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      const oracles = [user1, user2, user3, user4, user5]
      const validatorsToRemove = Array.from({ length: 100 }, (_, i) => ethers.hexlify(new Uint8Array(32)))

      for (const oracle of oracles) {
        await router.connect(owner).addReportOracle(oracle.address)
      }

      const report = {
        epoch: 2n,
        merkleRoot: ethers.hexlify(new Uint8Array(32)),
        profitAmount: 1000n,
        profitShares: 100n,
        lossAmount: 0n,
        withdrawAmount: 0n,
        withdrawRefundAmount: 0n,
        routerExtraAmount: 55n,
        validatorsToRemove: validatorsToRemove,
      }

      await advanceBlocks(1000)

      for (const oracle of oracles) {
        await router.connect(oracle).submitReport(report)
      }

      const delayBlocks = (await router.config()).reportDelayBlock

      for (let i = 0; i < delayBlocks; i++) {
        await network.provider.send('evm_mine')
      }

      await owner.sendTransaction({ to: routerProxy, value: ethers.parseEther('1') })

      const reportBlock = await router.reportBlock()

      const executeTx = await router.connect(user1).executeReport(report)
      await expect(executeTx)
        .to.emit(router, 'ValidatorsToRemove')
        .withArgs(reportBlock, validatorsToRemove)
    })

    it('should reach consensus and execute the report, adding Merkle root', async function () {
      const publicKey =
        '0x954c931791b73c03c5e699eb8da1222b221b098f6038282ff7e32a4382d9e683f0335be39b974302e42462aee077cf93'
      const signature =
        '0x967d1b93d655752e303b43905ac92321c048823e078cadcfee50eb35ede0beae1501a382a7c599d6e9b8a6fd177ab3d711c44b2115ac90ea1dc7accda6d0352093eaa5f2bc9f1271e1725b43b3a74476b9e749fc011de4a63d9e72cf033978ed'
      const depositDataRoot = '0x4ef3924ceb993cbc51320f44cb28ffb50071deefd455ce61feabb7b6b2f1d0e8'

      const oracle = user1
      await stakeTogether.connect(owner).grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, owner)
      await stakeTogether.connect(owner).addValidatorOracle(oracle)

      // Sending sufficient funds for pool size and validator size
      await owner.sendTransaction({ to: stakeTogetherProxy, value: ethers.parseEther('30.1') })

      // Deposit
      const depositAmount = ethers.parseEther('2')
      const poolAddress = user3.address
      const referral = user4.address
      await stakeTogether.connect(owner).addPool(poolAddress, true)

      const delegations = [{ pool: poolAddress, percentage: ethers.parseEther('1') }]

      const tx1 = await stakeTogether
        .connect(user1)
        .depositPool(delegations, referral, { value: depositAmount })
      await tx1.wait()

      // Creating the validator
      const tx = await stakeTogether
        .connect(oracle)
        .createValidator(publicKey, signature, depositDataRoot)

      const withdrawAmount = ethers.parseEther('1.5')

      await stakeTogether.connect(user1).withdrawValidator(withdrawAmount, delegations)

      // Router

      await router.connect(owner).grantRole(ORACLE_REPORT_MANAGER_ROLE, owner.address)
      const oracles = [user1, user2, user3, user4, user5]

      const merkleRoot = ethers.keccak256('0x1234')

      for (const oracle of oracles) {
        await router.connect(owner).addReportOracle(oracle.address)
      }

      await advanceBlocks(1000)

      report = {
        epoch: 2n,
        merkleRoot: merkleRoot,
        profitAmount: 1000n,
        profitShares: 100n,
        lossAmount: 0n,
        withdrawAmount: 100n,
        withdrawRefundAmount: 0n,
        routerExtraAmount: 55n,
        validatorsToRemove: [],
      }

      for (const oracle of oracles) {
        await router.connect(oracle).submitReport(report)
      }

      const delayBlocks = (await router.config()).reportDelayBlock

      for (let i = 0; i < delayBlocks; i++) {
        await network.provider.send('evm_mine')
      }

      await owner.sendTransaction({ to: routerProxy, value: ethers.parseEther('1') })

      const stakeTogetherFee = await stakeTogether.getFeeAddress(2)

      const stPreBalance = await ethers.provider.getBalance(stakeTogetherFee)

      const executeTx = await router.connect(user1).executeReport(report)

      const stPosBalance = await ethers.provider.getBalance(stakeTogetherFee)

      await expect(executeTx).to.emit(airdrop, 'AddMerkleRoot')
      await expect(executeTx).to.emit(stakeTogether, 'MintFeeShares')
      await expect(executeTx).to.emit(withdrawals, 'ReceiveWithdrawEther')
      expect(stPosBalance).to.equal(stPreBalance + report.routerExtraAmount)
    })

    it('should return the correct hash for the report', async function () {
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
        profitShares: 100n,
        lossAmount: 0n,
        withdrawAmount: 200n,
        withdrawRefundAmount: 100n,
        routerExtraAmount: 300n,
        validatorsToRemove: [],
      }

      const contractHash = await router.getReportHash(report)

      expect(contractHash).to.be.equal(
        '0x9ba292af0dcc0bee66d17d06254b1ffcdd5175dca3034f0bdd30890f8fca3c11',
      )
    })
  })

  describe('Set Consensus', () => {
    it('should set the last executed epoch', async function () {
      const newEpoch = 42

      await router.connect(owner).grantRole(ADMIN_ROLE, owner.address)

      await expect(router.connect(owner).setLastExecutedEpoch(newEpoch))
        .to.emit(router, 'SetLastExecutedEpoch')
        .withArgs(newEpoch)

      expect(await router.lastExecutedEpoch()).to.equal(newEpoch)
    })

    it('should revert if called by non-admin', async function () {
      const newEpoch = 42

      await expect(router.connect(user1).setLastExecutedEpoch(newEpoch)).to.be.reverted
    })
  })
})
