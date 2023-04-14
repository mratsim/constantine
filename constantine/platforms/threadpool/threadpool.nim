# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

when not compileOption("threads"):
  {.error: "This requires --threads:on compilation flag".}

{.push raises: [], checks: off.}

import
  std/[cpuinfo, atomics, macros],
  ./crossthread/[
    taskqueues,
    backoff,
    scoped_barriers,
    tasks_flowvars],
  ./instrumentation,
  ./primitives/barriers,
  ./parallel_offloading,
  ../allocs, ../bithacks

export
  # flowvars
  Flowvar, isSpawned, isReady

when defined(TP_Metrics):
  import ../static_for
  import system/ansi_c

# ############################################################
#                                                            #
#                            RNG                             #
#                                                            #
# ############################################################
#
# We don't need a CSPRNG, the RNG is to select a random victim when work-stealing
#
# - Scrambled Linear Pseudorandom Number Generators
#   Blackman, Vigna, 2021
#   https://vigna.di.unimi.it/ftp/papers/ScrambledLinear.pdf
#   https://prng.di.unimi.it/

type WorkStealingRng = object
  ## This is the state of a Xoshiro256+ PRNG
  ## It is used for work-stealing. The low bits have low linear complexity.
  ## So we use the high 32 bits to seed our pseudo random walk of thread taskqueues.
  s: array[4, uint64]

func splitMix64(state: var uint64): uint64 =
  state += 0x9e3779b97f4a7c15'u64
  result = state
  result = (result xor (result shr 30)) * 0xbf58476d1ce4e5b9'u64
  result = (result xor (result shr 27)) * 0xbf58476d1ce4e5b9'u64
  result = result xor (result shr 31)

func seed(rng: var WorkStealingRng, x: SomeInteger) =
  ## Seed the random number generator with a fixed seed
  var sm64 = uint64(x)
  rng.s[0] = splitMix64(sm64)
  rng.s[1] = splitMix64(sm64)
  rng.s[2] = splitMix64(sm64)
  rng.s[3] = splitMix64(sm64)

func rotl(x: uint64, k: static int): uint64 {.inline.} =
  return (x shl k) or (x shr (64 - k))

template `^=`(x: var uint64, y: uint64) =
  x = x xor y

func nextU32(rng: var WorkStealingRng): uint32 =
  ## Compute a random uint32
  # Need to use the high bits
  result = uint32((rng.s[0] + rng.s[3]) shr 32)

  let t = rng.s[1] shl 17
  rng.s[2] ^= rng.s[0];
  rng.s[3] ^= rng.s[1];
  rng.s[1] ^= rng.s[2];
  rng.s[0] ^= rng.s[3];

  rng.s[2] ^= t;

  rng.s[3] = rotl(rng.s[3], 45);

iterator pseudoRandomPermutation(randomSeed: uint32, maxExclusive: int32): int32 =
  ## Create (low-quality) pseudo-random permutations for [0, max)
  # Design considerations and randomness constraint for work-stealing, see docs/random_permutations.md
  #
  # Linear Congruential Generator: https://en.wikipedia.org/wiki/Linear_congruential_generator
  #
  # Xₙ₊₁ = aXₙ+c (mod m) generates all random number mod m without repetition
  # if and only if (Hull-Dobell theorem):
  # 1. c and m are coprime
  # 2. a-1 is divisible by all prime factors of m
  # 3. a-1 is divisible by 4 if m is divisible by 4
  #
  # Alternative 1. By choosing a=1, all conditions are easy to reach.
  #
  # The randomness quality is not important besides distributing potential contention,
  # i.e. randomly trying thread i, then i+1, then i+n-1 (mod n) is good enough.
  #
  # Assuming 6 threads, co-primes are [1, 5], which means the following permutations
  # assuming we start with victim 0:
  # - [0, 1, 2, 3, 4, 5]
  # - [0, 5, 4, 3, 2, 1]
  # While we don't care much about randoness quality, it's a bit disappointing.
  #
  # Alternative 2. We can choose m to be the next power of 2, meaning all odd integers are co-primes,
  # consequently:
  # - we don't need a GCD to find the coprimes
  # - we don't need to cache coprimes, removing a cache-miss potential
  # - a != 1, so we now have a multiplicative factor, which makes output more "random looking".

  # n and (m-1) <=> n mod m, if m is a power of 2
  let maxExclusive = cast[uint32](maxExclusive)
  let M = maxExclusive.nextPowerOfTwo_vartime()
  let c = (randomSeed and ((M shr 1) - 1)) * 2 + 1 # c odd and c ∈ [0, M)
  let a = (randomSeed and ((M shr 2) - 1)) * 4 + 1 # a-1 divisible by 2 (all prime factors of m) and by 4 if m divisible by 4

  let mask = M-1                                   # for mod M
  let start = randomSeed and mask

  var x = start
  while true:
    if x < maxExclusive:
      yield cast[int32](x)
    x = (a*x + c) and mask                         # ax + c (mod M), with M power of 2
    if x == start:
      break

# ############################################################
#                                                            #
#                           Types                            #
#                                                            #
# ############################################################

let countersDesc {.compileTime.} = @[
  ("tasksScheduled", "tasks scheduled"),
  ("tasksStolen", "tasks stolen"),
  ("tasksExecuted", "tasks executed"),
  ("unrelatedTasksExecuted", "unrelated tasks executed"),
  ("loopsSplit", "loops split"),
  ("itersScheduled", "iterations scheduled"),
  ("itersStolen", "iterations stolen"),
  ("itersExecuted", "iterations executed"),
  ("theftsIdle", "thefts while idle in event loop"),
  ("theftsAwaiting", "thefts while awaiting a future"),
  ("theftsLeapfrog", "leapfrogging thefts"),
  ("backoffGlobalSleep", "sleeps on global backoff"),
  ("backoffGlobalSignalSent", "signals sent on global backoff"),
  ("backoffTaskAwaited", "sleeps on task-local backoff")
]

