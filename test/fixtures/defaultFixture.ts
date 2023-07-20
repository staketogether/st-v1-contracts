import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { ethers } from 'hardhat'

import {
  Airdrop__factory,
  Fees__factory,
  Liquidity__factory,
  Router__factory,
  StakeTogether__factory,
  Validators__factory,
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
  const Liquidity = await new Liquidity__factory().connect(owner).deploy()
  const Airdrop = await new Airdrop__factory().connect(owner).deploy()
  const Validators = await new Validators__factory()
    .connect(owner)
    .deploy(process.env.GOERLI_DEPOSIT_ADDRESS as string)
  const Router = await new Router__factory()
    .connect(owner)
    .deploy(
      await Withdrawals.getAddress(),
      await Liquidity.getAddress(),
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
      await Liquidity.getAddress(),
      await Validators.getAddress(),
      {
        value: initialDeposit
      }
    )

  await StakeTogether.bootstrap()

  await Router.setStakeTogether(await StakeTogether.getAddress())

  await Validators.setStakeTogether(await StakeTogether.getAddress())
  await Validators.setRouter(await Router.getAddress())

  await Airdrop.setStakeTogether(await StakeTogether.getAddress())
  await Airdrop.setRouter(await Router.getAddress())

  await Withdrawals.setStakeTogether(await StakeTogether.getAddress())

  await Fees.setStakeTogether(await StakeTogether.getAddress())
  await Fees.setRouter(await Router.getAddress())
  await Fees.setFee(1n, 1000000000000000n, 1n)
  await Fees.setFeeAllocation(1n, (await Fees.getFeesRoles())[1], 400000000000000000n)
  await Fees.setFeeAllocation(1n, (await Fees.getFeesRoles())[2], 400000000000000000n)
  await Fees.setFeeAllocation(1n, (await Fees.getFeesRoles())[5], 200000000000000000n)
  await Fees.setFeeAddress((await Fees.getFeesRoles())[1], await StakeTogether.getAddress())
  await Fees.setFeeAddress((await Fees.getFeesRoles())[2], await StakeTogether.getAddress())
  await Fees.setFeeAddress((await Fees.getFeesRoles())[5], await StakeTogether.getAddress())

  await Liquidity.setFees(await Fees.getAddress())
  await Liquidity.setRouter(await Router.getAddress())
  await Liquidity.setStakeTogether(await StakeTogether.getAddress())

  await StakeTogether.grantRole(await StakeTogether.POOL_MANAGER_ROLE(), owner.address)
  await Validators.grantRole(await Validators.ORACLE_VALIDATOR_MANAGER_ROLE(), owner.address)
  await Router.grantRole(await Router.ORACLE_REPORT_MANAGER_ROLE(), user1.address)

  await Router.addReportOracle(process.env.GOERLI_ORACLE_ADDRESS as string)
  await Validators.addValidatorOracle(process.env.GOERLI_VALIDATOR_ADDRESS as string)

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
    nullAddress,
    initialDeposit,
    Router,
    Airdrop,
    Withdrawals,
    Liquidity,
    Validators,
    Fees,
    StakeTogether
  }
}
