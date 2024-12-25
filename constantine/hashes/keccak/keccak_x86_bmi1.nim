# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./keccak_generic

# Notes:
# - AVX2 makes thing **slower**
# - BMI2 makes the compiler use RORX everywhere
#   but
#   - hardware already has instruction-level parallelism (ILP)
#     when modified flags are not consumed by next instructions
#   - compiler generates RORX everywhere even when self-rotating a register
#     and the instructions is 2x bigger than ROL/ROR so it hurts instruction cache.
#   - benchmarks appear to be the same
{.localpassC:"-mbmi".}

func permute_x86_bmi1*(A: var KeccakState, NumRounds: static int) =
  permute_impl(A, NumRounds)

func xorInPartial_x86_bmi1*(H: var KeccakState, hByteOffset: int, msg: openArray[byte]) =
  ## Add multiple bytes to the state
  ## The hByteOffset+length MUST be less than the state length.
  xorInPartial_impl(H, hByteOffset, msg)

func copyOutPartial_x86_bmi1*(
      H: KeccakState,
      hByteOffset: int,
      dst: var openArray[byte]) {.inline.} =
  ## Read data from the Keccak state
  ## and write it into `dst`
  ## starting from the state byte offset `hByteOffset`
  ## hByteOffset + dst length MUST be less than the Keccak rate
  copyOutPartial_impl(H, hByteOffset, dst)

func hashMessageBlocks_x86_bmi1*(
      H: var KeccakState,
      message: ptr UncheckedArray[byte],
      numBlocks: int) =
  ## Hash a message block by block
  ## Keccak block size is the rate: 64
  ## The state MUST be absorb ready
  ## i.e. previous operation cannot be a squeeze
  ##      a permutation is needed in-between
  hashMessageBlocks_impl(H, message, numBlocks)

func squeezeDigestBlocks_x86_bmi1*(
      H: var KeccakState,
      digest: ptr UncheckedArray[byte],
      numBlocks: int) =
  ## Squeeze a digest block by block
  ## Keccak block digest is the rate: 64
  ## The state MUST be squeeze ready
  ## i.e. previous operation cannot be an absorb
  ##      a permutation is needed in-between
  squeezeDigestBlocks_impl(H, digest, numBlocks)