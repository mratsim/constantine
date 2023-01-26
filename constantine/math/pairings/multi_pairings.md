# Multi-pairing discussion:

Aranha & Scott proposes 2 different approaches for multi-pairing.

- Software Implementation, Algorithm 11.2 & 11.3\
  Aranha, Dominguez Perez, A. Mrabet, Schwabe,\
  Guide to Pairing-Based Cryptography, 2015
- Pairing Implementation Revisited
  Mike Scott, 2019
  https://eprint.iacr.org/2019/077.pdf

## Scott approach

```
Algorithm 2: Calculate and store line functions for BLS12 curve
Input: Q ∈ G2, P ∈ G1 , curve parameter u
Output: An array g of ceil(log2(u)) line functions ∈ Fp12
  1 T ← Q
  2 for i ← ceil(log2(u)) − 1 to 0 do
  3   g[i] ← lT,T(P), T ← 2T
  4   if ui = 1 then
  5     g[i] ← g[i].lT,Q(P), T ← T + Q
  6 return g
```

And to accumulate lines from a new (P, Q) tuple of points

```
Algorithm 4: Accumulate another set of line functions into g
Input: The array g, Qj ∈ G2 , Pj ∈ G1 , curve parameter u
Output: Updated array g of ceil(log2(u)) line functions ∈ Fp12
  1 T ← Qj
  2 for i ← ceil(log2(u)) − 1 to 0 do
  3   t ← lT,T (Pj), T ← 2T
  4   if ui = 1 then
  5     t ← t.lT,Qj (Pj), T ← T + Qj
  6   g[i] ← g[i].t
  7 return g
```

## Aranha approach

```
Algorithm 11.2 Explicit multipairing version of Algorithm 11.1.
(we extract the Miller Loop part only)
Input : P1 , P2 , . . . Pn ∈ G1 ,
        Q1 , Q2, . . . Qn ∈ G2
Output: (we focus on the Miller Loop)

Write l in binary form, l = sum(0 ..< m-1)
f ← 1, l ← abs(AteParam)
for j ← 1 to n do
  Tj ← Qj
end

for i = m-2 down to 0 do
  f ← f²
  for j ← 1 to n do
    f ← f.gTj,Tj(Pj), Tj ← [2]Tj
    if li = 1 then
      f ← f.gTj,Qj(Pj), Tj ← Tj + Qj
    end
  end
end
```

## Analysis

Assuming we have N tuples (Pj, Qj) of points j in 0 ..< N
and M operations to do in our Miller loop:
- M = HammingWeight(AteParam) + Bitwidth(AteParam)
  - HammingWeight(AteParam) corresponds to line additions
  - Bitwidth(AteParam) corresponds to line doublings

Scott approach is to have:
- M Fp12 line accumulators `g`
- 1 G2 accumulator `T`
and then accumulating each (Pj, Qj) lines into their corresponding `g` accumulator.
Then those precomputed lines are merged into the final GT result.

Aranha approach is to have:
- 1 Fp12 accumulator `f`
- N G2 accumulators  `T`
and then pairings of each tuple are directly merged on GT.

Scott approach is fully "online"/"streaming",
while Aranha's saves space.
For BLS12_381,
M = 68 hence we would need 68\*12\*48 = 39168 bytes (381-bit needs 48 bytes)
G2 has size 3\*2\*48 = 288 bytes (3 proj coordinates on Fp2)
and while we can choose N to be anything (which can be 1 for single pairing or reverting to Scott approach).

In practice, "streaming pairings" are not used, pairings to compute are receive
by batch, for example for blockchain you receive a batch of N blocks to verify from one peer.
Furthermore, 39kB would be over L1 cache size and incurs cache misses.
Additionally Aranha approach would make it easier to batch inversions
using Montgomery's simultaneous inversion technique.
Lastly, while a higher level API will need to store N (Pj, Qj) pairs for multi-pairings
for Aranha approach, it can decide how big N is depending on hardware and/or protocol.

## Further optimizations

Regarding optimizations, as the Fp12 accumulator is dense
and lines are sparse (xyz000 or xy000z) Scott mentions the following costs:
- squaring                 is 11m
- Dense-sparse             is 13m
- sparse-sparse            is 6m
- Dense-(somewhat sparse)  is 17m
Hence when accumulating lines from multiple points:
- 2x Dense-sparse is 26m
- sparse-sparse then Dense-(somewhat sparse) is 23m
a 11.5% speedup

We can use Aranha approach but process lines function 2-by-2 merging them
before merging them to the dense Fp12 accumulator.

In benchmarks though, the speedup doesn't work for BN curves but does for BLS curves.

For single pairings
Unfortunately, it's BN254_Snarks which requires a lot of addition in the Miller loop.
BLS12-377 and BLS12-381 require 6 and 7 line addition in their Miller loop,
the saving is about 150 cycles per addition for about 1000 cycles saved.
A full pairing is ~2M cycles so this is only 0.5% for significantly
more maintenance and bounds analysis complexity.

For multipairing it is interesting since for a BLS signature verification (double pairing)
we would save 1000 cycles per Ate iteration so ~70000 cycles, while a Miller loop is ~800000 cycles.
