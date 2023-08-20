import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { StandardMerkleTree } from '@openzeppelin/merkle-tree'
import { expect } from 'chai'
import dotenv from 'dotenv'
import { ethers, upgrades } from 'hardhat'
import { Airdrop, MockAirdrop__factory, MockRouter, MockStakeTogether } from '../../typechain'
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
      await expect(connect(airdrop, owner).setStakeTogether(nullAddress)).to.be.reverted

      // User1 tries to set the StakeTogether address to their own address - should fail
      await expect(connect(airdrop, user1).setStakeTogether(user1.address)).to.be.reverted

      // Owner sets the StakeTogether address - should succeed
      await connect(airdrop, owner).setStakeTogether(user1.address)

      // Verify that the StakeTogether address was correctly set
      expect(await airdrop.stakeTogether()).to.equal(user1.address)
    })

    it('should correctly set the Router address', async function () {
      await expect(connect(airdrop, owner).setRouter(nullAddress)).to.be.reverted

      await expect(connect(airdrop, user1).setRouter(user1.address)).to.be.reverted

      await connect(airdrop, owner).setRouter(user1.address)

      expect(await airdrop.router()).to.equal(user1.address)
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
      await expect(airdrop.connect(owner).transferExtraAmount()).to.be.revertedWith('NO_EXTRA_AMOUNT')
    })
  })

  describe('addMerkleRoot', function () {
    it('should add a Merkle root if called by the router address', async function () {
      const epoch = 1
      const merkleRoot = ethers.keccak256('0x1234')

      await connect(airdrop, owner).setRouter(owner.address)

      await expect(connect(airdrop, owner).addMerkleRoot(epoch, merkleRoot))
        .to.emit(airdrop, 'AddMerkleRoot')
        .withArgs(epoch, merkleRoot)

      expect(await airdrop.merkleRoots(epoch)).to.equal(merkleRoot)
    })

    it('should fail if called by an address other than the router', async function () {
      const epoch = 1
      const merkleRoot = ethers.keccak256('0x1234')

      await expect(connect(airdrop, user1).addMerkleRoot(epoch, merkleRoot)).to.be.revertedWith(
        'ONLY_ROUTER',
      )
    })

    it('should fail if Merkle root is already set for the epoch', async function () {
      const epoch = 1
      const merkleRoot1 = ethers.keccak256('0x1234')
      const merkleRoot2 = ethers.keccak256('0x5678')

      await connect(airdrop, owner).setRouter(owner.address)
      await connect(airdrop, owner).addMerkleRoot(epoch, merkleRoot1)

      await expect(connect(airdrop, owner).addMerkleRoot(epoch, merkleRoot2)).to.be.revertedWith(
        'MERKLE_ALREADY_SET_FOR_EPOCH',
      )
    })
  })

  describe('Claim', function () {
    it('should allow a valid claim and emit claim event', async function () {
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

      const tx1 = await mockStakeTogether
        .connect(user1)
        .depositPool(user1Delegations, referral, { value: user1DepositAmount })
      await tx1.wait()

      const epoch = 1
      const index0 = 0n
      const index1 = 1n

      const values: [bigint, string, bigint][] = [
        [index0, user5.address, 50000000000000n],
        [index1, user2.address, 25000000000000n],
      ]

      const tree = StandardMerkleTree.of(values, ['uint256', 'address', 'uint256'])

      const proof1 = tree.getProof([index0, user5.address, 50000000000000n])
      const proof2 = tree.getProof([index1, user2.address, 25000000000000n])

      await airdrop.connect(owner).setRouter(owner.address)
      await airdrop.connect(owner).addMerkleRoot(epoch, tree.root)

      await expect(airdrop.connect(user1).claim(epoch, index0, user5.address, 50000000000000n, proof1))
        .to.emit(airdrop, 'Claim')
        .withArgs(epoch, index0, user5.address, 50000000000000n, proof1)

      await expect(
        airdrop.connect(user1).claim(epoch, index0, user5.address, 50000000000000n, proof1),
      ).to.be.revertedWith('ALREADY_CLAIMED')

      expect(await airdrop.isClaimed(epoch, index0)).to.equal(true)
      expect(await airdrop.isClaimed(epoch, index1)).to.equal(false)

      await airdrop.connect(user1).claim(epoch, index1, user2.address, 25000000000000n, proof2)

      expect(await airdrop.isClaimed(epoch, index1)).to.equal(true)

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
      ).to.be.revertedWith('MERKLE_ROOT_NOT_SET')
    })

    it('should revert if the account address is zero', async function () {
      const epoch = 1
      const index0 = 0n
      const index1 = 1n

      const values: [bigint, string, bigint][] = [
        [index0, nullAddress, 5000000000000000000n],
        [index1, user2.address, 2500000000000000000n],
      ]

      const tree = StandardMerkleTree.of(values, ['uint256', 'address', 'uint256'])

      const proof1 = tree.getProof([index0, nullAddress, 5000000000000000000n])
      const proof2 = tree.getProof([index1, user2.address, 2500000000000000000n])

      await airdrop.connect(owner).setRouter(owner.address)
      await airdrop.connect(owner).addMerkleRoot(epoch, tree.root)

      await expect(
        airdrop.connect(user1).claim(epoch, index0, nullAddress, 5000000000000000000n, proof1),
      ).to.be.revertedWith('ZERO_ADDRESS')
    })

    it('should revert if the account amount is zero', async function () {
      const epoch = 1
      const index0 = 0n
      const index1 = 1n

      const values: [bigint, string, bigint][] = [
        [index0, user1.address, 0n],
        [index1, user2.address, 2500000000000000000n],
      ]

      const tree = StandardMerkleTree.of(values, ['uint256', 'address', 'uint256'])

      const proof1 = tree.getProof([index0, user1.address, 0n])

      await airdrop.connect(owner).setRouter(owner.address)
      await airdrop.connect(owner).addMerkleRoot(epoch, tree.root)

      await expect(
        airdrop.connect(user1).claim(epoch, index0, user1.address, 0n, proof1),
      ).to.be.revertedWith('ZERO_AMOUNT')
    })

    it('should revert if proof is invalid', async function () {
      const epoch = 1
      const index0 = 0n
      const index1 = 1n

      const values: [bigint, string, bigint][] = [
        [index0, user1.address, 5000000000000000000n],
        [index1, user2.address, 2500000000000000000n],
      ]

      const tree = StandardMerkleTree.of(values, ['uint256', 'address', 'uint256'])

      await airdrop.connect(owner).setRouter(owner.address)
      await airdrop.connect(owner).addMerkleRoot(epoch, tree.root)

      await expect(
        airdrop.connect(user1).claim(epoch, index0, user1.address, 5000000000000000000n, []),
      ).to.be.revertedWith('INVALID_PROOF')
    })
  })
})
