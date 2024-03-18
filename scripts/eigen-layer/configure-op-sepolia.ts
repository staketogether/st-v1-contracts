import { task } from 'hardhat/config'

const configureOpSepolia = task('configure-op-sepolia', 'Configures the OP Sepolia contracts')
  .addParam('adapterAddress', 'The address of the adapter contract')
  .addParam('stakeTogetherAddress', 'The address of the StakeTogether contract')
  .setAction(async (taskArgs, hre) => {
    await hre.network.provider.request({
      method: 'hardhat_setNetwork',
      params: [taskArgs.network]
    })

    const { ethers } = hre

    const adapterAddress = taskArgs.adapterAddress
    const stakeTogetherAddress = taskArgs.stakeTogetherAddress
    const [owner] = await ethers.getSigners()
    const stakeTogether = await ethers.getContractAt('contracts/ethereum-staking-restaking/StakeTogether.sol:StakeTogether', stakeTogetherAddress)
    await (await stakeTogether.connect(owner).setL1Adapter(adapterAddress)).wait()
    console.log('🔷 Configured OP Sepolia contracts')
  })

export default configureOpSepolia