import { ethers } from 'ethers'
import { StakeTogether } from '../../typechain'

export const stValidatorsKeys: string[] = []
export const stValidatorsBlocks: number[] = []

async function getPastValidators(provider: ethers.Provider, stContract: StakeTogether) {
  const createValidatorTopic = ethers.id('CreateValidator(address,uint256,bytes,bytes,bytes,bytes32)')
  const removeValidatorTopic = ethers.id('RemoveValidator(address,bytes)')

  const creationLogs = await provider.getLogs({
    fromBlock: (await stContract.deploymentTransaction())?.blockNumber ?? 0,
    toBlock: 'latest',
    topics: [createValidatorTopic],
    address: await stContract.getAddress()
  })

  const removalLogs = await provider.getLogs({
    fromBlock: (await stContract.deploymentTransaction())?.blockNumber ?? 0,
    toBlock: 'latest',
    topics: [removeValidatorTopic],
    address: await stContract.getAddress()
  })

  for (const log of creationLogs) {
    const mutableLog = { ...log, topics: [...log.topics], data: log.data }
    const parsedLog = stContract.interface.parseLog(mutableLog)

    if (parsedLog) {
      const publicKey = parsedLog.args.publicKey
      if (parsedLog.name === 'CreateValidator' && !stValidatorsKeys.includes(publicKey)) {
        stValidatorsKeys.push(publicKey)
        stValidatorsBlocks.push(log.blockNumber)
      }
    }
  }

  for (const log of removalLogs) {
    const mutableLog = { ...log, topics: [...log.topics], data: log.data }
    const parsedLog = stContract.interface.parseLog(mutableLog)

    if (parsedLog) {
      const publicKey = parsedLog.args.publicKey
      if (parsedLog.name === 'RemoveValidator' && stValidatorsKeys.includes(publicKey)) {
        const index = stValidatorsKeys.indexOf(publicKey)
        if (log.blockNumber > stValidatorsBlocks[index]) {
          stValidatorsKeys.splice(index, 1)
          stValidatorsBlocks.splice(index, 1)
        }
      }
    }
  }

  return stValidatorsKeys
}

export const stObtainPools = async (
  stakeTogether: StakeTogether,
  implementationAddress: string,
  provider: ethers.Provider
) => {
  const stContractAddress = process.env.ST_CONTRACT as string
  const stContract = new ethers.Contract(
    implementationAddress,
    stakeTogether.interface.format(),
    provider
  )

  return getPastValidators(provider, stakeTogether)
}
