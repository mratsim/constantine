# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[os, strutils, cpuinfo, strformat, deques],
  std/[asyncfutures, asyncdispatch],
  asynctools/[asyncproc, asyncpipe, asyncsync]

# Pararun is a parallel shell command runner
# ------------------------------------------
# Usage: pararun <file-with-1-command-per-line> <numWorkers>

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
  outputQueue: AsyncQueue[tuple[cmd: string, p: AsyncProcess, output: AsyncQueue[string]]]

proc monitorProcessLoop(output: AsyncQueue[string], cmd: string, id, total: int, p: AsyncProcess, sem: AsyncSemaphore) {.async.} =
  # Ideally we want AsynStreams but that requires chronos, which doesn't support processes/pipes
  # Or the nimboost package that hasn't been updated since 2019. So poor man's streams.
  template doBuffering: untyped =
    while true:
      buf.setLen(256)
      let charsRead = await p.outputHandle.readInto(buf[0].addr, buf.len)
      if charsRead > 0:
        buf.setLen(charsRead)
        output.putNoWait(buf)
      else:
        break

  var buf = newString(256)
  doBuffering()

  # Despite the output being empty we might still get STILL_ACTIVE: https://github.com/cheatfate/asynctools/blob/84ced6d/asynctools/asyncproc.nim#L24
  # Unfortunately this gives "Resource temporarily unavailable" so we use exponential backoff.
  # See also:
  #  - https://github.com/cheatfate/asynctools/issues/20
  #  - https://forum.nim-lang.org/t/5565
  #
  # let exitCode = await p.waitForExit()
  var backoff = 8
  while p.running():
    backoff = min(backoff*2, 1024) # Exponential backoff
    await sleepAsync(backoff)

  doBuffering()
  buf.setLen(0)

  let exitCode = p.peekExitCode()
  if exitCode != 0:
    buf.add("\n" & '='.repeat(26) & " Command exited with code " & $exitCode & " " & '='.repeat(26) & '\n')
    buf.add("[FAIL]: '" & cmd & "' (#" & $id & "/" & $total & ")\n")
    buf.add("[FAIL]: Command #" & $id & " exited with error " & $exitCode & '\n')
    buf.add('='.repeat(80) & '\n')
    output.putNoWait(buf)

  # close not exported: https://github.com/cheatfate/asynctools/issues/16
  p.inputHandle.close()
  p.outputHandle.close()
  p.errorHandle.close()

  output.putNoWait("")
  if exitCode == 0:
    sem.release()

proc enqueuePendingCommands(wq: WorkQueue) {.async.} =
  var id = 0
  let total = wq.cmdQueue.len
  while wq.cmdQueue.len > 0:
    id += 1

    await wq.sem.acquire()
    let cmd = wq.cmdQueue.popFirst()
    let p = cmd.startProcess(options = {poStdErrToStdOut, poUsePath, poEvalCommand})

    let bufOut = newAsyncQueue[string]()
    asyncCheck bufOut.monitorProcessLoop(cmd, id, total, p, wq.sem)

    wq.outputQueue.putNoWait((cmd, p, bufOut))

proc flushCommandsOutput(wq: WorkQueue, total: int) {.async.} =
  var id = 0
  while true:
    id += 1
    let (cmd, p, processOutput) = await wq.outputQueue.get()

    echo '\n', '='.repeat(80)
    echo "||\n|| Running #", id, "/", total, ": ", cmd ,"\n||"
    echo '='.repeat(80)

    while true:
      let output = await processOutput.get()
      if output == "":
        break
      stdout.write(output)

    let exitCode = p.peekExitCode()
    if exitCode != 0:
      quit exitCode

    if wq.cmdQueue.len == 0 and wq.outputQueue.len == 0:
      return

proc runCommands(commandFile: string, numWorkers: int) =
  # State
  # -----

  let wq = WorkQueue(
    sem: AsyncSemaphore.new(numWorkers),
    cmdQueue: initDeque[string](),
    outputQueue: newAsyncQueue[tuple[cmd: string, p: AsyncProcess, output: AsyncQueue[string]]]())

  # Parse the file
  # --------------
  for cmd in lines(commandFile):
    if cmd.len == 0: continue
    wq.cmdQueue.addLast(cmd)

  let total = wq.cmdQueue.len
  echo "Found ", total, " commands to run"

  # Run the commands
  # ----------------
  asyncCheck wq.enqueuePendingCommands()
  waitFor wq.flushCommandsOutput(total)

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
