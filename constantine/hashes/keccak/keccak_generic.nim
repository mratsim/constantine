# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/primitives,
  constantine/serialization/endians

# Keccak
# --------------------------------------------------------------------------------
#
# References:
# - https://keccak.team/keccak_specs_summary.html
# - https://keccak.team/files/Keccak-reference-3.0.pdf
# - https://keccak.team/files/Keccak-implementation-3.2.pdf
# - SHA3 (different padding): https://csrc.nist.gov/publications/detail/fips/202/final
#
# Pseudo-code
# ~~~~~~~~~~~
# Keccak-f[b](A) {
#   for i in 0…n-1
#     A = Round[b](A, RC[i])
#   return A
# }
#
# Round[b](A,RC) {
#   # θ step
#   C[x] = A[x,0] xor A[x,1] xor A[x,2] xor A[x,3] xor A[x,4],   for x in 0…4
#   D[x] = C[x-1] xor rot(C[x+1],1),                             for x in 0…4
#   A[x,y] = A[x,y] xor D[x],                           for (x,y) in (0…4,0…4)
#
#   # ρ and π steps
#   B[y,2*x+3*y] = rot(A[x,y], r[x,y]),                 for (x,y) in (0…4,0…4)
#
#   # χ step
#   A[x,y] = B[x,y] xor ((not B[x+1,y]) and B[x+2,y]),  for (x,y) in (0…4,0…4)
#
#   # ι step
#   A[0,0] = A[0,0] xor RC
#
#   return A
# }

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

# Hardware acceleration considerations
# ------------------------------------------------
#
# 1. The χ step uses "and not", the Keccak implementation guide suggest a "lane-complementing technique"
#    to reduce the number of `not` from 5 to 1.
#    However, the BM1 CPU features introduced `andn` in AMD Piledriver (2012) and Intel Haswell (2013)
#    ARM has the BIC instruction (Bit Clear) for ANDNOT

# Types & Constants
# ------------------------------------------------

type KeccakState* = object
  ## A Keccak state matrix: 5*5*uint64 = 1600 bits, in column major order
  ##              ┌─┬─┬─┬─┬─┐
  ##             ┌─┬─┬─┬─┬─┐┤
  ##            ┌─┬─┬─┬─┬─┐┤┤
  ##           ┌─┬─┬─┬─┬─┐┤┤┤
  ##          ┌─┬─┬─┬─┬─┐┤┤┤┤
  ##         ┌─┬─┬─┬─┬─┐┤┤┤┤┘
  ##        ┌─┬─┬─┬─┬─┐┤┤┤┤┘
  ##       ┌─┬─┬─┬─┬─┐┤┤┤┤┘
  ##       ├─┼─┼─┼─┼─┤┤┤┤┘
  ##       ├─┼─┼─┼─┼─┤┤┤┘
  ##       ├─┼─┼─┼─┼─┤┤┘        ┌─┐ bit
  ##       ├─┼─┼─┼─┼─┤┘         └─┘         ┌─┐
  ##       └─┴─┴─┴─┴─┘                     ┌─┐┘
  ##          state                       ┌─┐┘
  ##                                     ┌─┐┘
  ##                    ┌─┐             ┌─┐┘
  ##                    ├─┤ column     ┌─┐┘
  ##      row           ├─┤           ┌─┐┘
  ##  ┌─┬─┬─┬─┬─┐       ├─┤          ┌─┐┘  lane
  ##  └─┴─┴─┴─┴─┘       ├─┤          └─┘
  ##                    └─┘
  ##
  ##  plane = row * lane
  ##  slice = row * column
  ##  sheet = column * lane
  ##
  ## Credit: https://github.com/tecosaur/KangarooTwelve.jl
  state {.align: 64.}: array[5*5, uint64]

func lin_idx(x, y: int): int {.inline.} =
  5*y+x

func `[]`(A: KeccakState, x, y: int): uint64 {.inline.} =
  A.state[lin_idx(x, y)]

func `[]=`(A: var KeccakState, x, y: int, val: uint64) {.inline.} =
  A.state[lin_idx(x, y)] = val

