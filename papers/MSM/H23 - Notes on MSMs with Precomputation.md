---
title: Notes on MSMs with Precomputation
source: https://hackmd.io/@1rDV_-HiSd-uTLJAZgeQTg/Hk0Ec7hO3
author: Gottfried Herold
date: 2023-07-12
---

# Notes on MSMs with Precomputation

## Problem statement

Ethereum's Verkle upgrade is to a large part about replacing the Merkle tree by a so-called verkle tree. This heavily makes use of so-called Pedersen commitments.

Concretely, in our use case, we have (as part of a setup) 256  elliptic curve points
$P_1, P_2, \ldots, P_{256}$. Those points are fixed once and forever.

The main computation we need to perform is, given a vector $(a_1,\ldots,a_{256})$ of scalars, to compute
$a_1P_1 + \ldots + a_{256}P_{256}$.
In our case, the elliptic curve under consideration is Bandersnatch[^Bandersnatch] (an incomplete twisted Edwards curve with an efficient endomorphism). We work in a 253-bit subgroup,
so we can view $a_i$'s as have this many bits.

[^Bandersnatch]: "Bandersnatch: a fast elliptic curve built over the
BLS12-381 scalar field" by Simon Masson, Antonio Sanso and Zhenfei Zhang https://eprint.iacr.org/2021/1152.pdf

Due to the fact that the $P_1,\ldots,P_{256}$ are fixed, we may store large pre-computed tables of curve points in memory and try to use those to then speed up the computation of $a_1P_1 + \ldots + a_{256}P_{256}$.

## Naive algorithm

A somewhat naive way is to binary decompose each $a_i$ into bits $a_i = \sum_i a_{i,j} 2^j$ with $a_{i,j}\in\{0,1\}$. This means we decompose the exponents into a matrix of bits.

![Figure 1: Naive algorithm binary decomposition](./images/H23%20-%20Notes%20on%20MSMs%20with%20Precomputation/H23%20-%20Fig%201%20-%20Naive%20algorithm%20binary%20decomposition.png)

The columns of this matrix correspond to the (binary decomposition of) $a_i$'s and are what gets multiplied by $P_i$. The rows correspond to powers of 2.

We can then write
$\sum_i a_i P_i = \sum_{i,j} a_{i,j}\cdot 2^jP_i$

If we precompute all $256\cdot 253$ values of the form $2^jP_i$, we can compute this sum as a sum of at most $256\cdot 253$ terms (typically $\approx\frac12$ of it, with one summand per 1 in the matrix).

## Vertical blocks

A better algorithm with more memory usage is the one currently being implemented:

![Figure 2: Vertical blocks decomposition](./images/H23%20-%20Notes%20on%20MSMs%20with%20Precomputation/H23%20-%20Fig%202%20-%20Vertical%20blocks.png)

Notably, we fix some block size $b$ (with $b=8$ in the figure).
We subdivide the input matrix into vertical blocks, as depicted in the figure.
For each of the possible $2^b-1$ non-zero combinations of bits in a block, we precompute the contribution this would give to the sum.

In the example (with $b=8$), this means we precompute

$P_i, 2\cdot P_i, 3\cdot P_i, \ldots, 255\cdot P_i$,
$256P_i, 2\cdot 256P_i, 3\cdot 256P_i,\ldots, 255\cdot 256 P_i$,
$2^{16}P_i, 2\cdot 2^{16}P_i, 3\cdot 2^{16}P_i,\ldots, 255\cdot 2^{16}P_i$,
$\ldots$
for each $i$.

(Note that the top blocks are not full.)
Generally, we need $\approx 256\cdot \lceil\frac{253}{b}\rceil$ blocks and each block requires $2^b-1$ precomputed values. We can then compute the sum we are actually interested in as a sum of $256\cdot\lceil\frac{253}{b}\rceil$ summands, with one summand coming from each block (this ignores that some summands may be zero and are skipped).

Obtaining the actually needed summands corresponds to decomposing each input $a_i$ in base $2^b$.

## Arbitrary blocks

Observe that the strategy above actually does not need that the blocks are vertical. It works with *any* decomposition of the $256\cdot 253$ bit matrix into blocks of size $b$.

![Figure 3: Arbitrary blocks decomposition](./images/H23%20-%20Notes%20on%20MSMs%20with%20Precomputation/H23%20-%20Fig%203%20-%20Arbitrary%20blocks.png)

We just pre-compute any of the $2^b-1$ potential non-zero sums per block. The blocks may have any shape and need not even be connected. The figure shows 2 such blocks. Of course, the decomposition into blocks has then to be applied to any given input bit-matrix and doing something weird makes this (needlessly) complicated. Still, the complexity in terms of precomputation size and number of group operations is independent from the block decomposition strategy; it only depends on $b$ (and whether there is some loss from non-full blocks).
However, as we shall see, horizontal blocks are typically better than vertical ones.

