import { task } from 'hardhat/config'

const eigenLayerTestnet = task("ethereum-staking-restaking:testnet", "Deploys and configures the contract", async (taskArgs, hre) => {
  const { run } = hre;
  const { opAdapter } = await run('deploy-eth-sepolia', {
    network: 'sepolia',
    withdrawalsCredentials: process.env.SEPOLIA_WITHDRAWAL_ADDRESS as string,
    bridgeAddress: process.env.ETH_SEPOLIA_BRIDGE_ADDRESS as string,
    depositAddress: process.env.SEPOLIA_DEPOSIT_ADDRESS as string,
  });

  const { stakeTogether } = await run('deploy-op-sepolia', {
    network: 'optimismSepolia',
    bridgeAddress: process.env.OP_SEPOLIA_BRIDGE_ADDRESS as string,
  });
  console.log('\n🔷 Setting configurations \n')

  await run('configure-eth-sepolia', {
    network: 'sepolia',
    adapterAddress: opAdapter.proxyAddress,
    stakeTogetherAddress: stakeTogether.proxyAddress
  });
  await run('configure-op-sepolia',
    {
      network: 'optimismSepolia',
      adapterAddress: opAdapter.proxyAddress,
      stakeTogetherAddress: stakeTogether.proxyAddress
    });

  console.log('\n🔷 All contracts deployed and configured!\n');
});

export default eigenLayerTestnet;