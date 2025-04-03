# GT MultiExp call details

## Metrics details

Due to a current limitation, generic procedures call counts are common even if the function
is instantiated on different types.

For example a `prod_generic(r: var QuadraticExt, a, b: QuadraticExt)` function called on Fp2 and Fp12
would unfortunately have merged statistics.

To avoid confusion, we only report functions with an unambiguous field/extension field meaning:
- the base field
- Fp2 as Fp2 has custom optimization due to the -1 quadratic non-residue
- GT / cyclotomic subgroup / Fp12

Note that even with Fp2->Fp6->Fp12 towering, Fp4 is used for optimized cyclotomic square.

## CLI

Compilation can be run with

```
nim c -r -d:CTT_METER -d:release --outdir:build metering/m_gt_multiexp.nim
```

The option can be edited by changing the following lines

```
let (elems, exponents) = rng.genBatch(GT_12o4, 128)
...
mexpMeter(elems, exponents, useTorus = false)
```

to adjust:
- Towering Fp12 over Fp6 over Fp2 (torus, non-torus) or Fp12 over Fp4 over Fp2 (non-torus only)
- Number of inputs (128 or 256)
- Use of torus acceleration

## Warning on time measuring

Counting the exact number of function calls has a non-negligeable overhead.
Hence function timings are informative of how heavy a function is.

For small functions in the order of nanosecond like field addition, registering the call
can easily be 5x to 15x more costly.

Benchmarks where done on a Apple M4 Max.
On x86, extra functions for ADX assembly will appear in the report.

The random seed is fixed for reproducibility

## BLS12-381, Fp12 over Fp4 over Fp2, 128 inputs, non-torus