defCountersType(Counters, countersDesc)

type
  WorkerID = int32
  Signal = object
    terminate {.align: 64.}: Atomic[bool]

  WorkerContext = object
    ## Thread-local worker context

    # Params
    id: WorkerID
    threadpool: Threadpool

    # Tasks
    taskqueue: ptr Taskqueue    # owned task queue
    currentTask: ptr Task

    # Synchronization
    currentScope*: ptr ScopedBarrier # need to be exported for syncScope template
    signal: ptr Signal          # owned signal

    # Thefts
    rng: WorkStealingRng        # RNG state to select victims

    when defined(TP_Metrics):
      counters: Counters

  Threadpool* = ptr object
    # All synchronization objects are put in their own cache-line to avoid invalidating
    # and reloading cache for immutable fields
    barrier{.align: 64.}: SyncBarrier                            # Barrier for initialization and teardown
    # -- align: 64
    globalBackoff{.align: 64.}: EventCount                       # Multi-Producer Multi-Consumer backoff
    # -- align: 64
    numThreads*{.align: 64.}: int32                              # N regular workers
    workerQueues: ptr UncheckedArray[Taskqueue]                  # size N
    workers: ptr UncheckedArray[Thread[(Threadpool, WorkerID)]]  # size N
    workerSignals: ptr UncheckedArray[Signal]                    # size N

# ############################################################
#                                                            #
#                          Metrics                           #
#                                                            #
# ############################################################

template metrics(body: untyped): untyped =
  when defined(TP_Metrics):
    block: {.noSideEffect, gcsafe.}: body

template incCounter(ctx: var WorkerContext, name: untyped{ident}, amount = 1) =
  bind name
  metrics:
    # Assumes workerContext is in the calling context
    ctx.counters.name += amount

proc calcDerivedMetrics(ctx: var WorkerContext) {.used.} =
  metrics:
    ctx.counters.tasksStolen = ctx.counters.theftsIdle + ctx.counters.theftsAwaiting

proc printWorkerMetrics(ctx: var WorkerContext) =
  metrics:
    if ctx.id == 0:
      c_printf("\n")
      c_printf("+========================================+\n")
      c_printf("|  Per-worker statistics                 |\n")
      c_printf("+========================================+\n")
      flushFile(stdout)

    ctx.calcDerivedMetrics()
    discard ctx.threadpool.barrier.wait()

    staticFor i, 0, countersDesc.len:
      const (propName, propDesc) = countersDesc[i]
      c_printf("Worker %3d: counterId %2d, %10d, %-32s\n", ctx.id, i, ctx.counters.getCounter(propName), propDesc)

    flushFile(stdout)

# ############################################################
#                                                            #
#                        Profiling                           #
#                                                            #
# ############################################################

profileDecl(run_task)
profileDecl(backoff_idle)
profileDecl(backoff_awaiting)

# ############################################################
#                                                            #
#                         Workers                            #
#                                                            #
# ############################################################

var workerContext {.threadvar.}: WorkerContext
  ## Thread-local Worker context
  ## We assume that a threadpool has exclusive ownership
  ##
  ## TODO: if we want to allow non-conflicting threadpools instantiated by the same thread:
  ##       - only the threadID per threadpool should be stored and the associated
  ##         context should be stored at the Threadpool-level.
  ##         Then we need to associate threadpool pointer to workerID in that threadpool
  ##       - Or we completely remove thread-local data
  ##         and use a Minimal Perfect Hash Function.
  ##         We can approximate a threadID by retrieving the address of a dummy thread-local variable.
  ##       - Or we sort threadID and use binary search
  ##       The FlowVar would also need to store the Threadpool

proc setupWorker(ctx: var WorkerContext) =
  ## Initialize the thread-local context of a worker
  ## Requires the ID and threadpool fields to be initialized
  preCondition: not ctx.threadpool.isNil()
  preCondition: 0 <= ctx.id and ctx.id < ctx.threadpool.numThreads
  preCondition: not ctx.threadpool.workerQueues.isNil()
  preCondition: not ctx.threadpool.workerSignals.isNil()

  # Thefts
  ctx.rng.seed(0xEFFACED + ctx.id)

  # Synchronization
  ctx.currentScope = nil
  ctx.signal = addr ctx.threadpool.workerSignals[ctx.id]
  ctx.signal.terminate.store(false, moRelaxed)

  # Tasks
  ctx.taskqueue = addr ctx.threadpool.workerQueues[ctx.id]
  ctx.currentTask = nil

  # Init
  ctx.taskqueue[].init(initialCapacity = 32)

proc teardownWorker(ctx: var WorkerContext) =
  ## Cleanup the thread-local context of a worker
  ctx.taskqueue[].teardown()

proc eventLoop(ctx: var WorkerContext) {.raises:[], gcsafe.}

proc workerEntryFn(params: tuple[threadpool: Threadpool, id: WorkerID]) {.raises: [].} =
  ## On the start of the threadpool workers will execute this
  ## until they receive a termination signal
  # We assume that thread_local variables start all at their binary zero value
  preCondition: workerContext == default(WorkerContext)

  template ctx: untyped = workerContext

  # If the following crashes, you need --tlsEmulation:off
  ctx.id = params.id
  ctx.threadpool = params.threadpool

  ctx.setupWorker()

  # 1 matching barrier in Threadpool.new() for root thread
  discard params.threadpool.barrier.wait()

  ctx.eventLoop()

  debugTermination:
    log(">>> Worker %3d shutting down <<<\n", ctx.id)

  # 1 matching barrier in threadpool.shutdown() for root thread
  discard params.threadpool.barrier.wait()

  ctx.printWorkerMetrics()
  ctx.id.printWorkerProfiling()

  ctx.teardownWorker()

