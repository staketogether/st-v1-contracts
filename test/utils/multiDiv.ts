/**
 * @deprecated don't use this function
 */
export function multiDiv(x: bigint, y: bigint): bigint {
  return (x * y) / BigInt(10) ** BigInt(9)
}
