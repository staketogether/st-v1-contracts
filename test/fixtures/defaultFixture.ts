import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { ethers } from 'hardhat'

import {
  Airdrop__factory,
  Fees__factory,
  RewardsLoan__factory,
  Router__factory,
  StakeTogether__factory,
  Validators__factory,
  WithdrawalsLoan__factory,
  Withdrawals__factory
} from '../../typechain'
import { checkVariables } from '../utils/env'

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
  const initialDeposit = 1n
  ;[owner, user1, user2, user3, user4, user5, user6, user7, user8, user9] = await ethers.getSigners()

  const Fees = await new Fees__factory().connect(owner).deploy()
  const Withdrawals = await new Withdrawals__factory().connect(owner).deploy()
  const WithdrawalsLoan = await new WithdrawalsLoan__factory().connect(owner).deploy()
  const Airdrop = await new Airdrop__factory().connect(owner).deploy()
  const RewardsLoan = await new RewardsLoan__factory().connect(owner).deploy()
  const Validators = await new Validators__factory()
    .connect(owner)
    .deploy(process.env.GOERLI_DEPOSIT_ADDRESS as string)
  const Router = await new Router__factory()
    .connect(owner)
    .deploy(
      await Withdrawals.getAddress(),
      await WithdrawalsLoan.getAddress(),
      await Airdrop.getAddress(),
      await Validators.getAddress(),
      await Fees.getAddress()
    )

  const StakeTogether = await new StakeTogether__factory()
    .connect(owner)
    .deploy(
      await Router.getAddress(),
      await Fees.getAddress(),
      await Airdrop.getAddress(),
      await Withdrawals.getAddress(),
      await WithdrawalsLoan.getAddress(),
      await Validators.getAddress(),
      await RewardsLoan.getAddress(),
      {
        value: initialDeposit
      }
    )

  await Router.setStakeTogether(await StakeTogether.getAddress())
  await Router.addReportOracle(process.env.GOERLI_ORACLE_ADDRESS as string)

  await Airdrop.setRouter(await Router.getAddress())
  await Airdrop.setStakeTogether(await StakeTogether.getAddress())

  await Fees.setStakeTogether(await StakeTogether.getAddress())
  await Fees.setRouter(await Router.getAddress())
  await Fees.setFee(0n, 1n, 0n)

  await Validators.setRouter(await Router.getAddress())
  await Validators.addValidatorOracle(process.env.GOERLI_VALIDATOR_ADDRESS as string)
  await Validators.setStakeTogether(await StakeTogether.getAddress())

  await Withdrawals.setStakeTogether(await StakeTogether.getAddress())

  await WithdrawalsLoan.setFees(await Fees.getAddress())
  await WithdrawalsLoan.setRouter(await Router.getAddress())
  await WithdrawalsLoan.setStakeTogether(await StakeTogether.getAddress())

  await RewardsLoan.setFees(await Fees.getAddress())
  await RewardsLoan.setRouter(await Router.getAddress())
  await RewardsLoan.setStakeTogether(await StakeTogether.getAddress())

  await StakeTogether.bootstrap()

  await StakeTogether.addPool(user2.address)
  await StakeTogether.addPool(user3.address)
  await StakeTogether.addPool(user4.address)

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
    initialDeposit,
    Router,
    Airdrop,
    Withdrawals,
    WithdrawalsLoan,
    RewardsLoan,
    Validators,
    Fees,
    StakeTogether
  }
}
