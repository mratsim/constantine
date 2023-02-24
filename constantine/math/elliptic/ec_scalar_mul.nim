# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../config/curves,
  ../arithmetic,
  ../extension_fields,
  ../io/io_bigints,
  ../constants/zoo_endomorphisms,
  ./ec_endomorphism_accel

# ############################################################
#                                                            #
#                   Scalar Multiplication                    #
#                                                            #
# ############################################################
#
# Scalar multiplication is a key algorithm for cryptographic protocols:
# - it is slow,
# - it is performance critical as it is used to generate signatures and authenticate messages
# - it is a high-value target as the "scalar" is very often the user secret key
#
# A safe scalar multiplication MUST:
# - Use no branching (to prevent timing and simple power analysis attacks)
# - Always do the same memory accesses (in particular for table lookups) (to prevent cache-timing attacks)
# - Not expose the bitlength of the exponent (use the curve order bitlength instead)
#
# Constantine does not make an extra effort to defend against the smart-cards
# and embedded device attacks:
# - Differential Power-Analysis which may allow for example retrieving bit content depending on the cost of writing 0 or 1
#   (Address-bit DPA by Itoh, Izu and Takenaka)
# - Electro-Magnetic which can be used in a similar way to power analysis but based on EM waves
# - Fault Attacks which can be used by actively introducing faults (via a laser for example) in an algorithm
#
# The current security efforts are focused on preventing attacks
# that are effective remotely including through the network,
# a colocated VM or a malicious process on your phone.
#
# - Survey for Performance & Security Problems of Passive Side-channel Attacks     Countermeasures in ECC\
#   Rodrigo Abarúa, Claudio Valencia, and Julio López, 2019\
#   https://eprint.iacr.org/2019/010
#
# - State-of-the-art of secure ECC implementations:a survey on known side-channel attacks and countermeasures\
#   Junfeng Fan,XuGuo, Elke De Mulder, Patrick Schaumont, Bart Preneel and Ingrid Verbauwhede, 2010
#   https://www.esat.kuleuven.be/cosic/publications/article-1461.pdf

template checkScalarMulScratchspaceLen(len: int) =
  ## CHeck that there is a minimum of scratchspace to hold the temporaries
  debug:
    assert len >= 2, "Internal Error: the scratchspace for scalar multiplication should be equal or greater than 2"

func getWindowLen(bufLen: int): uint =
  ## Compute the maximum window size that fits in the scratchspace buffer
  checkScalarMulScratchspaceLen(bufLen)
  result = 5
  while (1 shl result) + 1 > bufLen:
    dec result

func scalarMulPrologue[EC](
       P: var EC,
       scratchspace: var openarray[EC]
     ): uint =
  ## Setup the scratchspace then set P to infinity
  ## Returns the fixed-window size for scalar mul with window optimization
  result = scratchspace.len.getWindowLen()
  # Precompute window content, special case for window = 1
  # (i.e scratchspace has only space for 2 temporaries)
  # The content scratchspace[2+k] is set at [k]P
  # with scratchspace[0] untouched
  if result == 1:
    scratchspace[1] = P
  else:
    scratchspace[2] = P
    for k in 2 ..< 1 shl result:
      scratchspace[k+1].sum(scratchspace[k], P)

  # Set a to infinity
  P.setInf()

func scalarMulDoubling[EC](
       P: var EC,
       exponent: openArray[byte],
       tmp: var EC,
       window: uint,
       acc, acc_len: var uint,
       e: var int
     ): tuple[k, bits: uint] {.inline.} =
  ## Doubling steps of doubling and add for scalar multiplication
  ## Get the next k bits in range [1, window)
  ## and double k times
  ## Returns the number of doubling done and the corresponding bits.
  ##
  ## Updates iteration variables and accumulators
  #
  # ⚠️: Extreme care should be used to not leak
  #    the exponent bits nor its real bitlength
  #    i.e. if the exponent is zero but encoded in a
  #    256-bit integer, only "256" should leak
  #    as for most applications like ECDSA or BLS signature schemes
  #    the scalar is the user secret key.

  # Get the next bits
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

  # We have k bits and can do k doublings
  for i in 0 ..< k:
    tmp.double(P)
    P = tmp

  return (k, bits)