# ############################################################
#                                                            #
#                           Tasks                            #
#                                                            #
# ############################################################
#
# Task notification overview
#
# 2 strategies can be used to notify idle workers of new tasks entering the runtime
#
# 1. "notify-on-new": Always try to wake a worker on the backoff on new tasks.
# 2. "notify-on-transition": Wake a worker if-and-only-if our queue was empty when scheduling the task.
#
# In the second case, we also need a notify on successful theft to maintain the invariant that
# there is at least a thread looking for work if work is available, or all threads are busy.
#
# The notify-on-transition strategy minimizes kernel syscalls at the expense of reading an atomic,
# our dequeue status (a guaranteed cache miss).
# This is almost always the better tradeoff.
# Furthermore, in work-stealing, having an empty dequeue is a good approximation for starvation.
#
# We can minimize syscalls in the "notify-on-new" strategy as well by reading the backoff status
# and checking if there is an idle worker not yet parked or no parked threads at all.
# In that case we also need a notification on successful theft,
# in case 2 threads enqueueing work find concurrently the same non-parked idle worker, otherwise one task will be missed.
#
# The "notify-on-new" minimizes latency in case a producer enqueues tasks quickly.
#
# Lastly, when awaiting a future, a worker can give up its own queue if tasks are unrelated to the awaited task.
# In "notify-on-transition" strategy, that worker needs to wake up a relay.
#
# Concretely on almost-empty tasks like fibonacci or DFS, "notify-on-new" is 10x slower.
# However, when quickly enqueueing tasks, like Multi-Scalar Multiplication,
# There is a noticeable ramp-up.This might be solved with steal-half.

# Sentinel values
const RootTask = cast[ptr Task](0xEFFACED0)

proc run(ctx: var WorkerContext, task: ptr Task) {.raises:[].} =
  ## Run a task, frees it if it is not owned by a Flowvar

  let suspendedTask = ctx.currentTask
  let suspendedScope = ctx.currentScope

  ctx.currentTask = task
  ctx.currentScope = task.scopedBarrier

  debug: log("Worker %3d: running task 0x%.08x (previous: 0x%.08x, %d pending, thiefID %d)\n", ctx.id, task, suspendedTask, ctx.taskqueue[].peek(), task.getThief())
  profile(run_task):
    task.fn(task.env.addr)
  task.scopedBarrier.unlistDescendant()
  debug: log("Worker %3d: completed task 0x%.08x (%d pending)\n", ctx.id, task, ctx.taskqueue[].peek())

  ctx.currentTask = suspendedTask
  ctx.currentScope = suspendedScope

  ctx.incCounter(tasksExecuted)
  ctx.incCounter(itersExecuted):
    if task.loopStepsLeft == NotALoop: 0
    else: (task.loopStop - task.loopStart + task.loopStride-1) div task.loopStride

  if not task.hasFuture: # Are we the final owner?
    debug: log("Worker %3d: freeing task 0x%.08x with no future\n", ctx.id, task)
    freeHeap(task)
    return

  # Sync with an awaiting thread in completeFuture that didn't find work
  # and transfer ownership of the task to it.
  debug: log("Worker %3d: transfering task 0x%.08x to future holder\n", ctx.id, task)
  task.setCompleted()
  task.setGcReady()

proc schedule(ctx: var WorkerContext, task: ptr Task, forceWake = false) {.inline.} =
  ## Schedule a task in the threadpool
  ## This wakes another worker if our local queue is empty
  ## or forceWake is true.
  debug: log("Worker %3d: schedule task 0x%.08x (parent/current task 0x%.08x, scope 0x%.08x)\n", ctx.id, task, task.parent, task.scopedBarrier)

  # Instead of notifying every time a task is scheduled, we notify
  # only when the worker queue is empty. This is a good approximation
  # of starvation in work-stealing.
  let wasEmpty = ctx.taskqueue[].peek() == 0
  ctx.taskqueue[].push(task)

  ctx.incCounter(tasksScheduled)
  ctx.incCounter(itersScheduled):
    if task.loopStepsLeft == NotALoop: 0
    else: task.loopStepsLeft

  if forceWake or wasEmpty:
    ctx.threadpool.globalBackoff.wake()
    ctx.incCounter(backoffGlobalSignalSent)

# ############################################################
#                                                            #
#              Parallel-loops load-balancing                 #
#                                                            #
# ############################################################

# Inpired by
# - Lazy binary-splitting: a run-time adaptive work-stealing scheduler.
#   Tzannes, A., G. C. Caragea, R. Barua, and U. Vishkin.
#   In PPoPP ’10, Bangalore, India, January 2010. ACM, pp. 179–190.
#   https://user.eng.umd.edu/~barua/ppopp164.pdf
# - Embracing Explicit Communication in Work-Stealing Runtime Systems.
#   Andreas Prell, 2016
#   https://epub.uni-bayreuth.de/id/eprint/2990/
#
# Instead of splitting loops ahead of time depending on the number of cores,
# we split just-in-time depending on idle threads.
# This allows the code to lazily evaluate when it's profitable to split,
# making parallel-for performance portable to any CPU and any inner algorithm
# unlike OpenMP or TBB for example, see design.md for performance unportability benchmark numbers.
# This frees the developer from grain size / work splitting thresholds.

