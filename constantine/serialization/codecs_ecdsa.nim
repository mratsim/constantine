# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

##[

Performs (de-)serialization of ECDSA signatures into ASN.1 DER encoded
data following SEC1:

https://www.secg.org/sec1-v2.pdf

In contrast to `codecs_ecdsa_secp256k1.nim` this file is generic under the choice
of elliptic curve.
]##

#import
#  constantine/named/algebras,
#  constantine/platforms/primitives,
#  constantine/platforms/abstractions,
#  constantine/math/arithmetic/finite_fields,
#  constantine/math/elliptic/ec_shortweierstrass_affine,
#  constantine/math/io/io_bigints

import
  constantine/hashes,
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields, io_ec],
  constantine/math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_jacobian, ec_scalar_mul, ec_multi_scalar_mul],
  constantine/math/[arithmetic, ec_shortweierstrass],
  constantine/platforms/[abstractions, views],
  constantine/serialization/codecs, # for fromHex and (in the future) base64 encoding
  constantine/mac/mac_hmac, # for deterministic nonce generation via RFC 6979
  constantine/named/zoo_generators, # for generator
  constantine/csprngs/sysrand,
  constantine/signatures/common_signature_ops # for `derivePubkey`

type
  ## Helper type for ASN.1 DER signatures to avoid allocation.
  ## Has a `data` buffer of 72 bytes (maximum possible size for
  ## a signature for `secp256k1`) and `len` of actually used data.
  ## `data[0 ..< len]` is the actual signature.
  DERSignature*[N: static int] = object
    data*: array[N, byte] # Max size: 6 bytes overhead + 33 bytes each for r,s
    len*: int # Actual length used

template DERSigSize*(Name: static Algebra): int =
  6 + 2 * (Fr[Name].bits.ceilDiv_vartime(sizeof(pointer)) + 1)

proc toDER*[Name: static Algebra; N: static int](derSig: var DERSignature[N], r, s: Fr[Name]) =
  ## Converts signature (r,s) to DER format without allocation.
  ## Max size is 72 bytes (for Secp256k1 or any curve with 32 byte scalars in `Fr`):
  ## 6 bytes overhead + up to 32+1 bytes each for r,s.
  ## 6 byte 'overhead' for:
  ## - `0x30` byte SEQUENCE designator
  ## - total length of the array
  ## - integer type designator `0x02` (before `r` and `s`)
  ## - length of `r` and `s`
  ##
  ## Implementation follows ideas of Bitcoin's secp256k1 implementation:
  ## https://github.com/bitcoin-core/secp256k1/blob/f79f46c70386c693ff4e7aef0b9e7923ba284e56/src/ecdsa_impl.h#L171-L193

  const WordSize = sizeof(BaseType)
  const N = Fr[Name].bits.ceilDiv_vartime(WordSize) # 32 for `secp256k1`

  template toByteArray(x: Fr[Name]): untyped =
    ## Convert to a 33 byte array. Leading zero byte required if
    ## first real byte (idx 1) highest bit set (> 0x80).
    var a: array[N+1, byte]
    discard toOpenArray[byte](a, 1, N).marshal(x.toBig(), bigEndian)
    a

  # 1. Prepare the data & determine required sizes

  # Convert r,s to big-endian bytes
  var rBytes = r.toByteArray()
  var sBytes = s.toByteArray()
  var rLen = N + 1
  var sLen = N + 1

  # Skip leading zeros but ensure high bit constraint
  var rPos = 0
  while rLen > 1 and rBytes[rPos] == 0 and (rBytes[rPos+1] < 0x80.byte):
    dec rLen
    inc rPos
  var sPos = 0
  while sLen > 1 and sBytes[sPos] == 0 and (sBytes[sPos+1] < 0x80.byte):
    dec sLen
    inc sPos

  # Set total length
  derSig.len = 6 + rLen + sLen


  # 2. Write the actual data
  var pos = 0
  template setInc(val: byte): untyped =
    # Set `val` at `pos` and increase `pos`
    derSig.data[pos] = val
    inc pos

  # Write DER structure, global
  setInc 0x30                   # sequence
  setInc (4 + rLen + sLen).byte # total length

  # `r` prefix
  setInc 0x02                   # integer
  setInc rLen.byte              # length of `r`
  # Write `r` bytes in valid region
  derSig.data.rawCopy(pos, rBytes, rPos, rLen)
  inc pos, rLen

  # `s` prefix
  setInc 0x02                   # integer
  setInc sLen.byte              # length of `s`
  # Write `s` bytes in valid region
  derSig.data.rawCopy(pos, sBytes, sPos, sLen)
  inc pos, sLen

  assert derSig.len == pos

proc fromRawDER*(r, s: var array[32, byte], sig: openArray[byte]): bool =
  ## Extracts the `r` and `s` values from a given DER signature.
  ##
  ## Returns `true` if the input is a valid DER encoded signature
  ## for `secp256k1` (or any curve with 32 byte scalars).
  var pos = 0

  template checkInc(val: untyped): untyped =
    if pos > sig.high or sig[pos] != val:
      # Invalid signature
      return false
    inc pos
  template readInc(val: untyped): untyped =
    if pos > sig.high:
      return false
    val = sig[pos]
    inc pos

  checkInc(0x30) # SEQUENCE
  var totalLen: byte; readInc(totalLen)

  template parseElement(el: var array[32, byte]): untyped =
    var eLen: byte; readInc(eLen) # len of `r`
    if pos + eLen.int > sig.len: # would need more data than available
      return false
    # read `r` into *last* `rLen` bytes
    var eStart = el.len - eLen.int
    if eStart < 0: # indicates prefix 0 due to first byte >= 0x80 (highest bit set)
      doAssert eLen == 33
      inc pos # skip first byte
      eStart = 0 # start from 0 in `el`
      dec eLen # decrease eLen by 1
    el.rawCopy(eStart, sig, pos, eLen.int)
    inc pos, eLen.int

  # `r`
  checkInc(0x02) # INTEGER
  parseElement(r)

  # `s`
  checkInc(0x02) # INTEGER
  parseElement(s)

  # NOTE: `totalLen` does not include the prefix [0x30, totalLen] 2 bytes. Hence -2.
  assert pos - 2 == totalLen.int, "Pos = " & $pos & ", totalLen = " & $totalLen

  result = true

proc fromDER*(r, s: var array[32, byte], derSig: DERSignature) =
  ## Splits a given `DERSignature` back into the `r` and `s` elements as
  ## raw byte arrays.
  fromRawDER(r, s, derSig.data)
