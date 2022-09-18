# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[os, strutils, cpuinfo, strformat, deques, terminal],
  std/[asyncfutures, asyncdispatch],
  asynctools/[asyncproc, asyncpipe, asyncsync]

# Pararun is a parallel shell command runner
# ------------------------------------------
# Usage: pararun <file-with-1-command-per-line> <numWorkers

# AsyncSemaphore
# ----------------------------------------------------------------

type AsyncSemaphore = ref object
  waiters: Deque[Future[void]]
  slots, max: int

proc new(_: type AsyncSemaphore, max: int): AsyncSemaphore =
  ## Initialize an AsyncSemaphore that can release up to max items
  AsyncSemaphore(
    waiters: default(Deque[Future[void]]),
    slots: max,
    max: max)

proc acquire(s: AsyncSemaphore) {.async.} =
  doAssert s.slots in {0..s.max}
  if s.slots == 0:
    let waiter = newFuture[void]("AsyncSemaphore.acquire")
    s.waiters.addLast(waiter)
    await waiter
  s.slots -= 1

  doAssert s.slots in {0..s.max}

proc release(s: AsyncSemaphore) =
  doAssert s.slots in {0..s.max-1}

  s.slots += 1
  if s.waiters.len > 0:
    let waiter = s.waiters.popFirst()
    waiter.complete()
  
  doAssert s.slots in {0..s.max}

# Task runner
# ----------------------------------------------------------------

type WorkQueue = ref object
  sem: AsyncSemaphore
  cmdQueue: Deque[string]
  outputQueue: AsyncQueue[tuple[cmd: string, p: AsyncProcess]]
  lineBuf: string

proc releaseOnProcessExit(sem: AsyncSemaphore, p: AsyncProcess) {.async.} =
  # TODO: addProcess callback on exit is cleaner but locks the AsyncPipe "readInto"
  #
  # p.processID.addProcess do (fd: AsyncFD) -> bool:
  #   sem.release()
  #
  # see also: https://forum.nim-lang.org/t/5565

  var backoff = 8
  while p.running():
    backoff = min(backoff*2, 1024) # Exponential backoff
    await sleepAsync(backoff)
  sem.release()

proc enqueuePendingCommands(wq: WorkQueue) {.async.} =
  while wq.cmdQueue.len > 0:
    await wq.sem.acquire()
    let cmd = wq.cmdQueue.popFirst()
    let p = cmd.startProcess(
      options = {poStdErrToStdOut, poUsePath, poEvalCommand}
    )

    asyncCheck wq.sem.releaseOnProcessExit(p)
    wq.outputQueue.putNoWait((cmd, p))

proc flushCommandsOutput(wq: WorkQueue) {.async.} =
  var id = 0
  while true:
    let (cmd, p) = await wq.outputQueue.get()
    
    echo '\n', '='.repeat(80)
    echo "||\n|| Running: ", cmd ,"\n||"
    echo '='.repeat(80)
    
    while true:
      let charsRead = await p.outputHandle.readInto(wq.lineBuf[0].addr, wq.lineBuf.len)
      if charsRead == 0:
        break
      let charsWritten = stdout.writeBuffer(wq.lineBuf[0].addr, charsRead)
      doAssert charsRead == charsWritten
    
    let exitCode = p.peekExitCode()
    if exitCode != 0:
      quit "Command #" & $id & "exited with error " & $exitCode, exitCode
    
    id += 1

    if wq.cmdQueue.len == 0 and wq.outputQueue.len == 0:
      return

proc runCommands(commandFile: string, numWorkers: int) =
  # State
  # -----

  let wq = WorkQueue(
    sem: AsyncSemaphore.new(numWorkers),
    cmdQueue: initDeque[string](),
    outputQueue: newAsyncQueue[tuple[cmd: string, p: AsyncProcess]](),
    lineBuf: newString(max(80, terminalWidth()))
  )

  # Parse the file
  # --------------
  for cmd in lines(commandFile):
    if cmd.len == 0: continue
    wq.cmdQueue.addLast(cmd)

  echo "Found ", wq.cmdQueue.len, " commands to run"
  
  # Run the commands
  # ----------------
  asyncCheck wq.enqueuePendingCommands()
  waitFor wq.flushCommandsOutput()

# Main
# ----------------------------------------------------------------
  
proc main() =
  var commandFile: string
  var numWorkers = countProcessors()

  if paramCount() == 0:
    let exeName = getAppFilename().extractFilename()
    echo &"Usage: {exeName} <file-with-commands-1-per-line> <numWorkers: {numWorkers}>"

  if paramCount() >= 1:
    commandFile = paramStr(1)
  
  if paramCount() == 2:
    numWorkers = paramStr(2).parseInt()

  if paramCount() > 2:
    let exeName = getAppFilename().extractFilename()
    echo &"Usage: {exeName} <file-with-commands-1-per-line> <numThreads: {numWorkers}>"
    quit 1

  runCommands(commandFile, numWorkers)

when isMainModule:
  main()