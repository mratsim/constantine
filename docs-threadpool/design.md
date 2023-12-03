# Threadpool design

The threadpool design is heavily inspired by [Weave](https://github.com/mratsim/weave), the wealth of preparatory [research](https://github.com/mratsim/weave/tree/master/research) and the simplified Weave, [nim-taskpools](https://github.com/status-im/nim-taskpools)

The goal is to produce an extremely high-performance, low-overhead, energy-efficient multithreading runtime.
However, as the backend to a cryptographic library it needs to be high-assurance, in particular auditable and maintainable.

Unfortunately, Weave design, based on work-requesting requires more machinery compared to work-stealing, which means more state. Furthermore it includes a custom memory pool.

On the other hand, nim-taskpools does not support data parallelism (parallel for loop).

Also neither supports putting awaiting threads to sleep when the future they want to complete is not done AND there is no work left.

## Features

| Features                                                                                         | OpenMP                                                     | Weave                                              | nim-taskpools | Constantine's Threadpool                           |
|--------------------------------------------------------------------------------------------------|------------------------------------------------------------|----------------------------------------------------|---------------|----------------------------------------------------|
| Task parallelism (Futures with spawn/sync)                                                       | no                                                         | yes                                                | yes           | yes                                                |
| Data parallelism (parallel for-loop)                                                             | yes                                                        | yes                                                | no            | yes                                                |
| Nested parallel-for regions support                                                              | no (lead to oversubscription)                              | yes                                                | N/A           | yes                                                |
| Dataflow parallelism (Tasks triggered by events / precise task dependencies)                     | yes                                                        | yes                                                | no            | yes                                                |
| Communication mechanisms | Shared-memory | Message-passing / Channels | Shared-memory | Shared-memory
| Load balancing strategy                                                                          | static (GCC), work-stealing (Intel/LLVM)                   | work-sharing / work-requesting                     | work-stealing | work-stealing                                      |
| Blocked tasks don't block runtime                                                                | N/A                                                        | no                                                 | yes           | yes                                                |
| Load-balancing strategy for task parallelism (important for fine-grained parallelism)            | global queue (GCC), steal-one (Intel/LLVM)                 | Adaptative steal-one/steal-half                    | steal-one     | steal-one                                         |
| Load-balancing strategy for data parallelism                                                     | eager splitting depending on iteration count and cpu count | lazy splitting depending on idle CPUs and workload | N/A           | lazy splitting depending on idle CPUs and workload |
| Backoff worker when idle                                                                         | yes (?)                                                    | yes                                                | yes           | yes                                                |
| Backoff worker when awaiting task but no work                                                    | N/A                                                        | no                                                 | no            | yes                                                |
| Scheduler overhead/contention (measured on Fibonacci 40), important for fine-grained parallelism | Extreme: frozen runtime (GCC), high (Intel/LLVM)           | low to very low                                    | medium        | low                                                |

## Key features design

### Scheduler overhead/contention

#### Distributed task queues
To enable fine-grained parallelism, i.e. parallelizing tasks in the microseconds range, it's critical to reduce contention.
A global task queue will be hammered by N threads, leading to each thrashing each other caches.
In contrast, distributed task queues with random victim selection significantly reduce contention.

#### Memory allocation
Another source of overhead is the allocator, the worst case for allocators is allocation in a thread and deallocation in another, especially if the
allocating thread is always the same. Unfortunately this is common in producer-consumer workloads.
Besides multithreaded allocations/deallocations will trigger costly atomic-swaps and possibly fragmentation.
Minimizing allocations to the utmost will significantly help on fine-grained tasks.
- Weave solved that problem by having 2 levels of cache: a memory-pool for tasks and futures and a lookaside list that caches tasks to reduce further pressure on the memory pool.
- Nim-taskpools does not address this problem, it has an allocation overhead per tasks of 1 for std/tasks, 1 for the linked list that holds them, 1 for the result channel/flowvar.
  Unlike GCC OpenMP which freezes on a fibonacci 40 benchmark, it can still finish but it's 20x slower than Weave.
- Constantine's threadpool solves the problem by making everything intrusive to a task: the task env, the future, the linked list.
In fact this solution is even faster than Weave's, probably due to significantly less page faults and cache misses.
Note that Weave has an even faster mode when futures don't escape their function by allocating them on the stack but without compiler support (heap allocation elision) that restricts the programs you can write.

### Load balancing for task parallelism

When a worker runs out of task, it steals from others' task queues.
They may steal one or multiple tasks.
In case of severe load imbalance, a steal-half policy can quickly rebalance workers queue to the global average.
This also helps reduce scheduler overhead by having logarithmically less steal attempts.
However, it may lead to significantly more rebalancing if workers generate few tasks.

Weave implements adaptative work-stealing with runtime selection of steal-one/steal-half
- Embracing Explicit Communication in Work-Stealing Runtime Systems.\
  Andreas Prell, 2016\
  https://epub.uni-bayreuth.de/id/eprint/2990/

Constantine's threadpool will likely adopt the same if the following task queues can be implemented with low overhead
- Non-Blocking Steal-Half Work Queues\
  Danny Hendler, Nir Shavit, 2002\
  https://www.cs.bgu.ac.il/~hendlerd/papers/p280-hendler.pdf

### Load-balancing for data parallelism

A critical issue in most (all?) runtimes used in HPC (OpenMP and Intel TBB in particular) is that they split their parallel for loop ahead of time.
They do not know how many idle threads there are, or how costly the workload that will be run will be. This leads to significant inefficiencies and performance unportability.
For example this repo https://github.com/zy97140/omp-benchmark-for-pytorch gives the number of elements thresholds under which parallelization is not profitable or even hurt performance for common float operations:

> |CPU Model|Sockets|Cores/Socket|Frequency|
> |---|---|---|---|
> |Intel(R) Xeon(R) CPU E5-2699 v4   |2|22|2.20GHz|
> |Intel(R) Xeon(R) Platinum 8180 CPU|2|28|2.50GHz|
> |Intel(R) Core(TM) i7-5960X CPU |1|8|3.00GHz|
>
> |   |Xeon(R) Platinum 8180 CPU|Xeon(R) CPU E5-2699 v4| i7-5960X CPU|
> |---|------------------------:|---------------------:|------------:|
> |copy|80k|20k|8k|
> |add |80k|20k|8k|
> |div |50k|10k|2k|
> |exp |1k |1k |1k|
> |sin |1k |1k |1k|
> |sum |1k |1k |1k|
> |prod|1k |1k |1k|
>
> Details on the Xeon Platinum
>
> |Tensor Size|In series|In parallel|SpeedUp|
> |---|---:|---:|---:|
> |1k	|1.04	|5.15|		0.20X      |
> |2k	|1.23	|5.47|		0.22X      |
> |3k	|1.33	|5.34|		0.24X      |
> |4k	|1.47	|5.41|		0.27X      |
> |5k	|1.48	|5.40|		0.27X      |
> |8k	|1.81	|5.55|		0.32X      |
> |10k|1.98	|5.66|		0.35X      |
> |20k|2.74	|6.74|		0.40X      |
> |50k|5.12	|6.59|		0.77X      |
> |__80k__|__14.79__|__6.59__|		__2.24X__      |
> |__100k__|__21.97__|__6.70__|		__3.27X__      |

Instead we can have each thread start working and use backpressure to lazily evaluate when it's profitable to split:
- Lazy Binary-Splitting: A Run-Time Adaptive Work-Stealing Scheduler
  Tzannes, Caragea, Barua, Vishkin
  https://terpconnect.umd.edu/~barua/ppopp164.pdf

### Backoff workers when awaiting a future

This problem is quite tricky:
- For latency we want the worker to continue as soon as the future is completed. This might also create more work and expose more parallelism opportunities (in recursive divide-and-conquer algorithms for example).\
  Note that with hyperthreading, the sibling thread(s) can still use the core fully so throughput might not be impacted.
- For throughput, and because a scheduler is optimal only when greedy (i.e. within 2x of the best schedule, see Cilk paper), we want an idle thread to take any available work ASAP.
  - but what if that worker ends up with work that blocks it for a long-time? It may lead to work starvation.
- There is no robust, cross-platform API, to wake a specific thread awaiting on a futex or condition variable.
  - The simplest design then would be to have an array of futexes, when backing-off sleep on those.
    The issue then is that when offering work you have to scan that array to find a worker to wake.
    Contrary to a idle worker, the waker is working so this scan hurts throughput and latency, and due to the many
    atomics operations required, will completely thrash the cache of that worker.
  - The even more simple is to wake-all on future completion
  - Another potential data structure would be a concurrent sparse-set but designing concurrent data structures is difficult.
    and locking would be expensive for an active worker.
- Alternative designs would be:
  - Not sleep
  - Having reserve threads:
    Before sleeping when blocked on a future the thread wakes a reserve thread. As the number of hardware resources is maintained we maintain throughput.
    The waiting thread is also immediately available when the future is completed since it cannot be stuck in work.
    A well-behaved program will always have at least 1 thread making progress among N, so a reserve of size N is sufficient.
    Unfortunately, this solution suffers for high latency of wakeups and/or kernel context-switch.
    For fine-grained tasks it is quite impactful: heat benchmark is 7x slower, fibonacci 1.5x, depth-first-search 2.5x.
    For actual workload, the elliptic curve sum reduction is also significantly slower.
  - Using continuations:
    We could just store a continuation in the future so the thread that completes the future picks up the continuation.

Besides design issues, there are also engineering issues as we can't wake a specific thread on a common futex or condition variable.
- Either a thread sleeps on a locally owned one, but how to communicate its address to the thief?
  And how to synchronize freeing the task memory?
  In particular, if we use the task as the medium, how to avoid race condition where:
  task is completed by thief, task memory is freed by waiter, thief tries to get the waiter futex/condition variable
  and triggers a use-after-free.
- or its sleeps on the global and each stolen completed task triggers a wakeAll
- or we create a backoff data structure where specific waiters can be woken up.

Our solution is to embed the backoff structure in the task and add an additional flag to notify when the task can be freed safely.