import constantine/[threadpool, threadpool/instrumentation]

block:
  proc main() =
    echo "\n=============================================================================================="
    echo "Running 'threadpool/examples/e03_parallel_for.nim'"
    echo "=============================================================================================="

    let tp = Threadpool.new(numThreads = 4)

    tp.parallelFor i in 0 ..< 100:
      log("%d\n", i)

    tp.shutdown()

  echo "Simple parallel for"
  echo "-------------------------"
  main()
  echo "-------------------------"

block: # Capturing outside scope
  proc main2() =
    echo "\n=============================================================================================="
    echo "Running 'threadpool/examples/e03_parallel_for.nim'"
    echo "=============================================================================================="

    let tp = Threadpool.new(numThreads = 4)

    var a = 100
    var b = 10
    tp.parallelFor i in 0 ..< 10:
      captures: {a, b}
      log("a+b+i = %d \n", a+b+i)

    tp.shutdown()

  echo "\n\nCapturing outside variables"
  echo "-------------------------"
  main2()
  echo "-------------------------"

block: # Nested loops
  proc main3() =
    echo "\n=============================================================================================="
    echo "Running 'threadpool/examples/e03_parallel_for.nim'"
    echo "=============================================================================================="

    let tp = Threadpool.new(numThreads = 4)

    tp.parallelFor i in 0 ..< 4:
      tp.parallelFor j in 0 ..< 8:
        captures: {i}
        log("Matrix[%d, %d]\n", i, j)

    tp.shutdown()

  echo "\n\nNested loops"
  echo "-------------------------"
  main3()
  echo "-------------------------"
