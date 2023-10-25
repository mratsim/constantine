# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  ../../platforms/[abstractions, allocs, bithacks],
  ./limbs_views,
  ./limbs_multiprec,
  ./limbs_fixedprec,
  ./limbs_divmod_vartime

# No exceptions allowed
{.push raises: [], checks: off.}

# ############################################################
#
#         Arbitrary-precision Montgomery Arithmetic
#
# ############################################################

# Montgomery magic constants
# ------------------------------------------

func oneMont_vartime*(r: var openArray[SecretWord], M: openArray[SecretWord]) {.noInline, meter.} =
  ## Returns 1 in Montgomery domain:
  let t = allocStackArray(SecretWord, M.len + 1)
  zeroMem(t, M.len*sizeof(SecretWord))
  t[M.len] = One

  discard r.reduce_vartime(t.toOpenArray(0, M.len), M)


# Montgomery multiplication
# ------------------------------------------

func mulMont_FIPS*(
       r: LimbsViewMut,
       a, b: distinct LimbsViewAny,
       M: LimbsViewConst,
       m0ninv: SecretWord,
       mBits: int,
       skipFinalSub: static bool = false) {.noInline, tags:[Alloca], meter.} =
  ## Montgomery Multiplication using Finely Integrated Product Scanning (FIPS)
  ##
  ## This maps
  ## - [0, 2p) -> [0, 2p) with skipFinalSub
  ## - [0, 2p) -> [0, p) without
  ##
  ## skipFinalSub skips the final substraction step.
  # - Architectural Enhancements for Montgomery
  #   Multiplication on Embedded RISC Processors
  #   Johann Großschädl and Guy-Armand Kamendje, 2003
  #   https://pure.tugraz.at/ws/portalfiles/portal/2887154/ACNS2003_AEM.pdf
  #
  # - New Speed Records for Montgomery Modular
  #   Multiplication on 8-bit AVR Microcontrollers
  #   Zhe Liu and Johann Großschädl, 2013
  #   https://eprint.iacr.org/2013/882.pdf
  let L = wordsRequired(mBits)
  var z = LimbsViewMut allocStackArray(SecretWord, L)
  z.setZero(L)

  var t, u, v = Zero

  for i in 0 ..< L:
    for j in 0 ..< i:
      mulAcc(t, u, v, a[j], b[i-j])
      mulAcc(t, u, v, z[j], M[i-j])
    mulAcc(t, u, v, a[i], b[0])
    z[i] = v * m0ninv
    mulAcc(t, u, v, z[i], M[0])
    v = u
    u = t
    t = Zero
  for i in L ..< 2*L:
    for j in i-L+1 ..< L:
      mulAcc(t, u, v, a[j], b[i-j])
      mulAcc(t, u, v, z[j], M[i-j])
    z[i-L] = v
    v = u
    u = t
    t = Zero

  when not skipFinalSub:
    discard z.csub(M, v.isNonZero() or not(z.lt(M, L)), L)
  r.copyWords(0, z, 0, L)

# Montgomery conversions
# ------------------------------------------

func fromMont*(r: LimbsViewMut, a: LimbsViewAny, M: LimbsViewConst,
               m0ninv: SecretWord, mBits: int) {.noInline, tags:[Alloca], meter.} =
  ## Transform a bigint ``a`` from it's Montgomery N-residue representation (mod N)
  ## to the regular natural representation (mod N)
  ##
  ## with W = M.len
  ## and R = (2^WordBitWidth)^W
  ##
  ## Does "a * R^-1 (mod M)" = montMul(a, 1)
  ##
  ## This is called a Montgomery Reduction
  ## The Montgomery Magic Constant is µ = -1/N mod M
  ## is used internally and can be precomputed with m0ninv(Curve)
  let N = wordsRequired(mBits)
  var t = LimbsViewMut allocStackArray(SecretWord, N)
  t.copyWords(0, a, 0, N)

  for i in 0 ..< N:
    let m = t[0] * m0ninv
    var C, lo: SecretWord
    muladd1(C, lo, m, M[0], t[0])
    for j in 1 ..< N:
      muladd2(C, t[j-1], m, M[j], C, t[j])
    t[N-1] = C

  discard t.csub(M, not(t.lt(M, N)), N)
  r.copyWords(0, t, 0, N)

