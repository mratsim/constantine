# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

when not compileOption("threads"):
  {.error: "This requires --threads:on compilation flag".}

{.push raises: [].}

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
  WorkerID = uint32
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
    recentTasks: uint32
    recentThefts: uint32
    recentTheftsAdaptative: uint32
    recentLeaps: uint32

  Threadpool* = ptr object
    barrier: SyncBarrier             # Barrier for initialization and teardown
    # -- align: 64
    globalBackoff: EventCount        # Multi-Producer Multi-Consumer backoff
    # -- align: 64
    numThreads*{.align: 64.}: uint32
    workerQueues: ptr UncheckedArray[Taskqueue]
    workers: ptr UncheckedArray[Thread[(Threadpool, WorkerID)]]
    workerSignals: ptr UncheckedArray[Signal]

# Thread-local config
# ---------------------------------------------

var workerContext {.threadvar.}: WorkerContext
  ## Thread-local Worker context

proc setupWorker() =
  ## Initialize the thread-local context of a worker
  ## Requires the ID and threadpool fields to be initialized
  template ctx: untyped = workerContext

  preCondition: not ctx.threadpool.isNil()
  preCondition: 0 <= ctx.id and ctx.id < ctx.threadpool.numThreads.uint32
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

proc eventLoop(ctx: var WorkerContext) {.raises:[].}

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

  {.cast(gcsafe).}: # Compiler does not consider that GC-safe by default when multi-threaded due to thread-local variables
    ctx.eventLoop()

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

  # Sync with an awaiting thread without work in completeFuture
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

iterator pseudoRandomPermutation(randomSeed, maxExclusive: uint32): uint32 =
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
  let M = maxExclusive.nextPowerOfTwo_vartime()
  let c = (randomSeed and ((M shr 1) - 1)) * 2 + 1 # c odd and c ∈ [0, M)
  let a = (randomSeed and ((M shr 2) - 1)) * 4 + 1 # a-1 divisible by 2 (all prime factors of m) and by 4 if m divisible by 4

  let mask = M-1                                   # for mod M
  let start = randomSeed and mask

  var x = start
  while true:
    if x < maxExclusive:
      yield x
    x = (a*x + c) and mask                         # ax + c (mod M), with M power of 2
    if x == start:
      break

proc tryStealOne(ctx: var WorkerContext): ptr Task =
  ## Try to steal a task.
  let seed = ctx.rng.next().uint32
  for targetId in seed.pseudoRandomPermutation(ctx.threadpool.numThreads):
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
  for targetId in seed.pseudoRandomPermutation(ctx.threadpool.numThreads):
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
  ascertain: 0 <= thiefID and thiefID < ctx.threadpool.numThreads

  # Leapfrogging is used when completing a future, steal only one
  # and don't leave tasks stranded in our queue.
  let leapTask = ctx.id.steal(ctx.threadpool.workerQueues[thiefID])
  if not leapTask.isNil():
    ctx.recentLeaps += 1
    # Theft successful, there might be more work for idle threads, wake one
    ctx.threadpool.globalBackoff.wake()
    return leapTask
  return nil

