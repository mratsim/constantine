---
title: Verkle Trees - Another iteration of VKTs MSM
source: https://hackmd.io/@jsign/vkt-another-iteration-of-vkt-msms
author: Ignacio Hagopian
date: 2024-03-21
---

# Verkle Trees - Another iteration of VKTs MSM

This document revisits potential Verkle Tree-related Multiscalar Multiplications (MSM) optimizations.

The main gist of this round is to focus on how Gottfried Herold's ideas in [Notes on MSMs with Precomputation](https://hackmd.io/WfIjm0icSmSoqy2cfqenhQ) could improve our current (Geth) performance (but the ideas apply to any other VKT crypto library).

## Refresher on Verkle Trees and MSM

Most non-proof-related cryptography in Verkle Trees involves an MSM with a fixed basis of length 256.

The fundamental work of the following EL tasks are a fixed-basis MSM calculation:
- Calculating the tree key for an account header or contract storage slot.
- Most of the state migration from MPT to VKT is since we have to migrate leaf nodes.
- State tree updating requires updating internal node commitments and calculating extension level commitments (e.g. C1 and C2).

As we can see, optimizing MSM calculation is relevant for many important tasks.

### How do we calculate MSMs today? (in Geth)

Today’s algorithm exploits the fact that the basis is fixed, compared to other kinds of MSM where the basis isn’t fixed and where a Pippenger-like algorithm is the usual choice.

We calculate precomputed tables from the basis points to speed up the scalar multiplications. Originally, we calculated windows of 8 bits, but last year, I had the idea of using a window size of 16 bits (i.e. 16 windows) for the first five points and 8 bits (i.e. 32 windows) for the rest.

Calculating tree keys and extension node updates only requires an MSM using the first five elements of the basis. Considering “five” is a small number, we can push the windows on these points further without exploding the table sizes. This gives a ~2x speedup on these cases, which are quite common and greatly impact overall client performance.

Sometime later, I implemented a suggested trick for halving the table sizes. Since elliptic curve negation is cheap, we can reduce the precomputed values of each window by 1 bit. This doesn't change performance but reduces memory usage and table generation times (i.e: startup time).

Regarding the theoretical performance of this algorithm, counting the number of elliptic curve operations we must do is straightforward. For the first five elements, each scalar multiplication requires 16 point additions (i.e: 16-bit window). For the rest, it takes 32 point additions (i.e: 8-bit window). As in, a **full 256-MSM in this algorithm takes: $5*16+251*32=8112$ point additions**. Calculating tree-keys for accounts and storage slots require fewer point additions since we only involve 2 or 4 basis points (the first scalar multiplication involves the version which is fixed now, so we can cache that result).

Regarding how big the precomputed table size is, it's also easy to calculate :
- $5 * 16 * 2^{15}$ points: the first 5 elements have 16 windows of 15 bits (since we do point negation trick)
- $251 * 32 * 2^7$ points: the rest have 8 windows of 7 bits (since we do point negation trick).
- We use "extended normalized points" for faster group law operations, which takes three (32 bytes) coordinates.
- Summing all up: 3649536 points * 3 * 32 = 334MiB.

**In summary, the current implementation has:**

- **8112 point additions for a 256 MSM (you can adjust the calculation for shorter MSMs).**
- **The presented benchmark numbers (in my CPU).**
- **A table configuration that uses 334MiB of memory.**

## Intuition of Gottfried’s idea (new algorithm)

I won’t explain the algorithm in detail, but I’ll try to give a good intuition here if you want to avoid reading his document.

Let’s look at the following image presented there:

![](./images/H24%20-%20Verkle%20Trees%20-%20Another%20iteration%20of%20VKTs%20MSM/H24%20-%20Fig%201%20-%20Gottfried%20algorithm%20visualization.png)

The “x-axis” is the basis of the MSM. The “y-axis” are the 253 bits of each scalar corresponding to each point we want to calculate.

The algorithm has two main knobs you have to choose from:

- *t*: this indicates that we’ll consider bits every *t* rows to form the bits of the windows.  In the image *t=5*, as you can see, every 5 rows, we color that bit with blue. Blue boxes are bits of the windows.
- *b*: this indicates that we group *b* blue-colored bits (from bottom to top and wrapping around) to form the windows.

In summary, we form the windows by grouping *b* bits that we select every *t* rows. We “wrap around” when we reach the top, continuing with the next P_i. A window can involve two different points, which is not the case in our current algorithm.

After we define *t* and *b*, this already defines the windows we have to precompute in the same style as our current algorithm. The idea is that we do a similar fashion of a “double-and-add” where we sum all the windows for some bits, then double them, then sum the windows for the next bits, then double them, etc (i.e: filling the gaps between blue boxes). The number of iterations is *t-1*. The "wrap around" situation makes things a bit more tricky.

Let’s say that we choose some *t* and *b*, build some intuition of what we gain/lose by increasing each knob:

- Increase *t* by one: This would reduce the number of windows and thus memory usage. The cost is one extra total doubling. We still have to do a similar-ish number of point additions, since now we have to do an extra round of window aggregation.
- Increase *b* by one: This will reduce the number of windows, but each window will have more bits thus it’s table will be bigger. The cost to pay is more memory.

The cool fact is that increasing *t* by 1 means only 1 extra doubling independently of the length of the MSM, which is very interesting. For example, if we switch from *t=2* to *t=4* with only two extra doublings, we reduce the table’s memory to half the size (again, independently of the length of the MSM).

Are two (or four, or 10, etc.) extra doublings relevant? It depends on the total number of point additions. If we have to do 1000 point additions and doublings for `t=2`, then doubling *t* to `t=4` would decrease the table size in half and only add **a total** of 2 extra operations (i.e., a total of 1002), which is a big win in terms of efficiency.

In reality, things are a bit harder since there’s some “efficiency loss” with this “wrap around” situation where some bits in the tables are “lost” depending how _t_ divides 253.  I'll touch on this a bit more later.

## New algorithm implementation and benchmark

