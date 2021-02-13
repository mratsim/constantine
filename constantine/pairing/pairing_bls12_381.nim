# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[common, curves, type_ff],
  ../towers,
  ../elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective
  ],
  ../curves/zoo_pairings,
  ./lines_projective, ./mul_fp12_by_lines,
  ./miller_loops

# ############################################################
#
#                 Optimal ATE pairing for
#                      BLS12-381
#
# ############################################################
#
# - Software Implementation, Algorithm 11.2 & 11.3
#   Aranha, Dominguez Perez, A. Mrabet, Schwabe,
#   Guide to Pairing-Based Cryptography, 2015
#
# - Physical Attacks,
#   N. El Mrabet, Goubin, Guilley, Fournier, Jauvart, Moreau, Rauzy, Rondepierre,
#   Guide to Pairing-Based Cryptography, 2015
#
# - Pairing Implementation Revisited
#   Mike Scott, 2019
#   https://eprint.iacr.org/2019/077.pdf
#
# Fault attacks:
# To limite exposure to some fault attacks (flipping bits with a laser on embedded):
# - changing the number of Miller loop iterations
# - flipping the bits in the Miller loop
# we hardcode unrolled addition chains.
# This should also contribute to performance.
#
# Multi-pairing discussion:
# Aranha & Scott proposes 2 different approaches for multi-pairing.
#
# -----
# Scott
#
# Algorithm 2: Calculate and store line functions for BLS12 curve
# Input: Q ∈ G2, P ∈ G1 , curve parameter u
# Output: An array g of blog2(u)c line functions ∈ Fp12
#   1 T ← Q
#   2 for i ← ceil(log2(u)) − 1 to 0 do
#   3   g[i] ← lT,T(P), T ← 2T
#   4   if ui = 1 then
#   5     g[i] ← g[i].lT,Q(P), T ← T + Q
#   6 return g
#
# And to accumulate lines from a new (P, Q) tuple of points
#
# Algorithm 4: Accumulate another set of line functions into g
# Input: The array g, Qj ∈ G2 , Pj ∈ G1 , curve parameter u
# Output: Updated array g of ceil(log2(u)) line functions ∈ Fp12
#   1 T ← Qj
#   2 for i ← blog2 (u)c − 1 to 0 do
#   3   t ← lT,T (Pj), T ← 2T
#   4   if ui = 1 then
#   5     t ← t.lT,Qj (Pj), T ← T + Qj
#   6   g[i] ← g[i].t
#   7 return g
#
# ------
# Aranha
#
# Algorithm 11.2 Explicit multipairing version of Algorithm 11.1.
# (we extract the Miller Loop part only)
# Input : P1 , P2 , . . . Pn ∈ G1 ,
#         Q1 , Q2, . . . Qn ∈ G2
# Output: (we focus on the Miller Loop)
#
# Write l in binary form, l = sum(0 ..< m-1)
# f ← 1, l ← abs(AteParam)
# for j ← 1 to n do
#   Tj ← Qj
# end
#
# for i = m-2 down to 0 do
#   f ← f²
#   for j ← 1 to n do
#     f ← f gTj,Tj(Pj), Tj ← [2]Tj
#     if li = 1 then
#       f ← f gTj,Qj(Pj), Tj ← Tj + Qj
#     end
#   end
# end
#
# -----
# Assuming we have N tuples (Pj, Qj) of points j in 0 ..< N
# and I operations to do in our Miller loop:
# - I = HammingWeight(AteParam) + Bitwidth(AteParam)
#   - HammingWeight(AteParam) corresponds to line additions
#   - Bitwidth(AteParam) corresponds to line doublings
#
# Scott approach is to have:
# - I Fp12 accumulators `g`
# - 1 G2 accumulator `T`
# and then accumulating each (Pj, Qj) into their corresponding `g` accumulator.
#
# Aranha approach is to have:
# - 1 Fp12 accumulator `f`
# - N G2 accumulators  `T`
# and accumulate N points per I.
#
# Scott approach is fully "online"/"streaming",
# while Aranha's saves space.
# For BLS12_381,
# I = 68 hence we would need 68*12*48 = 39168 bytes (381-bit needs 48 bytes)
# G2 has size 3*2*48 = 288 bytes (3 proj coordinates on Fp2)
# and we choose N (which can be 1 for single pairing or reverting to Scott approach).
#
# In actual use, "streaming pairings" are not used, pairings to compute are receive
# by batch, for example for blockchain you receive a batch of N blocks to verify from one peer.
# Furthermore, 39kB would be over L1 cache size and incurs cache misses.
# Additionally Aranha approach would make it easier to batch inversions
# using Montgomery's simultaneous inversion technique.
# Lastly, while a higher level API will need to store N (Pj, Qj) pairs for multi-pairings
# for Aranha approach, it can decide how big N is depending on hardware and/or protocol.
#
# Regarding optimizations, as the Fp12 accumulator is dense
# and lines are sparse (xyz000 or xy000z) Scott mentions the following costs:
# - Dense-sparse             is 13m
# - sparse-sparse            is 6m
# - Dense-(somewhat sparse)  is 17m
# Hence when accumulating lines from multiple points:
# - 2x Dense-sparse is 26m
# - sparse-sparse then Dense-(somewhat sparse) is 23m
# a 11.5% speedup
#
# We can use Aranha approach but process lines function 2-by-2 merging them
# before merging them to the dense Fp12 accumulator

