export function formatWithdrawal(eth1Address: string): string {
  const address = eth1Address.startsWith('0x') ? eth1Address.slice(2) : eth1Address
  const paddedAddress = address.padStart(64, '0')
  const withdrawalAddress = '0x01' + paddedAddress
  return withdrawalAddress
}
