# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  ../config/curves,
  ../extension_fields,
  ../isogenies/frobenius,
  ../elliptic/ec_shortweierstrass_affine,
  ../elliptic/ec_twistededwards_projective,

  ./bls12_377_endomorphisms,
  ./bls12_381_endomorphisms,
  ./bn254_nogami_endomorphisms,
  ./bn254_snarks_endomorphisms,
  ./bw6_761_endomorphisms,
  ./pallas_endomorphisms,
  ./vesta_endomorphisms

{.experimental: "dynamicBindSym".}

macro dispatch(C: static Curve, tag: static string, G: static string): untyped =
  result = bindSym($C & "_" & tag & "_" & G)

template babai*(F: typedesc[Fp or Fp2]): untyped =
  ## Return the GLV Babai roundings vector
  const G = if F is Fp: "G1"
            else: "G2"
  dispatch(F.C, "Babai", G)

template lattice*(F: typedesc[Fp or Fp2]): untyped =
  ## Returns the GLV Decomposition Lattice
  const G = if F is Fp: "G1"
            else: "G2"
  dispatch(F.C, "Lattice", G)

macro getCubicRootOfUnity_mod_p*(C: static Curve): untyped =
  ## Get a non-trivial cubic root of unity (mod p) with p the prime field
  result = bindSym($C & "_cubicRootOfUnity_mod_p")

func computeEndoBander[F](r {.noalias.}: var ECP_TwEdwards_Prj[F], P: ECP_TwEdwards_Prj[F]) =
  static: doAssert F.C in {Bandersnatch, Banderwagon}

  var xy {.noInit.}, yy {.noInit.}, zz {.noInit.}: F

  xy.prod(P.x, P.y)
  yy.square(P.y)
  zz.square(P.z)

  const b = ECP_TwEdwards_Prj[F].fromHex("0x52c9f28b828426a561f00d3a63511a882ea712770d9af4d6ee0f014d172510b4")
  const c = ECP_TwEdwards_Prj[F].fromHex("0x6cc624cf865457c3a97c6efd6c17d1078456abcfff36f4e9515c806cdf650b3d")

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
  const C = EC.F.C

  when C in {Bandersnatch, Banderwagon}:
    endo.computeEndoBander(P)
  elif P.G == G1:
    endo.x.prod(P.x, C.getCubicRootOfUnity_mod_p())
    endo.y = P.y
    endo.z = P.z
  else: # For BW6-761, both G1 and G2 are on Fp
    endo.frobenius_psi(P, 2)

func computeEndomorphisms*[EC; M: static int](endos: var array[M-1, EC], P: EC) =
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

func hasEndomorphismAcceleration*(C: static Curve): bool =
  C in {
    BN254_Nogami,
    BN254_Snarks,
    BLS12_377,
    BLS12_381,
    BW6_761,
    Pallas,
    Vesta
  }

const EndomorphismThreshold* = 196
  ## We use substraction by maximum infinity norm coefficient
  ## to split scalars for endomorphisms
  ## For small scalars the substraction will overflow
  ##
  ## TODO: implement an alternative way to split scalars.
