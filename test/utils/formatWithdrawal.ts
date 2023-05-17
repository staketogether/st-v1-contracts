import { ethers } from 'ethers'

export function formatAddressToWithdrawalCredentials(address: string): string {
  return '0x010000000000000000000000' + ethers.getAddress(address).slice(2).toLowerCase()
}
