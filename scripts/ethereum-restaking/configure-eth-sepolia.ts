import { task } from 'hardhat/config'
import { TaskArguments } from 'hardhat/types'

const configureEthSepolia = task('configure-eth-sepolia', 'Configures adapters for ETH Sepolia')
  .addParam('adapterAddress', 'The address of the adapter contract')
  .addParam('stakeTogetherAddress', 'The address of the StakeTogether contract')
  .setAction(async (taskArgs: TaskArguments, hre) => {
    await hre.network.provider.request({
      method: 'hardhat_setNetwork',
      params: [taskArgs.network]
    })

    const { ethers } = hre

    const adapterAddress = taskArgs.adapterAddress as string
    const stakeTogetherAddress = taskArgs.stakeTogetherAddress as string
    const [owner] = await ethers.getSigners()
    const adapter = await ethers.getContractAt('Adapter', adapterAddress)
    await (await adapter.connect(owner).setL2StakeTogether(stakeTogetherAddress)).wait()
    console.log('🔷 Configured ETH Sepolia contracts')
  })

export default configureEthSepolia