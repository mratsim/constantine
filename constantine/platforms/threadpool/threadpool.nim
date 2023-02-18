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
    tasks_flowvars],
  ./instrumentation,
  ./primitives/barriers,
  ./parallel_offloading,
  ../allocs, ../bithacks,
  ../../../helpers/prng_unsafe

export
  # flowvars
  Flowvar, isSpawned, isReady, sync

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
    taskqueue: ptr Taskqueue          # owned task queue
    currentTask: ptr Task

    # Synchronization
    localBackoff: EventNotifier       # Multi-Producer Single-Consumer backoff
    signal: ptr Signal                # owned signal

    # Thefts
    rng: RngState                     # RNG state to select victims

    # Adaptative theft policy
    stealHalf: bool
    recentTasks: int32
    recentThefts: int32
    recentTheftsAdaptative: int32
    recentLeaps: int32

  Threadpool* = ptr object
    barrier: SyncBarrier                                         # Barrier for initialization and teardown
    # -- align: 64
    globalBackoff: EventCount                                    # Multi-Producer Multi-Consumer backoff
    reserveBackoff: EventCount
    # -- align: 64
    numThreads*{.align: 64.}: int32                              # N regular workers + N reserve workers
    workerQueues: ptr UncheckedArray[Taskqueue]                  # size 2N
    workers: ptr UncheckedArray[Thread[(Threadpool, WorkerID)]]  # size 2N
    workerSignals: ptr UncheckedArray[Signal]                    # size 2N
    # -- align: 64
    numIdleThreadsAwaitingFutures*{.align: 64.}: Atomic[int32]

# Thread-local config
# ---------------------------------------------

var workerContext {.threadvar.}: WorkerContext
  ## Thread-local Worker context

proc setupWorker() =
  ## Initialize the thread-local context of a worker
  ## Requires the ID and threadpool fields to be initialized
  template ctx: untyped = workerContext

  preCondition: not ctx.threadpool.isNil()
  preCondition: 0 <= ctx.id and ctx.id < 2*ctx.threadpool.numThreads
  preCondition: not ctx.threadpool.workerQueues.isNil()
  preCondition: not ctx.threadpool.workerSignals.isNil()

  # Thefts
  ctx.rng.seed(0xEFFACED + ctx.id)

  # Synchronization
  ctx.localBackoff.initialize()
  ctx.signal = addr ctx.threadpool.workerSignals[ctx.id]
  ctx.signal.terminate.store(false, moRelaxed)

  # Tasks
  ctx.taskqueue = addr ctx.threadpool.workerQueues[ctx.id]
  ctx.currentTask = nil

  # Init
  ctx.taskqueue[].init(initialCapacity = 32)

  # Adaptative theft policy
  ctx.recentTasks = 0
  ctx.recentThefts = 0
  ctx.recentTheftsAdaptative = 0
  ctx.recentLeaps = 0

proc teardownWorker() =
  ## Cleanup the thread-local context of a worker
  workerContext.localBackoff.`=destroy`()
  workerContext.taskqueue[].teardown()

proc eventLoopRegular(ctx: var WorkerContext) {.raises:[], gcsafe.}
proc eventLoopReserve(ctx: var WorkerContext) {.raises:[], gcsafe.}

proc workerEntryFn(params: tuple[threadpool: Threadpool, id: WorkerID]) {.raises: [].} =
  ## On the start of the threadpool workers will execute this
  ## until they receive a termination signal
  # We assume that thread_local variables start all at their binary zero value
  preCondition: workerContext == default(WorkerContext)

  template ctx: untyped = workerContext

  # If the following crashes, you need --tlsEmulation:off
  ctx.id = params.id
  ctx.threadpool = params.threadpool

  setupWorker()

  # 1 matching barrier in Threadpool.new() for root thread
  discard params.threadpool.barrier.wait()

  if ctx.id < ctx.threadpool.numThreads:
    ctx.eventLoopRegular()
  else:
    ctx.eventLoopReserve()

  debugTermination:
    log(">>> Worker %2d shutting down <<<\n", ctx.id)

  # 1 matching barrier in threadpool.shutdown() for root thread
  discard params.threadpool.barrier.wait()

  teardownWorker()