iterator splitUpperRanges(
           ctx: WorkerContext, task: ptr Task,
           curLoopIndex: int, approxIdle: int32
         ): tuple[start, size: int] =
  ## Split the iteration range based on the number of idle threads
  ## returns chunks with parameters (start, stopEx, len)
  ##
  ## - Chunks are balanced, their size differs by at most 1.
  ##   Balanced workloads are scheduled with overhead similar to static scheduling.
  ## - Split is adaptative, unlike static scheduling or guided scheduling in OpenMP
  ##   it is based on idle workers and not the number of cores.
  ##   If enough parallelism is exposed, for example due to nested parallelism,
  ##   there is no splitting overhead.
  ##
  ## - Updates the current task loopStop with the lower range
  #
  # Unbalanced example:
  #  Splitting 40 iterations on 12 threads
  #  A simple chunking algorithm with division + remainder
  #  will lead to a base chunk size of 40/12 = 3.
  #  3*11 = 33, so last thread will do 7 iterations, more than twice the work.
  #
  # Note: Each division costs 55 cycles, 55x more than addition/substraction/bit operations
  #       and they can't use instruction-level parallelism.
  #       When dealing with loop ranges and strides we need to carefully craft our code to
  #       only use division where unavoidable: dividing by the number of idle threads.
  #       Loop metadata should allow us to avoid loop-bounds-related divisions completely.
  preCondition: task.loopStepsLeft > 1
  preCondition: curLoopIndex mod task.loopStride == 0

  debugSplit:
    log("Worker %3d: task 0x%.08x - %8d step(s) left                    (current: %3d, start: %3d, stop: %3d, stride: %3d, %3d idle worker(s))\n",
      ctx.id, task, task.loopStepsLeft, curLoopIndex, task.loopStart, task.loopStop, task.loopStride, approxIdle)

  # Send a chunk of work to all idle workers + ourselves
  let availableWorkers = cast[int](approxIdle + 1)
  let baseChunkSize = task.loopStepsLeft div availableWorkers
  let cutoff        = task.loopStepsLeft mod availableWorkers

  block: # chunkID 0 is ours! My precious!!!
    task.loopStepsLeft = baseChunkSize + int(0 < cutoff)
    task.loopStop = min(task.loopStop, curLoopIndex + task.loopStepsLeft*task.loopStride)

    debugSplit:
      log("Worker %3d: task 0x%.08x - %8d step(s) kept locally            (current: %3d, start: %3d, stop: %3d, stride: %3d)\n",
        ctx.id, task, task.loopStepsLeft, curLoopIndex, task.loopStart, task.loopStop, task.loopStride)

  for chunkID in 1 ..< availableWorkers:
    # As the iterator callsite is copy-pasted, we want a single yield point.
    var chunkSize = baseChunkSize
    var offset    = curLoopIndex
    if chunkID < cutoff:
      chunkSize += 1
      offset += task.loopStride*chunkSize*chunkID
    else:
      offset += task.loopStride*(baseChunkSize*chunkID + cutoff)
    yield (offset, chunkSize)

type BalancerBackoff = object
  ## We want to dynamically split parallel loops depending on the number of idle threads.
  ## However checking an atomic variable require synchronization which at the very least means
  ## reloading its value in all caches, a guaranteed cache miss. In a tight loop,
  ## this might be a significant cost, especially given that memory is often the bottleneck.
  ##
  ## There is no synchronization possible with thieves, unlike Prell PhD thesis.
  ## We want to avoid the worst-case scenario in Tzannes paper, tight-loop with too many available cores
  ## so the producer deque is always empty, leading to it spending all its CPU time splitting loops.
  ## For this we split depending on the numbers of idle CPUs. This prevents also splitting unnecessarily.
  ##
  ## Tzannes et al mentions that checking the thread own deque emptiness is a good approximation of system load
  ## with low overhead except in very fine-grained parallelism.
  ## With a better approximation, by checking the number of idle threads we can instead
  ## directly do the correct number of splits or avoid splitting. But this check is costly.
  ##
  ## To minimize checking cost while keeping latency low, even in bursty cases,
  ## we use log-log iterated backoff.
  ## - Adversarial Contention Resolution for Simple Channels
  ##   Bender, Farach-Colton, He, Kuszmaul, Leiserson, 2005
  ##   https://people.csail.mit.edu/bradley/papers/BenderFaHe05.pdf
  nextCheck: int
  windowLogSize: uint32 # while loopIndex < lastCheck + 2^windowLogSize, don't recheck.
  round: uint32         # windowSize += 1 after log(windowLogSize) rounds

func increase(backoff: var BalancerBackoff) {.inline.} =
  # On failure, we use log-log iterated backoff, an optimal backoff strategy
  # suitable for bursts and adversarial conditions.
  backoff.round += 1
  if backoff.round >= log2_vartime(backoff.windowLogSize):
    backoff.round = 0
    backoff.windowLogSize += 1

func decrease(backoff: var BalancerBackoff) {.inline.} =
  # On success, we exponentially reduce check window.
  # Note: the thieves will start contributing as well.
  if backoff.windowLogSize > 0:
    backoff.windowLogSize -= 1
  backoff.round = 0

proc splitAndDispatchLoop(ctx: var WorkerContext, task: ptr Task, curLoopIndex: int, approxIdle: int32) =
  # The iterator mutates the task with the first chunk metadata
  let stop = task.loopStop
  for (offset, numSteps) in ctx.splitUpperRanges(task, curLoopIndex, approxIdle):
    if numSteps == 0:
      break

    let upperSplit = allocHeapUnchecked(Task, sizeof(Task) + task.envSize)
    copyMem(upperSplit, task, sizeof(Task) + task.envSize)

    upperSplit.initSynchroState()
    upperSplit.parent        = task
    upperSplit.scopedBarrier.registerDescendant()

    upperSplit.isFirstIter   = false
    upperSplit.loopStart     = offset
    upperSplit.loopStop      = min(stop, offset + numSteps*upperSplit.loopStride)
    upperSplit.loopStepsLeft = numSteps

    if upperSplit.hasFuture:
      # Update self-reference
      cast[ptr ptr Task](upperSplit.env.addr)[] = upperSplit
      # Create a private task-local linked-list of awaited tasks
      task.reductionDAG = newReductionDagNode(task = upperSplit, next = task.reductionDAG)
      upperSplit.reductionDAG = nil

    debugSplit:
      log("Worker %3d: task 0x%.08x - %8d step(s) sent in task 0x%.08x (start: %3d, stop: %3d, stride: %3d)\n",
           ctx.id, task, upperSplit.loopStepsLeft, upperSplit, upperSplit.loopStart, upperSplit.loopStop, upperSplit.loopStride)
    ctx.taskqueue[].push(upperSplit)

  ctx.threadpool.globalBackoff.wakeAll()
  ctx.incCounter(backoffGlobalSignalSent)

