import { ethers } from 'hardhat'

const walletAddress = 'YOUR_WALLET_ADDRESS_HERE'
const contractAddresses = ['CONTRACT_ADDRESS_1', 'CONTRACT_ADDRESS_2']
const roles = ['ROLE_HASH_1', 'ROLE_HASH_2']

const abi = ['function hasRole(bytes32 role, address account) public view returns (bool)']

async function checkRolesForWallet() {
  console.log('Starting role verification...\n')

  for (const contractAddress of contractAddresses) {
    const contract = await ethers.getContractAt(abi, contractAddress)

    for (const role of roles) {
      const hasRole = await contract.hasRole(role, walletAddress)
      console.log(`Contract: ${contractAddress}, Role: ${role}, Has role: ${hasRole}`)
    }
  }

  console.log('\n✅ Role verification completed.')
}

async function main() {
  try {
    await checkRolesForWallet()
  } catch (error) {
    console.error('Error during role verification:', error)
    process.exitCode = 1
  }
}

main()
