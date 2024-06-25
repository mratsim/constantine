import constantine/threadpool

block: # Async without result

  proc displayInt(x: int) {.raises: [].} =
    try:
      stdout.write(x)
      stdout.write(" - SUCCESS\n")
    except:
      quit 1

  proc main() =
    echo "\n=============================================================================================="
    echo "Running 'threadpool/examples/e01_simple_tasks.nim'"
    echo "=============================================================================================="

    echo "\nSanity check 1: Printing 123456 654321 in parallel"

    let tp = Threadpool.new(numThreads = 4)
    tp.spawn displayInt(123456)
    tp.spawn displayInt(654321)
    tp.shutdown()

  main()

block: # Async/Await
  var tp: Threadpool

  proc asyncFib(n: int): int {.gcsafe, raises: [].} =
    if n < 2:
      return n

    let x = tp.spawn asyncFib(n-1)
    let y = asyncFib(n-2)

    result = sync(x) + y

  proc main2() =
    echo "\n=============================================================================================="
    echo "Running 'threadpool/examples/e01_simple_tasks.nim'"
    echo "=============================================================================================="

    echo "\nSanity check 2: fib(20)"

    tp = Threadpool.new()
    let f = asyncFib(20)
    tp.shutdown()

    doAssert f == 6765, "f was " & $f

  main2()