func N(exponent: static int, x, y: int): int {.inline.} =
  # We use algorithm 4 in https://keccak.team/files/Keccak-implementation-3.2.pdf
  # We have a coordinate displacement matrix N = [1 0]
  #                                              [1 2]
  # to store data without overwriting it
  const exponent = exponent and 3 # exponent mod 4 as N has order 4
  when exponent == 0:
    # N⁰ = [1 0]
    #      [0 1]
    lin_idx(x, y)
  elif exponent == 1:
    # N¹ = [1 0]
    #      [1 2]
    lin_idx(x, (x+2*y) mod 5)
  elif exponent == 2:
    # N² = [1 0]
    #      [3 4]
    lin_idx(x, (3*x+4*y) mod 5)
  elif exponent == 3:
    # N³ = [1 0]
    #      [2 3]
    lin_idx(x, (2*x+3*y) mod 5)
  else:
    {.error: "unreachable".}

func N(A: KeccakState, i: static int, x, y: int): uint64 {.inline.} =
  A.state[N(i, x, y)]

func N(A: var KeccakState, i: static int, x, y: int): var uint64 {.inline.} =
  A.state[N(i, x, y)]

# Keccak round constants
#   are iteratively computed via a linear feedback shift register
#   rc[t] = (xᵗ mod x⁸ + x⁶ + x⁵ + x⁴ + 1) mod x in GF(2)[x]
const KRC: array[24, uint64] = [
    0x0000000000000001'u64,
    0x0000000000008082'u64,
    0x800000000000808a'u64,
    0x8000000080008000'u64,
    0x000000000000808b'u64,
    0x0000000080000001'u64,
    0x8000000080008081'u64,
    0x8000000000008009'u64,
    0x000000000000008a'u64,
    0x0000000000000088'u64,
    0x0000000080008009'u64,
    0x000000008000000a'u64,
    0x000000008000808b'u64,
    0x800000000000008b'u64,
    0x8000000000008089'u64,
    0x8000000000008003'u64,
    0x8000000000008002'u64,
    0x8000000000000080'u64,
    0x000000000000800a'u64,
    0x800000008000000a'u64,
    0x8000000080008081'u64,
    0x8000000000008080'u64,
    0x0000000080000001'u64,
    0x8000000080008008'u64,
]

func genRho(): array[5*5, int] =
  result[lin_idx(0, 0)] = 0
  var (x, y) = (1, 0)

  for t in 0 ..< result.len-1: # skip 0
    # rotation constant r = i(i+1)/2, skipping (0, 0) hence (t+1)(t+2)/2
    result[lin_idx(x, y)] =
        (((t+1) * (t+2)) shr 1) and (64-1)

    let Y = (2*x + 3*y) mod 5
    let X = y
    x = X
    y = Y

func rotl(x: uint64, k: static int): uint64 {.inline.} =
  return (x shl k) or (x shr (64 - k))

func permute_generic*(A: var KeccakState, NumRounds: static int) =
  # We use algorithm 4 in https://keccak.team/files/Keccak-implementation-3.2.pdf
  const Rho = genRho()

  var C {.noinit.}: array[5, uint64]
  var D {.noinit.}: array[5, uint64]
  template B: array[5, uint64] = C # Reuse C statefer for B

  # We unroll the loop by 4 to:
  # - reuse memory locations as N is cyclic of order 4
  # - minimize code size vs unrolling by 24
  static: doAssert((NumRounds and 3) == 0, "The number of rounds must be a multiple of 4")
  for j in countup(0, NumRounds-1, 4):
    staticFor i, 0, 4:
      # θ₁: Column-parity via sum reduction in GF(2) (i.e. addition is xor)
      staticFor x, 0, 5:
        C[x] = A.N(i, x, 0) xor
                A.N(i, x, 1) xor
                A.N(i, x, 2) xor
                A.N(i, x, 3) xor
                A.N(i, x, 4)

      # θ₂: Sum adjacent column parities
      staticFor x, 0, 5:
        D[x] = C[(x+4) mod 5] xor rotl(C[(x+1) mod 5], 1)

      # Keccak state matrix is column major
      # so y should be the outer loop for cache-friendliness
      staticFor y, 0, 5:
        staticFor x, 0, 5:
          # θ₃: Diffusion
          # ρ: inter-slice diffusion
          # π: long-term diffusion
          B[(x + 2*y) mod 5] = rotl(A.N(i+1, x, y) xor D[x], Rho[N(1, x, y)])
        staticFor x, 0, 5:
          # χ: non-linearity
          A.N(i+1, x, y) = B[x] xor (not(B[(x+1) mod 5]) and B[(x+2) mod 5])

      # ι step: break symmetries
      A[0, 0] = A[0, 0] xor KRC[i+j]

template `^=`(accum: var SomeInteger, b: SomeInteger) =
  accum = accum xor b

