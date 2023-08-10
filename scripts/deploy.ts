import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import * as dotenv from "dotenv";
import { ethers, network, upgrades } from "hardhat";
import { checkVariables } from "../test/utils/env";
import {
  Airdrop,
  Airdrop__factory,
  Fees,
  Fees__factory,
  Router,
  Router__factory,
  StakeTogether,
  StakeTogether__factory,
  Withdrawals,
  Withdrawals__factory,
} from "../typechain";

dotenv.config();

const depositAddress = String(process.env.GOERLI_DEPOSIT_ADDRESS);

export async function deploy() {
  checkVariables();

  const [owner] = await ethers.getSigners();

  const fees = await deployFees(owner);
  const airdrop = await deployAirdrop(owner);
  const withdrawals = await deployWithdrawals(owner);
  const router = await deployRouter(
    owner,
    airdrop.proxyAddress,
    fees.proxyAddress,
    withdrawals.proxyAddress,
  );

  await fees.feesContract.setFeeAddress(0, airdrop.proxyAddress);
  await fees.feesContract.setFeeAddress(1, owner);
  await fees.feesContract.setFeeAddress(2, owner);
  await fees.feesContract.setFeeAddress(3, owner);

  const stakeTogether = await deployStakeTogether(
    owner,
    fees.proxyAddress,
    router.proxyAddress,
    withdrawals.proxyAddress,
  );

  await fees.feesContract.setStakeTogether(stakeTogether.proxyAddress);

  await airdrop.airdropContract.setStakeTogether(stakeTogether.proxyAddress);
  await airdrop.airdropContract.setRouter(router.proxyAddress);

  await withdrawals.withdrawalsContract.setStakeTogether(
    stakeTogether.proxyAddress,
  );

  await router.routerContract.setStakeTogether(stakeTogether.proxyAddress);

  console.log("\n🔷 All ST V2 Contracts Deployed!\n");

  verifyContracts(
    airdrop.proxyAddress,
    airdrop.implementationAddress,
    fees.proxyAddress,
    fees.implementationAddress,
    router.proxyAddress,
    router.implementationAddress,
    stakeTogether.proxyAddress,
    stakeTogether.implementationAddress,
    withdrawals.proxyAddress,
    withdrawals.implementationAddress,
  );
}

async function deployFees(owner: HardhatEthersSigner) {
  const FeesFactory = new Fees__factory().connect(owner);
  const fees = await upgrades.deployProxy(FeesFactory);
  await fees.waitForDeployment();
  const proxyAddress = await fees.getAddress();
  const implementationAddress = await getImplementationAddress(
    network.provider,
    proxyAddress,
  );

  console.log(`Fees\t\t Proxy\t\t\t ${proxyAddress}`);
  console.log(`Fees\t\t Implementation\t\t ${implementationAddress}`);

  const feesContract = fees as unknown as Fees;

  // Set the StakeEntry fee to 0.003 ether and make it a percentage-based fee
  await feesContract.setFee(0n, ethers.parseEther("0.003"), 1n, [
    ethers.parseEther("0.6"),
    0n,
    ethers.parseEther("0.4"),
    0n,
  ]);

  // Set the StakeRewards fee to 0.09 ether and make it a percentage-based fee
  await feesContract.setFee(1n, ethers.parseEther("0.09"), 1n, [
    ethers.parseEther("0.33"),
    ethers.parseEther("0.33"),
    ethers.parseEther("0.34"),
    0n,
  ]);

  // Set the StakePool fee to 1 ether and make it a fixed fee
  await feesContract.setFee(2n, ethers.parseEther("1"), 0n, [
    ethers.parseEther("0.4"),
    0n,
    ethers.parseEther("0.6"),
    0n,
  ]);

  // Set the StakeValidator fee to 0.01 ether and make it a fixed fee
  await feesContract.setFee(3n, ethers.parseEther("0.01"), 0n, [
    0n,
    0n,
    ethers.parseEther("1"),
    0n,
  ]);

  return { proxyAddress, implementationAddress, feesContract };
}

async function deployAirdrop(owner: HardhatEthersSigner) {
  const AirdropFactory = new Airdrop__factory().connect(owner);
  const airdrop = await upgrades.deployProxy(AirdropFactory);
  await airdrop.waitForDeployment();
  const proxyAddress = await airdrop.getAddress();
  const implementationAddress = await getImplementationAddress(
    network.provider,
    proxyAddress,
  );

  console.log(`Airdrop\t\t Proxy\t\t\t ${proxyAddress}`);
  console.log(`Airdrop\t\t Implementation\t\t ${implementationAddress}`);

  const airdropContract = airdrop as unknown as Airdrop;

  await airdropContract.setMaxBatchSize(100);

  return { proxyAddress, implementationAddress, airdropContract };
}