func getMont*(r: LimbsViewMut, a: LimbsViewAny, M, r2modM: LimbsViewConst,
                   m0ninv: SecretWord, mBits: int) {.inline, meter.} =
  ## Transform a bigint ``a`` from it's natural representation (mod N)
  ## to a the Montgomery n-residue representation
  ##
  ## Montgomery-Multiplication - based
  ##
  ## with W = M.len
  ## and R = (2^WordBitWidth)^W
  ##
  ## Does "a * R (mod M)"
  ##
  ## `a`: The source BigInt in the natural representation. `a` in [0, N) range
  ## `M`: The field modulus. M must be odd.
  ## `r2modM`: 2^WordBitWidth mod `M`. Can be precomputed with `r2mod` function
  ##
  ## Important: `r` is overwritten
  ## The result `r` buffer size MUST be at least the size of `M` buffer
  # Reference: https://eprint.iacr.org/2017/1057.pdf
  mulMont_FIPS(r, a, r2ModM, M, m0ninv, mBits)

func getMont_vartime*(r: var openArray[SecretWord], a, M: openArray[SecretWord]) {.noInline, meter.} =
  ## Transform a bigint ``a`` from it's natural representation (mod N)
  ## to a the Montgomery n-residue representation
  ##
  ## Shift + reduction based
  let aBits  = a.getBits_LE_vartime()
  let mBits  = M.getBits_LE_vartime()
  let L      = wordsRequired(mBits)
  let aR_len = wordsRequired(aBits) + L

  var aR_buf = allocStackArray(SecretWord, aR_len)
  template aR: untyped = aR_Buf.toOpenArray(0, aR_len - 1)

  aR.shiftLeft_vartime(a, WordBitWidth * L)
  discard r.reduce_vartime(aR, M)

# Montgomery Modular Exponentiation
# ------------------------------------------
# We use fixed-window based exponentiation
# that is constant-time: i.e. the number of multiplications
# does not depend on the number of set bits in the exponents
# those are always done and conditionally copied.
#
# The exponent MUST NOT be private data (until audited otherwise)
# - Power attack on RSA, https://www.di.ens.fr/~fouque/pub/ches06.pdf
# - Flush-and-reload on Sliding window exponentiation: https://tutcris.tut.fi/portal/files/8966761/p1639_pereida_garcia.pdf
# - Sliding right into disaster, https://eprint.iacr.org/2017/627.pdf
# - Fixed window leak: https://www.scirp.org/pdf/JCC_2019102810331929.pdf
# - Constructing sliding-windows leak, https://easychair.org/publications/open/fBNC
#
# For pairing curves, this is the case since exponentiation is only
# used for inversion via the Little Fermat theorem.
# For RSA, some exponentiations uses private exponents.
#
# Note:
# - Implementation closely follows Thomas Pornin's BearSSL
# - Apache Milagro Crypto has an alternative implementation
#   that is more straightforward however:
#   - the exponent hamming weight is used as loop bounds
#   - the baseᵏ is stored at each index of a temp table of size k
#   - the baseᵏ to use is indexed by the hamming weight
#     of the exponent, leaking this to cache attacks
#   - in contrast BearSSL touches the whole table to
#     hide the actual selection

template checkPowScratchSpaceLen(bufLen, wordLen: int) =
  ## Checks that there is a minimum of scratchspace to hold the temporaries
  debug:
    assert bufLen >= 2*wordLen, "Internal Error: the scratchspace for powmod should be equal or greater than 2"

func getWindowLen(bufLen, wordLen: int): uint =
  ## Compute the maximum window size that fits in the scratchspace buffer
  checkPowScratchSpaceLen(bufLen, wordLen)
  result = 5
  while ((1 shl result) + 1)*wordLen > bufLen:
    dec result

func precomputeWindow(
       a: LimbsViewMut,
       M, one: LimbsViewConst,
       m0ninv: SecretWord,
       scratchspace: LimbsViewMut,
       wordLen: int,
       mBits: int,
       windowLen: uint) =
  # Precompute window content, special case for window = 1
  # (i.e scratchspace has only space for 2 temporaries)
  # The content scratchspace[2+k] is set at aᵏ
  # with scratchspace[0] untouched
  if windowLen == 1:
    scratchspace.copyWords(1*wordLen, a, 0, wordLen)
  else:
    scratchspace.copyWords(2*wordLen, a, 0, wordLen)
    for k in 2 ..< 1 shl windowLen:
      let sk1 = cast[LimbsViewMut](scratchspace[(k+1)*wordLen].addr)
      let sk = cast[LimbsViewConst](scratchspace[k*wordLen].addr)
      sk1.mulMont_FIPS(sk, a, M, m0ninv, mBits)

  # Set a to one
  a.copyWords(0, one, 0, wordLen)