func xorInSingle(H: var KeccakState, val: byte, offset: int) {.inline.} =
  ## Add a single byte in the Keccak state

  # Shift of 3    = log2(sizeof(byte) * 8) - Find the word to read/write
  # WordMask of 7 = sizeof(byte) * 8 - 1   - In the word, shift to the offset to read/write
  let slot = (offset and 7) shl 3
  let lane = uint64(val) shl slot # All bits but the one set in `val` are 0, and 0 is neutral element of xor
  H.state[offset shr 3] ^= lane

func xorInBlock_generic(H: var KeccakState, msg: array[200 - 2*32, byte]) {.inline.} =
  ## Add new data into the Keccak state
  # This can benefit from vectorized instructions
  for i in 0 ..< msg.len div 8:
    H.state[i] ^= uint64.fromBytes(msg, i*8, littleEndian)

func xorInPartial*(H: var KeccakState, msg: openArray[byte]) =
  ## Add multiple bytes to the state
  ## The length MUST be less than the state length.
  debug: doAssert msg.len <= H.state

  # Implementation detail:
  #   We could avoid an intermediate variable but
  #   dealing with non-multiple of size(T) length
  #   would be verbose, and require less than size(T)
  #   endianness handling.
  #   Furthermore 2 copies without the "multiple-of"
  #   tracking overhead might be faster, especially
  #   if the compiler vectorize the second one
  #   or is able to fuse the 2 together.
  #   Lastly, this is only called when transitioning
  #   between absorbing and squeezing, for hashing
  #   this means once, however long a message to hash is.
  var blck: array[200 - 2*32, byte] # zero-init
  rawCopy(blck, 0, msg, 0, msg.len)
  H.xorInBlock_generic(blck)

func copyOutWords[W: static int](
      H: KeccakState,
      dst: var array[W*8, byte]) {.inline.} =
  ## Read data from the Keccak state
  ## and write it into `dst`
  debug: doAssert dst.len <= sizeof(H.state)

  for w in 0 ..< W:
    let word = H.state[w]
    for i in 0 ..< 8:
      dst[w*8+i] = toByte(word shr (i*8))

func copyOutPartial*(
      H: KeccakState,
      hByteOffset: int,
      dst: var openArray[byte]) {.inline.} =
  ## Read data from the Keccak state
  ## and write it into `dst`
  ## starting from the state byte offset `hByteOffset`
  ## hByteOffset + dst length MUST be less than the Keccak rate
  debug: doAssert dst.len + hByteOffset <= sizeof(H.state.size)

  # Implementation details:
  #   we could avoid a temporary block
  #   see `xorInPartial` for rationale
  var blck {.noInit.}: array[200 - 2*32, byte]
  H.copyOutWords(blck)
  rawCopy(dst, 0, blck, hByteOffset, dst.len)

func pad*(H: var KeccakState, hByteOffset: int, delim: static byte, rate: static int) {.inline.} =
  debug: doAssert hByteOffset < rate
  H.xorInSingle(delim, hByteOffset)
  H.xorInSingle(0x80, rate-1)

func hashMessageBlocks_generic*(
      H: var KeccakState,
      message: ptr UncheckedArray[byte],
      numBlocks: int) =
  ## Hash a message block by block
  ## Keccak block size is the rate: 64
  ## The state MUST be absorb ready
  ## i.e. previous operation cannot be a squeeze
  ##      a permutation is needed in-between

  var message = message
  const rate = 200 - 2*32 # TODO: make a generic Keccak state with auto-derived rate
  const numRounds = 24    # TODO: auto derive number of rounds
  for _ in 0 ..< numBlocks:
    let msg = cast[ptr array[rate, byte]](message)
    H.xorInBlock_generic(msg[])
    H.permute_generic(numRounds)
    message +%= rate

func squeezeDigestBlocks_generic*(
      H: var KeccakState,
      digest: ptr UncheckedArray[byte],
      numBlocks: int) =
  ## Squeeze a digest block by block
  ## Keccak block digest is the rate: 64
  ## The state MUST be squeeze ready
  ## i.e. previous operation cannot be an absorb
  ##      a permutation is needed in-between
  var digest = digest
  const rate = 200 - 2*32 # TODO: make a generic Keccak state with auto-derived rate
  const numRounds = 24    # TODO: auto derive number of rounds
  for _ in 0 ..< numBlocks:
    let msg = cast[ptr array[rate, byte]](digest)
    H.copyOutWords(msg[])
    H.permute_generic(numRounds)
    digest +%= rate