proc loadBalanceLoop(ctx: var WorkerContext, task: ptr Task, curLoopIndex: int, backoff: var BalancerBackoff) =
  ## Split a parallel loop when necessary
  # We might want to make this inline to cheapen the first check
  # but it is 10% faster not inline on the transpose benchmark (memory-bandwidth bound)
  if task.loopStepsLeft > 1 and curLoopIndex == backoff.nextCheck:
    if ctx.taskqueue[].peek() == 0:
      let waiters = ctx.threadpool.globalBackoff.getNumWaiters()
      # We assume that the worker that scheduled the task will work on it. I.e. idleness is underestimated.
      let approxIdle = waiters.preSleep + waiters.committedSleep + cast[int32](task.isFirstIter)
      if approxIdle > 0:
        ctx.splitAndDispatchLoop(task, curLoopIndex, approxIdle)
        ctx.incCounter(loopsSplit)
        backoff.decrease()
      else:
        backoff.increase()
    else:
      backoff.increase()

    backoff.nextCheck += task.loopStride shl backoff.windowLogSize

template parallelForWrapper(idx: untyped{ident}, loopBody: untyped): untyped =
  block:
    let this = workerContext.currentTask
    var backoff = BalancerBackoff(
      nextCheck: this.loopStart,
      windowLogSize: 0,
      round: 0)
    if not this.isFirstIter:
      # Task was just stolen, no need to check runtime status. do one loop first
      backoff.nextCheck += this.loopStride

    var idx = this.loopStart
    while idx < this.loopStop:
      loadBalanceLoop(workerContext, this, idx, backoff)
      loopBody
      idx += this.loopStride
      this.loopStepsLeft -= 1

template parallelReduceWrapper(
    idx: untyped{ident},
    prologue, loopBody, mergeLocalWithRemote, epilogue,
    remoteTaskAwaitable, awaitableType: untyped): untyped =
  block:
    let this = workerContext.currentTask
    var backoff = BalancerBackoff(
      nextCheck: this.loopStart,
      windowLogSize: 0,
      round: 0
    )
    if not this.isFirstIter:
      # Task was just stolen, no need to check runtime status. do one loop first
      backoff.nextCheck += this.loopStride

    prologue

    block: # loop body
      var idx = this.loopStart
      while idx < this.loopStop:
        loadBalanceLoop(workerContext, this, idx, backoff)
        loopBody
        idx += this.loopStride
        this.loopStepsLeft -= 1

    block: # Merging with flowvars from remote threads
      while not this.reductionDAG.isNil:
        let reductionDagNode = this.reductionDAG
        let remoteTaskAwaitable = cast[Flowvar[awaitableType]](reductionDagNode.task)
        this.reductionDAG = reductionDagNode.next

        mergeLocalWithRemote

        # In `merge` there should be a sync which frees `reductionDagNode.task`
        freeHeap(reductionDagNode)

    epilogue

# ############################################################
#                                                            #
#                       Scheduler                            #
#                                                            #
# ############################################################

proc tryStealOne(ctx: var WorkerContext): ptr Task =
  ## Try to steal a task.
  let seed = ctx.rng.nextU32()
  for targetId in seed.pseudoRandomPermutation(ctx.threadpool.numThreads):
    if targetId == ctx.id:
      continue

    let stolenTask = ctx.id.steal(ctx.threadpool.workerQueues[targetId])

    if not stolenTask.isNil():
      return stolenTask
  return nil

proc tryLeapfrog(ctx: var WorkerContext, awaitedTask: ptr Task): ptr Task =
  ## Leapfrogging:
  ##
  ## - Leapfrogging: a portable technique for implementing efficient futures,
  ##   David B. Wagner, Bradley G. Calder, 1993
  ##   https://dl.acm.org/doi/10.1145/173284.155354
  ##
  ## When awaiting a future, we can look in the thief queue first. They steal when they run out of tasks.
  ## If they have tasks in their queue, it's the task we are awaiting that created them and it will likely be stuck
  ## on those tasks as well, so we need to help them help us.

  var thiefID = SentinelThief
  while true:
    debug: log("Worker %3d: leapfrogging - waiting for thief of task 0x%.08x to publish their ID (thiefID read %d)\n", ctx.id, awaitedTask, thiefID)
    thiefID = awaitedTask.getThief()
    if thiefID != SentinelThief:
      break
    cpuRelax()
  ascertain: 0 <= thiefID and thiefID < ctx.threadpool.numThreads

  let leapTask = ctx.id.steal(ctx.threadpool.workerQueues[thiefID])
  if not leapTask.isNil():
    return leapTask
  return nil

