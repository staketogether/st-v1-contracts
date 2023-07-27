import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import { airdropFixture } from './airdropFixture'
import { ethers } from 'hardhat'
import { Airdrop as AirdropContract } from '../../typechain'

describe.only('Airdrop', function () {
  it('Only router should be able to add merkleRoot', async function () {
    const { Airdrop, user1, user2, owner } = await loadFixture(airdropFixture)

    const airdropUser1 = Airdrop.contract.connect(user1) as unknown as AirdropContract
    const airdropOwner = Airdrop.contract.connect(owner) as unknown as AirdropContract

    await expect(
      airdropUser1.addAirdropMerkleRoot(1, ethers.encodeBytes32String('MerkleRoot'))
    ).to.be.revertedWith('ONLY_ROUTER')
    await expect(airdropOwner.addAirdropMerkleRoot(1, ethers.encodeBytes32String('MerkleRoot'))).to.not.be
      .reverted
  })
  it('Adding merkleRoot for an already defined epoch should not be allowed', async function () {
    const { Airdrop, owner } = await loadFixture(airdropFixture)
    const airdropOwner = Airdrop.contract.connect(owner) as unknown as AirdropContract

    await airdropOwner.addAirdropMerkleRoot(1, ethers.encodeBytes32String('MerkleRoot1'))
    await expect(
      airdropOwner.addAirdropMerkleRoot(1, ethers.encodeBytes32String('MerkleRoot2'))
    ).to.be.revertedWith('MERKLE_ALREADY_SET_FOR_EPOCH')
  })

  it('Adding merkleRoot for a new epoch should be possible', async function () {
    const { Airdrop, owner } = await loadFixture(airdropFixture)
    const airdropOwner = Airdrop.contract.connect(owner) as unknown as AirdropContract

    await expect(airdropOwner.addAirdropMerkleRoot(1, ethers.encodeBytes32String('MerkleRoot1'))).to.not
      .be.reverted
    expect(
      await Airdrop.contract.addAirdropMerkleRoot(2, ethers.encodeBytes32String('MerkleRoot1'))
    ).to.equal(ethers.encodeBytes32String('MerkleRoot2'))
  })

  it('An event should be emitted when a new merkleRoot is added', async function () {
    const { Airdrop, owner } = await loadFixture(airdropFixture)
    const airdropOwner = Airdrop.contract.connect(owner) as unknown as AirdropContract

    await expect(airdropOwner.addAirdropMerkleRoot(1, ethers.encodeBytes32String('MerkleRoot1')))
      .to.emit(Airdrop, 'AddAirdropMerkleRoot')
      .withArgs(1, ethers.encodeBytes32String('MerkleRoot1'))
  })
})