func powMontPrologue(
       a: LimbsViewMut, M, one: LimbsViewConst,
       m0ninv: SecretWord,
       scratchspace: LimbsViewMut,
       scratchLen: int,
       mBits: int): uint {.tags:[Alloca], meter.} =
  ## Setup the scratchspace
  ## Returns the fixed-window size for exponentiation with window optimization.
  # Precompute window content, special case for window = 1
  # (i.e scratchspace has only space for 2 temporaries)
  # The content scratchspace[2+k] is set at aᵏ
  # with scratchspace[0] untouched
  let wordLen = wordsRequired(mBits)
  result = scratchLen.getWindowLen(wordLen)
  precomputeWindow(
    a, M, one,
    m0ninv, scratchSpace,
    wordLen, mBits,
    result)

func powMontSquarings(
        a: LimbsViewMut,
        exponent: openarray[byte],
        M: LimbsViewConst,
        m0ninv: SecretWord,
        mBits: int,
        tmp: LimbsViewMut,
        window: uint,
        acc, acc_len: var uint,
        e: var int): tuple[k, bits: uint] {.inline, meter.}=
  ## Squaring step of exponentiation by squaring
  ## Get the next k bits in range [1, window)
  ## Square k times
  ## Returns the number of squarings done and the corresponding bits
  ##
  ## Updates iteration variables and accumulators
  # Due to the high number of parameters,
  # forcing this inline actually reduces the code size
  #
  # ⚠️: Extreme care should be used to not leak
  #    the exponent bits nor its real bitlength
  #    i.e. if the exponent is zero but encoded in a
  #    256-bit integer, only "256" should leak
  #    as for some application like RSA
  #    the exponent might be the user secret key.

  # Get the next bits
  # acc/acc_len must be uint to avoid Nim runtime checks leaking bits
  # acc/acc_len must be uint to avoid Nim runtime checks leaking bits
  # e is public
  var k = window
  if acc_len < window:
    if e < exponent.len:
      acc = (acc shl 8) or exponent[e].uint
      inc e
      acc_len += 8
    else: # Drained all exponent bits
      k = acc_len

  let bits = (acc shr (acc_len - k)) and ((1'u32 shl k) - 1)
  acc_len -= k

  # We have k bits and can do k squaring
  for i in 0 ..< k:
    a.mulMont_FIPS(a, a, M, m0ninv, mBits)

  return (k, bits)

func powMont*(
       a: LimbsViewMut,
       exponent: openarray[byte],
       M, one: LimbsViewConst,
       m0ninv: SecretWord,
       scratchspace: LimbsViewMut,
       scratchLen: int,
       mBits: int) {.meter.} =
  ## Modular exponentiation r = a^exponent mod M
  ## in the Montgomery domain
  ##
  ## This uses fixed-window optimization if possible
  ##
  ## - On input ``a`` is the base, on ``output`` a = a^exponent (mod M)
  ##   ``a`` is in the Montgomery domain
  ## - ``exponent`` is the exponent in big-endian canonical format (octet-string)
  ##   Use ``marshal`` for conversion
  ## - ``M`` is the modulus
  ## - ``one`` is 1 (mod M) in montgomery representation
  ## - ``m0ninv`` is the montgomery magic constant "-1/M[0] mod 2^WordBitWidth"
  ## - ``scratchspace`` with k the window bitsize of size up to 5
  ##   This is a buffer that can hold between 2 and up to 2ᵏ + 1 big-ints
  ##   A window of 1-bit (no window optimization) requires only 2 big-ints
  ##
  ## Note that the best window size require benchmarking and is a tradeoff between
  ## - performance
  ## - stack usage
  ## - precomputation
  ##
  ## For example BLS12-381 window size of 5 is 30% faster than no window,
  ## but windows of size 2, 3, 4 bring no performance benefit, only increased stack space.
  ## A window of size 5 requires (2^5 + 1)*(381 + 7)/8 = 33 * 48 bytes = 1584 bytes
  ## of scratchspace (on the stack).

  let N = wordsRequired(mBits)
  let window = powMontPrologue(a, M, one, m0ninv, scratchspace, scratchLen, mBits)

  # We process bits with from most to least significant.
  # At each loop iteration with have acc_len bits in acc.
  # To maintain constant-time the number of iterations
  # or the number of operations or memory accesses should be the same
  # regardless of acc & acc_len
  var
    acc, acc_len: uint
    e = 0

  let s0 = cast[LimbsViewMut](scratchspace[0].addr)
  let s1 = cast[LimbsViewConst](scratchspace[1*N].addr)

  while acc_len > 0 or e < exponent.len:
    let (k, bits) = powMontSquarings(
      a, exponent, M, m0ninv, mBits,
      s0, window,
      acc, acc_len, e)

    # Window lookup: we set scratchspace[1] to the lookup value.
    # If the window length is 1, then it's already set.
    if window > 1:
      # otherwise we need a constant-time lookup
      # in particular we need the same memory accesses, we can't
      # just index the openarray with the bits to avoid cache attacks.
      for i in 1 ..< 1 shl k:
        let ctl = SecretWord(i) == SecretWord(bits)
        scratchspace.ccopyWords(1*N, scratchspace, (1+i)*N, ctl, N)

    # Multiply with the looked-up value
    # we keep the product only if the exponent bits are not all zeroes
    s0.mulMont_FIPS(a, s1, M, m0ninv, mBits)
    a.ccopyWords(0, s0, 0, SecretWord(bits).isNonZero(), N)

# Montgomery Modular Exponentiation (vartime)
# -------------------------------------------

func getWindowLen_vartime(bufLen, expLen, wordLen: int): uint =
  ## Compute the maximum window size that fits in the scratchspace buffer
  if expLen == 1:
    return 1
  else:
    return getWindowLen(bufLen, wordLen)

func powMontPrologue_vartime(
       a: LimbsViewMut,
       expLen: int,
       M, one: LimbsViewConst,
       m0ninv: SecretWord,
       scratchspace: LimbsViewMut,
       scratchLen: int,
       mBits: int): uint {.tags:[Alloca], meter.} =
  ## Setup the scratchspace
  ## Returns the fixed-window size for exponentiation with window optimization.
  # Precompute window content, special case for window = 1
  # (i.e scratchspace has only space for 2 temporaries)
  # The content scratchspace[2+k] is set at aᵏ
  # with scratchspace[0] untouched
  let wordLen = wordsRequired(mBits)
  result = scratchLen.getWindowLen_vartime(expLen, wordLen)
  precomputeWindow(
    a, M, one,
    m0ninv, scratchSpace,
    wordLen, mBits,
    result)

func powMont_vartime*(
       a: LimbsViewMut,
       exponent: openArray[byte],
       M, one: LimbsViewConst,
       m0ninv: SecretWord,
       scratchspace: LimbsViewMut,
       scratchLen: int,
       mBits: int) {.tags:[VarTime, Alloca], meter.} =
  ## Modular exponentiation a <- a^exponent (mod M)
  ## in the Montgomery domain
  ##
  ## Warning ⚠️ :
  ## This is an optimization for public exponent
  ## Otherwise bits of the exponent can be retrieved with:
  ## - memory access analysis
  ## - power analysis
  ## - timing analysis

  # TODO: scratchspace[1] is unused when window > 1
  let N = wordsRequired(mBits)
  let eBits = exponent.getBits_BE_vartime()
  let eBytes = bytesRequired(eBits)

  let window = powMontPrologue_vartime(a, eBytes, M, one, m0ninv, scratchspace, scratchLen, mBits)

  var
    acc, acc_len: uint
    e = 0

  let s0 = cast[LimbsViewMut](scratchspace[0].addr)
  let s1 = cast[LimbsViewConst](scratchspace[1*N].addr)

  while acc_len > 0 or e < eBytes:
    let (_, bits) = powMontSquarings(
      a,
      exponent.toOpenArray(exponent.len - eBytes, exponent.len-1), # BigEndian slicing
      M, m0ninv, mBits,
      s0, window,
      acc, acc_len, e)

    ## Warning ⚠️: Exposes the exponent bits
    if bits != 0:
      if window > 1:
        let sBits = cast[LimbsViewConst](scratchspace[int(1+bits)*N].addr)
        s0.mulMont_FIPS(a, sBits, M, m0ninv, mBits)
      else:
        # scratchspace[1] holds the original `a`
        s0.mulMont_FIPS(a, s1, M, m0ninv, mBits)
      a.copyWords(0, s0, 0, N)

{.pop.}