proc eventLoop(ctx: var WorkerContext) {.raises:[], gcsafe.} =
  ## Each worker thread executes this loop over and over.
  while true:
    # 1. Pick from local queue
    debug: log("Worker %3d: eventLoop 1 - searching task from local queue\n", ctx.id)
    while (var task = ctx.taskqueue[].pop(); not task.isNil):
      debug: log("Worker %3d: eventLoop 1 - running task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, task, task.parent, ctx.currentTask)
      ctx.run(task)

    # 2. Run out of tasks, become a thief
    debug: log("Worker %3d: eventLoop 2 - becoming a thief\n", ctx.id)
    let ticket = ctx.threadpool.globalBackoff.sleepy()
    if (var stolenTask = ctx.tryStealOne(); not stolenTask.isNil):
      # We manage to steal a task, cancel sleep
      ctx.threadpool.globalBackoff.cancelSleep()
      # Theft successful, there might be more work for idle threads, wake one
      # cancelSleep must be done before as wake has an optimization
      # to not notify when a thread is sleepy
      ctx.threadpool.globalBackoff.wake()
      ctx.incCounter(backoffGlobalSignalSent)

      ctx.incCounter(theftsIdle)
      ctx.incCounter(itersStolen):
        if stolenTask.loopStepsLeft == NotALoop: 0
        else: stolenTask.loopStepsLeft
      # 2.a Run task
      debug: log("Worker %3d: eventLoop 2.a - stole task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, stolenTask, stolenTask.parent, ctx.currentTask)
      ctx.run(stolenTask)
    elif ctx.signal.terminate.load(moAcquire):
      # 2.b Threadpool has no more tasks and we were signaled to terminate
      ctx.threadpool.globalBackoff.cancelSleep()
      debugTermination: log("Worker %3d: eventLoop 2.b - terminated\n", ctx.id)
      break
    else:
      # 2.c Park the thread until a new task enters the threadpool
      debugTermination: log("Worker %3d: eventLoop 2.b - sleeping\n", ctx.id)
      ctx.incCounter(backoffGlobalSleep)
      profile(backoff_idle):
        ctx.threadpool.globalBackoff.sleep(ticket)
      debugTermination: log("Worker %3d: eventLoop 2.b - waking\n", ctx.id)

# ############################################################
#                                                            #
#                 Futures & Synchronization                  #
#                                                            #
# ############################################################

proc completeFuture[T](fv: Flowvar[T], parentResult: var T) {.raises:[].} =
  ## Eagerly complete an awaited FlowVar
  template ctx: untyped = workerContext

  template isFutReady(): untyped =
    let isReady = fv.isReady()
    if isReady:
      parentResult.copyResult(fv)
    isReady

  if isFutReady():
    return

  ## 1. Process all the children of the current tasks first, ignoring the rest.
  debug: log("Worker %3d: sync 1 - searching task from local queue (awaitedTask 0x%.08x)\n", ctx.id, fv.task)
  while (let task = ctx.taskqueue[].pop(); not task.isNil):
    if task.parent != ctx.currentTask:
      debug: log("Worker %3d: sync 1 - skipping non-direct descendant task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, task, task.parent, ctx.currentTask)
      ctx.schedule(task, forceWake = true) # reschedule task and wake a sibling to take it over.
      break
    debug: log("Worker %3d: sync 1 - running task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, task, task.parent, ctx.currentTask)
    ctx.run(task)
    if isFutReady():
      debug: log("Worker %3d: sync 1 - future ready, exiting (awaitedTask 0x%.08x)\n", ctx.id, fv.task)
      return

  # 2. We run out-of-tasks or out-of-direct-child of our current awaited task
  #    So the task is bottlenecked by dependencies in other threads,
  #    hence we abandon our enqueued work and steal.
  #
  #    See also
  #    - Proactive work-stealing for futures
  #      Kyle Singer, Yifan Xu, I-Ting Angelina Lee, 2019
  #      https://dl.acm.org/doi/10.1145/3293883.3295735
  #
  # Design tradeoffs
  # ----------------
  # see ./docs/design.md
  #
  # Rundown:
  #
  # At this point, we have significant design decisions:
  # - Do we steal from other workers in hope we advance our awaited task?
  #   Note: A greedy scheduler (no worker idle as long as there is a runnable task)
  #         is at most 2x slower than the optimal schedule (proof in Cilk paper)
  # - Do we advance our own queue for tasks that are not child of our awaited tasks?
  # - Do we park instead of working on unrelated task?
  #   Note: With hyperthreading, real hardware resources are 2x less than the reported number of cores.
  #         Hence parking might free contended memory bandwitdh or execution ports.
  # - Do we just not sleep, potentially wasting energy?
  #   Note: on "empty tasks" (like Fibonacci), the constant hammering of threads
  #         actually slows down performance by 2x.
  #         This is a realistic scenario for IO (waiting to copy a network buffer for example)
  #         but the second almost-empty benchmark, depth-first-search is actually faster by 17%.
  #
  # - If we work, we maximize throughput, but we increase latency to handle the future's continuation.
  #   If that continuation would have created more parallel work, we would actually have restricted parallelism.
  # - If we park with tasks left, we minimize latency on the continuation, but we don't use hardware resources fully,
  #   and there are CPUs without hyperthreading (on ARM for example)
  # - If we park when no tasks are left, if more work is enqueued, as we don't park on the global backoff we will miss it.
  #   Note: we don't park on the global backoff, because it's not possible to control which thread to wake with it (or we wake all).
  # - Wakeup latency is high, having "reserve threads" that take over the active slot of the awaiting thread
  #   in theory maintains throughput and minimize the latency of the future's continuation
  #   but in practice, performance can worsen significantly on fine-grained parallelism.

  debug: log("Worker %3d: sync 2 - future not ready, becoming a thief (currentTask 0x%.08x, awaitedTask 0x%.08x)\n", ctx.id, ctx.currentTask, fv.task)
  while not isFutReady():
    if (let leapTask = ctx.tryLeapfrog(fv.getTask()); not leapTask.isNil):
      # Theft successful, there might be more work for idle threads, wake one
      ctx.threadpool.globalBackoff.wake()
      ctx.incCounter(backoffGlobalSignalSent)

      # Leapfrogging, the thief had an empty queue, hence if there are tasks in its queue, it's generated by our blocked task.
      # Help the thief clear those, as if it did not finish, it's likely blocked on those children tasks.
      ctx.incCounter(theftsLeapfrog)
      ctx.incCounter(itersStolen):
        if leapTask.loopStepsLeft == NotALoop: 0
        else: leapTask.loopStepsLeft

      debug: log("Worker %3d: sync 2.1 - leapfrog task 0x%.08x (parent 0x%.08x, current 0x%.08x, awaitedTask 0x%.08x)\n", ctx.id, leapTask, leapTask.parent, ctx.currentTask, fv.task)
      ctx.run(leapTask)
    elif (let stolenTask = ctx.tryStealOne(); not stolenTask.isNil):
      # Theft successful, there might be more work for idle threads, wake one
      ctx.threadpool.globalBackoff.wake()
      ctx.incCounter(backoffGlobalSignalSent)

      # We stole a task, we hope we advance our awaited task.
      ctx.incCounter(theftsAwaiting)
      ctx.incCounter(itersStolen):
        if stolenTask.loopStepsLeft == NotALoop: 0
        else: stolenTask.loopStepsLeft

      debug: log("Worker %3d: sync 2.2 - stole task 0x%.08x (parent 0x%.08x, current 0x%.08x, awaitedTask 0x%.08x)\n", ctx.id, stolenTask, stolenTask.parent, ctx.currentTask, fv.task)
      ctx.run(stolenTask)
    elif (let ownTask = ctx.taskqueue[].pop(); not ownTask.isNil):
      # We advance our own queue, this increases global throughput but may impact latency on the awaited task.
      debug: log("Worker %3d: sync 2.3 - couldn't steal, running own task (awaitedTask 0x%.08x)\n", ctx.id, fv.task)
      ctx.incCounter(unrelatedTasksExecuted)
      ctx.run(ownTask)
    else:
      # Nothing to do, we park.
      # - On today's hyperthreaded systems, this might reduce contention on a core resources like memory caches and execution ports
      # - If more work is created, we won't be notified as we need to park on a dedicated notifier for precise wakeup when future is ready
      debugTermination: log("Worker %3d: sync 2.4 - Empty runtime, parking (awaitedTask 0x%.08x)\n", ctx.id, fv.task)
      ctx.incCounter(backoffTaskAwaited)
      profile(backoff_awaiting):
        fv.getTask().sleepUntilComplete(ctx.id)
      debugTermination: log("Worker %3d: sync 2.4 - signaled, waking (awaitedTask 0x%.08x)\n", ctx.id, fv.task)

proc syncAll*(tp: Threadpool) {.raises: [].} =
  ## Blocks until all pending tasks are completed
  ## This MUST only be called from the root scope that created the threadpool
  template ctx: untyped = workerContext

  debugTermination:
    log(">>> Worker %3d enters global barrier <<<\n", ctx.id)

  preCondition: ctx.id == 0
  preCondition: ctx.currentTask.isRootTask()

  profileStop(run_task)

  while true:
    # 1. Empty local tasks
    debug: log("Worker %3d: syncAll 1 - searching task from local queue\n", ctx.id)
    while (let task = ctx.taskqueue[].pop(); not task.isNil):
      debug: log("Worker %3d: syncAll 1 - running task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, task, task.parent, ctx.currentTask)
      ctx.run(task)

    # 2. Help other threads
    if (var stolenTask = ctx.tryStealOne(); not stolenTask.isNil):
      # 2.a We stole some task
      debug: log("Worker %3d: syncAll 2.a - stole task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, stolenTask, stolenTask.parent, ctx.currentTask)

      # Theft successful, there might be more work for idle threads, wake one
      ctx.threadpool.globalBackoff.wake()
      ctx.incCounter(backoffGlobalSignalSent)

      ctx.incCounter(theftsIdle)
      ctx.incCounter(itersStolen):
        if stolenTask.loopStepsLeft == NotALoop: 0
        else: stolenTask.loopStepsLeft
      ctx.run(stolenTask)
    elif tp.globalBackoff.getNumWaiters() == (0'i32, tp.numThreads-1): # Don't count ourselves
      # 2.b all threads besides the current are parked
      debugTermination: log("Worker %3d: syncAll 2.b - termination, all other threads sleeping\n", ctx.id)
      break
    else:
      # 2.c We don't park as there is no notif for task completion
      cpuRelax()

  debugTermination:
    log(">>> Worker %3d leaves barrier <<<\n", ctx.id)

  profileStart(run_task)

proc wait(scopedBarrier: ptr ScopedBarrier) {.raises:[], gcsafe.} =
  ## Wait at barrier until all descendant tasks are completed
  template ctx: untyped = workerContext

  debugTermination:
    log(">>> Worker %3d enters scoped barrier 0x%.08x <<<\n", ctx.id, scopedBarrier)

  while scopedBarrier.hasDescendantTasks():
    # 1. Empty local tasks, the initial loop only has tasks from that scope or a child scope.
    debug: log("Worker %3d: syncScope 1 - searching task from local queue\n", ctx.id)
    while (let task = ctx.taskqueue[].pop(); not task.isNil):
      debug: log("Worker %3d: syncScope 1 - running task 0x%.08x (parent 0x%.08x, current 0x%.08x, scope 0x%.08x)\n", ctx.id, task, task.parent, ctx.currentTask, task.scopedBarrier)
      ctx.run(task)
      if not scopedBarrier.hasDescendantTasks():
        debugTermination:
          log(">>> Worker %3d exits scoped barrier 0x%.08x <<<\n", ctx.id, scopedBarrier)
        return

    # TODO: consider leapfrogging

    if (var stolenTask = ctx.tryStealOne(); not stolenTask.isNil):
      # 2.a We stole some task
      debug: log("Worker %3d: syncScope 2 - stole task 0x%.08x (parent 0x%.08x, current 0x%.08x, scope 0x%.08x)\n", ctx.id, stolenTask, stolenTask.parent, ctx.currentTask, stolenTask.scopedBarrier)

      # Theft successful, there might be more work for idle threads, wake one
      ctx.threadpool.globalBackoff.wake()
      ctx.incCounter(backoffGlobalSignalSent)

      ctx.incCounter(theftsIdle)
      ctx.incCounter(itersStolen):
        if stolenTask.loopStepsLeft == NotALoop: 0
        else: stolenTask.loopStepsLeft
      ctx.run(stolenTask)
    else:
      # TODO: backoff
      cpuRelax()

  debugTermination:
    log(">>> Worker %3d exits scoped barrier 0x%.08x <<<\n", ctx.id, scopedBarrier)

# ############################################################
#                                                            #
#                     Runtime API                            #
#                                                            #
# ############################################################

proc new*(T: type Threadpool, numThreads = countProcessors()): T {.raises: [ResourceExhaustedError].} =
  ## Initialize a threadpool that manages `numThreads` threads.
  ## Default to the number of logical processors available.
  ##
  ## A Constantine's threadpool cannot be instantiated
  ## on a thread managed by another Constantine's threadpool
  ## including the root thread.
  ##
  ## Mixing with other libraries' threadpools and runtime
  ## will not impact correctness but may impact performance.

  type TpObj = typeof(default(Threadpool)[]) # due to C import, we need a dynamic sizeof
  var tp = allocHeapUncheckedAlignedPtr(Threadpool, sizeof(TpObj), alignment = 64)

  tp.barrier.init(numThreads.uint32)
  tp.globalBackoff.initialize()
  tp.numThreads = numThreads.int32
  tp.workerQueues = allocHeapArrayAligned(Taskqueue, numThreads, alignment = 64)
  tp.workers = allocHeapArrayAligned(Thread[(Threadpool, WorkerID)], numThreads, alignment = 64)
  tp.workerSignals = allocHeapArrayAligned(Signal, numThreads, alignment = 64)

  # Setup master thread
  workerContext.id = 0
  workerContext.threadpool = tp

  # Start worker threads
  for i in 1 ..< numThreads:
    createThread(tp.workers[i], workerEntryFn, (tp, WorkerID(i)))

  # Root worker
  workerContext.setupWorker()

  # Root task, this is a sentinel task that is never called.
  workerContext.currentTask = RootTask

  # Wait for the child threads
  discard tp.barrier.wait()
  profileStart(run_task)
  return tp

proc cleanup(tp: var Threadpool) {.raises: [].} =
  ## Cleanup all resources allocated by the threadpool
  preCondition: workerContext.currentTask.isRootTask()

  for i in 1 ..< tp.numThreads:
    joinThread(tp.workers[i])

  tp.workerSignals.freeHeapAligned()
  tp.workers.freeHeapAligned()
  tp.workerQueues.freeHeapAligned()
  tp.globalBackoff.`=destroy`()
  tp.barrier.delete()

  tp.freeHeapAligned()

proc shutdown*(tp: var Threadpool) {.raises:[].} =
  ## Wait until all tasks are processed and then shutdown the threadpool
  preCondition: workerContext.currentTask.isRootTask()
  tp.syncAll()
  profileStop(run_task)

  # Signal termination to all threads
  for i in 0 ..< tp.numThreads:
    tp.workerSignals[i].terminate.store(true, moRelease)

  tp.globalBackoff.wakeAll()

  # 1 matching barrier in workerEntryFn
  discard tp.barrier.wait()

  workerContext.printWorkerMetrics()
  workerContext.id.printWorkerProfiling()

  workerContext.teardownWorker()
  tp.cleanup()

  # Delete dummy task
  workerContext.currentTask = nil

{.pop.} # raises:[]

# ############################################################
#                                                            #
#                     Parallel API                           #
#                                                            #
# ############################################################

# Structured parallelism API
# ---------------------------------------------

template syncScope*(body: untyped): untyped =
  block:
    let suspendedScope = workerContext.currentScope
    var scopedBarrier {.noInit.}: ScopedBarrier
    initialize(scopedBarrier)
    workerContext.currentScope = addr scopedBarrier
    block:
      body
    wait(scopedBarrier.addr)
    workerContext.currentScope = suspendedScope

# Task parallel API
# ---------------------------------------------

macro spawn*(tp: Threadpool, fnCall: typed): untyped =
  ## Spawns the input function call asynchronously, potentially on another thread of execution.
  ##
  ## If the function calls returns a result, spawn will wrap it in a Flowvar.
  ## You can use `sync` to block the current thread and extract the asynchronous result from the flowvar.
  ## You can use `isReady` to check if result is available and if a subsequent
  ## `sync` returns immediately.
  ##
  ## Tasks are processed approximately in Last-In-First-Out (LIFO) order
  result = spawnImpl(tp, fnCall, bindSym"workerContext", bindSym"schedule")

macro spawnAwaitable*(tp: Threadpool, fnCall: typed): untyped =
  ## Spawns the input function call asynchronously, potentially on another thread of execution.
  ##
  ## This allows awaiting a void function.
  ## The result, once ready, is always `true`.
  ##
  ## You can use `sync` to block the current thread until the function is finished.
  ## You can use `isReady` to check if result is available and if a subsequent
  ## `sync` returns immediately.
  ##
  ## Tasks are processed approximately in Last-In-First-Out (LIFO) order
  result = spawnAwaitableImpl(tp, fnCall, bindSym"workerContext", bindSym"schedule")

proc sync*[T](fv: sink Flowvar[T]): T {.noInit, inline, gcsafe.} =
  ## Blocks the current thread until the flowvar is available
  ## and returned.
  ## The thread is not idle and will complete pending tasks.
  profileStop(run_task)
  completeFuture(fv, result)
  cleanup(fv)
  profileStart(run_task)

# Data parallel API
# ---------------------------------------------

macro parallelFor*(tp: Threadpool, loopParams: untyped, body: untyped): untyped =
  ## Parallel for loop.
  ## Syntax:
  ##
  ## tp.parallelFor i in 0 ..< 10:
  ##   echo(i)
  ##
  ## Variables from the external scope needs to be explicitly captured
  ##
  ##  var a = 100
  ##  var b = 10
  ##  tp.parallelFor i in 0 ..< 10:
  ##    captures: {a, b}
  ##    echo a + b + i
  ##
  result = newStmtList()
  result.add quote do:
    # Avoid integer overflow checks in tight loop
    # and no exceptions in code.
    {.push checks:off.}

  if body.hasReduceSection():
    result.add parallelReduceImpl(
      bindSym"workerContext", bindSym"schedule",
      bindSym"parallelReduceWrapper",
      loopParams, body)
  else:
    result.add parallelForImpl(
      bindSym"workerContext", bindSym"schedule",
      bindSym"parallelForWrapper",
      loopParams, body)

  result.add quote do:
    {.pop.}
