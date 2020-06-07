# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../primitives,
  ../config/[common, curves],
  ../arithmetic,
  ../towers,
  ./ec_weierstrass_affine

# ############################################################
#
#             Elliptic Curve in Weierstrass form
#                 with Projective Coordinates
#
# ############################################################

type ECP_SWei_Proj*[F] = object
  ## Elliptic curve point for a curve in Short Weierstrass form
  ##   y² = x³ + a x + b
  ##
  ## over a field F
  ##
  ## in projective coordinates (X, Y, Z)
  ## corresponding to (x, y) with X = xZ and Y = yZ
  ##
  ## Note that projective coordinates are not unique
  x*, y*, z*: F

func `==`*[F](P, Q: ECP_SWei_Proj[F]): SecretBool =
  ## Constant-time equality check
  # Reminder: the representation is not unique

  var a{.noInit.}, b{.noInit.}: F

  a.prod(P.x, Q.z)
  b.prod(Q.x, P.z)
  result = a == b

  a.prod(P.y, Q.z)
  b.prod(Q.y, P.z)
  result = result and a == b

func isInf*(P: ECP_SWei_Proj): SecretBool =
  ## Returns true if P is an infinity point
  ## and false otherwise
  ##
  ## Note: the projective coordinates equation is
  ##       Y²Z = X³ + aXZ² + bZ³
  ## A "zero" point is any point with coordinates X and Z = 0
  ## Y can be anything
  result = P.x.isZero() and P.z.isZero()

func setInf*(P: var ECP_SWei_Proj) =
  ## Set ``P`` to infinity
  P.x.setZero()
  P.y.setOne()
  P.z.setZero()

func ccopy*(P: var ECP_SWei_Proj, Q: ECP_SWei_Proj, ctl: SecretBool) =
  ## Constant-time conditional copy
  ## If ctl is true: Q is copied into P
  ## if ctl is false: Q is not copied and P is unmodified
  ## Time and memory accesses are the same whether a copy occurs or not
  for fP, fQ in fields(P, Q):
    ccopy(fP, fQ, ctl)

func trySetFromCoordsXandZ*[F](P: var ECP_SWei_Proj[F], x, z: F): SecretBool =
  ## Try to create a point the elliptic curve
  ## Y²Z = X³ + aXZ² + bZ³ (projective coordinates)
  ## y² = x³ + a x + b     (affine coordinate)
  ## return true and update `P` if `x` leads to a valid point
  ## return false otherwise, in that case `P` is undefined.
  ##
  ## Note: Dedicated robust procedures for hashing-to-curve
  ##       will be provided, this is intended for testing purposes.
  P.y.curve_eq_rhs(x)
  # TODO: supports non p ≡ 3 (mod 4) modulus like BLS12-377
  result = sqrt_if_square_p3mod4(P.y)

  P.x.prod(x, z)
  P.y *= z
  P.z = z

func trySetFromCoordX*[F](P: var ECP_SWei_Proj[F], x: F): SecretBool =
  ## Try to create a point the elliptic curve
  ## y² = x³ + a x + b     (affine coordinate)
  ##
  ## The `Z` coordinates is set to 1
  ##
  ## return true and update `P` if `x` leads to a valid point
  ## return false otherwise, in that case `P` is undefined.
  ##
  ## Note: Dedicated robust procedures for hashing-to-curve
  ##       will be provided, this is intended for testing purposes.
  P.y.curve_eq_rhs(x)
  # TODO: supports non p ≡ 3 (mod 4) modulus like BLS12-377
  result = sqrt_if_square_p3mod4(P.y)
  P.x = x
  P.z.setOne()

func neg*(P: var ECP_SWei_Proj) =
  ## Negate ``P``
  P.y.neg(P.y)

