import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { ethers } from 'hardhat'

import { STOracle__factory, STValidator__factory, StakeTogether__factory } from '../../typechain'
import { checkVariables } from '../utils/env'
import { formatAddressToWithdrawalCredentials } from '../utils/formatWithdrawal'

export async function defaultFixture() {
  checkVariables()

  const provider = ethers.provider

  let owner: SignerWithAddress
  let user1: SignerWithAddress
  let user2: SignerWithAddress
  let user3: SignerWithAddress
  let user4: SignerWithAddress
  let user5: SignerWithAddress
  let user6: SignerWithAddress
  let user7: SignerWithAddress
  let user8: SignerWithAddress
  let user9: SignerWithAddress
  let nullAddress: string = '0x0000000000000000000000000000000000000000'
  ;[owner, user1, user2, user3, user4, user5, user6, user7, user8, user9] = await ethers.getSigners()

  const STOracle = await new STOracle__factory().connect(owner).deploy()

  const STValidator = await new STValidator__factory()
    .connect(owner)
    .deploy(
      process.env.GOERLI_DEPOSIT_ADDRESS as string,
      process.env.GOERLI_SSV_NETWORK_ADDRESS as string,
      process.env.GOERLI_SSV_TOKEN_ADDRESS as string
    )

  const StakeTogether = await new StakeTogether__factory()
    .connect(owner)
    .deploy(await STOracle.getAddress(), await STValidator.getAddress(), {
      value: 1n
    })

  await StakeTogether.setStakeTogetherFeeRecipient(owner.address)
  await StakeTogether.setOperatorFeeRecipient(user9.address)

  await StakeTogether.addCommunity(user2.address)
  await StakeTogether.addCommunity(user3.address)
  await StakeTogether.addCommunity(user4.address)

  await STOracle.addNode(user1.address)
  await STOracle.addNode(user2.address)
  await STOracle.setStakeTogether(await StakeTogether.getAddress())

  await STValidator.setStakeTogether(await StakeTogether.getAddress())
  await STValidator.setWithdrawalCredentials(
    formatAddressToWithdrawalCredentials(await StakeTogether.getAddress())
  )

  return {
    provider,
    owner,
    user1,
    user2,
    user3,
    user4,
    user5,
    user6,
    user7,
    user8,
    user9,
    nullAddress,
    STOracle,
    STValidator,
    StakeTogether
  }
}