# Miller Loop
# -------------------------------------------------------------------------------------------------------

{.push raises: [].}

import
  strutils,
  ../io/io_towers

func miller_first_iter[N: static int](
       f: var Fp12[BLS12_381],
       Ts: var array[N, ECP_ShortW_Prj[Fp2[BLS12_381], OnTwist]],
       Qs: array[N, ECP_ShortW_Aff[Fp2[BLS12_381], OnTwist]],
       Ps: array[N, ECP_ShortW_Aff[Fp[BLS12_381], NotOnTwist]]
     ) =
  ## Start a Miller Loop
  ## This means
  ## - 1 doubling
  ## - 1 add
  ##
  ## f is overwritten
  ## Ts are overwritten by Qs
  static:
    doAssert N >= 1
    doAssert f.c0 is Fp4

  {.push checks: off.} # No OverflowError or IndexError allowed
  var line {.noInit.}: Line[Fp2[BLS12_381]]

  # First step: T <- Q, f = 1 (mod p¹²), f *= line
  # ----------------------------------------------
  for i in 0 ..< N:
    Ts[i].projectiveFromAffine(Qs[i])

  line.line_double(Ts[0], Ps[0])

  # f *= line <=> f = line for the first iteration
  # With Fp2 -> Fp4 -> Fp12 towering and a M-Twist
  # The line corresponds to a sparse xy000z Fp12
  f.c0.c0 = line.x
  f.c0.c1 = line.y
  f.c1.c0.setZero()
  f.c1.c1.setZero()
  f.c2.c0.setZero()
  f.c2.c1 = line.z

  when N >= 2:
    line.line_double(Ts[1], Ps[1])
    f.mul_sparse_by_line_xy000z(line)  # TODO: sparse-sparse mul

    # Sparse merge 2 by 2, starting from 2
    for i in countup(2, N-1, 2):
      # var f2 {.noInit.}: Fp12[BLS12_381] # TODO: sparse-sparse mul
      var line2 {.noInit.}: Line[Fp2[BLS12_381]]

      line.line_double(Ts[i], Ps[i])
      line2.line_double(Ts[i+1], Ps[i+1])

      # f2.mul_sparse_sparse(line, line2)
      # f.mul_somewhat_sparse(f2)
      f.mul_sparse_by_line_xy000z(line)
      f.mul_sparse_by_line_xy000z(line2)

    when N and 1 == 1: # N >= 2 and N is odd, there is a leftover
      line.line_double(Ts[N-1], Ps[N-1])
      f.mul_sparse_by_line_xy000z(line)

  # 2nd step: Line addition as MSB is always 1
  # ----------------------------------------------
  when N >= 2: # f is dense, there are already many lines accumulated
    # Sparse merge 2 by 2, starting from 0
    for i in countup(0, N-1, 2):
      # var f2 {.noInit.}: Fp12[BLS12_381] # TODO: sparse-sparse mul
      var line2 {.noInit.}: Line[Fp2[BLS12_381]]

      line.line_add(Ts[i], Qs[i], Ps[i])
      line2.line_add(Ts[i+1], Qs[i+1], Ps[i+1])

      # f2.mul_sparse_sparse(line, line2)
      # f.mul_somewhat_sparse(f2)
      f.mul_sparse_by_line_xy000z(line)
      f.mul_sparse_by_line_xy000z(line2)

    when N and 1 == 1: # N >= 2 and N is odd, there is a leftover
      line.line_add(Ts[N-1], Qs[N-1], Ps[N-1])
      f.mul_sparse_by_line_xy000z(line)

  else: # N = 1, f is sparse
    line.line_add(Ts[0], Qs[0], Ps[0])
    # f.mul_sparse_sparse(line)
    f.mul_sparse_by_line_xy000z(line)

  {.pop.} # No OverflowError or IndexError allowed