# Tasks
# ---------------------------------------------

# Sentinel values
const ReadyFuture = cast[ptr EventNotifier](0xCA11AB1E)
const RootTask = cast[ptr Task](0xEFFACED0)

proc run*(ctx: var WorkerContext, task: ptr Task) {.raises:[].} =
  ## Run a task, frees it if it is not owned by a Flowvar
  let suspendedTask = workerContext.currentTask
  ctx.currentTask = task
  debug: log("Worker %2d: running task.fn 0x%.08x (%d pending)\n", ctx.id, task.fn, ctx.taskqueue[].peek())
  task.fn(task.data.addr)
  debug: log("Worker %2d: completed task.fn 0x%.08x (%d pending)\n", ctx.id, task.fn, ctx.taskqueue[].peek())
  ctx.recentTasks += 1
  ctx.currentTask = suspendedTask
  if not task.hasFuture:
    freeHeap(task)
    return

  # Sync with an awaiting thread in completeFuture that didn't find work
  var expected = (ptr EventNotifier)(nil)
  if not compareExchange(task.waiter, expected, desired = ReadyFuture, moAcquireRelease):
    debug: log("Worker %2d: completed task 0x%.08x, notifying waiter 0x%.08x\n", ctx.id, task, expected)
    expected[].notify()

