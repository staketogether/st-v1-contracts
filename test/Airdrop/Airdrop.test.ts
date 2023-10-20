import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { StandardMerkleTree } from '@openzeppelin/merkle-tree'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers, upgrades } from 'hardhat'
import {
  Airdrop,
  Airdrop__factory,
  MockAirdrop__factory,
  MockRouter,
  MockStakeTogether,
} from '../../typechain'
import connect from '../utils/connect'
import { airdropFixture } from './Airdrop.fixture'

dotenv.config()

describe('Airdrop', function () {
  let airdrop: Airdrop
  let airdropProxy: string
  let mockStakeTogether: MockStakeTogether
  let mockStakeTogetherProxy: string
  let mockRouter: MockRouter
  let mockRouterProxy: string
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
    const fixture = await loadFixture(airdropFixture)
    airdrop = fixture.airdrop
    airdropProxy = fixture.airdropProxy
    mockStakeTogether = fixture.mockStakeTogether
    mockStakeTogetherProxy = fixture.mockStakeTogetherProxy

    mockRouter = fixture.mockRouter as unknown as MockRouter
    mockRouterProxy = fixture.mockRouterProxy
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

  describe('Upgrade', () => {
    // Test to check if pause and unpause functions work properly
    it('should pause and unpause the contract if the user has admin role', async function () {
      // Check if the contract is not paused at the beginning
      expect(await airdrop.paused()).to.equal(false)

      // User without admin role tries to pause the contract - should fail
      await expect(connect(airdrop, user1).pause()).to.reverted

      // The owner pauses the contract
      await connect(airdrop, owner).pause()

      // Check if the contract is paused
      expect(await airdrop.paused()).to.equal(true)

      // User without admin role tries to unpause the contract - should fail
      await expect(connect(airdrop, user1).unpause()).to.reverted

      // The owner unpauses the contract
      await connect(airdrop, owner).unpause()
      // Check if the contract is not paused
      expect(await airdrop.paused()).to.equal(false)
    })

    it('should upgrade the contract if the user has upgrader role', async function () {
      expect(await airdrop.version()).to.equal(1n)

      const MockAirdrop = new MockAirdrop__factory(user1)

      // A user without the UPGRADER_ROLE tries to upgrade the contract - should fail
      await expect(upgrades.upgradeProxy(airdropProxy, MockAirdrop)).to.be.reverted

      const MockAirdropOwner = new MockAirdrop__factory(owner)

      // The owner (who has the UPGRADER_ROLE) upgrades the contract - should succeed
      const upgradedContract = await upgrades.upgradeProxy(airdropProxy, MockAirdropOwner)

      // Upgrade version
      await upgradedContract.initializeV2()

      expect(await upgradedContract.version()).to.equal(2n)
    })
  })

  describe('Set Config', function () {
    it('should correctly set the StakeTogether address', async function () {
      // User1 tries to set the StakeTogether address to zero address - should fail
      await expect(connect(airdrop, owner).setStakeTogether(nullAddress)).to.be.revertedWithCustomError(
        airdrop,
        'StakeTogetherAlreadySet',
      )

      // Verify that the StakeTogether address was correctly set
      expect(await airdrop.stakeTogether()).to.equal(await mockStakeTogether.getAddress())
    })

    it('should correctly set the Router address', async function () {
      await expect(connect(airdrop, owner).setRouter(nullAddress)).to.be.revertedWithCustomError(
        airdrop,
        'RouterAlreadySet',
      )

      expect(await airdrop.router()).to.equal(await mockRouter.getAddress())
    })
  })

  describe('Receive Ether', function () {
    it('should correctly receive Ether', async function () {
      const initBalance = await ethers.provider.getBalance(airdropProxy)

      const tx = await user1.sendTransaction({
        to: airdropProxy,
        value: ethers.parseEther('1.0'),
      })

      await tx.wait()

      const finalBalance = await ethers.provider.getBalance(airdropProxy)
      expect(finalBalance).to.equal(initBalance + ethers.parseEther('1.0'))

      await expect(tx).to.emit(airdrop, 'ReceiveEther').withArgs(ethers.parseEther('1.0'))
    })
  })

  describe('transferExtraAmount', function () {
    it('should transfer the extra Ether to StakeTogether fee address', async function () {
      await mockStakeTogether.setFeeAddress(2, user5.address)

      const stFeeAddress = await mockStakeTogether.getFeeAddress(2)

      const stBalanceBefore = await ethers.provider.getBalance(stFeeAddress)

      await owner.sendTransaction({
        to: airdropProxy,
        value: ethers.parseEther('20.0'),
      })

      await airdrop.connect(owner).transferExtraAmount()

      const airdropBalanceAfter = 0n
      const airdropBalance = await ethers.provider.getBalance(airdrop)

      const extraAmount = ethers.parseEther('20.0')
      const stBalanceAfter = await ethers.provider.getBalance(stFeeAddress)

      expect(airdropBalanceAfter).to.equal(airdropBalance)
      expect(stBalanceAfter).to.equal(stBalanceBefore + extraAmount)
    })

    it('should revert if there is no extra Ether in contract balance', async function () {
      await mockStakeTogether.setFeeAddress(2, user5.address)
      await expect(airdrop.connect(owner).transferExtraAmount()).to.be.revertedWithCustomError(
        airdrop,
        'NoExtraAmountAvailable',
      )
    })
  })

  describe('addMerkleRoot', function () {
    it('should add a Merkle root if called by the router address', async function () {
      const AirdropFactory = new Airdrop__factory().connect(owner)
      const airdrop2 = await upgrades.deployProxy(AirdropFactory)
      await airdrop2.waitForDeployment()
      const airdropContract2 = airdrop2 as unknown as Airdrop
      const AIR_ADMIN_ROLE = await airdropContract2.ADMIN_ROLE()
      await airdropContract2.connect(owner).grantRole(AIR_ADMIN_ROLE, owner)
      await airdropContract2.connect(owner).setStakeTogether(mockStakeTogetherProxy)
      await airdropContract2.connect(owner).setRouter(owner.address)

      const reportBlock = await mockRouter.reportBlock()
      const merkleRoot = ethers.keccak256('0x1234')

      await expect(connect(airdropContract2, owner).addMerkleRoot(reportBlock, merkleRoot))
        .to.emit(airdropContract2, 'AddMerkleRoot')
        .withArgs(reportBlock, merkleRoot)

      expect(await airdrop2.merkleRoots(reportBlock)).to.equal(merkleRoot)
    })

    it('should fail if called by an address other than the router', async function () {
      const reportBlock = await mockRouter.reportBlock()
      const merkleRoot = ethers.keccak256('0x1234')

      await expect(
        connect(airdrop, user1).addMerkleRoot(reportBlock, merkleRoot),
      ).to.be.revertedWithCustomError(airdrop, 'OnlyRouter')
    })

    it('should fail if Merkle root is already set for the report block', async function () {
      const AirdropFactory = new Airdrop__factory().connect(owner)
      const airdrop2 = await upgrades.deployProxy(AirdropFactory)
      await airdrop2.waitForDeployment()
      const airdropContract2 = airdrop2 as unknown as Airdrop
      const AIR_ADMIN_ROLE = await airdropContract2.ADMIN_ROLE()
      await airdropContract2.connect(owner).grantRole(AIR_ADMIN_ROLE, owner)
      await airdropContract2.connect(owner).setStakeTogether(mockStakeTogetherProxy)
      await airdropContract2.connect(owner).setRouter(owner.address)

      const merkleRoot1 = ethers.keccak256('0x1234')
      const merkleRoot2 = ethers.keccak256('0x5678')

      const reportBlock = await mockRouter.reportBlock()

      await connect(airdropContract2, owner).addMerkleRoot(reportBlock, merkleRoot1)

      await expect(
        connect(airdropContract2, owner).addMerkleRoot(reportBlock, merkleRoot2),
      ).to.be.revertedWithCustomError(airdrop, 'MerkleRootAlreadySetForBlock')
    })
  })

  describe('Claim', function () {
    it('should allow a valid claim and emit claim event', async function () {
      const AirdropFactory = new Airdrop__factory().connect(owner)
      const airdrop2 = await upgrades.deployProxy(AirdropFactory)
      await airdrop2.waitForDeployment()
      const airdropContract2 = airdrop2 as unknown as Airdrop
      const AIR_ADMIN_ROLE = await airdropContract2.ADMIN_ROLE()
      await airdropContract2.connect(owner).grantRole(AIR_ADMIN_ROLE, owner)
      await airdropContract2.connect(owner).setStakeTogether(mockStakeTogetherProxy)
      await airdropContract2.connect(owner).setRouter(owner.address)

      const user5Balance = await mockStakeTogether.balanceOf(user5.address)
      expect(user5Balance).to.equal(0n)

      const user2Balance = await mockStakeTogether.balanceOf(user2.address)
      expect(user2Balance).to.equal(0n)

      const user1DepositAmount = ethers.parseEther('100')
      const poolAddress = user3.address
      const referral = user4.address
      await mockStakeTogether.connect(owner).addPool(poolAddress, true)

      const fee = (user1DepositAmount * 3n) / 1000n
      const user1Shares = user1DepositAmount - fee

      const user1Delegations = [{ pool: poolAddress, percentage: ethers.parseEther('1') }]

      await mockStakeTogether.connect(owner).setFeeAddress(0, await airdropContract2.getAddress())

      const tx1 = await mockStakeTogether
        .connect(user1)
        .depositPool(poolAddress, referral, { value: user1DepositAmount })
      await tx1.wait()

      const epoch = 1
      const index0 = 0n
      const index1 = 1n

      // 1
      const values: [bigint, string, bigint][] = [
        [index0, user5.address, 50000000000000n],
        [index1, user2.address, 25000000000000n],
      ]

      // 2
      const tree = StandardMerkleTree.of(values, ['uint256', 'address', 'uint256'])

      const proof1 = tree.getProof([index0, user5.address, 50000000000000n])

      const proof2 = tree.getProof([index1, user2.address, 25000000000000n])

      // 3
      await airdropContract2.connect(owner).addMerkleRoot(epoch, tree.root)

      // 4
      await expect(
        airdropContract2.connect(user1).claim(epoch, index0, user5.address, 50000000000000n, proof1),
      )
        .to.emit(airdropContract2, 'Claim')
        .withArgs(epoch, index0, user5.address, 50000000000000n, proof1)

      await expect(
        airdropContract2.connect(user1).claim(epoch, index0, user5.address, 50000000000000n, proof1),
      ).to.be.revertedWithCustomError(airdrop, 'AlreadyClaimed')

      expect(await airdropContract2.isClaimed(epoch, index0)).to.equal(true)
      expect(await airdropContract2.isClaimed(epoch, index1)).to.equal(false)

      await airdropContract2.connect(user1).claim(epoch, index1, user2.address, 25000000000000n, proof2)

      expect(await airdropContract2.isClaimed(epoch, index1)).to.equal(true)

      const user5BalanceUpdated = await mockStakeTogether.balanceOf(user5.address)
      expect(user5BalanceUpdated).to.equal(50000000000000n)

      const user2BalanceUpdated = await mockStakeTogether.balanceOf(user2.address)
      expect(user2BalanceUpdated).to.equal(25000000000000n)
    })

    it('should revert if the Merkle root is not set', async function () {
      const epoch = 1
      const index = 0
      const sharesAmount = ethers.parseEther('5')
      const proof: string[] = []
      await expect(
        airdrop.connect(user1).claim(epoch, index, user1.address, sharesAmount, proof),
      ).to.be.revertedWithCustomError(airdrop, 'MerkleRootNotSet')
    })

    it('should revert if the account address is zero', async function () {
      const AirdropFactory = new Airdrop__factory().connect(owner)
      const airdrop2 = await upgrades.deployProxy(AirdropFactory)
      await airdrop2.waitForDeployment()
      const airdropContract2 = airdrop2 as unknown as Airdrop
      const AIR_ADMIN_ROLE = await airdropContract2.ADMIN_ROLE()
      await airdropContract2.connect(owner).grantRole(AIR_ADMIN_ROLE, owner)
      await airdropContract2.connect(owner).setStakeTogether(mockStakeTogetherProxy)
      await airdropContract2.connect(owner).setRouter(owner.address)

      const epoch = 1
      const index0 = 0n
      const index1 = 1n

      const values: [bigint, string, bigint][] = [
        [index0, nullAddress, 5000000000000000000n],
        [index1, user2.address, 2500000000000000000n],
      ]

      const tree = StandardMerkleTree.of(values, ['uint256', 'address', 'uint256'])

      const proof1 = tree.getProof([index0, nullAddress, 5000000000000000000n])

      await airdropContract2.connect(owner).addMerkleRoot(epoch, tree.root)

      await expect(
        airdropContract2.connect(user1).claim(epoch, index0, nullAddress, 5000000000000000000n, proof1),
      ).to.be.revertedWithCustomError(airdropContract2, 'ZeroAddress')
    })

    it('should revert if the account amount is zero', async function () {
      const AirdropFactory = new Airdrop__factory().connect(owner)
      const airdrop2 = await upgrades.deployProxy(AirdropFactory)
      await airdrop2.waitForDeployment()
      const airdropContract2 = airdrop2 as unknown as Airdrop
      const AIR_ADMIN_ROLE = await airdropContract2.ADMIN_ROLE()
      await airdropContract2.connect(owner).grantRole(AIR_ADMIN_ROLE, owner)
      await airdropContract2.connect(owner).setStakeTogether(mockStakeTogetherProxy)
      await airdropContract2.connect(owner).setRouter(owner.address)

      const epoch = 1
      const index0 = 0n
      const index1 = 1n

      const values: [bigint, string, bigint][] = [
        [index0, user1.address, 0n],
        [index1, user2.address, 2500000000000000000n],
      ]

      const tree = StandardMerkleTree.of(values, ['uint256', 'address', 'uint256'])

      const proof1 = tree.getProof([index0, user1.address, 0n])

      await airdropContract2.connect(owner).addMerkleRoot(epoch, tree.root)

      await expect(
        airdropContract2.connect(user1).claim(epoch, index0, user1.address, 0n, proof1),
      ).to.be.revertedWithCustomError(airdrop, 'ZeroAmount')
    })

    it('should revert if proof is invalid', async function () {
      const AirdropFactory = new Airdrop__factory().connect(owner)
      const airdrop2 = await upgrades.deployProxy(AirdropFactory)
      await airdrop2.waitForDeployment()
      const airdropContract2 = airdrop2 as unknown as Airdrop
      const AIR_ADMIN_ROLE = await airdropContract2.ADMIN_ROLE()
      await airdropContract2.connect(owner).grantRole(AIR_ADMIN_ROLE, owner)
      await airdropContract2.connect(owner).setStakeTogether(mockStakeTogetherProxy)
      await airdropContract2.connect(owner).setRouter(owner.address)

      const epoch = 1
      const index0 = 0n
      const index1 = 1n

      const values: [bigint, string, bigint][] = [
        [index0, user1.address, 5000000000000000000n],
        [index1, user2.address, 2500000000000000000n],
      ]

      const tree = StandardMerkleTree.of(values, ['uint256', 'address', 'uint256'])

      await airdropContract2.connect(owner).addMerkleRoot(epoch, tree.root)

      await expect(
        airdropContract2.connect(user1).claim(epoch, index0, user1.address, 5000000000000000000n, []),
      ).to.be.revertedWithCustomError(airdropContract2, 'InvalidProof')
    })
  })
})
