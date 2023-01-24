# Random permutations

Work-stealing is more efficient when the thread we steal from is randomized.
If all threads steal in the same order, we increase contention
on the start victims task queues.

The randomness quality is not important besides distributing potential contention,
i.e. randomly trying thread i, then i+1, then i+n-1 (mod n) is good enough.

Hence for efficiency, so that a thread can go to sleep faster, we want to
reduce calls to to the RNG as:
- Getting a random value itself can be expensive, especially if we use a CSPRNG (not a requirement)
- a CSPRNG can be starved of entropy as with small tasks, threads might make millions of calls.
- If we want unbiaised thread ID generation in a range, rejection sampling is costly (not a requirement).

Instead of using Fisher-Yates
  - generates the victim set eagerly, inefficient if the first steal attempts are successful
  - needs a RNG call when sampling a victim
  - memory usage: numThreads per thread so numthreads² uint8 (255 threads max) or uint32

or a sparseset
  - 1 RNG call when sampling a victim
  - memory usage: 2\*numThreads per thread so 2\*numthreads² uint8 (255 threads max) or uint32

we can use Linear Congruential Generators, a recurrence relation of the form Xₙ₊₁ = aXₙ+c (mod m)
If we respect the Hull-Dobell theorem requirements, we can generate pseudo-random permutations in [0, m)
with fixed memory usage whatever the number of potential victims: just 4 registers for a, x, c, m

References:
- Fisher-Yates: https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle
- Sparse sets: https://dl.acm.org/doi/pdf/10.1145/176454.176484
               https://github.com/mratsim/weave/blob/7682784/weave/datatypes/sparsesets.nim
               https://github.com/status-im/nim-taskpools/blob/4bc0b59/taskpools/sparsesets.nim
- Linear Congruential Generator: https://en.wikipedia.org/wiki/Linear_congruential_generator

And if we want cryptographic strength:
- Ciphers with Arbitrary Finite Domains
  John Black and Phillip Rogaway, 2001
  https://eprint.iacr.org/2001/012
- An Enciphering Scheme Based on a Card Shuffle
  Viet Tung Hoang, Ben Morris, Phillip Rogaway
  https://www.iacr.org/archive/crypto2012/74170001/74170001.pdf