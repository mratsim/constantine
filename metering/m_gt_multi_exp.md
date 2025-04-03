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
|neg*(r: var FF; a: FF)                                      |         19254|       122702592.470|           156.916|             0.008|
|neg*(a: var FF)                                             |          2048|        33346902.223|            61.415|             0.030|
|`+=`*(a: var FF; b: FF)                                     |           720|       144115292.234|             4.996|             0.007|
|double*(a: var FF)                                          |           720|       126961735.144|             5.671|             0.008|
|sum*(r: var FF; a, b: FF)                                   |        141300|       134697274.311|          1049.019|             0.007|
|sumUnr*(r: var FF; a, b: FF)                                |        353916|       136966251.478|          2583.965|             0.007|
|diff*(r: var FF; a, b: FF)                                  |           960|       149393090.570|             6.426|             0.007|
|prod*(r: var FF; a, b: FF; lazyReduce: static bool = false) |          1536|        73128927.823|            21.004|             0.014|
|prod2x*(r: var FpDbl; a, b: Fp)                             |        319554|       128695027.412|          2483.033|             0.008|
|redc2x*(r: var Fp; a: FpDbl)                                |         72516|       114905592.212|           631.092|             0.009|
|diff2xUnr*(r: var FpDbl; a, b: FpDbl)                       |        212316|       129110095.308|          1644.457|             0.008|
|diff2xMod*(r: var FpDbl; a, b: FpDbl)                       |        434938|       124428975.543|          3495.472|             0.008|
|sum2xMod*(r: var FpDbl; a, b: FpDbl)                        |        187900|       120900156.031|          1554.175|             0.008|
|square2x_complex(r: var QuadraticExt2x; a: Fp2)             |           540|         8165981.128|            66.128|             0.122|
|prod2x_complex(r: var QuadraticExt2x; a, b: Fp2)            |        106158|         5183667.195|         20479.324|             0.193|
|cyclotomic_inv*(a: var FT)                                  |           256|         3618374.558|            70.750|             0.276|
|cyclotomic_inv*(r: var FT; a: FT)                           |          2569|         6448455.032|           398.390|             0.155|
|cyclotomic_square*(r: var FT; a: FT)                        |            60|          320929.412|           186.957|             3.116|
|`~*=`(a: var Gt; b: Gt)                                     |          6222|          146563.558|         42452.572|             6.823|
|`~/=`(a: var Gt; b: Gt)                                     |          2569|          142160.939|         18071.068|             7.034|
|setNeutral(a: var Gt)                                       |           385|        95155709.343|             4.046|             0.011|
|accumulate(buckets: ptr UncheckedArray[GtAcc]; val: Secr ...|          5632|          147013.903|         38309.302|             6.802|
|bucketReduce(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            11|            2334.961|          4711.000|           428.273|
|miniMultiExp(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            11|             253.630|         43370.209|          3942.746|
|multiExpImpl_vartime(r: var GtAcc; elems: ptr UncheckedA ...|             1|              23.052|         43380.166|         43380.166|
|multiExp_vartime*(r: var GT; elems: ptr UncheckedArray[G ...|             1|              22.826|         43810.458|         43810.458|
|multiExp_vartime*(r: var GT; elems: openArray[GT]; expos ...|             1|              22.826|         43810.500|         43810.500|

## BLS12-381, Fp12 over Fp6 over Fp2, 128 inputs, non-torus

|                         Procedures                         |  # of Calls  | Throughput (ops/s) |    Time (µs)     |  Avg Time (µs)   |
|------------------------------------------------------------|--------------|--------------------|------------------|------------------|
|neg*(r: var FF; a: FF)                                      |         19254|       131545146.480|           146.368|             0.008|
|neg*(a: var FF)                                             |          2048|        37609725.640|            54.454|             0.027|
|`+=`*(a: var FF; b: FF)                                     |           720|       172910662.824|             4.164|             0.006|
|double*(a: var FF)                                          |           720|       171265461.465|             4.204|             0.006|
|sum*(r: var FF; a, b: FF)                                   |        211560|       143783191.585|          1471.382|             0.007|
|sumUnr*(r: var FF; a, b: FF)                                |        283656|       145350124.210|          1951.536|             0.007|
|diff*(r: var FF; a, b: FF)                                  |           960|       159813550.857|             6.007|             0.006|
|prod*(r: var FF; a, b: FF; lazyReduce: static bool = false) |          1536|        75438337.999|            20.361|             0.013|
|prod2x*(r: var FpDbl; a, b: Fp)                             |        319554|       138028474.415|          2315.131|             0.007|
|redc2x*(r: var Fp; a: FpDbl)                                |         72516|       124491414.563|           582.498|             0.008|
|diff2xUnr*(r: var FpDbl; a, b: FpDbl)                       |        212316|       138593347.629|          1531.935|             0.007|
|diff2xMod*(r: var FpDbl; a, b: FpDbl)                       |        429083|       132738774.529|          3232.537|             0.008|
|sum2xMod*(r: var FpDbl; a, b: FpDbl)                        |        182045|       130376616.503|          1396.301|             0.008|
|square2x_complex(r: var QuadraticExt2x; a: Fp2)             |           540|         8899876.391|            60.675|             0.112|
|prod2x_complex(r: var QuadraticExt2x; a, b: Fp2)            |        106158|         5529144.285|         19199.716|             0.181|
|cyclotomic_inv*(a: var FT)                                  |           256|         3797318.144|            67.416|             0.263|
|cyclotomic_inv*(r: var FT; a: FT)                           |          2569|         6909164.257|           371.825|             0.145|
|cyclotomic_square*(r: var FT; a: FT)                        |            60|          346486.340|           173.167|             2.886|
|`~*=`(a: var Gt; b: Gt)                                     |          6222|          157532.392|         39496.639|             6.348|
|`~/=`(a: var Gt; b: Gt)                                     |          2569|          152816.881|         16810.970|             6.544|
|setNeutral(a: var Gt)                                       |           385|       106031396.310|             3.631|             0.009|
|accumulate(buckets: ptr UncheckedArray[GtAcc]; val: Secr ...|          5632|          158170.053|         35607.246|             6.322|
|bucketReduce(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            11|            2486.507|          4423.876|           402.171|
|miniMultiExp(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            11|             272.586|         40354.250|          3668.568|
|multiExpImpl_vartime(r: var GtAcc; elems: ptr UncheckedA ...|             1|              24.778|         40357.750|         40357.750|
|multiExp_vartime*(r: var GT; elems: ptr UncheckedArray[G ...|             1|              24.545|         40742.208|         40742.208|
|multiExp_vartime*(r: var GT; elems: openArray[GT]; expos ...|             1|              24.545|         40742.292|         40742.292|

## BLS12-381, Fp12 over Fp6 over Fp2, 128 inputs, with-torus

|                         Procedures                         |  # of Calls  | Throughput (ops/s) |    Time (µs)     |  Avg Time (µs)   |
|------------------------------------------------------------|--------------|--------------------|------------------|------------------|
|neg*(r: var FF; a: FF)                                      |         56561|       132501077.606|           426.872|             0.008|
|neg*(a: var FF)                                             |          2054|        35983322.238|            57.082|             0.028|
|`+=`*(a: var FF; b: FF)                                     |             2|                 inf|             0.000|             0.000|
|`-=`*(a: var FF; b: FF)                                     |           370|       156646909.399|             2.362|             0.006|
|sum*(r: var FF; a, b: FF)                                   |        118050|       144184967.145|           818.740|             0.007|
|sumUnr*(r: var FF; a, b: FF)                                |         36716|       148534718.514|           247.188|             0.007|
|diff*(r: var FF; a, b: FF)                                  |         33674|       144130802.320|           233.635|             0.007|
|prod*(r: var FF; a, b: FF; lazyReduce: static bool = false) |          1540|        75431034.483|            20.416|             0.013|
|square*(r: var FF; a: FF; lazyReduce: static bool = false)  |             4|        95238095.238|             0.042|             0.011|
|sumprod*(r: var FF; a, b: array[N, FF]; lazyReduce: stat ...|         74574|        20986814.222|          3553.374|             0.048|
|inv_vartime*(r: var FF; a: FF)                              |             2|          623247.117|             3.209|             1.605|
|prod2x*(r: var FpDbl; a, b: Fp)                             |         42030|       137851187.626|           304.894|             0.007|
|redc2x*(r: var Fp; a: FpDbl)                                |         10624|       119171275.056|            89.149|             0.008|
|diff2xUnr*(r: var FpDbl; a, b: FpDbl)                       |         27284|       138409638.554|           197.125|             0.007|
|diff2xMod*(r: var FpDbl; a, b: FpDbl)                       |         53702|       129650150.770|           414.207|             0.008|
|sum2xUnr*(r: var FpDbl; a, b: FpDbl)                        |             4|        48192771.084|             0.083|             0.021|
|sum2xMod*(r: var FpDbl; a, b: FpDbl)                        |         24492|       129794010.567|           188.699|             0.008|
|square2x_complex(r: var QuadraticExt2x; a: Fp2)             |           552|         8749405.611|            63.090|             0.114|
|prod2x_complex(r: var QuadraticExt2x; a, b: Fp2)            |         13642|         5550578.128|          2457.762|             0.180|
|prodImpl_fp6o2_complex_snr_1pi(r: var Fp6[Name]; a, b: F ...|         12429|         1842136.232|          6747.058|             0.543|
|cyclotomic_inv*(a: var FT)                                  |           256|         3813666.632|            67.127|             0.262|
|square*(r: var T2Prj[F]; a: T2Prj[F])                       |            60|          209031.557|           287.038|             4.784|
|`~*=`(a: var T2Prj; b: T2Aff)                               |          5529|          745849.668|          7413.022|             1.341|
|`~*=`(a: var T2Prj; b: T2Prj)                               |           693|          148080.942|          4679.873|             6.753|
|`~/=`(a: var T2Prj; b: T2Aff)                               |          2569|          666131.307|          3856.597|             1.501|
|accumulate(buckets: ptr UncheckedArray[GtAcc]; val: Secr ...|          5632|          710603.012|          7925.663|             1.407|
|bucketReduce(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            11|            2382.844|          4616.332|           419.667|
|miniMultiExp(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            11|             847.033|         12986.501|          1180.591|
|multiExpImpl_vartime(r: var GtAcc; elems: ptr UncheckedA ...|             1|              76.978|         12990.708|         12990.708|
|multiExp_vartime*(r: var GT; elems: ptr UncheckedArray[G ...|             1|              68.407|         14618.292|         14618.292|
|multiExp_vartime*(r: var GT; elems: openArray[GT]; expos ...|             1|              68.407|         14618.375|         14618.375|

## BLS12-381, Fp12 over Fp4 over Fp2, 256 inputs, non-torus

|                         Procedures                         |  # of Calls  | Throughput (ops/s) |    Time (µs)     |  Avg Time (µs)   |
|------------------------------------------------------------|--------------|--------------------|------------------|------------------|
|neg*(r: var FF; a: FF)                                      |         35166|       126704690.805|           277.543|             0.008|
|neg*(a: var FF)                                             |          4096|        34578823.847|           118.454|             0.029|
|`+=`*(a: var FF; b: FF)                                     |           756|       169773186.616|             4.453|             0.006|
|double*(a: var FF)                                          |           756|       167701863.354|             4.508|             0.006|
|sum*(r: var FF; a, b: FF)                                   |        252939|       145085575.245|          1743.378|             0.007|
|sumUnr*(r: var FF; a, b: FF)                                |        634506|       146501318.384|          4331.060|             0.007|
|diff*(r: var FF; a, b: FF)                                  |          1008|       144890038.810|             6.957|             0.007|
|prod*(r: var FF; a, b: FF; lazyReduce: static bool = false) |          3072|        79877271.900|            38.459|             0.013|
|prod2x*(r: var FpDbl; a, b: Fp)                             |        573012|       137301264.775|          4173.392|             0.007|
|redc2x*(r: var Fp; a: FpDbl)                                |        129888|       124049960.747|          1047.062|             0.008|
|diff2xUnr*(r: var FpDbl; a, b: FpDbl)                       |        381252|       137476142.380|          2773.223|             0.007|
|diff2xMod*(r: var FpDbl; a, b: FpDbl)                       |        779851|       132272789.104|          5895.778|             0.008|
|sum2xMod*(r: var FpDbl; a, b: FpDbl)                        |        336727|       131844901.434|          2553.963|             0.008|
|square2x_complex(r: var QuadraticExt2x; a: Fp2)             |           567|         8937156.187|            63.443|             0.112|
|prod2x_complex(r: var QuadraticExt2x; a, b: Fp2)            |        190626|         5544119.501|         34383.458|             0.180|
|cyclotomic_inv*(a: var FT)                                  |           512|         3806606.544|           134.503|             0.263|
|cyclotomic_inv*(r: var FT; a: FT)                           |          4581|         6975596.832|           656.718|             0.143|
|cyclotomic_square*(r: var FT; a: FT)                        |            63|          332966.894|           189.208|             3.003|
|`~*=`(a: var Gt; b: Gt)                                     |         11208|          157395.771|         71209.029|             6.353|
|`~/=`(a: var Gt; b: Gt)                                     |          4581|          152702.005|         29999.606|             6.549|
|setNeutral(a: var Gt)                                       |           705|        97241379.310|             7.250|             0.010|
|accumulate(buckets: ptr UncheckedArray[GtAcc]; val: Secr ...|         10240|          158735.712|         64509.743|             6.300|
|bucketReduce(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            10|            1297.515|          7707.041|           770.704|
|miniMultiExp(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            10|             137.709|         72617.043|          7261.704|
|multiExpImpl_vartime(r: var GtAcc; elems: ptr UncheckedA ...|             1|              13.770|         72622.000|         72622.000|
|multiExp_vartime*(r: var GT; elems: ptr UncheckedArray[G ...|             1|              13.626|         73388.625|         73388.625|
|multiExp_vartime*(r: var GT; elems: openArray[GT]; expos ...|             1|              13.626|         73388.667|         73388.667|

## BLS12-381, Fp12 over Fp6 over Fp2, 256 inputs, non-torus

|                         Procedures                         |  # of Calls  | Throughput (ops/s) |    Time (µs)     |  Avg Time (µs)   |
|------------------------------------------------------------|--------------|--------------------|------------------|------------------|
|neg*(r: var FF; a: FF)                                      |         35166|       129358101.894|           271.850|             0.008|
|neg*(a: var FF)                                             |          4096|        35248356.339|           116.204|             0.028|
|`+=`*(a: var FF; b: FF)                                     |           756|       160373355.961|             4.714|             0.006|
|double*(a: var FF)                                          |           756|       160851063.830|             4.700|             0.006|
|sum*(r: var FF; a, b: FF)                                   |        378999|       144678416.061|          2619.596|             0.007|
|sumUnr*(r: var FF; a, b: FF)                                |        508446|       147919223.163|          3437.322|             0.007|
|diff*(r: var FF; a, b: FF)                                  |          1008|       170616113.744|             5.908|             0.006|
|prod*(r: var FF; a, b: FF; lazyReduce: static bool = false) |          3072|        73174217.522|            41.982|             0.014|
|prod2x*(r: var FpDbl; a, b: Fp)                             |        573012|       137890872.128|          4155.547|             0.007|
|redc2x*(r: var Fp; a: FpDbl)                                |        129888|       122722131.991|          1058.391|             0.008|
|diff2xUnr*(r: var FpDbl; a, b: FpDbl)                       |        381252|       138533518.213|          2752.056|             0.007|
|diff2xMod*(r: var FpDbl; a, b: FpDbl)                       |        769346|       133013460.821|          5783.971|             0.008|
|sum2xMod*(r: var FpDbl; a, b: FpDbl)                        |        326222|       128821031.399|          2532.366|             0.008|
|square2x_complex(r: var QuadraticExt2x; a: Fp2)             |           567|         8935466.078|            63.455|             0.112|
|prod2x_complex(r: var QuadraticExt2x; a, b: Fp2)            |        190626|         5548382.515|         34357.040|             0.180|
|cyclotomic_inv*(a: var FT)                                  |           512|         3797205.494|           134.836|             0.263|
|cyclotomic_inv*(r: var FT; a: FT)                           |          4581|         6896520.577|           664.248|             0.145|
|cyclotomic_square*(r: var FT; a: FT)                        |            63|          347029.046|           181.541|             2.882|
|`~*=`(a: var Gt; b: Gt)                                     |         11208|          158719.866|         70614.979|             6.300|
|`~/=`(a: var Gt; b: Gt)                                     |          4581|          153921.025|         29762.016|             6.497|
|setNeutral(a: var Gt)                                       |           705|       107045247.495|             6.586|             0.009|
|accumulate(buckets: ptr UncheckedArray[GtAcc]; val: Secr ...|         10240|          160108.491|         63956.633|             6.246|
|bucketReduce(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            10|            1303.632|          7670.875|           767.087|
|miniMultiExp(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            10|             138.845|         72022.999|          7202.300|
|multiExpImpl_vartime(r: var GtAcc; elems: ptr UncheckedA ...|             1|              13.884|         72026.708|         72026.708|
|multiExp_vartime*(r: var GT; elems: ptr UncheckedArray[G ...|             1|              13.734|         72809.959|         72809.959|
|multiExp_vartime*(r: var GT; elems: openArray[GT]; expos ...|             1|              13.734|         72809.959|         72809.959|

## BLS12-381, Fp12 over Fp6 over Fp2, 256 inputs, with-torus
|                         Procedures                         |  # of Calls  | Throughput (ops/s) |    Time (µs)     |  Avg Time (µs)   |
|------------------------------------------------------------|--------------|--------------------|------------------|------------------|
|neg*(r: var FF; a: FF)                                      |        103631|       129407886.275|           800.809|             0.008|
|neg*(a: var FF)                                             |          4102|        34947519.084|           117.376|             0.029|
|`+=`*(a: var FF; b: FF)                                     |             2|                 inf|             0.000|             0.000|
|`-=`*(a: var FF; b: FF)                                     |           388|       118076688.984|             3.286|             0.008|
|sum*(r: var FF; a, b: FF)                                   |        213827|       140828345.469|          1518.352|             0.007|
|sumUnr*(r: var FF; a, b: FF)                                |         66038|       144445440.885|           457.183|             0.007|
|diff*(r: var FF; a, b: FF)                                  |         61714|       143491898.151|           430.087|             0.007|
|prod*(r: var FF; a, b: FF; lazyReduce: static bool = false) |          3076|        74041979.588|            41.544|             0.014|
|square*(r: var FF; a: FF; lazyReduce: static bool = false)  |             4|        32000000.000|             0.125|             0.031|
|sumprod*(r: var FF; a, b: array[N, FF]; lazyReduce: stat ...|        136890|        20475818.595|          6685.447|             0.049|
|inv_vartime*(r: var FF; a: FF)                              |             2|          551571.980|             3.626|             1.813|
|prod2x*(r: var FpDbl; a, b: Fp)                             |         75600|       136551073.895|           553.639|             0.007|
|redc2x*(r: var Fp; a: FpDbl)                                |         19120|       124395750.246|           153.703|             0.008|
|diff2xUnr*(r: var FpDbl; a, b: FpDbl)                       |         49628|       135367427.042|           366.617|             0.007|
|diff2xMod*(r: var FpDbl; a, b: FpDbl)                       |         96702|       131104823.392|           737.593|             0.008|
|sum2xUnr*(r: var FpDbl; a, b: FpDbl)                        |             4|        95238095.238|             0.042|             0.011|
|sum2xMod*(r: var FpDbl; a, b: FpDbl)                        |         42526|       125849705.988|           337.911|             0.008|
|square2x_complex(r: var QuadraticExt2x; a: Fp2)             |           579|         8918806.513|            64.919|             0.112|
|prod2x_complex(r: var QuadraticExt2x; a, b: Fp2)            |         24814|         5465659.233|          4539.983|             0.183|
|prodImpl_fp6o2_complex_snr_1pi(r: var Fp6[Name]; a, b: F ...|         22815|         1799026.042|         12681.862|             0.556|
|cyclotomic_inv*(a: var FT)                                  |           512|         3797458.966|           134.827|             0.263|
|square*(r: var T2Prj[F]; a: T2Prj[F])                       |            63|          210557.979|           299.205|             4.749|
|`~*=`(a: var T2Prj; b: T2Aff)                               |          9938|          724421.693|         13718.529|             1.380|
|`~*=`(a: var T2Prj; b: T2Prj)                               |          1270|          146443.966|          8672.259|             6.829|
|`~/=`(a: var T2Prj; b: T2Aff)                               |          4581|          653314.390|          7011.938|             1.531|
|accumulate(buckets: ptr UncheckedArray[GtAcc]; val: Secr ...|         10240|          698654.823|         14656.737|             1.431|
|bucketReduce(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            10|            1160.144|          8619.623|           861.962|
|miniMultiExp(r: var GtAcc; buckets: ptr UncheckedArray[G ...|            10|             420.192|         23798.665|          2379.867|
|multiExpImpl_vartime(r: var GtAcc; elems: ptr UncheckedA ...|             1|              42.000|         23809.625|         23809.625|
|multiExp_vartime*(r: var GT; elems: ptr UncheckedArray[G ...|             1|              36.887|         27110.167|         27110.167|
|multiExp_vartime*(r: var GT; elems: openArray[GT]; expos ...|             1|              36.887|         27110.167|         27110.167|