## Horizontal blocks

![Figure 4: Horizontal blocks decomposition](./images/H23%20-%20Notes%20on%20MSMs%20with%20Precomputation/H23%20-%20Fig%204%20-%20Horizontal%20blocks.png)


Pre-computing horizontal blocks with block size $b$ means that we precompute (parts of) rows. I.e. we precompute sums of the form

$S_{i',j,\vec{c}} = 2^j \cdot \sum_{k=1}^{b} c_{k}P_{i'\cdot b +k}$

where $0\leq i' < \lceil\frac{256}{b}\rceil$ ranges over the blocks of a given row and the $c_{k}\in\{0,1\}$ are the potential values of the bits in this block. Now observe that
$S_{i',j+1,\vec{c}} = 2\cdot S_{i',j,\vec{c}}$.
This means that we actually retrieve all precomputed values for a given row block from the one below by simply doubling.
Consequently, we may actually precompute **only** the bottom row and then compute the values for the other rows as needed:

Note that

$\sum_i a_i P_i = \sum_{i,j} a_{i,j}\cdot 2^jP_i =
\sum_j 2^j \cdot \sum_i a_{i,j} P_i =\\
(\sum_{i}a_{i,0}P_i) + 2\cdot(\ (\sum_{i}a_{i,1}P_i)\ + 2\cdot (\ (\sum_{i}a_{i,2}P_i) + \ldots + 2\cdot\ (\sum_{i}a_{i,252}P_i)\ )))\ldots)$

