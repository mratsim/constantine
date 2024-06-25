import constantine/threadpool

block:
  proc main() =
    echo "\n=============================================================================================="
    echo "Running 'threadpool/examples/e04_parallel_reduce.nim'"
    echo "=============================================================================================="

    proc sumReduce(tp: Threadpool, n: int): int64 =
      tp.parallelFor i in 0 .. n:
        reduceInto(globalSum: Flowvar[int64]):
          prologue:
            var localSum = 0'i64
          forLoop:
            localSum += int64(i)
          merge(remoteSum: Flowvar[int64]):
            localSum += sync(remoteSum)
          epilogue:
            return localSum

      result = sync(globalSum)

    let tp = Threadpool.new(numThreads = 4)

    let sum1M = tp.sumReduce(1000000)
    echo "Sum reduce(0..1000000): ", sum1M
    doAssert sum1M == 500_000_500_000'i64, "incorrect sum was " & $sum1M

    tp.shutdown()

  echo "Simple parallel reduce"
  echo "-------------------------"
  main()
  echo "-------------------------"
