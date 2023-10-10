# From issue #241

import
  ../../constantine/math/[
    arithmetic,
    io/io_bigints],
  ../../constantine/math_arbitrary_precision/arithmetic/limbs_divmod_vartime

let a = BigInt[64].fromUint(0xa0e5cb56a1c08396'u64)
let M = BigInt[64].fromUint(0xae57180eceb0206f'u64)

var r, r2: BigInt[64]

r.reduce(a, M)
doAssert r2.limbs.reduce_vartime(a.limbs, M.limbs)

let rU64 = 0xa0e5cb56a1c08396'u64 mod 0xae57180eceb0206f'u64
echo r.toHex()

doAssert rU64 == a.limbs[0].uint64
doAssert bool(a == r)