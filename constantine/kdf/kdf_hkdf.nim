# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../hashes,
  ../mac/mac_hmac,
  ../platforms/[primitives, views]

# HMAC-based Extract-and-Expand Key Derivation Function (HKDF)
# ------------------------------------------------------------
#
# https://datatracker.ietf.org/doc/html/rfc5869

{.push raises: [].} # No exceptions

type HKDF*[H: CryptoHash] = object
  hmac: HMAC[H]

func clear*(ctx: var HKDF) {.inline.} =
  ctx.hmac.clear()

func hkdf_extract_init*[H: CryptoHash](
       ctx: var HKDF[H],
       salt: openArray[byte],
       ikm: openArray[byte]) {.inline.}=
  ctx.hmac.init(salt)
  ctx.hmac.update(ikm)

func hkdf_extract_append_to_IKM*[H: CryptoHash](
       ctx: var HKDF[H], append: openArray[byte]) {.inline.} =
  ctx.hmac.update(append)

func hkdf_extract_finish*[H: CryptoHash, N: static int](
       ctx: var HKDF[H], prk: var array[N, byte]) {.inline.} =
  ## Allows appending to IKM without allocating it on the heap
  static: doAssert H.digestSize == N
  ctx.hmac.finish(prk)

func hkdfExtract*[H: CryptoHash; N: static int](
                     ctx: var HKDF[H],
                     prk: var array[N, byte],
                     salt: openArray[byte],
                     ikm: openArray[byte]) {.inline.} =
  ## "Extract" step of HKDF.
  ## Extract a fixed size pseudom-random key
  ## from an optional salt value
  ## and a secret input keying material.
  ##
  ## Inputs:
  ## - salt: a buffer to an optional salt value (set to nil if unused)
  ## - ikm: "input keying material", the secret value to hash.
  ##        If a protocol needs to append to the IKM, it is recommended
  ##        to use the:
  ##          hkdf_extract_init,
  ##          hkdf_extract_append_to_IKM
  ##          hkdf_extract_finish
  ##        to avoid allocating and exposing secrets to the heap.
  ##
  ## Output:
  ## - prk: a pseudo random key of fixed size. The size is the same as the cryptographic hash chosen.
  ##
  ## Temporary:
  ## - ctx: a HMAC["cryptographic-hash"] context, for example HMAC[sha256].

  static: doAssert N == H.digestSize()

  ctx.hkdf_extract_init(salt, ikm)
  ctx.hkdf_extract_finish(prk)

iterator hkdfExpandChunk*[H: CryptoHash; N: static int](
          ctx: var HKDF[H],
          chunk: var array[N, byte],
          prk: array[N, byte],
          info: openArray[byte],
          append: openArray[byte]): int =
  ## "Expand" step of HKDF, with an iterator with up to 255 iterations.
  ##
  ## Note: The output MUST be at most 255 iterations as per RFC5869
  ##       https://datatracker.ietf.org/doc/html/rfc5869
  ##
  ## Expand a fixed size pseudo random-key
  ## into several pseudo-random keys
  ##
  ## Inputs:
  ## - prk: a pseudo random key (PRK) of fixed size. The size is the same as the cryptographic hash chosen.
  ## - info: optional context and application specific information (set to nil if unused)
  ## - append:
  ##   Compared to the spec we add a specific append procedure to do
  ##   OKM = HKDF-Expand(PRK, key_info || I2OSP(L, 2), L)
  ##   without having additional allocation on the heap
  ## Input/Output:
  ## - chunk:
  ##   In:  OKMᵢ₋₁ (output keying material chunk i-1)
  ##   Out: OKMᵢ (output keying material chunk i).
  ##
  ## Output:
  ## - returns the current chunk number i
  ##
  ## Temporary:
  ## - ctx: a HMAC["cryptographic-hash"] context, for example HMAC[sha256].
  ##
  ## After iterating, the HKDF context should be cleared
  ## if secret keying material was used.

  const HashLen = H.digestSize()
  static: doAssert N == HashLen

  {.push checks: off.} # No OverflowError or IndexError allowed
  for i in 0 ..< 255:
    ctx.hmac.init(prk)
    # T(0) = empty string
    if i != 0:
      ctx.hmac.update(chunk)
    ctx.hmac.update(info)
    ctx.hmac.update(append)
    ctx.hmac.update([uint8(i)+1]) # For byte 255, this append "0" and not "256"
    ctx.hmac.finish(chunk)

    yield i