|                         Procedures                         |  # of Calls  | Throughput (ops/s) |    Time (µs)     |  Avg Time (µs)   |
|------------------------------------------------------------|--------------|--------------------|------------------|------------------|
|neg*(r: var FF; a: FF)                                      |         19254|        86320291.590|           223.053|             0.012|
|neg*(a: var FF)                                             |          2048|        26101474.580|            78.463|             0.038|
|`+=`*(a: var FF; b: FF)                                     |           720|        94401468.467|             7.627|             0.011|
|double*(a: var FF)                                          |           720|        94924192.485|             7.585|             0.011|
|sum*(r: var FF; a, b: FF)                                   |        141300|        93223576.262|          1515.711|             0.011|
|sumUnr*(r: var FF; a, b: FF)                                |        353916|        94649407.860|          3739.231|             0.011|
|diff*(r: var FF; a, b: FF)                                  |           960|        85653104.925|            11.208|             0.012|
|prod*(r: var FF; a, b: FF; lazyReduce: static bool = false) |          1536|        59946142.138|            25.623|             0.017|
|square2x_complex(r: var QuadraticExt2x; a: Fp2)             |           540|         9686619.908|            55.747|             0.103|
|prod2x_complex(r: var QuadraticExt2x; a, b: Fp2)            |        106158|        11048526.593|          9608.340|             0.091|
|cyclotomic_inv*(a: var FT)                                  |           256|         2883175.097|            88.791|             0.347|
|cyclotomic_inv*(r: var FT; a: FT)                           |          2569|         5278622.503|           486.680|             0.189|
|cyclotomic_square*(r: var FT; a: FT)                        |            60|          373645.535|           160.580|             2.676|
|`~*=`(a: var Gt; b: Gt)                                     |          6222|          274170.653|         22693.895|             3.647|
|`~/=`(a: var Gt; b: Gt)                                     |          2569|          256820.514|         10003.095|             3.894|
|setNeutral(a: var Gt)                                       |           385|        55983713.829|             6.877|             0.018|
|accumulate(buckets: ptr UncheckedArray[GtAcc]; val: Secr ...|          5632|          269712.192|         20881.518|             3.708|
|bucketReduce(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            11|            4287.663|          2565.500|           233.227|
|miniMultiExp(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            11|             463.026|         23756.790|          2159.708|
|multiExpImpl_vartime(r: var GtAcc; elems: ptr UncheckedA ...|             1|              42.072|         23769.000|         23769.000|
|multiExp_vartime*(r: var GT; elems: ptr UncheckedArray[G ...|             1|              41.410|         24148.959|         24148.959|
|multiExp_vartime*(r: var GT; elems: openArray[GT]; expos ...|             1|              41.410|         24148.959|         24148.959|

## BLS12-381, Fp12 over Fp6 over Fp2, 128 inputs, non-torus

|                         Procedures                         |  # of Calls  | Throughput (ops/s) |    Time (µs)     |  Avg Time (µs)   |
|------------------------------------------------------------|--------------|--------------------|------------------|------------------|
|neg*(r: var FF; a: FF)                                      |         19254|        88220335.488|           218.249|             0.011|
|neg*(a: var FF)                                             |          2048|        25589124.622|            80.034|             0.039|
|`+=`*(a: var FF; b: FF)                                     |           720|        85908602.792|             8.381|             0.012|
|double*(a: var FF)                                          |           720|       102272727.273|             7.040|             0.010|
|sum*(r: var FF; a, b: FF)                                   |        211560|        91116918.736|          2321.852|             0.011|
|sumUnr*(r: var FF; a, b: FF)                                |        283656|        92888065.127|          3053.740|             0.011|
|diff*(r: var FF; a, b: FF)                                  |           960|        94432421.798|            10.166|             0.011|
|prod*(r: var FF; a, b: FF; lazyReduce: static bool = false) |          1536|        59451927.543|            25.836|             0.017|
|square2x_complex(r: var QuadraticExt2x; a: Fp2)             |           540|        10031208.203|            53.832|             0.100|
|prod2x_complex(r: var QuadraticExt2x; a, b: Fp2)            |        106158|        10833964.629|          9798.629|             0.092|
|cyclotomic_inv*(a: var FT)                                  |           256|         2831419.913|            90.414|             0.353|
|cyclotomic_inv*(r: var FT; a: FT)                           |          2569|         5168504.514|           497.049|             0.193|
|cyclotomic_square*(r: var FT; a: FT)                        |            60|          381759.530|           157.167|             2.619|
|`~*=`(a: var Gt; b: Gt)                                     |          6222|          269578.239|         23080.498|             3.709|
|`~/=`(a: var Gt; b: Gt)                                     |          2569|          251725.283|         10205.570|             3.973|
|setNeutral(a: var Gt)                                       |           385|        62867406.924|             6.124|             0.016|
|accumulate(buckets: ptr UncheckedArray[GtAcc]; val: Secr ...|          5632|          264929.447|         21258.490|             3.775|
|bucketReduce(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            11|            4229.886|          2600.543|           236.413|
|miniMultiExp(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            11|             455.240|         24163.083|          2196.644|
|multiExpImpl_vartime(r: var GtAcc; elems: ptr UncheckedA ...|             1|              41.356|         24180.334|         24180.334|
|multiExp_vartime*(r: var GT; elems: ptr UncheckedArray[G ...|             1|              40.712|         24562.500|         24562.500|
|multiExp_vartime*(r: var GT; elems: openArray[GT]; expos ...|             1|              40.712|         24562.583|         24562.583|

## BLS12-381, Fp12 over Fp6 over Fp2, 128 inputs, with-torus

|                         Procedures                         |  # of Calls  | Throughput (ops/s) |    Time (µs)     |  Avg Time (µs)   |
|------------------------------------------------------------|--------------|--------------------|------------------|------------------|
|neg*(r: var FF; a: FF)                                      |         56561|        84604775.837|           668.532|             0.012|
|neg*(a: var FF)                                             |          2054|        23331894.495|            88.034|             0.043|
|`+=`*(a: var FF; b: FF)                                     |             2|        23809523.810|             0.084|             0.042|
|`-=`*(a: var FF; b: FF)                                     |           370|        82996859.578|             4.458|             0.012|
|sum*(r: var FF; a, b: FF)                                   |        118050|        88042349.825|          1340.832|             0.011|
|sumUnr*(r: var FF; a, b: FF)                                |         36716|        90489886.555|           405.747|             0.011|
|diff*(r: var FF; a, b: FF)                                  |         33674|        89482355.442|           376.320|             0.011|
|prod*(r: var FF; a, b: FF; lazyReduce: static bool = false) |          1540|        57636887.608|            26.719|             0.017|
|square*(r: var FF; a: FF; lazyReduce: static bool = false)  |             4|        12012012.012|             0.333|             0.083|
|sumprod*(r: var FF; a, b: array[N, FF]; lazyReduce: stat ...|         74574|        17977262.646|          4148.240|             0.056|
|inv_vartime*(r: var FF; a: FF)                              |             2|          539374.326|             3.708|             1.854|
|square2x_complex(r: var QuadraticExt2x; a: Fp2)             |           552|         9449627.664|            58.415|             0.106|
|prod2x_complex(r: var QuadraticExt2x; a, b: Fp2)            |         13642|        10365521.004|          1316.094|             0.096|
|prodImpl_fp6o2_complex_snr_1pi(r: var Fp6[Name]; a, b: F ...|         12429|         1450595.883|          8568.203|             0.689|
|cyclotomic_inv*(a: var FT)                                  |           256|         2652712.295|            96.505|             0.377|
|square*(r: var T2Prj[F]; a: T2Prj[F])                       |            60|          350109.409|           171.375|             2.856|
|`~*=`(a: var T2Prj; b: T2Aff)                               |          5529|          574309.393|          9627.215|             1.741|
|`~*=`(a: var T2Prj; b: T2Prj)                               |           693|          245976.701|          2817.340|             4.065|
|`~/=`(a: var T2Prj; b: T2Aff)                               |          2569|          508621.319|          5050.909|             1.966|
|accumulate(buckets: ptr UncheckedArray[GtAcc]; val: Secr ...|          5632|          544711.722|         10339.414|             1.836|
|bucketReduce(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            11|            3948.375|          2785.956|           253.269|
|miniMultiExp(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            11|             817.391|         13457.458|          1223.405|
|multiExpImpl_vartime(r: var GtAcc; elems: ptr UncheckedA ...|             1|              74.293|         13460.166|         13460.166|
|multiExp_vartime*(r: var GT; elems: ptr UncheckedArray[G ...|             1|              64.634|         15471.792|         15471.792|
|multiExp_vartime*(r: var GT; elems: openArray[GT]; expos ...|             1|              64.634|         15471.833|         15471.833|

## BLS12-381, Fp12 over Fp4 over Fp2, 256 inputs, non-torus

|                         Procedures                         |  # of Calls  | Throughput (ops/s) |    Time (µs)     |  Avg Time (µs)   |
|------------------------------------------------------------|--------------|--------------------|------------------|------------------|
|neg*(r: var FF; a: FF)                                      |         35166|        82856604.307|           424.420|             0.012|
|neg*(a: var FF)                                             |          4096|        22717944.736|           180.298|             0.044|
|`+=`*(a: var FF; b: FF)                                     |           756|        90301003.344|             8.372|             0.011|
|double*(a: var FF)                                          |           756|        91536505.630|             8.259|             0.011|
|sum*(r: var FF; a, b: FF)                                   |        252939|        88082674.208|          2871.609|             0.011|
|sumUnr*(r: var FF; a, b: FF)                                |        634506|        88904862.188|          7136.910|             0.011|
|diff*(r: var FF; a, b: FF)                                  |          1008|        93489148.581|            10.782|             0.011|
|prod*(r: var FF; a, b: FF; lazyReduce: static bool = false) |          3072|        52603640.473|            58.399|             0.019|
|square2x_complex(r: var QuadraticExt2x; a: Fp2)             |           567|         9706078.710|            58.417|             0.103|
|prod2x_complex(r: var QuadraticExt2x; a, b: Fp2)            |        190626|        10452261.858|         18237.775|             0.096|
|cyclotomic_inv*(a: var FT)                                  |           512|         2506130.720|           204.299|             0.399|
|cyclotomic_inv*(r: var FT; a: FT)                           |          4581|         5021071.842|           912.355|             0.199|
|cyclotomic_square*(r: var FT; a: FT)                        |            63|          374069.280|           168.418|             2.673|
|`~*=`(a: var Gt; b: Gt)                                     |         11208|          260904.659|         42958.221|             3.833|
|`~/=`(a: var Gt; b: Gt)                                     |          4581|          244905.003|         18705.212|             4.083|
|setNeutral(a: var Gt)                                       |           705|        54710538.569|            12.886|             0.018|
|accumulate(buckets: ptr UncheckedArray[GtAcc]; val: Secr ...|         10240|          258035.819|         39684.413|             3.875|
|bucketReduce(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            10|            2114.818|          4728.540|           472.854|
|miniMultiExp(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            10|             223.091|         44824.833|          4482.483|
|multiExpImpl_vartime(r: var GtAcc; elems: ptr UncheckedA ...|             1|              22.305|         44832.084|         44832.084|
|multiExp_vartime*(r: var GT; elems: ptr UncheckedArray[G ...|             1|              21.898|         45666.125|         45666.125|
|multiExp_vartime*(r: var GT; elems: openArray[GT]; expos ...|             1|              21.898|         45666.125|         45666.125|

## BLS12-381, Fp12 over Fp6 over Fp2, 256 inputs, non-torus

|                         Procedures                         |  # of Calls  | Throughput (ops/s) |    Time (µs)     |  Avg Time (µs)   |
|------------------------------------------------------------|--------------|--------------------|------------------|------------------|
|neg*(r: var FF; a: FF)                                      |         35166|        81948914.176|           429.121|             0.012|
|neg*(a: var FF)                                             |          4096|        23624681.332|           173.378|             0.042|
|`+=`*(a: var FF; b: FF)                                     |           756|        85115964.873|             8.882|             0.012|
|double*(a: var FF)                                          |           756|        92094043.123|             8.209|             0.011|
|sum*(r: var FF; a, b: FF)                                   |        378999|        86020887.924|          4405.895|             0.012|
|sumUnr*(r: var FF; a, b: FF)                                |        508446|        88972315.734|          5714.654|             0.011|
|diff*(r: var FF; a, b: FF)                                  |          1008|        85765336.510|            11.753|             0.012|
|prod*(r: var FF; a, b: FF; lazyReduce: static bool = false) |          3072|        55221009.869|            55.631|             0.018|
|square2x_complex(r: var QuadraticExt2x; a: Fp2)             |           567|         9594233.307|            59.098|             0.104|
|prod2x_complex(r: var QuadraticExt2x; a, b: Fp2)            |        190626|        10336833.966|         18441.430|             0.097|
|cyclotomic_inv*(a: var FT)                                  |           512|         2618992.813|           195.495|             0.382|
|cyclotomic_inv*(r: var FT; a: FT)                           |          4581|         4949591.100|           925.531|             0.202|
|cyclotomic_square*(r: var FT; a: FT)                        |            63|          363281.993|           173.419|             2.753|
|`~*=`(a: var Gt; b: Gt)                                     |         11208|          257590.414|         43510.936|             3.882|
|`~/=`(a: var Gt; b: Gt)                                     |          4581|          241904.733|         18937.207|             4.134|
|setNeutral(a: var Gt)                                       |           705|        51094361.502|            13.798|             0.020|
|accumulate(buckets: ptr UncheckedArray[GtAcc]; val: Secr ...|         10240|          254477.607|         40239.297|             3.930|
|bucketReduce(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            10|            2098.874|          4764.459|           476.446|
|miniMultiExp(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            10|             220.100|         45433.876|          4543.388|
|multiExpImpl_vartime(r: var GtAcc; elems: ptr UncheckedA ...|             1|              22.007|         45440.625|         45440.625|
|multiExp_vartime*(r: var GT; elems: ptr UncheckedArray[G ...|             1|              21.619|         46255.958|         46255.958|
|multiExp_vartime*(r: var GT; elems: openArray[GT]; expos ...|             1|              21.619|         46256.042|         46256.042|

## BLS12-381, Fp12 over Fp6 over Fp2, 256 inputs, with-torus

|                         Procedures                         |  # of Calls  | Throughput (ops/s) |    Time (µs)     |  Avg Time (µs)   |
|------------------------------------------------------------|--------------|--------------------|------------------|------------------|
|neg*(r: var FF; a: FF)                                      |        103631|        84649113.492|          1224.242|             0.012|
|neg*(a: var FF)                                             |          4102|        24754088.468|           165.710|             0.040|
|`+=`*(a: var FF; b: FF)                                     |             2|                 inf|             0.000|             0.000|
|`-=`*(a: var FF; b: FF)                                     |           388|        94106233.325|             4.123|             0.011|
|sum*(r: var FF; a, b: FF)                                   |        213827|        87872641.033|          2433.374|             0.011|
|sumUnr*(r: var FF; a, b: FF)                                |         66038|        90162882.460|           732.430|             0.011|
|diff*(r: var FF; a, b: FF)                                  |         61714|        87589645.477|           704.581|             0.011|
|prod*(r: var FF; a, b: FF; lazyReduce: static bool = false) |          3076|        57089829.250|            53.880|             0.018|
|square*(r: var FF; a: FF; lazyReduce: static bool = false)  |             4|         8714596.950|             0.459|             0.115|
|sumprod*(r: var FF; a, b: array[N, FF]; lazyReduce: stat ...|        136890|        17828028.098|          7678.359|             0.056|
|inv_vartime*(r: var FF; a: FF)                              |             2|          466091.820|             4.291|             2.146|
|square2x_complex(r: var QuadraticExt2x; a: Fp2)             |           579|         9531491.785|            60.746|             0.105|
|prod2x_complex(r: var QuadraticExt2x; a, b: Fp2)            |         24814|        10474333.577|          2369.029|             0.095|
|prodImpl_fp6o2_complex_snr_1pi(r: var Fp6[Name]; a, b: F ...|         22815|         1435987.799|         15888.018|             0.696|
|cyclotomic_inv*(a: var FT)                                  |           512|         2713819.277|           188.664|             0.368|
|square*(r: var T2Prj[F]; a: T2Prj[F])                       |            63|          351217.554|           179.376|             2.847|
|`~*=`(a: var T2Prj; b: T2Aff)                               |          9938|          565468.546|         17574.806|             1.768|
|`~*=`(a: var T2Prj; b: T2Prj)                               |          1270|          245084.795|          5181.880|             4.080|
|`~/=`(a: var T2Prj; b: T2Aff)                               |          4581|          505328.396|          9065.392|             1.979|
|accumulate(buckets: ptr UncheckedArray[GtAcc]; val: Secr ...|         10240|          542745.156|         18867.050|             1.842|
|bucketReduce(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            10|            1935.093|          5167.709|           516.771|
|miniMultiExp(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            10|             408.821|         24460.582|          2446.058|
|multiExpImpl_vartime(r: var GtAcc; elems: ptr UncheckedA ...|             1|              40.851|         24479.500|         24479.500|
|multiExp_vartime*(r: var GT; elems: ptr UncheckedArray[G ...|             1|              35.167|         28435.667|         28435.667|
|multiExp_vartime*(r: var GT; elems: openArray[GT]; expos ...|             1|              35.167|         28435.750|         28435.750|