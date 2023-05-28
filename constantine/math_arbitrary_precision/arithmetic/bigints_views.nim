# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  ../../platforms/[abstractions, allocs],
  ../../math/config/precompute,
  ./limbs_views,
  ./limbs_montgomery,
  ./limbs_mod2k


import ../../math/config/type_bigint

# No exceptions allowed
{.push raises: [], checks: off.}

# ############################################################
#
#                 Arbitrary-precision integers
#
# ############################################################
#
# We only implement algorithms that work on views allocated by the caller
# as providing a full-blown arbitrary-precision library is not the goal.
# As the bigint sizes are relatively constrained
# in protocols we implement (4096 bits for RSA, 8192 bit s for the Ethereum EVM),
# this allows us to avoid heap allocations, which simplifies reentrancy and thread-safety.

# TODO: choose between:
# - openArray + countLeadingZeros
# - bits + numWordsFromBits
# for parameter passing
# This also impacts ergonomics of allocStackArray
#
# Also need to take into account constant-time for RSA
# i.e. countLeadingZeros can only be done on public moduli.

func powOddMod_vartime*(
       r: var openArray[SecretWord],
       a: openArray[SecretWord],
       exponent: openArray[byte],
       M: openArray[SecretWord],
       window: int) {.noInline, tags:[Alloca].} =
  ## r <- a^exponent (mod M) with M odd
  ##
  ## At least (2^window + 4) * sizeof(M) stack space will be allocated.
  ##
  ## TODO: we require the last M words to be != 0 (i.e. no extra zero words in modulus)

  debug:
    doAssert bool(M[0] and One)
    doAssert BaseType(M[M.len-1]) != 0

  let mBits = 1 + int(log2_vartime(BaseType M[M.len-1])) + int(WordBitWidth*(M.len - 1))
  let m0ninv = M[0].negInvModWord()
  var rMont      = allocStackArray(SecretWord, M.len)

  block:
    var r2Buf      = allocStackArray(SecretWord, M.len)
    template r2: untyped = r2Buf.toOpenArray(0, M.len-1)
    r2.r2_vartime(M)
    rMont.LimbsViewMut.getMont(a.view(), M.view(), LimbsViewConst r2.view(), m0ninv, mBits)

  block:
    var oneMontBuf = allocStackArray(SecretWord, M.len)
    template oneMont: untyped = oneMontBuf.toOpenArray(0, M.len-1)
    oneMont.oneMont_vartime(M)

    let scratchLen = M.len * ((1 shl window) + 1)
    var scratchSpace = allocStackArray(SecretWord, scratchLen)

    rMont.LimbsViewMut.powMont_vartime(
      exponent, M.view(), LimbsViewConst oneMontBuf,
      m0ninv, LimbsViewMut scratchSpace, scratchLen, mBits)

  r.view().fromMont(LimbsViewConst rMont, M.view(), m0ninv, mBits)
