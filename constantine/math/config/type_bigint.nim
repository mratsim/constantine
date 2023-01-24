# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ../../platforms/abstractions

func wordsRequired*(bits: int): int {.compileTime.} =
  ## Compute the number of limbs required
  # from the **announced** bit length
  (bits + WordBitWidth - 1) div WordBitWidth

type
  BigInt*[bits: static int] = object
    ## Fixed-precision big integer
    ##
    ## - "bits" is the announced bit-length of the BigInt
    ##   This is public data, usually equal to the curve prime bitlength.
    ##
    ## - "limbs" is an internal field that holds the internal representation
    ##   of the big integer. Least-significant limb first. Within limbs words are native-endian.
    ##
    ## This internal representation can be changed
    ## without notice and should not be used by external applications or libraries.
    limbs*: array[bits.wordsRequired, SecretWord]


debug:
  func toHex*(a: SecretWord): string =
    const hexChars = "0123456789abcdef"
    const L = 2*sizeof(SecretWord)
    result = newString(2 + L)
    result[0] = '0'
    result[1] = 'x'
    var a = a
    for j in countdown(result.len-1, 0):
      result[j] = hexChars.secretLookup(a and SecretWord 0xF)
      a = a shr 4

  func toString*(a: Limbs): string =
    result = "["
    result.add " " & toHex(a[0])
    for i in 1 ..< a.len:
      result.add ", " & toHex(a[i])
    result.add "]"

  func `$`*(a: BigInt): string =
    result = "BigInt["
    result.add $BigInt.bits
    result.add "](limbs: "
    result.add a.limbs.toString()
    result.add ")"