func sum*[F](
       r: var ECP_SWei_Proj[F],
       P, Q: ECP_SWei_Proj[F]
     ) =
  ## Elliptic curve point addition for Short Weierstrass curves in projective coordinate
  ##
  ##   R = P + Q
  ##
  ## Short Weierstrass curves have the following equation in projective coordinates
  ##   Y²Z = X³ + aXZ² + bZ³
  ## from the affine equation
  ##   y² = x³ + a x + b
  ##
  ## ``r`` is initialized/overwritten with the sum
  ##
  ## Implementation is constant-time, in particular it will not expose
  ## that P == Q or P == -Q or P or Q are the infinity points
  ## to simple side-channel attacks (SCA)
  ## This is done by using a "complete" or "exception-free" addition law.
  ##
  ## This requires the order of the curve to be odd
  #
  # Implementation:
  # Algorithms 1 (generic case), 4 (a == -3), 7 (a == 0) of
  #   Complete addition formulas for prime order elliptic curves
  #   Joost Renes and Craig Costello and Lejla Batina, 2015
  #   https://eprint.iacr.org/2015/1060
  #
  # with the indices 1 corresponding to ``P``, 2 to ``Q`` and 3 to the result ``r``
  #
  # X3 = (X1 Y2 + X2 Y1)(Y1 Y2 - a(X1 Z2 + X2 Z1) - 3b Z1 Z2)
  #      - (Y1 Z2 + Y2 Z1)(a X1 X2 + 3b(X1 Z2 + X2 Z1) - a² Z1 Z2)
  # Y3 = (3 X1 X2 + a Z1 Z2)(a X1 X2 + 3b (X1 Z2 + X2 Z1) - a² Z1 Z2)
  #      + (Y1 Y2 + a (X1 Z2 + X2 Z1) + 3b Z1 Z2)(Y1 Y2 - a(X1 Z2 + X2 Z1) - 3b Z1 Z2)
  # Z3 = (Y1 Z2 + Y2 Z1)(Y1 Y2 + a(X1 Z2 + X2 Z1) + 3b Z1 Z2) + (X1 Y2 + X2 Y1)(3 X1 X2 + a Z1 Z2)
  #
  # Cost: 12M + 3 mul(a) + 2 mul(3b) + 23 a

  # TODO: static doAssert odd order

  when F.C.getCoefA() == 0:
    var t0 {.noInit.}, t1 {.noInit.}, t2 {.noInit.}, t3 {.noInit.}, t4 {.noInit.}: F
    const b3 = 3 * F.C.getCoefB()

    # Algorithm 7 for curves: y² = x³ + b
    # 12M + 2 mul(3b) + 19A
    #
    # X3 = (X1 Y2 + X2 Y1)(Y1 Y2 − 3b Z1 Z2)
    #     − 3b(Y1 Z2 + Y2 Z1)(X1 Z2 + X2 Z1)
    # Y3 = (Y1 Y2 + 3b Z1 Z2)(Y1 Y2 − 3b Z1 Z2)
    #     + 9b X1 X2 (X1 Z2 + X2 Z1)
    # Z3= (Y1 Z2 + Y2 Z1)(Y1 Y2 + 3b Z1 Z2) + 3 X1 X2 (X1 Y2 + X2 Y1)
    t0.prod(P.x, Q.x)         # 1.  t0 <- X1 X2
    t1.prod(P.y, Q.y)         # 2.  t1 <- Y1 Y2
    t2.prod(P.z, Q.z)         # 3.  t2 <- Z1 Z2
    t3.sum(P.x, P.y)          # 4.  t3 <- X1 + Y1
    t4.sum(Q.x, Q.y)          # 5.  t4 <- X2 + Y2
    t3 *= t4                  # 6.  t3 <- t3 * t4
    t4.sum(t0, t1)            # 7.  t4 <- t0 + t1
    t3 -= t4                  # 8.  t3 <- t3 - t4   t3 = (X1 + Y1)(X2 + Y2) - (X1 X2 + Y1 Y2) = X1.Y2 + X2.Y1
    when F is Fp2 and F.C.getSexticTwist() == D_Twist:
      t3 *= F.sexticNonResidue()
    t4.sum(P.y, P.z)          # 9.  t4 <- Y1 + Z1
    r.x.sum(Q.y, Q.z)         # 10. X3 <- Y2 + Z2
    t4 *= r.x                 # 11. t4 <- t4 X3
    r.x.sum(t1, t2)           # 12. X3 <- t1 + t2   X3 = Y1 Y2 + Z1 Z2
    t4 -= r.x                 # 13. t4 <- t4 - X3   t4 = (Y1 + Z1)(Y2 + Z2) - (Y1 Y2 + Z1 Z2) = Y1 Z2 + Y2 Z1
    when F is Fp2 and F.C.getSexticTwist() == D_Twist:
      t4 *= F.sexticNonResidue()
    r.x.sum(P.x, P.z)         # 14. X3 <- X1 + Z1
    r.y.sum(Q.x, Q.z)         # 15. Y3 <- X2 + Z2
    r.x *= r.y                # 16. X3 <- X3 Y3     X3 = (X1 Z1)(X2 Z2)
    r.y.sum(t0, t2)           # 17. Y3 <- t0 + t2   Y3 = X1 X2 + Z1 Z2
    r.y.diff(r.x, r.y)        # 18. Y3 <- X3 - Y3   Y3 = (X1 + Z1)(X2 + Z2) - (X1 X2 + Z1 Z2) = X1 Z2 + X2 Z1
    when F is Fp2 and F.C.getSexticTwist() == D_Twist:
      t0 *= F.sexticNonResidue()
      t1 *= F.sexticNonResidue()
    r.x.double(t0)            # 19. X3 <- t0 + t0   X3 = 2 X1 X2
    t0 += r.x                 # 20. t0 <- X3 + t0   t0 = 3 X1 X2
    t2 *= b3                  # 21. t2 <- b3 t2     t2 = 3b Z1 Z2
    when F is Fp2 and F.C.getSexticTwist() == M_Twist:
      t2 *= F.sexticNonResidue()
    r.z.sum(t1, t2)           # 22. Z3 <- t1 + t2   Z3 = Y1 Y2 + 3b Z1 Z2
    t1 -= t2                  # 23. t1 <- t1 - t2   t1 = Y1 Y2 - 3b Z1 Z2
    r.y *= b3                 # 24. Y3 <- b3 Y3     Y3 = 3b(X1 Z2 + X2 Z1)
    when F is Fp2 and F.C.getSexticTwist() == M_Twist:
      r.y *= F.sexticNonResidue()
    r.x.prod(t4, r.y)         # 25. X3 <- t4 Y3     X3 = 3b(Y1 Z2 + Y2 Z1)(X1 Z2 + X2 Z1)
    t2.prod(t3, t1)           # 26. t2 <- t3 t1     t2 = (X1 Y2 + X2 Y1) (Y1 Y2 - 3b Z1 Z2)
    r.x.diff(t2, r.x)         # 27. X3 <- t2 - X3   X3 = (X1 Y2 + X2 Y1) (Y1 Y2 - 3b Z1 Z2) - 3b(Y1 Z2 + Y2 Z1)(X1 Z2 + X2 Z1)
    r.y *= t0                 # 28. Y3 <- Y3 t0     Y3 = 9b X1 X2 (X1 Z2 + X2 Z1)
    t1 *= r.z                 # 29. t1 <- t1 Z3     t1 = (Y1 Y2 - 3b Z1 Z2)(Y1 Y2 + 3b Z1 Z2)
    r.y += t1                 # 30. Y3 <- t1 + Y3   Y3 = (Y1 Y2 + 3b Z1 Z2)(Y1 Y2 - 3b Z1 Z2) + 9b X1 X2 (X1 Z2 + X2 Z1)
    t0 *= t3                  # 31. t0 <- t0 t3     t0 = 3 X1 X2 (X1.Y2 + X2.Y1)
    r.z *= t4                 # 32. Z3 <- Z3 t4     Z3 = (Y1 Y2 + 3b Z1 Z2)(Y1 Z2 + Y2 Z1)
    r.z += t0                 # 33. Z3 <- Z3 + t0   Z3 = (Y1 Z2 + Y2 Z1)(Y1 Y2 + 3b Z1 Z2) + 3 X1 X2 (X1.Y2 + X2.Y1)
  else:
    {.error: "Not implemented.".}