func hkdfExpand*[H: CryptoHash; K: static int](
                    ctx: var HKDF[H],
                    output: var openArray[byte],
                    prk: array[K, byte],
                    info: openArray[byte],
                    append: openArray[byte],
                    clearMem = false) =
  ## "Expand" step of HKDF
  ## Expand a fixed size pseudo random-key
  ## into several pseudo-random keys
  ##
  ## Inputs:
  ## - prk: a pseudo random key (PRK) of fixed size. The size is the same as the cryptographic hash chosen.
  ## - info: optional context and application specific information (set to nil if unused)
  ## - append:
  ##   Compared to the spec we add a specific append procedure to do
  ##   OKM = HKDF-Expand(PRK, key_info || I2OSP(L, 2), L)
  ##   without having additional allocation on the heap
  ## Output:
  ## - output: OKM (output keying material). The PRK is expanded to match
  ##           the output length, the result is stored in output.
  ##
  ## Temporary:
  ## - ctx: a HMAC["cryptographic-hash"] context, for example HMAC[sha256].

  const HashLen = H.digestSize()
  static: doAssert K == HashLen

  debug:
    doAssert output.len <= 255*HashLen

  var t{.noInit.}: array[HashLen, byte]

  {.push checks: off.} # No OverflowError or IndexError allowed
  for i in ctx.hkdfExpandChunk(t, prk, info, append):
    let iStart = i * HashLen
    let size = min(HashLen, output.len - iStart)
    rawCopy(output, iStart, t, 0, size)

    if iStart+HashLen >= output.len:
      break

  if clearMem:
    ctx.clear()

func hkdfExpand*[H: CryptoHash; K: static int](
                    ctx: var HKDF[H],
                    output: var openArray[byte],
                    prk: array[K, byte],
                    info: openArray[byte],
                    clearMem = false) {.inline.} =
  ## "Expand" step of HKDF
  ## Expand a fixed size pseudo random-key
  ## into several pseudo-random keys
  ##
  ## Inputs:
  ## - prk: a pseudo random key (PRK) of fixed size. The size is the same as the cryptographic hash chosen.
  ## - info: optional context and application specific information (set to nil if unused)
  ## Output:
  ## - output: OKM (output keying material). The PRK is expanded to match
  ##           the output length, the result is stored in output.
  ##
  ## Temporary:
  ## - ctx: a HMAC["cryptographic-hash"] context, for example HMAC[sha256].
  hkdfExpand(ctx, output, prk, info, default(array[0, byte]), clearMem)

func hkdf*[H: CryptoHash, N: static int](
       Hash: typedesc[H],
       output: var openArray[byte],
       salt: openArray[byte],
       ikm: openArray[byte],
       info: openArray[byte],
       clearMem = false) {.inline, genCharAPI.} =
  ## HKDF
  ## Inputs:
  ## - A hash function, with an output digest length HashLen
  ## - An opttional salt value (non-secret random value), if not provided,
  ##   it is set to an array of HashLen zero bytes
  ## - A secret Input Keying Material
  ## - info: an optional context and application specific information for domain separation
  ##   it can be an empty string
  var ctx{.noInit.}: HMAC[H]
  var prk{.noInit.}: array[H.digestSize(), byte]
  ctx.hkdfExtract(prk, salt, ikm)
  ctx.hkdfExpand(output, prk, info, clearMem)