func miller_accum_doublings[N: static int](
       f: var Fp12[BLS12_381],
       Ts: var array[N, ECP_ShortW_Prj[Fp2[BLS12_381], OnTwist]],
       Ps: array[N, ECP_ShortW_Aff[Fp[BLS12_381], NotOnTwist]],
       numDoublings: int
     ) =
  ## Accumulate `numDoublings` Miller loop doubling steps into `f`
  static: doAssert N >= 1
  {.push checks: off.} # No OverflowError or IndexError allowed

  var line {.noInit.}: Line[Fp2[BLS12_381]]

  for _ in 0 ..< numDoublings:
    f.square()
    when N >= 2:
      for i in countup(0, N-1, 2):
        # var f2 {.noInit.}: Fp12[BLS12_381] # TODO: sparse-sparse mul
        var line2 {.noInit.}: Line[Fp2[BLS12_381]]

        line.line_double(Ts[i], Ps[i])
        line2.line_double(Ts[i+1], Ps[i+1])

        # f2.mul_sparse_sparse(line, line2)
        # f.mul_somewhat_sparse(f2)
        f.mul_sparse_by_line_xy000z(line)
        f.mul_sparse_by_line_xy000z(line2)

      when N and 1 == 1: # N >= 2 and N is odd, there is a leftover
        line.line_double(Ts[N-1], Ps[N-1])
        f.mul_sparse_by_line_xy000z(line)
    else:
      line.line_double(Ts[0], Ps[0])
      f.mul_sparse_by_line_xy000z(line)

  {.pop.} # No OverflowError or IndexError allowed

func miller_accum_addition[N: static int](
       f: var Fp12[BLS12_381],
       Ts: var array[N, ECP_ShortW_Prj[Fp2[BLS12_381], OnTwist]],
       Qs: array[N, ECP_ShortW_Aff[Fp2[BLS12_381], OnTwist]],
       Ps: array[N, ECP_ShortW_Aff[Fp[BLS12_381], NotOnTwist]]
     ) =
  ## Accumulate a Miller loop addition step into `f`
  static: doAssert N >= 1
  {.push checks: off.} # No OverflowError or IndexError allowed

  var line {.noInit.}: Line[Fp2[BLS12_381]]

  when N >= 2:
    # Sparse merge 2 by 2, starting from 0
    for i in countup(0, N-1, 2):
      # var f2 {.noInit.}: Fp12[BLS12_381] # TODO: sparse-sparse mul
      var line2 {.noInit.}: Line[Fp2[BLS12_381]]

      line.line_add(Ts[i], Qs[i], Ps[i])
      line2.line_add(Ts[i+1], Qs[i+1], Ps[i+1])

      # f2.mul_sparse_sparse(line, line2)
      # f.mul_somewhat_sparse(f2)
      f.mul_sparse_by_line_xy000z(line)
      f.mul_sparse_by_line_xy000z(line2)

    when N and 1 == 1: # N >= 2 and N is odd, there is a leftover
      line.line_add(Ts[N-1], Qs[N-1], Ps[N-1])
      f.mul_sparse_by_line_xy000z(line)

  else:
    line.line_add(Ts[0], Qs[0], Ps[0])
    f.mul_sparse_by_line_xy000z(line)

  {.pop.} # No OverflowError or IndexError allowed

func millerLoop_opt_BLS12_381*[N: static int](
       f: var Fp12[BLS12_381],
       Qs: array[N, ECP_ShortW_Aff[Fp2[BLS12_381], OnTwist]],
       Ps: array[N, ECP_ShortW_Aff[Fp[BLS12_381], NotOnTwist]]
     ) {.meter.} =
  ## Generic Miller Loop for BLS12 curve
  ## Computes f{u,Q}(P) with u the BLS curve parameter

  var Ts {.noInit.}: array[N, ECP_ShortW_Prj[Fp2[BLS12_381], OnTwist]]

  # Ate param addition chain
  # Hex: 0xd201000000010000
  # Bin: 0b1101001000000001000000000000000000000000000000010000000000000000

  var iter = 1'u64

  f.miller_first_iter(Ts, Qs, Ps)       # 0b11
  f.miller_accum_doublings(Ts, Ps, 2)   # 0b1100
  f.miller_accum_addition(Ts, Qs, Ps)   # 0b1101
  f.miller_accum_doublings(Ts, Ps, 3)   # 0b1101000
  f.miller_accum_addition(Ts, Qs, Ps)   # 0b1101001
  f.miller_accum_doublings(Ts, Ps, 9)   # 0b1101001000000000
  f.miller_accum_addition(Ts, Qs, Ps)   # 0b1101001000000001
  f.miller_accum_doublings(Ts, Ps, 32)  # 0b110100100000000100000000000000000000000000000000
  f.miller_accum_addition(Ts, Qs, Ps)   # 0b110100100000000100000000000000000000000000000001
  f.miller_accum_doublings(Ts, Ps, 16)  # 0b1101001000000001000000000000000000000000000000010000000000000000

  # TODO: what is the threshold for Karabina's compressed squarings?