proc eventLoop(ctx: var WorkerContext) {.raises:[].} =
  ## Each worker thread executes this loop over and over.
  while true:
    # 1. Pick from local queue
    debug: log("Worker %2d: eventLoop 1 - searching task from local queue\n", ctx.id)
    while (var task = ctx.taskqueue[].pop(); not task.isNil):
      debug: log("Worker %2d: eventLoop 1 - running task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, task, task.parent, ctx.currentTask)
      ctx.run(task)

    # 2. Run out of tasks, become a thief
    debug: log("Worker %2d: eventLoop 2 - becoming a thief\n", ctx.id)
    let ticket = ctx.threadpool.globalBackoff.sleepy()
    if (var stolenTask = ctx.tryStealAdaptative(); not stolenTask.isNil):
      # We manage to steal a task, cancel sleep
      ctx.threadpool.globalBackoff.cancelSleep()
      # 2.a Run task
      debug: log("Worker %2d: eventLoop 2.a - stole task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, stolenTask, stolenTask.parent, ctx.currentTask)
      ctx.run(stolenTask)
    elif ctx.signal.terminate.load(moAcquire):
      # 2.b Threadpool has no more tasks and we were signaled to terminate
      ctx.threadpool.globalBackoff.cancelSleep()
      debugTermination: log("Worker %2d: eventLoop 2.b - terminated\n", ctx.id)
      break
    else:
      # 2.b Park the thread until a new task enters the threadpool
      debug: log("Worker %2d: eventLoop 2.b - sleeping\n", ctx.id)
      ctx.threadpool.globalBackoff.sleep(ticket)
      debug: log("Worker %2d: eventLoop 2.b - waking\n", ctx.id)

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
  ##    hence we abandon our enqueued work and steal in the others' queues
  ##    in hope it advances our awaited task. This prioritizes latency over throughput.
  ##
  ##    See also
  ##    - Proactive work-stealing for futures
  ##      Kyle Singer, Yifan Xu, I-Ting Angelina Lee, 2019
  ##      https://dl.acm.org/doi/10.1145/3293883.3295735
  debug: log("Worker %2d: sync 2 - future not ready, becoming a thief (currentTask 0x%.08x)\n", ctx.id, ctx.currentTask)
  while not isFutReady():
    if (let leapTask = ctx.tryLeapfrog(fv.task); not leapTask.isNil):
      # We stole a task generated by the task we are awaiting.
      debug: log("Worker %2d: sync 2.1 - leapfrog task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, leapTask, leapTask.parent, ctx.currentTask)
      ctx.run(leapTask)
    elif (let stolenTask = ctx.tryStealOne(); not stolenTask.isNil):
      # We stole a task, we hope we advance our awaited task.
      debug: log("Worker %2d: sync 2.2 - stole task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, stolenTask, stolenTask.parent, ctx.currentTask)
      ctx.run(stolenTask)
    elif (let ownTask = ctx.taskqueue[].pop(); not ownTask.isNil):
      # We advance our own queue, this increases global throughput but may impact latency on the awaited task.
      #
      # Note: for a scheduler to be optimal (i.e. within 2x than ideal) it should be greedy
      #       so all workers should be working. This is a difficult tradeoff.
      debug: log("Worker %2d: sync 2.3 - couldn't steal, running own task\n", ctx.id)
      ctx.run(ownTask)
    else:
      # Nothing to do, we park.
      # Note: On today's hyperthreaded systems, it might be more efficient to always park
      #       instead of working on unrelated tasks in our task queue, despite making the scheduler non-greedy.
      #       The actual hardware resources are 2x less than the actual number of cores
      ctx.localBackoff.prepareToPark()

      var expected = (ptr EventNotifier)(nil)
      if compareExchange(fv.task.waiter, expected, desired = ctx.localBackoff.addr, moAcquireRelease):
        ctx.localBackoff.park()

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

  while true:
    # 1. Empty local tasks
    debug: log("Worker %2d: syncAll 1 - searching task from local queue\n", ctx.id)
    while (let task = ctx.taskqueue[].pop(); not task.isNil):
      debug: log("Worker %2d: syncAll 1 - running task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, task, task.parent, ctx.currentTask)
      ctx.run(task)

    if tp.numThreads == 1:
      break

    # 2. Help other threads
    debug: log("Worker %2d: syncAll 2 - becoming a thief\n", ctx.id)
    if (var stolenTask = ctx.tryStealAdaptative(); not stolenTask.isNil):
      # 2.a We stole some task
      debug: log("Worker %2d: syncAll 2.a - stole task 0x%.08x (parent 0x%.08x, current 0x%.08x)\n", ctx.id, stolenTask, stolenTask.parent, ctx.currentTask)
      ctx.run(stolenTask)
    elif tp.globalBackoff.getNumWaiters() == (0'u32, tp.numThreads - 1):
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

  tp.barrier.init(numThreads.uint32)
  tp.globalBackoff.initialize()
  tp.numThreads = numThreads.uint32
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
  setupWorker()

  # Root task, this is a sentinel task that is never called.
  workerContext.currentTask = RootTask

  # Wait for the child threads
  discard tp.barrier.wait()
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

  # Signal termination to all threads
  for i in 0 ..< tp.numThreads:
    tp.workerSignals[i].terminate.store(true, moRelease)

  tp.globalBackoff.wakeAll()

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
