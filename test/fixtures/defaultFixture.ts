import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { ethers, upgrades } from 'hardhat'

import {
  Airdrop__factory,
  Fees__factory,
  Liquidity__factory,
  Router__factory,
  StakeTogether__factory,
  Validators__factory,
  Withdrawals__factory,
  Airdrop as AirdropContract,
  Fees as FeesContract,
  Liquidity as LiquidityContract,
  Router as RouterContract,
  StakeTogether as StakeTogetherContract,
  Validators as ValidatorsContract,
  Withdrawals as WithdrawalsContract
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

  const FeesFactory = await new Fees__factory().connect(owner)
  const Fees = (await upgrades.deployProxy(FeesFactory)) as unknown as FeesContract
  await Fees.waitForDeployment()
  const WithdrawalsFactory = await new Withdrawals__factory().connect(owner)
  const Withdrawals = (await upgrades.deployProxy(WithdrawalsFactory)) as unknown as WithdrawalsContract
  await Withdrawals.waitForDeployment()
  const LiquidityFactory = await new Liquidity__factory().connect(owner)
  const Liquidity = (await upgrades.deployProxy(LiquidityFactory)) as unknown as LiquidityContract
  await Liquidity.waitForDeployment()
  const AirdropFactory = await new Airdrop__factory().connect(owner)
  const Airdrop = (await upgrades.deployProxy(AirdropFactory)) as unknown as AirdropContract
  await Airdrop.waitForDeployment()
  const ValidatorsFactory = await new Validators__factory().connect(owner)
  const Validators = (await upgrades.deployProxy(ValidatorsFactory, [
    process.env.GOERLI_DEPOSIT_ADDRESS as string,
    await Fees.getAddress()
  ])) as unknown as ValidatorsContract
  await Validators.waitForDeployment()
  const RouterFactory = await new Router__factory().connect(owner)
  const Router = (await upgrades.deployProxy(RouterFactory, [
    await Withdrawals.getAddress(),
    await Liquidity.getAddress(),
    await Airdrop.getAddress(),
    await Validators.getAddress(),
    await Fees.getAddress()
  ])) as unknown as RouterContract
  await Router.waitForDeployment()

  const StakeTogetherFactory = await new StakeTogether__factory().connect(owner)
  const StakeTogether = (await upgrades.deployProxy(StakeTogetherFactory, [
    await Router.getAddress(),
    await Fees.getAddress(),
    await Airdrop.getAddress(),
    await Withdrawals.getAddress(),
    await Liquidity.getAddress(),
    await Validators.getAddress(),
    '0x',
    { value: initialDeposit }
  ])) as unknown as StakeTogetherContract
  await StakeTogether.waitForDeployment()

  await Router.setStakeTogether(await StakeTogether.getAddress())

  await Validators.setStakeTogether(await StakeTogether.getAddress())
  await Validators.setRouter(await Router.getAddress())

  await Airdrop.setStakeTogether(await StakeTogether.getAddress())
  await Airdrop.setRouter(await Router.getAddress())

  await Withdrawals.setStakeTogether(await StakeTogether.getAddress())

  await Fees.setStakeTogether(await StakeTogether.getAddress())
  await Fees.setRouter(await Router.getAddress())
  await Fees.setFeeValue(1n, 1000000000000000n, 1n)
  await Fees.setFeeAllocation(1n, (await Fees.getFeesRoles())[0], 400000000000000000n)
  await Fees.setFeeAllocation(1n, (await Fees.getFeesRoles())[1], 100000000000000000n)
  await Fees.setFeeAllocation(1n, (await Fees.getFeesRoles())[2], 100000000000000000n)
  await Fees.setFeeAllocation(1n, (await Fees.getFeesRoles())[3], 100000000000000000n)
  await Fees.setFeeAllocation(1n, (await Fees.getFeesRoles())[4], 100000000000000000n)
  await Fees.setFeeAllocation(1n, (await Fees.getFeesRoles())[5], 100000000000000000n)
  await Fees.setFeeAllocation(1n, (await Fees.getFeesRoles())[6], 100000000000000000n)
  await Fees.setFeeAddress((await Fees.getFeesRoles())[0], await user4.getAddress())
  await Fees.setFeeAddress((await Fees.getFeesRoles())[1], await user4.getAddress())
  await Fees.setFeeAddress((await Fees.getFeesRoles())[2], await user4.getAddress())
  await Fees.setFeeAddress((await Fees.getFeesRoles())[3], await user4.getAddress())
  await Fees.setFeeAddress((await Fees.getFeesRoles())[4], await user4.getAddress())
  await Fees.setFeeAddress((await Fees.getFeesRoles())[5], await user4.getAddress())
  await Fees.setFeeAddress((await Fees.getFeesRoles())[6], await user4.getAddress())

  // await Liquidity.setFees(await Fees.getAddress())
  await Liquidity.setRouter(await Router.getAddress())
  await Liquidity.setStakeTogether(await StakeTogether.getAddress())

  await StakeTogether.grantRole(await StakeTogether.POOL_MANAGER_ROLE(), owner.address)
  await Validators.grantRole(await Validators.ORACLE_VALIDATOR_MANAGER_ROLE(), owner.address)
  await Router.grantRole(await Router.ORACLE_REPORT_MANAGER_ROLE(), user1.address)

  await Router.addReportOracle(process.env.GOERLI_ORACLE_ADDRESS as string)
  await Validators.addValidatorOracle(process.env.GOERLI_VALIDATOR_ADDRESS as string)

  await StakeTogether.addPool(user2.address, true)
  await StakeTogether.addPool(user3.address, true)
  await StakeTogether.addPool(user4.address, true)

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
    Liquidity,
    Validators,
    Fees,
    StakeTogether
  }
}