func scalarMulGeneric[EC](
       P: var EC,
       scalar: openArray[byte],
       scratchspace: var openArray[EC]
     ) =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This uses fixed-window optimization if possible
  ## `scratchspace` MUST be of size 2 .. 2^4
  ##
  ## This is suitable to use with secret `scalar`, in particular
  ## to derive a public key from a private key or
  ## to sign a message.
  ##
  ## Particular care has been given to defend against the following side-channel attacks:
  ## - timing attacks: all exponents of the same length
  ##   will take the same time including
  ##   a "zero" exponent of length 256-bit
  ## - cache-timing attacks: Constantine does use a precomputed table
  ##   but when extracting a value from the table
  ##   the whole table is always accessed with the same pattern
  ##   preventing malicious attacks through CPU cache delay analysis.
  ## - simple power-analysis and electromagnetic attacks: Constantine always do the same
  ##   double and add sequences and those cannot be analyzed to distinguish
  ##   the exponent 0 and 1.
  ##
  ## I.e. As far as the author know, Constantine implements all countermeasures to the known
  ##      **remote** attacks on ECC implementations.
  ##
  ## Disclaimer:
  ##   Constantine is provided as-is without any guarantees.
  ##   Use at your own risks.
  ##   Thorough evaluation of your threat model, the security of any cryptographic library you are considering,
  ##   and the secrets you put in jeopardy is strongly advised before putting data at risk.
  ##   The author would like to remind users that the best code can only mitigate
  ##   but not protect against human failures which are the weakest links and largest
  ##   backdoors to secrets exploited today.
  ##
  ## Constantine is resistant to
  ## - Fault Injection attacks: Constantine does not have branches that could
  ##   be used to skip some additions and reveal which were dummy and which were real.
  ##   Dummy operations are like the double-and-add-always timing attack countermeasure.
  ##
  ##
  ## Constantine DOES NOT defend against Address-Bit Differential Power Analysis attacks by default,
  ## which allow differentiating between writing a 0 or a 1 to a memory cell.
  ## This is a threat for smart-cards and embedded devices (for example to handle authentication to a cable or satellite service)
  ## Constantine can be extended to use randomized projective coordinates to foil this attack.

  let window = scalarMulPrologue(P, scratchspace)

  # We process bits with from most to least significant.
  # At each loop iteration with have acc_len bits in acc.
  # To maintain constant-time the number of iterations
  # or the number of operations or memory accesses should be the same
  # regardless of acc & acc_len
  var
    acc, acc_len: uint
    e = 0
  while acc_len > 0 or e < scalar.len:
    let (k, bits) = scalarMulDoubling(
      P, scalar, scratchspace[0],
      window, acc, acc_len, e
    )

    # Window lookup: we set scratchspace[1] to the lookup value
    # If the window length is 1 it's already set.
    if window > 1:
      # otherwise we need a constant-time lookup
      # in particular we need the same memory accesses, we can't
      # just index the openarray with the bits to avoid cache attacks.
      for i in 1 ..< 1 shl k:
        let ctl = SecretWord(i) == SecretWord(bits)
        scratchspace[1].ccopy(scratchspace[1+i], ctl)

    # Multiply with the looked-up value
    # we need to keep the product only ig the exponent bits are not all zeroes
    scratchspace[0].sum(P, scratchspace[1])
    P.ccopy(scratchspace[0], SecretWord(bits).isNonZero())

func scalarMulGeneric*[EC](P: var EC, scalar: BigInt, window: static int = 5) =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This scalar multiplication can handle edge cases:
  ## - When a cofactor is not cleared
  ## - Multiplying by a number beyond curve order.
  ##
  ## A window size will reserve 2^window of scratch space to accelerate
  ## the scalar multiplication.
  var
    scratchSpace: array[1 shl window, EC]
    scalarCanonicalBE: array[scalar.bits.ceilDiv_vartime(8), byte] # canonical big endian representation
  scalarCanonicalBE.marshal(scalar, bigEndian)                     # Export is constant-time
  P.scalarMulGeneric(scalarCanonicalBE, scratchSpace)

func scalarMul*[EC](
       P: var EC,
       scalar: BigInt
     ) {.inline.} =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This use endomorphism acceleration by default if available
  ## Endomorphism acceleration requires:
  ## - Cofactor to be cleared
  ## - 0 <= scalar < curve order
  ## Those will be assumed to maintain constant-time property
  when BigInt.bits <= EC.F.C.getCurveOrderBitwidth() and
       EC.F.C.hasEndomorphismAcceleration():
    # TODO, min amount of bits for endomorphisms?
    when EC.F is Fp:
      P.scalarMulGLV_m2w2(scalar)
    elif EC.F is Fp2:
      P.scalarMulEndo(scalar)
    else: # Curves defined on Fp^m with m > 2
      {.error: "Unreachable".}
  else:
    scalarMulGeneric(P, scalar)
