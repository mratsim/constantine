# Constantine Threadpool

## API

The API spec follows https://github.com/nim-lang/RFCs/issues/347#task-parallelism-api

## Overview

This implements a lightweight, energy-efficient, easily auditable multithreaded threadpool.

This threadpool will desirable properties are:

- Ease of auditing and maintenance.
- Resource-efficient. Threads spindown to save power, low memory use.
- Decent performance and scalability. The CPU should spent its time processing user workloads
  and not dealing with threadpool contention, latencies and overheads.

Compared to [Weave](https://github.com/mratsim/weave), here are the tradeoffs:
- Constantine's threadpool provides spawn/sync (task parallelism)
  and optimized parallelFor for (data parallelism).\
  It however does not provide precise in/out dependencies (events / dataflow parallelism).
- Constantine's threadpool has been significantly optimized to provide
  overhead lower than Weave's default (and as low as Weave "lazy" + "alloca" allocation scheme).

Compared to [nim-taskpools](https://github.com/status-im), here are the tradeoffs:
- Constantine does not use std/tasks:
  - No external dependencies at runtime (apart from compilers, OS and drivers)
  - We can replace Task with an intrusive linked list
  - Furthermore we can embed tasks in their future
- Hence allocation/scheduler overhead is 3x less than nim-taskpools as we fuse the following allocations:
  - Task
  - The linked list of tasks
  - The future (Flowvar) result channel
- Contention improvement, Constantine is entirely lock-free while Nim-taskpools need a lock+condition variable for putting threads to sleep
- Powersaving improvement, threads sleep when awaiting for a task and there is no work available.
- Scheduling improvement, Constantine's threadpool incorporate Weave's adaptative scheduling policy with additional enhancement (leapfrogging)

See also [design.md](../../docs/threadpool-design.md)