proc schedule(ctx: var WorkerContext, tn: ptr Task, forceWake = false) {.inline.} =
  ## Schedule a task in the threadpool
  ## This wakes a sibling thread if our local queue is empty
  ## or forceWake is true.
  debug: log("Worker %2d: schedule task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, tn, tn.parent, ctx.currentTask)

  # Instead of notifying every time a task is scheduled, we notify
  # only when the worker queue is empty. This is a good approximation
  # of starvation in work-stealing.
  # - Tzannes, A., G. C. Caragea, R. Barua, and U. Vishkin.
  #   Lazy binary-splitting: a run-time adaptive work-stealing scheduler.
  #   In PPoPP ’10, Bangalore, India, January 2010. ACM, pp. 179–190.
  #   https://user.eng.umd.edu/~barua/ppopp164.pdf
  let wasEmpty = ctx.taskqueue[].peek() == 0
  ctx.taskqueue[].push(tn)
  if forceWake or wasEmpty:
    ctx.threadpool.globalBackoff.wake()

# Scheduler
# ---------------------------------------------

iterator pseudoRandomPermutation(randomSeed: uint32, maxExclusive: int32): int32 =
  ## Create a (low-quality) pseudo-random permutation from [0, max)
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

proc tryStealOne(ctx: var WorkerContext): ptr Task =
  ## Try to steal a task.
  let seed = ctx.rng.next().uint32
  for targetId in seed.pseudoRandomPermutation(2*ctx.threadpool.numThreads):
    if targetId == ctx.id:
      continue

    let stolenTask = ctx.id.steal(ctx.threadpool.workerQueues[targetId])

    if not stolenTask.isNil():
      ctx.recentThefts += 1
      # Theft successful, there might be more work for idle threads, wake one
      ctx.threadpool.globalBackoff.wake()
      return stolenTask
  return nil

proc updateStealStrategy(ctx: var WorkerContext) =
  ## Estimate work-stealing efficiency during the last interval
  ## If the value is below a threshold, switch strategies
  const StealAdaptativeInterval = 25
  if ctx.recentTheftsAdaptative == StealAdaptativeInterval:
    let recentTheftsNonAdaptative = ctx.recentThefts - ctx.recentTheftsAdaptative
    let adaptativeTasks = ctx.recentTasks - ctx.recentLeaps - recentTheftsNonAdaptative

    let ratio = adaptativeTasks.float32 / StealAdaptativeInterval.float32
    if ctx.stealHalf and ratio < 2.0f:
      # Tasks stolen are coarse-grained, steal only one to reduce re-steal
      ctx.stealHalf = false
    elif not ctx.stealHalf and ratio == 1.0f:
      # All tasks processed were stolen tasks, we need to steal many at a time
      ctx.stealHalf = true

    # Reset interval
    ctx.recentTasks = 0
    ctx.recentThefts = 0
    ctx.recentTheftsAdaptative = 0
    ctx.recentLeaps = 0

proc tryStealAdaptative(ctx: var WorkerContext): ptr Task =
  ## Try to steal one or many tasks, depending on load

  # TODO: while running 'threadpool/examples/e02_parallel_pi.nim'
  #       stealHalf can error out in tasks_flowvars.nim with:
  #       "precondition not task.completed.load(moAcquire)"
  ctx.stealHalf = false
  # ctx.updateStealStrategy()

  let seed = ctx.rng.next().uint32
  for targetId in seed.pseudoRandomPermutation(2*ctx.threadpool.numThreads):
    if targetId == ctx.id:
      continue

    let stolenTask =
      if ctx.stealHalf: ctx.id.stealHalf(ctx.taskqueue[], ctx.threadpool.workerQueues[targetId])
      else:             ctx.id.steal(ctx.threadpool.workerQueues[targetId])

    if not stolenTask.isNil():
      ctx.recentThefts += 1
      ctx.recentTheftsAdaptative += 1
      # Theft successful, there might be more work for idle threads, wake one
      ctx.threadpool.globalBackoff.wake()
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
    debug: log("Worker %2d: waiting for thief to publish their ID\n", ctx.id)
    thiefID = awaitedTask.thiefID.load(moAcquire)
    if thiefID != SentinelThief:
      break
    cpuRelax()
  ascertain: 0 <= thiefID and thiefID < 2*ctx.threadpool.numThreads

  # Leapfrogging is used when completing a future, so steal only one task
  # and don't leave tasks stranded in our queue.
  let leapTask = ctx.id.steal(ctx.threadpool.workerQueues[thiefID])
  if not leapTask.isNil():
    ctx.recentLeaps += 1
    # Theft successful, there might be more work for idle threads, wake one
    ctx.threadpool.globalBackoff.wake()
    return leapTask
  return nil

proc eventLoopRegular(ctx: var WorkerContext) {.raises:[], gcsafe.} =
  ## Each worker thread executes this loop over and over.
  while true:
    # 1. Pick from local queue
    debug: log("Regular Worker %2d: eventLoopRegular 1 - searching task from local queue\n", ctx.id)
    while (var task = ctx.taskqueue[].pop(); not task.isNil):
      debug: log("Regular Worker %2d: eventLoopRegular 1 - running task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, task, task.parent, ctx.currentTask)
      ctx.run(task)

    # 2. Run out of tasks, become a thief
    debug: log("Regular Worker %2d: eventLoopRegular 2 - becoming a thief\n", ctx.id)
    let ticket = ctx.threadpool.globalBackoff.sleepy()
    if (var stolenTask = ctx.tryStealAdaptative(); not stolenTask.isNil):
      # We manage to steal a task, cancel sleep
      ctx.threadpool.globalBackoff.cancelSleep()
      # 2.a Run task
      debug: log("Regular Worker %2d: eventLoopRegular 2.a - stole task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, stolenTask, stolenTask.parent, ctx.currentTask)
      ctx.run(stolenTask)
    elif ctx.signal.terminate.load(moAcquire):
      # 2.b Threadpool has no more tasks and we were signaled to terminate
      ctx.threadpool.globalBackoff.cancelSleep()
      debugTermination: log("Regular Worker %2d: eventLoopRegular 2.b - terminated\n", ctx.id)
      break
    else:
      # 2.c Park the thread until a new task enters the threadpool
      debug: log("Regular Worker %2d: eventLoopRegular 2.b - sleeping\n", ctx.id)
      ctx.threadpool.globalBackoff.sleep(ticket)
      debug: log("Regular Worker %2d: eventLoopRegular 2.b - waking\n", ctx.id)

proc eventLoopReserve(ctx: var WorkerContext) {.raises:[], gcsafe.} =
  ## A reserve worker is a relay when a thread is stuck awaiting a future completion.
  ## This ensure those threads are available as soon as the future completes, minimizing latency
  ## while ensuring the runtime uses all available hardware resources, maximizing throughput.

  template reserveSleepCheck: untyped =
    let ticket = ctx.threadpool.reserveBackoff.sleepy()
    let (reservePlanningSleep, reserveCommittedSleep) = ctx.threadpool.reserveBackoff.getNumWaiters()
    let numActiveReservists = ctx.threadpool.numThreads - (reservePlanningSleep-1 + reserveCommittedSleep) # -1 we don't want to count ourselves

    if ctx.signal.terminate.load(moAcquire): # If terminated, we leave everything as-is, the regular workers will finish
      ctx.threadpool.reserveBackoff.cancelSleep()
      debugTermination: log("Reserve Worker %2d: reserveSleepCheck - terminated\n", ctx.id)
      return
    elif numActiveReservists > ctx.threadpool.numIdleThreadsAwaitingFutures.load(moAcquire):
      ctx.threadpool.globalBackoff.wake() # In case we were just woken up for a task or we have tasks in our queue, pass the torch
      debug: log("Reserve Worker %2d: reserveSleepCheck - going to sleep on reserve backoff\n", ctx.id)
      ctx.threadpool.reserveBackoff.sleep(ticket)
      debug: log("Reserve Worker %2d: reserveSleepCheck - waking on reserve backoff\n", ctx.id)
    else:
      ctx.threadpool.reserveBackoff.cancelSleep()

  while true:
    # 1. Pick from local queue
    debug: log("Reserve Worker %2d: eventLoopReserve 1 - searching task from local queue\n", ctx.id)
    while true:
      reserveSleepCheck()
      var task = ctx.taskqueue[].pop()
      if task.isNil():
        break
      debug: log("Reserve Worker %2d: eventLoopReserve 1 - running task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, task, task.parent, ctx.currentTask)
      ctx.run(task)

    # 2. Run out of tasks, become a thief
    debug: log("Reserve Worker %2d: eventLoopReserve 2 - becoming a thief\n", ctx.id)
    let ticket = ctx.threadpool.globalBackoff.sleepy() # If using a reserve worker was necessary, sleep on the backoff for active threads
    if (var stolenTask = ctx.tryStealAdaptative(); not stolenTask.isNil):
      # We manage to steal a task, cancel sleep
      ctx.threadpool.globalBackoff.cancelSleep()
      # 2.a Run task
      debug: log("Reserve Worker %2d: eventLoopReserve 2.a - stole task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, stolenTask, stolenTask.parent, ctx.currentTask)
      ctx.run(stolenTask)
    elif ctx.signal.terminate.load(moAcquire):
      # 2.b Threadpool has no more tasks and we were signaled to terminate
      ctx.threadpool.globalBackoff.cancelSleep()
      debugTermination: log("Reserve Worker %2d: eventLoopReserve 2.b - terminated\n", ctx.id)
      break
    else:
      # 2.c Park the thread until a new task enters the threadpool.
      #     It is intentionally parked with all active threads as long as a reservist is needed
      let (reservePlanningSleep, reserveCommittedSleep) = ctx.threadpool.reserveBackoff.getNumWaiters()
      let numActiveReservists = ctx.threadpool.numThreads - (reservePlanningSleep-1 + reserveCommittedSleep) # -1 we don't want to count ourselves
      if numActiveReservists > ctx.threadpool.numIdleThreadsAwaitingFutures.load(moAcquire):
        ctx.threadpool.globalBackoff.cancelSleep()
        continue

      debug: log("Reserve Worker %2d: eventLoopReserve 2.b - sleeping on active threads backoff\n", ctx.id)
      ctx.threadpool.globalBackoff.sleep(ticket)
      debug: log("Reserve Worker %2d: eventLoopReserve 2.b - waking on active threads backoff\n", ctx.id)

# Sync
# ---------------------------------------------

template isRootTask(task: ptr Task): bool =
  task == RootTask

proc completeFuture*[T](fv: Flowvar[T], parentResult: var T) {.raises:[].} =
  ## Eagerly complete an awaited FlowVar
  template ctx: untyped = workerContext

  template isFutReady(): untyped =
    let isReady = fv.task.completed.load(moAcquire)
    if isReady:
      parentResult = cast[ptr (ptr Task, T)](fv.task.data.addr)[1]
    isReady

  if isFutReady():
    return

  ## 1. Process all the children of the current tasks.
  ##    This ensures that we can give control back ASAP.
  debug: log("Worker %2d: sync 1 - searching task from local queue\n", ctx.id)
  while (let task = ctx.taskqueue[].pop(); not task.isNil):
    if task.parent != ctx.currentTask:
      debug: log("Worker %2d: sync 1 - skipping non-direct descendant task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, task, task.parent, ctx.currentTask)
      ctx.schedule(task, forceWake = true) # reschedule task and wake a sibling to take it over.
      break
    debug: log("Worker %2d: sync 1 - running task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, task, task.parent, ctx.currentTask)
    ctx.run(task)
    if isFutReady():
      debug: log("Worker %2d: sync 1 - future ready, exiting\n", ctx.id)
      return

  ## 2. We run out-of-tasks or out-of-direct-child of our current awaited task
  ##    So the task is bottlenecked by dependencies in other threads,
  ##    hence we abandon our enqueued work and steal.
  ##
  ##    See also
  ##    - Proactive work-stealing for futures
  ##      Kyle Singer, Yifan Xu, I-Ting Angelina Lee, 2019
  ##      https://dl.acm.org/doi/10.1145/3293883.3295735
  debug: log("Worker %2d: sync 2 - future not ready, becoming a thief (currentTask 0x%.08x)\n", ctx.id, ctx.currentTask)
  while not isFutReady():
    if (let leapTask = ctx.tryLeapfrog(fv.task); not leapTask.isNil):
      # Leapfrogging, the thief had an empty queue, hence if there are tasks in its queue, it's generated by our blocked task.
      # Help the thief clear those, as if it did not finish, it's likely blocked on those children tasks.
      debug: log("Worker %2d: sync 2.1 - leapfrog task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, leapTask, leapTask.parent, ctx.currentTask)
      ctx.run(leapTask)
    else:
      # At this point, we have significant design decisions:
      # - Do we steal from other workers in hope we advance our awaited task?
      # - Do we advance our own queue for tasks that are not child of our awaited tasks?
      # - Do we park instead of working on unrelated task. With hyperthreading that would actually still leave the core busy enough?
      #
      # - If we work, we maximize throughput, but we increase latency to handle the future's continuation.
      #   If that future creates more parallel work, we would actually have restricted parallelism.
      # - If we park, we minimize latency, but we don't use the full hardware resources, and there are CPUs without hyperthreading (on ARM for example)
      #   Furthermore, a work-stealing scheduler is within 2x an optimal scheduler if it is greedy, i.e., as long as there is enough work, all cores are used.
      #
      # The solution chosen is to wake a reserve thread, keeping hardware offered/throughput constant. And put the awaiting thread to sleep.
      ctx.localBackoff.prepareToPark()
      discard ctx.threadpool.numIdleThreadsAwaitingFutures.fetchAdd(1, moRelease)
      ctx.threadpool.reserveBackoff.wake()

      var expected = (ptr EventNotifier)(nil)
      if compareExchange(fv.task.waiter, expected, desired = ctx.localBackoff.addr, moAcquireRelease):
        ctx.localBackoff.park()

      discard ctx.threadpool.numIdleThreadsAwaitingFutures.fetchSub(1, moRelease)

proc syncAll*(tp: Threadpool) {.raises: [].} =
  ## Blocks until all pending tasks are completed
  ## This MUST only be called from
  ## the root scope that created the threadpool
  template ctx: untyped = workerContext

  debugTermination:
    log(">>> Worker %2d enters barrier <<<\n", ctx.id)

  preCondition: ctx.id == 0
  preCondition: ctx.currentTask.isRootTask()

  # Empty all tasks
  tp.globalBackoff.wakeAll()
  tp.reserveBackoff.wakeAll()

  while true:
    # 1. Empty local tasks
    debug: log("Worker %2d: syncAll 1 - searching task from local queue\n", ctx.id)
    while (let task = ctx.taskqueue[].pop(); not task.isNil):
      debug: log("Worker %2d: syncAll 1 - running task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, task, task.parent, ctx.currentTask)
      ctx.run(task)

    # 2. Help other threads
    debug: log("Worker %2d: syncAll 2 - becoming a thief\n", ctx.id)
    if (var stolenTask = ctx.tryStealAdaptative(); not stolenTask.isNil):
      # 2.a We stole some task
      debug: log("Worker %2d: syncAll 2.a - stole task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, stolenTask, stolenTask.parent, ctx.currentTask)
      ctx.run(stolenTask)
    elif tp.reserveBackoff.getNumWaiters() == (0'i32, tp.numThreads) and
         tp.globalBackoff.getNumWaiters() == (0'i32, tp.numThreads-1): # Don't count ourselves
      # 2.b all threads besides the current are parked
      debugTermination: log("Worker %2d: syncAll 2.b - termination, all other threads sleeping\n", ctx.id)
      break
    else:
      # 2.c We don't park as there is no notif for task completion
      cpuRelax()

  debugTermination:
    log(">>> Worker %2d leaves barrier <<<\n", ctx.id)

# Runtime
# ---------------------------------------------

proc new*(T: type Threadpool, numThreads = countProcessors()): T {.raises: [ResourceExhaustedError].} =
  ## Initialize a threadpool that manages `numThreads` threads.
  ## Default to the number of logical processors available.

  type TpObj = typeof(default(Threadpool)[]) # due to C import, we need a dynamic sizeof
  var tp = allocHeapUncheckedAlignedPtr(Threadpool, sizeof(TpObj), alignment = 64)

  tp.barrier.init(2*numThreads.uint32)
  tp.globalBackoff.initialize()
  tp.numThreads = numThreads.int32
  # Allocate for `numThreads` regular workers and `numTHreads` reserve workers
  tp.workerQueues = allocHeapArrayAligned(Taskqueue, 2*numThreads, alignment = 64)
  tp.workers = allocHeapArrayAligned(Thread[(Threadpool, WorkerID)], 2*numThreads, alignment = 64)
  tp.workerSignals = allocHeapArrayAligned(Signal, 2*numThreads, alignment = 64)

  # Setup master thread
  workerContext.id = 0
  workerContext.threadpool = tp

  # Start worker threads
  for i in 1 ..< 2*numThreads:
    createThread(tp.workers[i], workerEntryFn, (tp, WorkerID(i)))

  # Root worker
  setupWorker()

  # Root task, this is a sentinel task that is never called.
  workerContext.currentTask = RootTask

  # Wait for the child threads
  discard tp.barrier.wait()
  return tp

proc cleanup(tp: var Threadpool) {.raises: [].} =
  ## Cleanup all resources allocated by the threadpool
  preCondition: workerContext.currentTask.isRootTask()

  for i in 1 ..< 2*tp.numThreads:
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

  # Signal termination to all threads
  for i in 0 ..< 2*tp.numThreads:
    tp.workerSignals[i].terminate.store(true, moRelease)

  tp.globalBackoff.wakeAll()
  tp.reserveBackoff.wakeAll()

  # 1 matching barrier in workerEntryFn
  discard tp.barrier.wait()

  teardownWorker()
  tp.cleanup()

  # Delete dummy task
  workerContext.currentTask = nil

{.pop.} # raises:[]

# Task parallel API
# ---------------------------------------------

macro spawn*(tp: Threadpool, fnCall: typed): untyped =
  ## Spawns the input function call asynchronously, potentially on another thread of execution.
  ##
  ## If the function calls returns a result, spawn will wrap it in a Flowvar.
  ## You can use `sync` to block the current thread and extract the asynchronous result from the flowvar.
  ## You can use `isReady` to check if result is available and if subsequent
  ## `spawn` returns immediately.
  ##
  ## Tasks are processed approximately in Last-In-First-Out (LIFO) order
  result = spawnImpl(tp, fnCall, bindSym"workerContext", bindSym"schedule")
