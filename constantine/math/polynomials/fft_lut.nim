# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/io/[io_fields, io_bigints]

# TODO automate this
# we can precompute everything in Sage
# and auto-generate the file.

# SageMath:
# `GF(0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001).primitive_element()`
const BLS12_381_Fr_primitive_root = 7

# SageMath:
# `GF(0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001).primitive_element()`
const BN254_Snarks_Fr_primitive_root = 5

#[
def precomp_ts(Fq):
    ## From q = p^m with p the prime characteristic of the field Fp^m
    ##
    ## Returns (s, e) such as
    ## q == s * 2^e + 1
    s = Fq.order() - 1
    e = 0
    while s & 1 == 0:
        s >>= 1
        e += 1
    return s, e

def find_any_qnr(Fq):
    ## Find a quadratic Non-Residue
    ## in GF(p^m)
    qnr = Fq(Fq.gen())
    r = Fq.order()
    while qnr.is_square():
        qnr += 1
    return qnr

s, e = precomp_ts(Fr)
qnr = find_any_qnr(Fr)
root_unity = qnr^s
]#


proc decomposeFieldOrder(F: type Fr): tuple[s: F, e: uint64] =
  ## Decomposes the field order of the given field into the form
  ##
  ## `q = s * 2^e + 1`
  ##
  ## where `q = p^m` with `p` the prime characteristic of the field Fp^m.
  # `s = p - 1`
  var s {.noInit.}: BigInt[F.bits()]
  s = F.getModulus()
  debugecho "Exp: ", s.tohex()
  s -= One

  # `e = 0`
  var e: uint64

  while s.isEven().bool:
    s.shiftRight(1)
    #e += F.fromUint(1'u64)
    inc e
  result = (s: F.fromBig(s), e: e)

proc findAnyQnr(F: type Fr): F =
  ## Returns the first quadratic non-residue found, i.e. a
  ## number in `F`, which is not a square in the field.
  ##
  ## That is, a `q` if there is no `x` in the field such that:
  ## `x² ≡ q (mod p)`
  let one = F.fromUint(1'u64)
  var qnr {.noInit.}: F
  qnr = one # Start with `1`
  while qnr.isSquare().bool:
    qnr += one
  result = qnr

func buildRootLUT(F: type Fr, primitive_root: uint64): array[32, F] =
  ## [pow(PRIMITIVE_ROOT, (MODULUS - 1) // (2**i), MODULUS) for i in range(32)]

  ##
  ## XXX: For some reason this does not work for BN254_Snarks (haven't tried with BLS12-381)

  let (s, e) = decomposeFieldOrder(F)
  let qnr = findAnyQnr(F)

  #var exponent {.noInit.}: BigInt[F.bits()]
  #exponent = F.getModulus()
  #debugecho "Exp: ", exponent.tohex()
  #exponent -= One
  #
  ## Start by the end
  #var i = result.len - 1
  #exponent.shiftRight(i)
  #debugecho "last Exponent : ", exponent.toHex()
  #result[i].fromUint(primitive_root)
  #result[i].pow_vartime(exponent)


  var i = e.int #e.toDecimal() # largest possible power of 2 for this field
  var rootUnity = qnr
  rootUnity.pow_vartime(s)
  result[i] = rootUnity


  while i > 0:
    result[i-1].square(result[i])
    #debugecho "At ", i, ": ", result[i-1].toHex()

    dec i

  # debugEcho "Fr[BLS12_81] - Roots of Unity:"
  # for i in 0 ..< result.len:
  #   debugEcho "    ", i, ": ", result[i].toHex()
  # debugEcho "Fr[BLS12_81] - Roots of Unity -- FIN\n"

#let BLS12_381_Fr_ScaleToRootOfUnity* = buildRootLUT(Fr[BLS12_381], BLS12_381_Fr_primitive_root)
let BN254_Snarks_Fr_ScaleToRootOfUnity* = buildRootLUT(Fr[BN254_Snarks], BN254_Snarks_Fr_primitive_root)
let g2 = BN254_Snarks_Fr_ScaleToRootOfUnity # [28 - order]
for i, el in g2:
  debugecho "ω^{2^", i, "} = ", el.toHex()

{.experimental: "dynamicBindSym".}
macro scaleToRootOfUnity*(Name: static Algebra): untyped =
  return bindSym($Name & "_Fr_ScaleToRootOfUnity")

macro primitiveRoot*(Name: static Algebra): untyped =
  return bindSym($Name & "_Fr_primitive_root")
