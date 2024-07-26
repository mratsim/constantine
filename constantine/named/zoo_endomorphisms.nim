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
  constantine/math/extension_fields,
  constantine/math/endomorphisms/frobenius,
  constantine/math/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian,
    ec_twistededwards_affine,
    ec_twistededwards_projective],
  constantine/math/io/io_fields,

  ./algebras,
  ./constants/bls12_377_endomorphisms,
  ./constants/bls12_381_endomorphisms,
  ./constants/bn254_nogami_endomorphisms,
  ./constants/bn254_snarks_endomorphisms,
  ./constants/bw6_761_endomorphisms,
  ./constants/pallas_endomorphisms,
  ./constants/vesta_endomorphisms,
  ./constants/secp256k1_endomorphisms,
  ./constants/bandersnatch_endomorphisms,
  ./constants/banderwagon_endomorphisms

export Subgroup

{.experimental: "dynamicBindSym".}

macro dispatch(Name: static Algebra, tag: static string, G: static string): untyped =
  result = bindSym($Name & "_" & tag & "_" & G)

template babai*(Name: static Algebra, G: static Subgroup): untyped =
  ## Return the GLV Babai roundings vector
  dispatch(Name, "Babai", $G)

template lattice*(Name: static Algebra, G: static Subgroup): untyped =
  ## Returns the GLV Decomposition Lattice
  dispatch(Name, "Lattice", $G)

macro getCubicRootOfUnity_mod_p*(Name: static Algebra): untyped =
  ## Get a non-trivial cubic root of unity (mod p) with p the prime field
  result = bindSym($Name & "_cubicRootOfUnity_mod_p")

func computeEndoBander[F](r {.noalias.}: var EC_TwEdw_Prj[F], P: EC_TwEdw_Prj[F]) =
  static: doAssert F.Name in {Bandersnatch, Banderwagon}

  var xy {.noInit.}, yy {.noInit.}, zz {.noInit.}: F

  xy.prod(P.x, P.y)
  yy.square(P.y)
  zz.square(P.z)

  const b = F.fromHex("0x52c9f28b828426a561f00d3a63511a882ea712770d9af4d6ee0f014d172510b4")
  const c = F.fromHex("0x6cc624cf865457c3a97c6efd6c17d1078456abcfff36f4e9515c806cdf650b3d")

  r.x.diff(zz, yy)
  r.x *= c

  zz *= b

  r.y.sum(yy, zz)
  r.y *= b

  r.z.diff(yy, zz)

  r.x *= r.z
  r.y *= xy
  r.z *= xy

func computeEndomorphism*[EC](endo: var EC, P: EC) =
  static: doAssert EC.F is Fp
  const C = EC.F.Name

  when C in {Bandersnatch, Banderwagon}:
    endo.computeEndoBander(P)
  elif P.G == G1:
    endo.x.prod(P.x, C.getCubicRootOfUnity_mod_p())
    endo.y = P.y
    when P isnot EC_ShortW_Aff:
      endo.z = P.z
  else: # For BW6-761, both G1 and G2 are on Fp
    endo.frobenius_psi(P, 2)

func computeEndomorphisms*[EC: not ExtensionField; M: static int](endos: var array[M-1, EC], P: EC) =
  ## An endomorphism decomposes M-way.
  when P.F is Fp:
    static: doAssert M == 2
    endos[0].computeEndomorphism(P)
  elif P.F is Fp2:
    static: doAssert M == 4
    endos[0].frobenius_psi(P)
    endos[1].frobenius_psi(P, 2)
    endos[2].frobenius_psi(P, 3)
  else:
    {.error: "Unconfigured".}

func computeEndomorphisms*[Gt: ExtensionField; M: static int](endos: var array[M-1, Gt], a: Gt) =
  staticFor i, 0, M-1:
    endos[i].frobenius_map(a, i+1)

func hasEndomorphismAcceleration*(Name: static Algebra): bool {.compileTime.} =
  Name in {
    Bandersnatch,
    Banderwagon,
    BN254_Nogami,
    BN254_Snarks,
    Secp256k1,
    BLS12_377,
    BLS12_381,
    BW6_761,
    Pallas,
    Vesta
  }

const EndomorphismThreshold* = 192
  ## We use substraction by maximum infinity norm coefficient
  ## to split scalars for endomorphisms
  ##
  ## TODO: explore an alternative way to split scalars, for example via division
  ## https://github.com/mratsim/constantine/issues/347