async function deployWithdrawals(owner: HardhatEthersSigner) {
  const WithdrawalsFactory = new Withdrawals__factory().connect(owner);

  const withdrawals = await upgrades.deployProxy(WithdrawalsFactory);
  await withdrawals.waitForDeployment();
  const proxyAddress = await withdrawals.getAddress();
  const implementationAddress = await getImplementationAddress(
    network.provider,
    proxyAddress,
  );

  console.log(`Withdrawals\t Proxy\t\t\t ${proxyAddress}`);
  console.log(`Withdrawals\t Implementation\t\t ${implementationAddress}`);

  const withdrawalsContract = withdrawals as unknown as Withdrawals;

  return { proxyAddress, implementationAddress, withdrawalsContract };
}

async function deployRouter(
  owner: HardhatEthersSigner,
  airdropContract: string,
  feesContract: string,
  withdrawalsContract: string,
) {
  const RouterFactory = new Router__factory().connect(owner);

  const router = await upgrades.deployProxy(RouterFactory, [
    airdropContract,
    feesContract,
    withdrawalsContract,
  ]);

  await router.waitForDeployment();
  const proxyAddress = await router.getAddress();
  const implementationAddress = await getImplementationAddress(
    network.provider,
    proxyAddress,
  );

  console.log(`Router\t\t Proxy\t\t\t ${proxyAddress}`);
  console.log(`Router\t\t Implementation\t\t ${implementationAddress}`);

  // Create the configuration
  const config = {
    bunkerMode: false,
    maxValidatorsToExit: 100,
    minBlocksBeforeExecution: 600,
    minReportOracleQuorum: 5,
    reportOracleQuorum: 5,
    oracleBlackListLimit: 3,
    reportBlockFrequency: 1,
  };

  // Cast the contract to the correct type
  const routerContract = router as unknown as Router;

  // Set the configuration
  await routerContract.setConfig(config);

  return { proxyAddress, implementationAddress, routerContract };
}

async function deployStakeTogether(
  owner: HardhatEthersSigner,
  feesContract: string,
  routerContract: string,
  withdrawalsContract: string,
) {
  const depositAddress = String(process.env.GOERLI_DEPOSIT_ADDRESS);

  function convertToWithdrawalAddress(eth1Address: string): string {
    const address = eth1Address.startsWith("0x")
      ? eth1Address.slice(2)
      : eth1Address;
    const paddedAddress = address.padStart(64, "0");
    const withdrawalAddress = "0x01" + paddedAddress;
    return withdrawalAddress;
  }

  const StakeTogetherFactory = new StakeTogether__factory().connect(owner);

  const stakeTogether = await upgrades.deployProxy(StakeTogetherFactory, [
    feesContract,
    routerContract,
    withdrawalsContract,
    depositAddress,
    convertToWithdrawalAddress(routerContract),
  ]);

  await stakeTogether.waitForDeployment();
  const proxyAddress = await stakeTogether.getAddress();
  const implementationAddress = await getImplementationAddress(
    network.provider,
    proxyAddress,
  );

  console.log(`StakeTogether\t Proxy\t\t\t ${proxyAddress}`);
  console.log(`StakeTogether\t Implementation\t\t ${implementationAddress}`);

  const stakeTogetherContract = stakeTogether as unknown as StakeTogether;

  const config = {
    validatorSize: ethers.parseEther("32"),
    poolSize: ethers.parseEther("32"),
    minDepositAmount: ethers.parseEther("0.001"),
    depositLimit: ethers.parseEther("1000"),
    withdrawalLimit: ethers.parseEther("1000"),
    blocksPerDay: 7200n,
    maxDelegations: 64n,
    feature: {
      AddPool: true,
      Deposit: true,
      WithdrawPool: true,
      WithdrawValidator: true,
    },
  };

  await stakeTogetherContract.setConfig(config);

  await stakeTogetherContract.initializeShares({ value: 1n });

  return { proxyAddress, implementationAddress, stakeTogetherContract };
}

async function verifyContracts(
  airdropProxy: string,
  airdropImplementation: string,
  feesProxy: string,
  feesImplementation: string,
  routerProxy: string,
  routerImplementation: string,
  stakeTogetherProxy: string,
  stakeTogetherImplementation: string,
  withdrawalsProxy: string,
  withdrawalsImplementation: string,
) {
  console.log("\nRUN COMMAND TO VERIFY ON ETHERSCAN\n");

  console.log(`npx hardhat verify --network goerli ${feesProxy} &&`);
  console.log(`npx hardhat verify --network goerli ${feesImplementation} &&`);
  console.log(`npx hardhat verify --network goerli ${airdropProxy} &&`);
  console.log(
    `npx hardhat verify --network goerli ${airdropImplementation} &&`,
  );
  console.log(`npx hardhat verify --network goerli ${withdrawalsProxy} &&`);
  console.log(
    `npx hardhat verify --network goerli ${withdrawalsImplementation} &&`,
  );
  console.log(`npx hardhat verify --network goerli ${routerProxy} &&`);
  console.log(`npx hardhat verify --network goerli ${routerImplementation} &&`);
  console.log(`npx hardhat verify --network goerli ${stakeTogetherProxy} &&`);
  console.log(
    `npx hardhat verify --network goerli ${stakeTogetherImplementation}`,
  );
}

deploy().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