I wrote a [Go implementation](https://github.com/crate-crypto/go-ipa/blob/c3e4522c7200c707a7e2e388fb9dc7bcbe705514/banderwagon/precomp2.go) and [benchmark](https://github.com/crate-crypto/go-ipa/blob/c3e4522c7200c707a7e2e388fb9dc7bcbe705514/banderwagon/precomp_test.go#L107-L130). The benchmark is reproducible, so you can run it on your machine.

The benchmark does a scan of three relevant dimensions:
- Parameter *t*
- Parameter *b*
- *msmLength*

The full benchmark output is quite long, so I put it in an appendix section at the end of the document. Next, I’ll explain how to interpret each line of the output.

Let’s take as an example the following line:

```
..../msmLength=4/t=32_b=10-16       	   35696	     33594 ns/op	       150.0 Add+Double	        19.22 MiB(tablesize)
```

- This is the run for the `msmLength=4,t=32,b=10` configuration.
- It takes 31μs to calculate this MSM under this configuration.
- For this case, we did 150 point additions+doublings.
    - This provides a more “neutral” metric to measure performance compared to time which depends on the CPU — this metric mainly depends on `(t, b)` but is also slightly influenced by the `msmLength` (this is a consequence of the “wrap around” of windows).
    - If we want to be precise, doublings is slightly faster than addition but for simplicity we aggregate them.
- The precomputed table size for this `(t, b)` setup is 19.22MiB.
    - Note that the table size only depends on `(t, b)`, so you’ll see that in other MSM lengths, for the same `(t, b)`, the table size should be the same (the table is always prepared for a 256-MSM).
    - This may be an obvious clarification, but the precomputed table must only be computed once and can be reused in many MSM calculations of different lengths (up to 256).

A curious reader might wonder why I added `t=23` and `t=11` as configurations if the rest are powers of two. Those numbers are factors of 253, the bit length of the scalar field. The “wrap around” nature of skipping every `t` rows makes the algorithm have “top efficiency” when each window perfectly fits each column. You can find cases where the total Add+Doublings remains the same even between `t=16->t=23` configurations. Despite having to do 7 extra doublings, due to the higher efficiency of `t=23`, we also pack more meaningful bits in window additions, resulting in the same total number of operations!

### What is the benchmark saying?

The obvious question is: What is the best `(t, b)` we can use to beat the current algorithm? You might have realized that the answer depends.

Increasing *t* is nice since, e.g., if we double it, we reduce the table size by half. Reducing the table size isn’t only a “save memory” benefit, but leaves more space to push *b* further, which gives us speedup. The cost of increasing *t* by 1 is increasing the **total** number of doublings by 1, but how much impact that has depends on the length of the MSM! Let’s look at two examples to understand this better.

First example:

```
.../msmLength=1/t=1_b=8-16         	  151861	      7689 ns/op	        32.00 Add+Double	       189.8 MiB(tablesize)
.../msmLength=1/t=2_b=8-16         	  148771	      7827 ns/op	        33.00 Add+Double	        95.25 MiB(tablesize)
```

The first setup has `t=1` which means no doublings. The second setup has `t=2` which means 1 doubling. The table size difference between both is 1/2, which is massive, but only at the total cost of extra 1 doubling! Is this extra doubling a big or low overhead? We moved from 32 to 33 operations, which makes sense. Adding one extra operation in 32 is ~3% overhead. If we increase from `t=1` to `t=32`, we’d include 31 doublings, which is ~97% overhead. In summary, in this case, we need low *t* because, in relative terms, doublings can add overhead quite quickly.

Second example:

```
.../msmLength=256/t=1_b=12-16      	     646	   1842674 ns/op	      5398 Add+Double	      2024 MiB(tablesize)
.../msmLength=256/t=2_b=12-16      	     612	   1888015 ns/op	      5418 Add+Double	      1016 MiB(tablesize)
```

Here we add an extra doubling as before. You might wonder why we changed from 5398 to 5418 instead of 5399. The reason is the “wrap around,” which is losing some extra efficiency due to “lost bits”. In any case, the important point is that 1 extra doubling in 5398 operations is ~0.02%, and we reduced the table size by half (~1GiB!), and the performance is almost the same!

Note that if we change from `t=1` to `t=32`:

```
.../msmLength=256/t=32_b=12-16     	     666	   1759856 ns/op	      5500 Add+Double	        64.12 MiB(tablesize)
```

That was a 5x table size reduction (1=2^0 → 32=2^5), and we only added 31 extra doublings which in relative terms to ~5400 operations is tiny (~0.57%).

**The longer the MSM length, the more aggressive we can increase *t* without significant overhead. This leads to smaller tables with roughly the same performance. Smaller tables give us more memory room to increase *b,* providing more performance.**

For a short MSM, we’d need a smaller *t* since each doubling, despite being constant, is significant relative to the total number of operations. For longer MSMs, increasing i*t* by a big amount can still be small relative to the rest of the operations, so we can push for a bigger *b*.

Regarding *b*, as you can see in the benchmark, we should increase it as much as possible since this directly improves performance at the cost of pushing for more memory usage. Note that each extra increase of *b* has less impact, and it doubles the table size, so there are diminishing returns of trying to push this knob too much.

The “unfortunate” conclusion is that the best setup might depend on at least some group of MSM length ranges.

## How to apply these lessons to Verkle Tree MSM?

As we’ve seen before, we need to analyze numbers more carefully since the new algorithm might be useful only in some cases.

A very important clarification worth doing now, is that when I said “a MSM of length X”, I mean having a 256-vector of scalars where only X scalars are non-zero. Since the number of non-zero scalars increases/decreases the total number of add+doubles we have to do, that’s what matters to know when adding more doublings starts to hurt performance too much.

These are the relevant MSMs that happen in VKT:

- MSMs that only have non-zero scalars for the first 5 elements of the basis:
    - Tree key calculation for account header
    - Tree key calculation for contract storage slot
    - Extension level commitment updates.
    - TL;DR: Very important and common cases!
- MSMs with non-zero scalars spread in all 256 elements of the basis:
    - Internal node commitment updates (diff updating internal nodes)
    - Contracts with few storage slot in a leaf node.
    - State conversion from MPT to VKT, since we’re moving lots of data from contracts.
    - EVM block executions that touch many storage slots in a group, or create new leaf nodes.

We’ll have to analyze each of these cases. The complexity of having to distinguish both cases comes from the current algorithm has different performance for MSMs of, for example, length 2 depending on whether these two scalars are in the first 5 or the rest of the elements—since recall for the first 5 we use 16-bit windows and for the rest 8-bit windows, so it gets complicated!

I wrote a benchmark that shows the current algorithm's performance in each scenario, so let’s analyze them separately. All the benchmarks shown below are reproducible also in [this development branch](https://github.com/crate-crypto/go-ipa/blob/c3e4522c7200c707a7e2e388fb9dc7bcbe705514/ipa/ipa_test.go#L328-L405).

### MSMs that only have non-zero scalars for the first 5 elements of the basis

Let’s look at the current algorithm performance in this case:

```
BenchmarkMSMComparison/MSM_in_the_basis[0:5]/msmLength=1-16         	  245980	      4289 ns/op	       0 B/op	       0 allocs/op
BenchmarkMSMComparison/MSM_in_the_basis[0:5]/msmLength=2-16         	  125569	      9471 ns/op	       0 B/op	       0 allocs/op
BenchmarkMSMComparison/MSM_in_the_basis[0:5]/msmLength=4-16         	   60856	     19540 ns/op	       0 B/op	       0 allocs/op
```

Notes about these numbers:

- 1 MSM (i.e: a scalar multiplication) takes ~4.2μs in my CPU.
- Remember, in this `basis[0:5]` range, we use 16-bit windows.
- This means a total of 16 total point additions.
- Considering the MSM length, the time duration is (should) linear.

It is very hard to beat these numbers since the current algorithm excels in this case. The tables are fully optimized for performance in this basis subset, and it would be very hard (or impossible?) to find another strategy that can beat this.

This is fine since using 16-bit windows was a conscious decision to put the feet on the gas for very important cases in Verkle. If you’re curious you could look at the *Appendix - New algorithm full benchmark output* section again and check that the scanned parameters can’t match this performance. For this case, we could try *t=1* and *b=16,* but we’d be pushing the new algorithm to try doing the same as we do today, without any point negation tricks or simply having a more inefficient implementation for this border case.

So, for this case, if we allow zero compromises on performance (which might be questionable, but let’s put that as a constraint), we still need to use the current algorithm. If losing 10% of performance is allowed for this case, then we can probably find a configuration in the new algorithm that is fast enough and probably uses less memory. For now, we stick to “0 performance compromises” to simplify the analysis.

### MSMs with non-zero scalars spread in all 256 elements of the basis

In this case, things start to get more interesting.

Let’s look at the performance of the current algorithm:

```
BenchmarkMSMComparison/MSM_in_the_basis[5:256]/msmLength=1-16       	  174397	      7051 ns/op	       0 B/op	       0 allocs/op
BenchmarkMSMComparison/MSM_in_the_basis[5:256]/msmLength=2-16       	   87318	     13727 ns/op	       0 B/op	       0 allocs/op
BenchmarkMSMComparison/MSM_in_the_basis[5:256]/msmLength=4-16       	   43476	     27446 ns/op	       0 B/op	       0 allocs/op
BenchmarkMSMComparison/MSM_in_the_basis[5:256]/msmLength=8-16       	   21643	     54970 ns/op	       0 B/op	       0 allocs/op
BenchmarkMSMComparison/MSM_in_the_basis[5:256]/msmLength=16-16      	   10816	    110915 ns/op	       0 B/op	       0 allocs/op
BenchmarkMSMComparison/MSM_in_the_basis[5:256]/msmLength=32-16      	    5148	    228504 ns/op	       0 B/op	       0 allocs/op
BenchmarkMSMComparison/MSM_in_the_basis[5:256]/msmLength=64-16      	    1940	    540530 ns/op	       0 B/op	       0 allocs/op
BenchmarkMSMComparison/MSM_in_the_basis[5:256]/msmLength=128-16     	     972	   1189247 ns/op	       0 B/op	       0 allocs/op
BenchmarkMSMComparison/MSM_length_all_basis_(256)-16                	     484	   2452469 ns/op	       0 B/op	       0 allocs/op
```


This case concerns MSM of non-zero scalars spread over all 256 bases. This means the current algorithm will usually use 8-bit windows instead of 16-bit ones, which only exist for the first five elements. Looking at MSM lengths between 1 and 4, we can already see how those are slower than the previous case using 16-bit windows (although it surprised me a bit how it isn’t closer to a 2x slowdown, but it could be related to 8-bit tables causing more cache hits—or maybe my computer had some CPU spike adding noise). In the current algorithm, the expected number of point additions is `32 windows per point * MSM length`.

Here’s where we find two sub-cases in this kind of MSM:

- Short-ish MSMs, between 1 and 8 elements.
- Longer MSMs, between 9 and 256.

Looking again at the output in *Appendix - New algorithm full benchmark output* we can already identify these cases with a similar or better performance.

Let’s start with the MSM length range between 1 and 8:

```
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=1_b=10-16        	  180130	      6439 ns/op	        26.00 Add+Double	       607.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=2_b=10-16        	  177812	      6636 ns/op	        27.00 Add+Double	       304.9 MiB(tablesize)

BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=1_b=10-16        	   91807	     12717 ns/op	        50.00 Add+Double	       607.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=2_b=10-16        	   90750	     12974 ns/op	        52.00 Add+Double	       304.9 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=4_b=10-16        	   89265	     13311 ns/op	        55.00 Add+Double	       153.7 MiB(tablesize)

BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=8_b=12-16        	   49772	     23311 ns/op	        95.00 Add+Double	       256.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=11_b=12-16       	   49486	     23932 ns/op	        98.00 Add+Double	       184.1 MiB(tablesize)

BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=8_b=10-16        	   22918	     52100 ns/op	       215.0 Add+Double	        76.88 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=11_b=10-16       	   22681	     52482 ns/op	       218.0 Add+Double	        55.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=16_b=10-16       	   22360	     53490 ns/op	       223.0 Add+Double	        38.44 MiB(tablesize)
```

The raw performance numbers are better than the current algorithm, but within this range is still hard to have a good tradeoff of memory usage. The underlying reason is not other than what we explained in previous sections. The new algorithm has a fixed cost of doublings that should amortize well in the total number of operations. Since these MSM lengths are still quite short, these costs aren’t amortized enough to make the new algorithm shine. Also note that ideally, we’d like a single *t* and *b* configuration to cover this range since having many configurations means adding the table sizes! So maybe using the current algorithm with 8-bit windows for these spread short MSM is still better.

Now let’s look at MSM ranges of 9 and 256 (quite a wide range):

```
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=11_b=12-16      	   13119	     90151 ns/op	       351.0 Add+Double	       184.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=16_b=12-16      	   13003	     90734 ns/op	       364.0 Add+Double	       128.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=23_b=12-16      	   13202	     90793 ns/op	       367.0 Add+Double	        88.12 MiB(tablesize)

BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=16_b=12-16      	    5389	    187291 ns/op	       703.0 Add+Double	       128.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=23_b=12-16      	    6604	    182876 ns/op	       712.0 Add+Double	        88.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=32_b=12-16      	    6602	    181060 ns/op	       734.0 Add+Double	        64.12 MiB(tablesize)

BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=32_b=12-16      	    2715	    378143 ns/op	      1406 Add+Double	        64.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=64_b=12-16      	    2826	    362490 ns/op	      1463 Add+Double	        32.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=128_b=12-16     	    2794	    375601 ns/op	      1534 Add+Double	        16.12 MiB(tablesize)

BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=64_b=12-16     	    1441	    741780 ns/op	      2815 Add+Double	        32.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=128_b=12-16    	    1438	    731027 ns/op	      2932 Add+Double	        16.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=256_b=12-16    	    1504	    751304 ns/op	      3037 Add+Double	         8.250 MiB(tablesize)

BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=64_b=12-16     	     692	   1679191 ns/op	      5564 Add+Double	        32.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=128_b=12-16    	     702	   1527611 ns/op	      5629 Add+Double	        16.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=256_b=12-16    	     788	   1465889 ns/op	      5810 Add+Double	         8.250 MiB(tablesize)
```

This is where the new strategy starts to have serious performance improvements using table sizes that are quite small:

- For MSMs between 9 and 32, *t=16* and *b=12* are good choices. Note that if we try to push it a bit further, we’d probably affect shorter MSMs not shown in the benchmark between lengths 9 and 16.
- For MSM between 33 and 256, looks like a good choice is *t=128* and *b=12*.

For these ranges above, the cost of doublings starts to become “negligible” compared to the total number of operations. This allows us to use less memory and a bigger *b*, which helps performance.

### Final strategy

The final strategy for our new MSM algorithm is the following:

- For MSMs that only touch the first 5 basis points, use the current algorithm (16-bits windows)
- For MSMs that only have between 1 and 8 non-zero scalars spread all over the basis, use the current algorithm (8-bits windows)
- For MSM that have between 9 and 32 non-zero scalars spread all over the basis, use the new algorithm with *t=16* and *b=12* (adding 128MiB of memory usage).
- For MSM that have between 33 and 256 non-zero scalars spread all over the basis, use the new algorithm with *t=128* and *b=12* (only adds 16MiB of memory usage).

So, in the most aggressive strategy, we would add 128+16MiB of memory usage and get a decent speedup, which we’ll see more clearly in the next section benchmarks. We could be more conservative and still use the current algorithm for the 9-32 range and save the extra 128MiB if we think it isn’t worth it.

## Final strategy implementation and benchmark

So, this final strategy is a hybrid algorithm implementation in their best performance for each case.

Here’s a final benchmark that compares our current strategy with the new proposed one in [AMD Ryzen 7 3800XT](https://www.amazon.com/AMD-Ryzen-3800XT-16-Threads-Processor/dp/B089WCXZJC):

```
MSMComparison/MSM_in_the_basis[0:5]/msmLength=1-16        4.29µs ± 1%    4.22µs ± 1%   -1.71%  (p=0.000 n=10+10)
MSMComparison/MSM_in_the_basis[0:5]/msmLength=2-16        9.50µs ± 0%    9.37µs ± 0%   -1.36%  (p=0.000 n=10+10)
MSMComparison/MSM_in_the_basis[0:5]/msmLength=4-16        19.4µs ± 1%    19.1µs ± 0%   -1.49%  (p=0.000 n=10+10)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=1-16      6.85µs ± 0%    6.79µs ± 0%   -0.89%  (p=0.000 n=10+9)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=2-16      13.7µs ± 0%    13.6µs ± 0%   -1.04%  (p=0.000 n=8+8)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=4-16      27.5µs ± 0%    27.1µs ± 0%   -1.25%  (p=0.000 n=8+8)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=8-16      55.1µs ± 0%    54.3µs ± 0%   -1.40%  (p=0.000 n=9+9)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=16-16      111µs ± 0%      88µs ± 1%  -20.73%  (p=0.000 n=9+10)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=32-16      229µs ± 1%     181µs ± 1%  -21.13%  (p=0.000 n=10+9)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=64-16      533µs ± 0%     370µs ± 0%  -30.61%  (p=0.000 n=8+9)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=128-16    1.19ms ± 0%    0.69ms ± 1%  -41.60%  (p=0.000 n=10+10)
MSMComparison/MSM_length_all_basis_(256)-16               2.45ms ± 0%    1.37ms ± 1%  -44.12%  (p=0.000 n=9+8)
```

For MSMs of 16 non-zero scalars up to 256, we got a speedup between 20% and 44%, which is very good, using only 144MiB more memory. This has 0 compromises in any other case (which was one of the constraints of this exploration).

Let's look at the above benchmark comparisons in a [Rock5B](https://ameridroid.com/products/rock5-model-b) (very low-hardware setup, maybe already discarded already for an Ethereum node post-4844):
```
name                                                   old time/op    new time/op    delta
MSMComparison/MSM_in_the_basis[0:5]/msmLength=1-8        27.1µs ± 2%    27.4µs ± 3%     ~     (p=0.247 n=10+10)
MSMComparison/MSM_in_the_basis[0:5]/msmLength=2-8        54.1µs ± 1%    54.6µs ± 2%     ~     (p=0.315 n=8+10)
MSMComparison/MSM_in_the_basis[0:5]/msmLength=4-8         111µs ± 2%     111µs ± 2%   -0.59%  (p=0.040 n=9+9)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=1-8      37.1µs ± 2%    37.3µs ± 2%     ~     (p=0.127 n=10+10)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=2-8      72.6µs ± 2%    74.0µs ± 1%   +1.86%  (p=0.001 n=10+9)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=4-8       147µs ± 2%     149µs ± 1%     ~     (p=0.065 n=10+9)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=8-8       334µs ± 2%     333µs ± 3%     ~     (p=0.739 n=10+10)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=16-8      783µs ± 2%     593µs ± 2%  -24.21%  (p=0.000 n=10+10)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=32-8     1.68ms ± 3%    1.20ms ± 3%  -28.18%  (p=0.000 n=10+10)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=64-8     3.39ms ± 2%    2.32ms ± 3%  -31.54%  (p=0.000 n=10+9)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=128-8    7.00ms ± 1%    4.89ms ± 1%  -30.09%  (p=0.000 n=8+9)
MSMComparison/MSM_length_all_basis_(256)-8               13.6ms ± 1%     9.2ms ± 0%  -32.13%  (p=0.000 n=10+10)
```


If we think using 144MiB of extra memory is too much, then by only using 16MiB of extra memory we can get the following:
```
MSMComparison/MSM_in_the_basis[0:5]/msmLength=1-16        4.29µs ± 1%    4.21µs ± 0%   -1.98%  (p=0.000 n=10+9)
MSMComparison/MSM_in_the_basis[0:5]/msmLength=2-16        9.50µs ± 0%    9.38µs ± 0%   -1.26%  (p=0.000 n=10+9)
MSMComparison/MSM_in_the_basis[0:5]/msmLength=4-16        19.4µs ± 1%    19.2µs ± 0%   -1.41%  (p=0.000 n=10+9)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=1-16      6.85µs ± 0%    6.81µs ± 0%   -0.66%  (p=0.000 n=10+9)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=2-16      13.7µs ± 0%    13.6µs ± 0%   -0.82%  (p=0.000 n=8+9)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=4-16      27.5µs ± 0%    27.2µs ± 0%   -0.97%  (p=0.000 n=8+8)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=8-16      55.1µs ± 0%    54.4µs ± 0%   -1.14%  (p=0.000 n=9+10)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=16-16      111µs ± 0%     109µs ± 0%   -1.40%  (p=0.000 n=9+9)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=32-16      229µs ± 1%     213µs ± 0%   -7.03%  (p=0.000 n=10+9)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=64-16      533µs ± 0%     370µs ± 0%  -30.51%  (p=0.000 n=8+10)
MSMComparison/MSM_in_the_basis[5:256]/msmLength=128-16    1.19ms ± 0%    0.69ms ± 1%  -41.46%  (p=0.000 n=10+10)
MSMComparison/MSM_length_all_basis_(256)-16               2.45ms ± 0%    1.37ms ± 2%  -44.08%  (p=0.000 n=9+10)
```

Which is the same speedups as before, but not having gains in the 8 and 32 range.

I think 144MiB of extra RAM sounds reasonable for a decent speedup in a wide range of MSM lengths. But this might be up to each client's decision! In the worst case with extra 16MiB it will be getting quite a good bang for the buck anyway.


To finish, let’s explore some parallel questions regarding this new strategy.

### Why none of the implementations is parallelized?

The current and new strategies can be parallelized since aggregating windows is fully parallelizable. I kept all benchmarks single-threaded to make a fair comparison without any extra noise (i.e., comparing a non-parallelized algorithm with a parallelized one) would be unfair.

Furthermore, it’s easy to lose the view of the big picture when doing benchmarks deep in the stack. In the Verkle Trees EIPs, the use of these MSM comes from:

- Calculating tree keys, which clients can parallelize if they do the EVM execution in flat-db storage, collecting all changes, and dumping everything at the end of the tree to calculate the new root. This means that all tree accesses can be paralellized at this level, thus it’s not necessary to add extra parallelization overhead at the cryptography layer. This hasn’t been done yet in Geth since it’s a big-ish change that can cause rebase pains in the medium term, but it will be done eventually.
- Updating tree nodes, which clients can “commit” in a single go by parallelizing work “per level”, means that MSMs should already take advantage of all cores but “higher in the stack”.
- The state conversion work from MPT to VKT happens on every block. In this case, we’re doing many tree key calculations and new *LeafNode* insertions, which require these MSMs. We’ve already parallelized this work at the geth level, so there’s no need to parallelize the MSMs.
- Clients could easily parallelize this algorithm but make it optional at runtime if some cases don’t fall into the above categories.

### What happened to the clever trick of the new algorithm to reduce the precomputed table sizes?

As mentioned in the *How do we calculate MSMs today? (in Geth)*  **section, today we do some point negation tricks to save 50% of table sizes by a known “point negation” trick where we can save 1-bit length in the windows.

As Gottfried mentioned in his document, the new algorithm includes a similar (but a bit more convoluted) trick that we can use to save 50% of pre-computation and, thus, memory usage.

The trick is very clever, where instead of aggregating window values from the identity element you start from a precomputed point that already adds “half” of the potential contribution of each scalar-bit in the windows. This allows you to represent the scalar bits with 1 and -1, which contribute the remaining “half” or cancel the existing one to have the correct contribution if the original bit was 0 or 1. Due to the sign symmetry of 1 and -1, we could do a similar “negation trick” to save 1 bit from the windows.

As mentioned in the original document, this trick creates a challenging situation if we have many scalars that are zero. The original point that we’re starting from to do the aggregation already assumes a contribution from each window, which should be zero in the case of zero scalars. We still have to add these zero-scalars, which hurts performance. Also as mentioned in the original doc, if we can predict which scalars might be zero, we could precompute some “cancelation points” such that a single point addition deals with the situation, but I don’t think this is quite possible since we’re using the new strategy for cases that aren’t very predictable.

I haven’t chatted with Gottfried about this situation to pick his brain, but my intuition said that all this probably isn’t worth it, considering our tables for the new strategy are already quite small for a lot of the complexity (and potential performance hurt) trying to do this trick would imply.

### How does the new MSM strategy affect table initialization times?

The original strategy required the following times of table precomputation at startup time:

- My CPU: ~402ms
- Rock5B: ~3.32s

The new strategy requires:

- My CPU: ~528ms
- Rock5B: 3.96s

## Conclusion and next steps

All the presented numbers are synthetic benchmarks that show the raw performance of MSMs. The speedups are quite significant, so this will be a good strategy to have from now on.

After preparing a more polished branch with this strategy to be used in `go-verkle` and geth, we could run other existing “higher level benchmarks” and a chain-replay run checking if we notice a `mgasps` throughput improvement or potential bump in the number of key-values we can migrate (MPT→VKT) per block.

Of course, any decision that considers performance should always consider slowest client implementation, so there won’t be an immediate decision regarding speeding up the migration. However, this this work and strategy could be applied to other libraries so more clients could benefit from it.

## Appendix - New algorithm full benchmark output

Below is the full benchmark output for the new algorithm (scroll horizontally to see all the columns):
```
goos: linux
goarch: amd64
pkg: github.com/crate-crypto/go-ipa/banderwagon
cpu: AMD Ryzen 7 3800XT 8-Core Processor
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=1_b=8-16         	  151861	      7689 ns/op	        32.00 Add+Double	       189.8 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=2_b=8-16         	  148771	      7827 ns/op	        33.00 Add+Double	        95.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=4_b=8-16         	  146248	      8114 ns/op	        34.00 Add+Double	        48.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=8_b=8-16         	  134646	      8785 ns/op	        39.00 Add+Double	        24.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=11_b=8-16        	  124125	      9662 ns/op	        42.00 Add+Double	        17.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=16_b=8-16        	  116090	     10303 ns/op	        47.00 Add+Double	        12.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=23_b=8-16        	   86211	     13759 ns/op	        67.00 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=32_b=8-16        	   89760	     13242 ns/op	        62.00 Add+Double	         6.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=64_b=8-16        	   49566	     24208 ns/op	       124.0 Add+Double	         3.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=128_b=8-16       	   27991	     42901 ns/op	       228.0 Add+Double	         1.500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=256_b=8-16       	   16648	     72012 ns/op	       383.0 Add+Double	         0.7500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=1_b=10-16        	  180130	      6439 ns/op	        26.00 Add+Double	       607.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=2_b=10-16        	  177812	      6636 ns/op	        27.00 Add+Double	       304.9 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=4_b=10-16        	  162784	      7271 ns/op	        31.00 Add+Double	       153.7 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=8_b=10-16        	  143562	      8275 ns/op	        36.00 Add+Double	        76.88 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=11_b=10-16       	  128248	      9240 ns/op	        43.00 Add+Double	        55.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=16_b=10-16       	  115963	     10248 ns/op	        47.00 Add+Double	        38.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=23_b=10-16       	  100366	     11942 ns/op	        54.00 Add+Double	        26.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=32_b=10-16       	   91568	     13067 ns/op	        63.00 Add+Double	        19.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=64_b=10-16       	   49497	     24243 ns/op	       122.0 Add+Double	         9.656 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=128_b=10-16      	   27986	     42894 ns/op	       216.0 Add+Double	         4.875 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=256_b=10-16      	   16545	     71987 ns/op	       381.0 Add+Double	         2.438 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=1_b=12-16        	  181618	      5834 ns/op	        21.00 Add+Double	      2024 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=2_b=12-16        	  183403	      5838 ns/op	        23.00 Add+Double	      1016 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=4_b=12-16        	  171466	      6472 ns/op	        27.00 Add+Double	       512.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=8_b=12-16        	  158220	      7254 ns/op	        31.00 Add+Double	       256.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=11_b=12-16       	  161642	      7312 ns/op	        32.00 Add+Double	       184.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=16_b=12-16       	  119091	      9995 ns/op	        45.00 Add+Double	       128.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=23_b=12-16       	  124302	      9587 ns/op	        45.00 Add+Double	        88.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=32_b=12-16       	   89646	     13059 ns/op	        63.00 Add+Double	        64.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=64_b=12-16       	   48892	     24307 ns/op	       120.0 Add+Double	        32.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=128_b=12-16      	   27898	     42910 ns/op	       221.0 Add+Double	        16.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=1/t=256_b=12-16      	   16663	     72082 ns/op	       387.0 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=1_b=8-16         	   77416	     15288 ns/op	        63.00 Add+Double	       189.8 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=2_b=8-16         	   76774	     15449 ns/op	        65.00 Add+Double	        95.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=4_b=8-16         	   75930	     15633 ns/op	        67.00 Add+Double	        48.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=8_b=8-16         	   73446	     16331 ns/op	        71.00 Add+Double	        24.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=11_b=8-16        	   68893	     17274 ns/op	        76.00 Add+Double	        17.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=16_b=8-16        	   67221	     17823 ns/op	        78.00 Add+Double	        12.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=23_b=8-16        	   59991	     19993 ns/op	        91.00 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=32_b=8-16        	   57742	     20759 ns/op	        94.00 Add+Double	         6.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=64_b=8-16        	   45346	     26475 ns/op	       127.0 Add+Double	         3.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=128_b=8-16       	   24482	     49048 ns/op	       248.0 Add+Double	         1.500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=256_b=8-16       	   13826	     85603 ns/op	       443.0 Add+Double	         0.7500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=1_b=10-16        	   91807	     12717 ns/op	        50.00 Add+Double	       607.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=2_b=10-16        	   90750	     12974 ns/op	        52.00 Add+Double	       304.9 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=4_b=10-16        	   89265	     13311 ns/op	        55.00 Add+Double	       153.7 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=8_b=10-16        	   81553	     14560 ns/op	        63.00 Add+Double	        76.88 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=11_b=10-16       	   79632	     14963 ns/op	        65.00 Add+Double	        55.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=16_b=10-16       	   71277	     16724 ns/op	        74.00 Add+Double	        38.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=23_b=10-16       	   63938	     18686 ns/op	        85.00 Add+Double	        26.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=32_b=10-16       	   58324	     20503 ns/op	        94.00 Add+Double	        19.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=64_b=10-16       	   45714	     26107 ns/op	       127.0 Add+Double	         9.656 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=128_b=10-16      	   24495	     49026 ns/op	       247.0 Add+Double	         4.875 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=256_b=10-16      	   13998	     85530 ns/op	       449.0 Add+Double	         2.438 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=1_b=12-16        	   92851	     11781 ns/op	        43.00 Add+Double	      2024 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=2_b=12-16        	   95461	     11251 ns/op	        45.00 Add+Double	      1016 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=4_b=12-16        	   99507	     11729 ns/op	        47.00 Add+Double	       512.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=8_b=12-16        	   90548	     13054 ns/op	        54.00 Add+Double	       256.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=11_b=12-16       	   91420	     12851 ns/op	        54.00 Add+Double	       184.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=16_b=12-16       	   81574	     14508 ns/op	        63.00 Add+Double	       128.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=23_b=12-16       	   77467	     15199 ns/op	        68.00 Add+Double	        88.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=32_b=12-16       	   59442	     20041 ns/op	        91.00 Add+Double	        64.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=64_b=12-16       	   45746	     26146 ns/op	       127.0 Add+Double	        32.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=128_b=12-16      	   24421	     49029 ns/op	       248.0 Add+Double	        16.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=2/t=256_b=12-16      	   14001	     85663 ns/op	       441.0 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=1_b=8-16         	   39063	     30568 ns/op	       125.0 Add+Double	       189.8 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=2_b=8-16         	   38768	     30742 ns/op	       128.0 Add+Double	        95.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=4_b=8-16         	   38539	     30859 ns/op	       131.0 Add+Double	        48.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=8_b=8-16         	   38257	     31226 ns/op	       135.0 Add+Double	        24.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=11_b=8-16        	   36728	     32580 ns/op	       142.0 Add+Double	        17.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=16_b=8-16        	   36700	     32836 ns/op	       143.0 Add+Double	        12.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=23_b=8-16        	   33697	     35616 ns/op	       158.0 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=32_b=8-16        	   33844	     35465 ns/op	       159.0 Add+Double	         6.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=64_b=8-16        	   29068	     41211 ns/op	       191.0 Add+Double	         3.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=128_b=8-16       	   22591	     53359 ns/op	       255.0 Add+Double	         1.500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=256_b=8-16       	   12241	     98071 ns/op	       490.0 Add+Double	         0.7500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=1_b=10-16        	   43082	     25505 ns/op	       102.0 Add+Double	       607.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=2_b=10-16        	   46455	     25346 ns/op	       102.0 Add+Double	       304.9 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=4_b=10-16        	   45505	     25990 ns/op	       107.0 Add+Double	       153.7 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=8_b=10-16        	   44721	     26632 ns/op	       110.0 Add+Double	        76.88 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=11_b=10-16       	   43125	     27658 ns/op	       115.0 Add+Double	        55.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=16_b=10-16       	   40711	     29338 ns/op	       124.0 Add+Double	        38.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=23_b=10-16       	   38950	     30888 ns/op	       136.0 Add+Double	        26.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=32_b=10-16       	   35696	     33594 ns/op	       150.0 Add+Double	        19.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=64_b=10-16       	   29358	     40873 ns/op	       190.0 Add+Double	         9.656 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=128_b=10-16      	   22988	     52219 ns/op	       255.0 Add+Double	         4.875 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=256_b=10-16      	   12260	     97909 ns/op	       492.0 Add+Double	         2.438 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=1_b=12-16        	   45807	     25910 ns/op	        85.00 Add+Double	      2024 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=2_b=12-16        	   49081	     23843 ns/op	        87.00 Add+Double	      1016 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=4_b=12-16        	   48309	     22795 ns/op	        91.00 Add+Double	       512.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=8_b=12-16        	   49772	     23311 ns/op	        95.00 Add+Double	       256.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=11_b=12-16       	   49486	     23932 ns/op	        98.00 Add+Double	       184.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=16_b=12-16       	   45255	     26202 ns/op	       110.0 Add+Double	       128.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=23_b=12-16       	   44236	     26659 ns/op	       114.0 Add+Double	        88.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=32_b=12-16       	   41250	     28919 ns/op	       126.0 Add+Double	        64.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=64_b=12-16       	   29852	     40291 ns/op	       190.0 Add+Double	        32.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=128_b=12-16      	   22729	     52407 ns/op	       254.0 Add+Double	        16.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=4/t=256_b=12-16      	   12237	     97996 ns/op	       491.0 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=1_b=8-16         	   19588	     60834 ns/op	       251.0 Add+Double	       189.8 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=2_b=8-16         	   19548	     61047 ns/op	       253.0 Add+Double	        95.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=4_b=8-16         	   19482	     61535 ns/op	       259.0 Add+Double	        48.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=8_b=8-16         	   19413	     61899 ns/op	       262.0 Add+Double	        24.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=11_b=8-16        	   19525	     61391 ns/op	       263.0 Add+Double	        17.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=16_b=8-16        	   18922	     62906 ns/op	       271.0 Add+Double	        12.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=23_b=8-16        	   19004	     63216 ns/op	       271.0 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=32_b=8-16        	   18427	     65199 ns/op	       285.0 Add+Double	         6.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=64_b=8-16        	   16959	     70774 ns/op	       318.0 Add+Double	         3.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=128_b=8-16       	   14432	     83266 ns/op	       379.0 Add+Double	         1.500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=256_b=8-16       	   10000	    105913 ns/op	       507.0 Add+Double	         0.7500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=1_b=10-16        	   20606	     55457 ns/op	       202.0 Add+Double	       607.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=2_b=10-16        	   22636	     50954 ns/op	       205.0 Add+Double	       304.9 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=4_b=10-16        	   23312	     51249 ns/op	       208.0 Add+Double	       153.7 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=8_b=10-16        	   22918	     52100 ns/op	       215.0 Add+Double	        76.88 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=11_b=10-16       	   22681	     52482 ns/op	       218.0 Add+Double	        55.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=16_b=10-16       	   22360	     53490 ns/op	       223.0 Add+Double	        38.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=23_b=10-16       	   22172	     54045 ns/op	       229.0 Add+Double	        26.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=32_b=10-16       	   20392	     58691 ns/op	       252.0 Add+Double	        19.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=64_b=10-16       	   17816	     67258 ns/op	       300.0 Add+Double	         9.656 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=128_b=10-16      	   14644	     81905 ns/op	       379.0 Add+Double	         4.875 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=256_b=10-16      	   10000	    104371 ns/op	       507.0 Add+Double	         2.438 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=1_b=12-16        	   21512	     54833 ns/op	       169.0 Add+Double	      2024 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=2_b=12-16        	   22207	     52010 ns/op	       171.0 Add+Double	      1016 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=4_b=12-16        	   25186	     46070 ns/op	       175.0 Add+Double	       512.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=8_b=12-16        	   24944	     45746 ns/op	       182.0 Add+Double	       256.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=11_b=12-16       	   25906	     46135 ns/op	       185.0 Add+Double	       184.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=16_b=12-16       	   25440	     46817 ns/op	       190.0 Add+Double	       128.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=23_b=12-16       	   24231	     49308 ns/op	       203.0 Add+Double	        88.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=32_b=12-16       	   22948	     52219 ns/op	       221.0 Add+Double	        64.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=64_b=12-16       	   20563	     58097 ns/op	       254.0 Add+Double	        32.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=128_b=12-16      	   14824	     80845 ns/op	       376.0 Add+Double	        16.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=8/t=256_b=12-16      	   10000	    104771 ns/op	       507.0 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=1_b=8-16        	    9540	    125675 ns/op	       504.0 Add+Double	       189.8 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=2_b=8-16        	    9784	    121522 ns/op	       506.0 Add+Double	        95.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=4_b=8-16        	    8254	    123226 ns/op	       511.0 Add+Double	        48.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=8_b=8-16        	    8803	    123347 ns/op	       519.0 Add+Double	        24.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=11_b=8-16       	    9166	    121921 ns/op	       514.0 Add+Double	        17.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=16_b=8-16       	    9126	    124311 ns/op	       525.0 Add+Double	        12.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=23_b=8-16       	    9172	    124496 ns/op	       526.0 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=32_b=8-16       	    9229	    125511 ns/op	       540.0 Add+Double	         6.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=64_b=8-16       	    9100	    130314 ns/op	       574.0 Add+Double	         3.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=128_b=8-16      	    8398	    142566 ns/op	       634.0 Add+Double	         1.500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=256_b=8-16      	    7230	    165761 ns/op	       759.0 Add+Double	         0.7500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=1_b=10-16       	    8898	    124725 ns/op	       405.0 Add+Double	       607.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=2_b=10-16       	    8974	    113692 ns/op	       408.0 Add+Double	       304.9 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=4_b=10-16       	   11568	    104227 ns/op	       414.0 Add+Double	       153.7 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=8_b=10-16       	   11625	    102726 ns/op	       419.0 Add+Double	        76.88 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=11_b=10-16      	   11761	    101660 ns/op	       417.0 Add+Double	        55.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=16_b=10-16      	    9756	    104791 ns/op	       430.0 Add+Double	        38.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=23_b=10-16      	   10000	    105418 ns/op	       435.0 Add+Double	        26.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=32_b=10-16      	   10000	    106613 ns/op	       447.0 Add+Double	        19.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=64_b=10-16      	    9662	    117825 ns/op	       506.0 Add+Double	         9.656 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=128_b=10-16     	    8672	    134703 ns/op	       604.0 Add+Double	         4.875 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=256_b=10-16     	    7263	    163517 ns/op	       757.0 Add+Double	         2.438 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=1_b=12-16       	   10000	    111287 ns/op	       338.0 Add+Double	      2024 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=2_b=12-16       	   10000	    111692 ns/op	       341.0 Add+Double	      1016 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=4_b=12-16       	   10000	    105686 ns/op	       347.0 Add+Double	       512.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=8_b=12-16       	   12398	     94808 ns/op	       351.0 Add+Double	       256.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=11_b=12-16      	   13119	     90151 ns/op	       351.0 Add+Double	       184.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=16_b=12-16      	   13003	     90734 ns/op	       364.0 Add+Double	       128.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=23_b=12-16      	   13202	     90793 ns/op	       367.0 Add+Double	        88.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=32_b=12-16      	   12829	     93492 ns/op	       383.0 Add+Double	        64.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=64_b=12-16      	   10000	    104035 ns/op	       443.0 Add+Double	        32.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=128_b=12-16     	    9612	    116959 ns/op	       508.0 Add+Double	        16.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=16/t=256_b=12-16     	    7191	    162424 ns/op	       744.0 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=1_b=8-16        	    3716	    288264 ns/op	      1010 Add+Double	       189.8 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=2_b=8-16        	    4825	    245827 ns/op	      1012 Add+Double	        95.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=4_b=8-16        	    4134	    247371 ns/op	      1019 Add+Double	        48.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=8_b=8-16        	    4873	    245557 ns/op	      1029 Add+Double	        24.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=11_b=8-16       	    4477	    245161 ns/op	      1017 Add+Double	        17.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=16_b=8-16       	    4566	    248149 ns/op	      1032 Add+Double	        12.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=23_b=8-16       	    4684	    245373 ns/op	      1030 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=32_b=8-16       	    4701	    247517 ns/op	      1052 Add+Double	         6.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=64_b=8-16       	    4750	    250902 ns/op	      1083 Add+Double	         3.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=128_b=8-16      	    4556	    262074 ns/op	      1147 Add+Double	         1.500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=256_b=8-16      	    4214	    284126 ns/op	      1262 Add+Double	         0.7500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=1_b=10-16       	    4422	    257006 ns/op	       809.0 Add+Double	       607.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=2_b=10-16       	    4478	    251490 ns/op	       814.0 Add+Double	       304.9 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=4_b=10-16       	    4573	    227108 ns/op	       822.0 Add+Double	       153.7 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=8_b=10-16       	    5800	    204740 ns/op	       827.0 Add+Double	        76.88 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=11_b=10-16      	    5890	    203860 ns/op	       823.0 Add+Double	        55.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=16_b=10-16      	    5836	    205369 ns/op	       842.0 Add+Double	        38.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=23_b=10-16      	    5036	    206072 ns/op	       846.0 Add+Double	        26.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=32_b=10-16      	    5236	    208688 ns/op	       863.0 Add+Double	        19.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=64_b=10-16      	    5298	    214153 ns/op	       893.0 Add+Double	         9.656 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=128_b=10-16     	    4983	    235783 ns/op	      1012 Add+Double	         4.875 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=256_b=10-16     	    4402	    270301 ns/op	      1214 Add+Double	         2.438 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=1_b=12-16       	    5252	    224539 ns/op	       675.0 Add+Double	      2024 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=2_b=12-16       	    5082	    226956 ns/op	       679.0 Add+Double	      1016 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=4_b=12-16       	    4938	    221246 ns/op	       687.0 Add+Double	       512.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=8_b=12-16       	    5191	    210796 ns/op	       692.0 Add+Double	       256.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=11_b=12-16      	    5265	    202910 ns/op	       689.0 Add+Double	       184.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=16_b=12-16      	    5389	    187291 ns/op	       703.0 Add+Double	       128.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=23_b=12-16      	    6604	    182876 ns/op	       712.0 Add+Double	        88.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=32_b=12-16      	    6602	    181060 ns/op	       734.0 Add+Double	        64.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=64_b=12-16      	    5552	    187304 ns/op	       767.0 Add+Double	        32.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=128_b=12-16     	    5109	    210059 ns/op	       885.0 Add+Double	        16.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=32/t=256_b=12-16     	    4741	    234825 ns/op	      1013 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=1_b=8-16        	    1838	    621275 ns/op	      2017 Add+Double	       189.8 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=2_b=8-16        	    1910	    562941 ns/op	      2028 Add+Double	        95.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=4_b=8-16        	    2030	    511173 ns/op	      2036 Add+Double	        48.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=8_b=8-16        	    2204	    495428 ns/op	      2045 Add+Double	        24.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=11_b=8-16       	    2224	    485922 ns/op	      2026 Add+Double	        17.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=16_b=8-16       	    2299	    494384 ns/op	      2057 Add+Double	        12.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=23_b=8-16       	    2330	    487262 ns/op	      2038 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=32_b=8-16       	    2358	    492105 ns/op	      2073 Add+Double	         6.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=64_b=8-16       	    2400	    495699 ns/op	      2103 Add+Double	         3.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=128_b=8-16      	    2101	    503598 ns/op	      2166 Add+Double	         1.500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=256_b=8-16      	    2290	    522219 ns/op	      2270 Add+Double	         0.7500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=1_b=10-16       	    2245	    524625 ns/op	      1617 Add+Double	       607.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=2_b=10-16       	    2204	    532348 ns/op	      1626 Add+Double	       304.9 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=4_b=10-16       	    2251	    503557 ns/op	      1642 Add+Double	       153.7 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=8_b=10-16       	    2346	    446931 ns/op	      1646 Add+Double	        76.88 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=11_b=10-16      	    2407	    421489 ns/op	      1633 Add+Double	        55.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=16_b=10-16      	    2919	    412557 ns/op	      1661 Add+Double	        38.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=23_b=10-16      	    2499	    408071 ns/op	      1651 Add+Double	        26.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=32_b=10-16      	    2508	    408546 ns/op	      1688 Add+Double	        19.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=64_b=10-16      	    2716	    418429 ns/op	      1723 Add+Double	         9.656 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=128_b=10-16     	    2734	    428369 ns/op	      1788 Add+Double	         4.875 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=256_b=10-16     	    2511	    470376 ns/op	      2009 Add+Double	         2.438 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=1_b=12-16       	    2619	    450111 ns/op	      1350 Add+Double	      2024 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=2_b=12-16       	    2467	    461427 ns/op	      1357 Add+Double	      1016 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=4_b=12-16       	    2626	    448999 ns/op	      1370 Add+Double	       512.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=8_b=12-16       	    2552	    446598 ns/op	      1373 Add+Double	       256.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=11_b=12-16      	    2626	    431863 ns/op	      1363 Add+Double	       184.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=16_b=12-16      	    2654	    419023 ns/op	      1391 Add+Double	       128.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=23_b=12-16      	    2672	    398540 ns/op	      1379 Add+Double	        88.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=32_b=12-16      	    2715	    378143 ns/op	      1406 Add+Double	        64.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=64_b=12-16      	    2826	    362490 ns/op	      1463 Add+Double	        32.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=128_b=12-16     	    2794	    375601 ns/op	      1534 Add+Double	        16.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=64/t=256_b=12-16     	    2750	    421819 ns/op	      1752 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=1_b=8-16       	     892	   1286933 ns/op	      4034 Add+Double	       189.8 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=2_b=8-16       	     932	   1247885 ns/op	      4050 Add+Double	        95.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=4_b=8-16       	     973	   1167525 ns/op	      4084 Add+Double	        48.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=8_b=8-16       	    1089	    998974 ns/op	      4085 Add+Double	        24.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=11_b=8-16      	    1120	    977049 ns/op	      4042 Add+Double	        17.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=16_b=8-16      	    1122	    985587 ns/op	      4088 Add+Double	        12.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=23_b=8-16      	    1186	    973032 ns/op	      4053 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=32_b=8-16      	    1173	    982519 ns/op	      4112 Add+Double	         6.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=64_b=8-16      	    1233	    985121 ns/op	      4138 Add+Double	         3.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=128_b=8-16     	    1201	    993412 ns/op	      4202 Add+Double	         1.500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=256_b=8-16     	    1191	   1005081 ns/op	      4291 Add+Double	         0.7500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=1_b=10-16      	    1124	   1058588 ns/op	      3236 Add+Double	       607.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=2_b=10-16      	    1090	   1083896 ns/op	      3251 Add+Double	       304.9 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=4_b=10-16      	    1086	   1052377 ns/op	      3279 Add+Double	       153.7 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=8_b=10-16      	    1138	    999620 ns/op	      3284 Add+Double	        76.88 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=11_b=10-16     	    1177	    962334 ns/op	      3253 Add+Double	        55.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=16_b=10-16     	    1239	    889109 ns/op	      3289 Add+Double	        38.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=23_b=10-16     	    1245	    842681 ns/op	      3258 Add+Double	        26.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=32_b=10-16     	    1216	    823554 ns/op	      3320 Add+Double	        19.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=64_b=10-16     	    1315	    824628 ns/op	      3366 Add+Double	         9.656 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=128_b=10-16    	    1389	    837321 ns/op	      3449 Add+Double	         4.875 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=256_b=10-16    	    1381	    854504 ns/op	      3543 Add+Double	         2.438 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=1_b=12-16      	    1252	    912670 ns/op	      2699 Add+Double	      2024 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=2_b=12-16      	    1246	    929593 ns/op	      2711 Add+Double	      1016 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=4_b=12-16      	    1314	    918202 ns/op	      2733 Add+Double	       512.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=8_b=12-16      	    1285	    920072 ns/op	      2742 Add+Double	       256.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=11_b=12-16     	    1327	    897145 ns/op	      2716 Add+Double	       184.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=16_b=12-16     	    1317	    889055 ns/op	      2749 Add+Double	       128.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=23_b=12-16     	    1308	    865738 ns/op	      2734 Add+Double	        88.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=32_b=12-16     	    1305	    836134 ns/op	      2779 Add+Double	        64.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=64_b=12-16     	    1441	    741780 ns/op	      2815 Add+Double	        32.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=128_b=12-16    	    1438	    731027 ns/op	      2932 Add+Double	        16.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=128/t=256_b=12-16    	    1504	    751304 ns/op	      3037 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=1_b=8-16       	     450	   2632082 ns/op	      8068 Add+Double	       189.8 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=2_b=8-16       	     463	   2566155 ns/op	      8101 Add+Double	        95.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=4_b=8-16       	     472	   2500952 ns/op	      8165 Add+Double	        48.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=8_b=8-16       	     502	   2309752 ns/op	      8172 Add+Double	        24.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=11_b=8-16      	     541	   2129316 ns/op	      8071 Add+Double	        17.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=16_b=8-16      	     549	   2032385 ns/op	      8170 Add+Double	        12.00 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=23_b=8-16      	     594	   1948640 ns/op	      8087 Add+Double	         8.250 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=32_b=8-16      	     600	   1963220 ns/op	      8198 Add+Double	         6.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=64_b=8-16      	     606	   1968427 ns/op	      8225 Add+Double	         3.000 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=128_b=8-16     	     602	   1979251 ns/op	      8281 Add+Double	         1.500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=256_b=8-16     	     602	   1982254 ns/op	      8323 Add+Double	         0.7500 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=1_b=10-16      	     552	   2160256 ns/op	      6474 Add+Double	       607.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=2_b=10-16      	     541	   2188014 ns/op	      6499 Add+Double	       304.9 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=4_b=10-16      	     549	   2157114 ns/op	      6552 Add+Double	       153.7 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=8_b=10-16      	     548	   2120105 ns/op	      6561 Add+Double	        76.88 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=11_b=10-16     	     570	   2056362 ns/op	      6482 Add+Double	        55.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=16_b=10-16     	     571	   1984028 ns/op	      6574 Add+Double	        38.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=23_b=10-16     	     607	   1907282 ns/op	      6500 Add+Double	        26.44 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=32_b=10-16     	     627	   1789389 ns/op	      6584 Add+Double	        19.22 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=64_b=10-16     	     678	   1669692 ns/op	      6644 Add+Double	         9.656 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=128_b=10-16    	     709	   1653831 ns/op	      6730 Add+Double	         4.875 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=256_b=10-16    	     705	   1673813 ns/op	      6824 Add+Double	         2.438 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=1_b=12-16      	     646	   1842674 ns/op	      5398 Add+Double	      2024 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=2_b=12-16      	     612	   1888015 ns/op	      5418 Add+Double	      1016 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=4_b=12-16      	     650	   1838161 ns/op	      5464 Add+Double	       512.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=8_b=12-16      	     644	   1835771 ns/op	      5469 Add+Double	       256.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=11_b=12-16     	     651	   1814031 ns/op	      5410 Add+Double	       184.1 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=16_b=12-16     	     651	   1813565 ns/op	      5484 Add+Double	       128.2 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=23_b=12-16     	     664	   1778933 ns/op	      5425 Add+Double	        88.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=32_b=12-16     	     666	   1759856 ns/op	      5500 Add+Double	        64.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=64_b=12-16     	     692	   1679191 ns/op	      5564 Add+Double	        32.25 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=128_b=12-16    	     702	   1527611 ns/op	      5629 Add+Double	        16.12 MiB(tablesize)
BenchmarkPrecompMSM/GottiPrecomputedTables/msmLength=256/t=256_b=12-16    	     788	   1465889 ns/op	      5810 Add+Double	         8.250 MiB(tablesize)
PASS
ok  	github.com/crate-crypto/go-ipa/banderwagon	634.382s
```