func double*[F](
       r: var ECP_SWei_Proj[F],
       P: ECP_SWei_Proj[F]
     ) =
  ## Elliptic curve point doubling for Short Weierstrass curves in projective coordinate
  ##
  ##   R = [2] P
  ##
  ## Short Weierstrass curves have the following equation in projective coordinates
  ##   Y²Z = X³ + aXZ² + bZ³
  ## from the affine equation
  ##   y² = x³ + a x + b
  ##
  ## ``r`` is initialized/overwritten with the sum
  ##
  ## Implementation is constant-time, in particular it will not expose
  ## that `P` is an infinity point.
  ## This is done by using a "complete" or "exception-free" addition law.
  ##
  ## This requires the order of the curve to be odd
  #
  # Implementation:
  # Algorithms 3 (generic case), 6 (a == -3), 9 (a == 0) of
  #   Complete addition formulas for prime order elliptic curves
  #   Joost Renes and Craig Costello and Lejla Batina, 2015
  #   https://eprint.iacr.org/2015/1060
  #
  # X3 = 2XY (Y² - 2aXZ - 3bZ²)
  #      - 2YZ (aX² + 6bXZ - a²Z²)
  # Y3 = (Y² + 2aXZ + 3bZ²)(Y² - 2aXZ - 3bZ²)
  #      + (3X² + aZ²)(aX² + 6bXZ - a²Z²)
  # Z3 = 8Y³Z
  #
  # Cost: 8M + 3S + 3 mul(a) + 2 mul(3b) + 15a

  when F.C.getCoefA() == 0:
    var t0 {.noInit.}, t1 {.noInit.}, t2 {.noInit.}: F
    const b3 = 3 * F.C.getCoefB()

    # Algorithm 9 for curves:
    # 6M + 2S + 1 mul(3b) + 9a
    #
    # X3 = 2XY(Y² - 9bZ²)
    # Y3 = (Y² - 9bZ²)(Y² + 3bZ²) + 24bY²Z²
    # Z3 = 8Y³Z

    t0.square(P.y)            # 1.  t0 <- Y Y
    r.z.double(t0)            # 2.  Z3 <- t0 + t0
    r.z.double()              # 3.  Z3 <- Z3 + Z3
    r.z.double()              # 4.  Z3 <- Z3 + Z3   Z3 = 8Y²
    t1.prod(P.y, P.z)         # 5.  t1 <- Y Z
    t2.square(P.z)            # 6.  t2 <- Z Z
    t2 *= b3                  # 7.  t2 <- b3 t2
    r.x.prod(t2, r.z)         # 8.  X3 <- t2 Z3
    r.y.sum(t0, t2)           # 9.  Y3 <- t0 + t2
    r.z *= t1                 # 10. Z3 <- t1 Z3
    t1.double(t2)             # 11. t1 <- t2 + t2
    t2 += t1                  # 12. t2 <- t1 + t2
    t0 -= t2                  # 13. t0 <- t0 - t2
    r.y *= t0                 # 14. Y3 <- t0 Y3
    r.y += r.x                # 15. Y3 <- X3 + Y3
    t1.prod(P.x, P.y)         # 16. t1 <- X Y
    r.x.prod(t0, t1)          # 17. X3 <- t0 t1
    r.x.double()              # 18. X3 <- X3 + X3
  else:
    {.error: "Not implemented.".}

func `+=`*[F](P: var ECP_SWei_Proj[F], Q: ECP_SWei_Proj[F]) =
  var tmp {.noInit.}: ECP_SWei_Proj[F]
  tmp.sum(P, Q)
  P = tmp

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
  result = 4
  while (1 shl result) + 1 > bufLen:
    dec result

func scalarMulPrologue(
       P: var ECP_SWei_Proj,
       scratchspace: var openarray[ECP_SWei_Proj]
     ): uint =
  ## Setup the scratchspace
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

func scalarMulDoubling(
       P: var ECP_SWei_Proj,
       exponent: openArray[byte],
       tmp: var ECP_SWei_Proj,
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


func scalarMul*(
       P: var ECP_SWei_Proj,
       scalar: openArray[byte],
       scratchspace: var openArray[ECP_SWei_Proj]
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