We can write every sum $\sum_i a_{i,j}P_i$ as a sum of $\lceil\frac{256}{b}\rceil$ precomputed values. In total, we only need 252 doublings (independent from the number of $P_i$'s -- those amortize by using a "standard" double-and-add trick!). So at an additive cost of 252 doublings, we cut down the number of precomputed values by a factor of $\frac{1}{253}$.
Using this saved factor to, e.g. increase $b$ (to compensate for the extra doublings) is actually much better for most parameter ranges that we are interested at.

## Pippenger Exponentiation

To alleviate the cost of the 252 doublings, we can use a more elaborate strategy:
Instead of precomputing blocks in every row or in only the bottom row, we can precompute in every $t$'th row, so we precompute in $s=\lceil\frac{253}{t}\rceil$ many rows.

![Figure 5: Pippenger precomputation](./images/H23%20-%20Notes%20on%20MSMs%20with%20Precomputation/H23%20-%20Fig%205%20-%20Pippenger%20precomputation.png)

The image shows an example where the blocksize is $b=12$ and we perform precomputations in every $t=5$'th row. As usual, the blue areas are the blocks for which we perform precomputation. Note that, if the number of points (256 for us) is not divisible by $b$, they can wrap into the next precomputed row, so we don't waste too much due to rounding.

Using literally the same trick as before, we have $\lceil\frac{s\cdot 256}{b}\rceil$ many blocks and hence need to precompute $(2^b-1)\cdot \lceil\frac{s\cdot 256}{b}\rceil$ many elements. The total computation then requires approximately $\frac{256\cdot 253}{b}$ additions and a total of $t-1$ doublings (these amortize as before).

Essentially, what we do here is trading the size of the basis for the size of the exponents: if we write each $a_i$ in $2^t$-ary decomposition, the desired sum takes the form

$\sum_{i}a_iP_i =\\
a'_1P_1 + \ldots + a'_{256}P_{256} +\\
a'_{257}2^tP_1 + \ldots + a'_{512}2^tP_{256}+\\
a'_{513}2^{2t}P_1 + \ldots + a'_{768}2^{2t}P_{256}$,

where $a_1 = a'_1 + a'_{257}2^t + a'_{513}2^{2t} + \ldots$ is the decomposition of $a_1$,$a_2 = a'_2 + a'_{258}2^t + a'_{514}2^{2t} + \ldots$ is the decomposition of $a_2$ etc.
This can be viewed as a multi-exponentiation with new basis $P_1,\ldots,P_{256},2^tP_1,\ldots, 2^tP_{256}, \ldots$,
consisting of $s\cdot 256$ elements and exponents of size at most $t$ bits each.
We can then just use the "only precompute bottom row" strategy on this transformed problem.

Note that the algorithm described here is what is used in Pippenger exponentiation[^Pippenger][^Pippenger2][^Yao] (without precomputation).

[^Pippenger]: Nicholas Pippenger, The minimum number of edges in graphs with prescribed paths, Mathematic Systems Theory 12 (1979), 325--346. MR 81e:05079
[^Pippenger2]: Nicholas Pippenger, On the evaluation of powers and Monomials, SIAM Journal on Computing 9 (1980), 230--250. MR 82c:10064
[^Yao]: Andrew C. Yao, On the evaluation of powers, SIAM Journal on Computing 5 (1976), 100--103. MR52 #16128

Notably, Pippenger's multi-exponentiation algorithm uses this trick to reduce $\kappa$ multi-exponentiation problems to the problem of computing $t\cdot \kappa$ sums of the form $\sum b_iP_i$ where $b_i\in\{0,1\}$ for the same $P_i$. This corresponds precisely to our "rows". The latter is then taken care of by Pippenger's multi-product algorithm, which is the "actual" Pippenger algorithm.
One essential step in Pippenger's multi-product algorithm is what's called input partitioning. Here the input $P_i$'s are partitioned into blocks of $b$ and we compute all possible binary sums within a block, in the hope that these sums are used in many of the $t\kappa$ rows. In the non-precomputation case (as is the normal case for Pippenger), $b$ is rather small.
This means that this algorithm is actually *exactly* Pippenger's algorithm with the first step of Pippenger's algorithm (which only depends on the basis) precomputed.

In principle, this also means that using Pippenger to amortize a bit when simultaneously computing multiple MSMs is compatible with these precomputation tricks.
However, some back-of-the-envelope computations show that this rarely helps. The reason is that for large values of $b$, most of the gains are already achieved: to benefit more from Pippenger's algorithm, the same subexpressions (which means a sum of 2 precomputed values) needs to appear in multiple desired outputs. This needs to happen rather often, which is just not the case for large $b$, as any individual precomputed value enters a multi-product output only with probability $\frac{1}{2^b}$. Also, Pippenger's algorithm itself requires additional memory, which has to compete with just using this additional memory to increase the precomputation.

## Horizontal variant

There is a variant of the above using vertical blocks as well. However, these blocks are no longer contiguous, but rather only have a contribution in every $t$'th row.

![Figure 6: Horizontal variant with vertical blocks](./images/H23%20-%20Notes%20on%20MSMs%20with%20Precomputation/H23%20-%20Fig%206%20-%20Horizontal%20variant%20vertical%20blocks.png)

Note that these disjoint blocks can wrap into the next column.
This is the same as the Pippenger algorithm above: We perform a $2^t$-ary decomposition of each basis element, but now instead of viewing it as multi-exponentiation with basis
$P_1,\ldots,P_{256},2^tP_1,\ldots, 2^tP_{256}, \ldots$
as before, we now view it as a multi-exponentiation with basis
$P_1,2^tP_1, 2^{2t}P_1,\ldots, P_2,2^{t}P_2,\ldots$
and perform the "only precompute bottom row" strategy.
It has the same performance and looks a bit more complicated (in the figure, in code it makes no difference, as it is really just a permutation of the basis). The advantage of this strategy is that if some of the original exponents $a_i$ are likely to be zero, then with this strategy, whole blocks become zero and can actually be skipped. In the vertical variant, b consecutive of the original exponents would need to be zero for this to happen.



## Using signs to save 50% precomputation

A little trick that can be used with the vertical decomposition is that each $a_i$ is only defined modulo $q$, where $q$ is the group order, which has $253$ bits. We may represent each $a_i$ by a signed number of $252$-bit absolute value and use *signed* $2^b$-ary decomposition. The result of this is that our precomputed tables contain pairs of the form $\{P, -P\}$, of which we only need to store 1 (since negation is essentially for free in elliptic curves). This reduces the precomputation cost by $\frac12$ for essentially free.

It turns out that we can actually save this factor $\frac12$ for **any** of our algorithms.
The trick is to use $\{\pm 1\}$-valued bits instead of $\{0,1\}$-valued bits.
Notably, we have

$\sum_i a_i P_i = \sum_{i,j} a_{i,j}\cdot 2^jP_i =\\
\Bigl(\frac{1}{2}\sum_{i,j} 2^jP_i\Bigr) + \sum_{i,j}a'_{i,j} \cdot\frac12 2^jP_i$

where $a'_{i,j} = +1$ if $a_{i,j}=1$ and $a'_{i,j} = -1$ if $a_{i,j} = 0$.
This just uses the fact that $a_{i,j} = \frac12 + \frac12\cdot a'_{i,j}$.

Note that to make sense of the expression $\frac12$, we need to compute modulo $q$, so this is really $\frac{q+1}{2}$. Fortunately, it only enters into precomputed values.

The expression $\Bigl(\frac{1}{2}\sum_{i,j} 2^jP_i\Bigr)$ is just a single precomputed point and we can use the above strategies exactly as before to compute $\sum_{i,j}a'_{i,j} \cdot\frac12 2^jP_i$. However, since $a'_{i,j}\in\{\pm 1\}$ now, we can save 50% of the precomputation due to sign-symmetry.

Note that this trick means that we cannot easily skip blocks that originally would give a contribution of zero any longer. For those, we have to work a bit:

If we suspect that only the first $r$ of the original $a_i$ are non-zero, then a certain set of the blocks (with 0/1-coefficients in the original setting) would be all-zero. We can just precompute their total contribution in the $+1/-1$-setting for each $r$.

If we suspect that a lot of the original $a_i$ are zero, but the non-zero positions may be spread out, we should consider the vertical Pippenger variant anyway.
In this case, we can (in addition to the above trick) precompute, for each individual $i$, the sum of contributions of each block that only involves bits coming from $a_i$ if $a_i$ is zero.
(This whole thing is a bit complicated by the fact that blocks may involve contributions from multiple $a_i$'s. Even in the vertical variant, a block may have contributions from $a_i$ and $a_{i+1}$ due to wraparound)


## The endomorphism seems useless?

In principle, Bandersnatch was chosen to contain an efficiently computable endomorphism $\psi$, where for points $P$ of the relevant subgroup, we have $\psi(P) = \alpha P$ where $\alpha$ is some number satisfying $\alpha^2 = -2 \bmod q$. This can be used to perform what's called a GLV decomposition to transform the problem into one with twice the basis elements and half the exponent bitlength by finding $c_i,d_i$ such that $a_iP_i = c_iP_i + \psi(d_iP_i)$ where $c_i, d_i$ have only $\approx 127$ bits (thereby halving the cost each)
If we do things right, we only need to compute $\psi$ a total of 1 time (amortizing it like our doublings).
The thing here is, that we can also just as well decompose $a_iP_i$ into
$a_iP_i = c'_iP_i + 2\cdot(d'_iP_i)$ where $c'_i, d'_i$ only have 1's in even bit-positions (thereby halving the cost each when using precomputations).
Essentially, it seems that in the precomputation settings, the endomorphism is kind-of useless (or rather, the exact same gains can be achieved by using the *doubling* endomorphism instead). When trying to combine doublings and $\psi$, I got the same as just using doublings.

## Point representation

The benefit of precomputation decays rather fast as we increase the table size. The reason is that each block requires $\approx 2^b$ precomputation and we save a total factor of $\approx \frac{1}{b}$. A consequence is that storing a redundant representation of individual points is actually a better use of space. Notably, we can use so-called extended coordinate (recall that Bandersnatch is an incomplete twisted Edwards curve) for the precomputed points, which just means we additionally store $x\cdot y$ for the $x$- and $y$-coordinates of each precomputed point. This can be used to save 1 field multiplication per point addition by using a better formula: since we already have the value of $x\cdot y$, we don't have to compute it during point addition, giving about a 10% saving at the expense of 50% larger tables. A back-of-the-envelope computation shows that this is actually worth it starting from $b=3$ or so.

## Choosing $b$ and $s$

The algorithm has two parameter, namely the blocksize $b$ and the number of rows $s$ where we perform precomputation. Of course, we want to minimize the time for a fixed amount of memory (or vice versa). For a basis size of 256 and 253-bit exponents, it turns out that using $s=1$ (i.e. only pre-compute the bottom row) is actually a good (and also simple) choice for $b\leq 16$.
The reason is that increasing $t$ only helps to reduce the total number of doublings. However, we effectively have only 1 doubling per row and until $b\approx 16$ (and actually even beyond, but rounding is an issue), increasing $b$ by 1 (which has about the same cost as increasing $t$ from 1 to 2) reduces the number of additions per round by at least 1.

In the Verkle setting, it turns out that many MSMs actually only have the first five $a_i$'s non-zero. So we additionally want to look at MSMs for only five basis elements.
Here, the situation is somewhat different, as 252 doublings would be very significant relative to the total cost. For this part of of the MSMs, we can use a much larger $s$, e.g. $s=64$ or $s=128$ (giving $t=4$ or $t=2$, which means 3 or 1 doublings).

Note that the vertical Pippenger variant actually allows setting a different $t$ for each column. The number of doublings is then $t_{max}-1$, where $t_{max}$ is the maximum $t$ among those columns that were actually used.

## Prefetching

It is possible to determine the precomputed points that enter the actual computation before doing a single elliptic curve operation. If the memory latency is high (the precomputation table might not fit into cache), it might be worthwhile to issue prefetch instructions (if supported) in advance, before doing the actual elliptic curve operations. This is up to experimentation.