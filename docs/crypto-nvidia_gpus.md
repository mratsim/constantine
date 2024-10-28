# Implementation on Nvidia GPUs

This documentation references useful information for implementing and optimizing for Nvidia GPUs

## Integer instruction bug

### Integer FMA with carry-in uint64

We get incorrect result for modular multiplication with 64-bit limbs due to a fused-multiuply-add with carry bug.

- https://gist.github.com/mratsim/a34df1e091925df15c13208df7eda569#file-mul-py
- https://forums.developer.nvidia.com/t/incorrect-result-of-ptx-code/221067

### Integer FMA with carry-in uint32

The instruction integer fused-multiply-add  with carry-in may
be incorrectly compiled in PTX prior to Cuda 11.5.1:
https://forums.developer.nvidia.com/t/wrong-result-returned-by-madc-hi-u64-ptx-instruction-for-specific-operands/196094

Test case from: https://github.com/tickinbuaa/CudaTest/blob/master/main.cu

```C
#include <cuda_runtime.h>
#include <memory>

__device__
inline void mac_with_carry(uint64_t &lo, uint64_t &hi, const uint64_t &a, const uint64_t &b, const uint64_t &c) {
    if (blockIdx.x == 0 && threadIdx.x == 0) {
        printf("GPU calculation input: a = %lx b = %lx c = %lx\n", a, b, c);
    }
    asm("mad.lo.cc.u64 %0, %2, %3, %4;\n\t"
        "madc.hi.u64 %1, %2, %3, 0;\n\t"
        :"=l"(lo), "=l"(hi): "l"(a), "l"(b), "l"(c));
    if (blockIdx.x == 0 && threadIdx.x == 0) {
        printf("GPU calculation result: hi = %lx low = %lx\n", hi, lo);
    }
}

__global__
void test(uint64_t *out, uint32_t num){
    unsigned int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= num) {
        return;
    }
    uint64_t a = 0x42737a020c0d6393UL;
    uint64_t b = 0xffffffff00000001UL;
    uint64_t c = 0xc999e990f3f29c6dUL;
    mac_with_carry(out[tid << 1], out[(tid << 1) + 1], a, b, c);
}

int main() {
    uint64_t *d_out;
    uint32_t num = 1;
    cudaMalloc(&d_out, num * 2 * sizeof(uint64_t));
    const uint32_t BLOCK_SIZE = 256;
    uint32_t block_num = (num + BLOCK_SIZE - 1) / BLOCK_SIZE;
    test<<<block_num, BLOCK_SIZE>>>(d_out, num);
    cudaDeviceSynchronize();
    unsigned __int128 a = 0x42737a020c0d6393UL;
    unsigned __int128 b = 0xffffffff00000001UL;
    unsigned __int128 c = 0xc999e990f3f29c6dUL;
    unsigned __int128 result = a * b + c;
    printf("Cpu result: hi:%lx low:%lx\n", (uint64_t)((result >> 64) & 0xffffffffffffffffUL), (uint64_t)(result & 0xffffffffffffffffUL));
}
```


## The hidden XMAD instruction

There is a "hidden" instruction called xmad on Nvidia GPUs described in
- Optimizing Modular Multiplication for NVIDIA’s Maxwell GPUs\
  Niall Emmart , Justin Luitjens , Charles Weems and Cliff Woolley\
  https://ieeexplore.ieee.org/abstract/document/7563271

On Maxwell and Pascal GPUs (SM 5.3), there was no native 32-bit integer multiplication, probably due to die size constraint.
So 32-bit mul was based on 16-bit muladd (XMAD) with some PTX->SASS compiler pattern matching to detect optimal XMAD
scheduling.
Starting from Volta (SM 7.0 / RTX 2XXX), there is now an hardware integer multiply again
https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#arithmetic-instructions

Code to generate the proper XMAD is available in:
- https://github.com/NVlabs/xmp/blob/0052dbb/src/include/ptx/PTXInliner_impl.h#L371-L384
- https://github.com/NVlabs/CGBN/blob/e8b9d26/include/cgbn/arith/asm.cu#L131-L142

## Double-precision floating point arithmetic

On double-precision floating point arithmetic.
There are some recent papers exploring using the 52-bit mantissa of a float64 to accelerate elliptic curve cryptography.
This is similar to the AVX approaches on CPU.

- Faster Modular Exponentiation Using Double Precision Floating Point Arithmetic on the GPU\
  Niall Emmart, Fangyu Zheng, Charles Weems\
  https://ieeexplore.ieee.org/document/8464792

- DPF-ECC: Accelerating Elliptic Curve Cryptography with Floating-Point Computing Power of GPUs
  Lili Gao, Fangyu Zheng, Niall Emmart, Jiankuo Dong, Jingqiang Lin, C. Weems\
  https://ieeexplore.ieee.org/document/9139772

Unfortunately float64 arithmetic is extremely slow on Nvidia GPUs except for Tesla-class GPU due to market segmentation.
https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#architecture-8-x

SM 8.0 corresponds to a Tesla A100, and SM 8.6 to RTX 30X0 or Quadro AX000

> A Streaming Multiprocessor (SM) consists of:
>   - 64 FP32 cores for single-precision arithmetic operations in devices of compute capability 8.0\
>        and 128 FP32 cores in devices of compute capability 8.6, 8.7 and 8.9,
>   - 32 FP64 cores for double-precision arithmetic operations in devices of compute capability 8.0\
>        and **2 FP64 cores** in devices of compute capability 8.6, 8.7 and 8.9
>   - **64 INT32 cores** for integer math

Hence Nvidia choose to replace 30 FP64 cores with 64 FP32 cores on consumer GPU. An understandable business decision since graphics and machine learning use and are benchmarked on FP32 with FP64 being used mostly in scientific and simulation workloads. Hozever for blockchain, it's important for decentralization that as much as possible can run on consumer hardware, Tesla cards are $10k so we want to optimize for consumer GPUs with 1/32 INT32/FP64 throughput ratio.

So assuming 1 cycle per instruction on the matching core, we can do 64 INT32 instructions while we do 2 FP64 instructions, hence 1/32 throughput ratio.

Concretely to emulate 64x64->128 extended precision multiplication we need 4 32-bit multiplications (and fused additions):
```
      a₁a₀
*     b₁b₀
---------------------------
      a₀b₀
    a₁b₀
    a₀b₁
  a₁b₁
```

Assuming we need only 2 FP64 instructions for 64x64->128 integer mul (mul.lo and mul.hi) the throughput ratio would be:
`1/32 (base throughput) * 4 (mul int32 instr) * 1/2 (mul fp64) = 1/16`

In reality:
- we use 52-bit mantissa so we would have calculated only 104 bit
- there is extra addition/substraction, shifting and masking involved
- this significantly increase the chances of mistakes. Furthermore formal verification or fuzzing on GPUs isn't the easiest

## Code generation considerations

### Parameter passing:
- https://reviews.llvm.org/D118084
  > The motivation for this change is to allow SROA to eliminate local copies in more cases. Local copies that make it to the generated PTX present a substantial performance hit, as we end up with all threads on the GPU rushing to access their own chunk of very high-latency memory.
Direct parameter passing is easier to analyze but not worthwhile
for large aggregate


### Important optimization passes:

- https://www.llvm.org/docs/Passes.html
- gvn, global value numbering to remove redundant loads
- mem2reg, will promote memory into regisster, memory is expensive in GPUs
  > This file promotes memory references to be register references. It promotes alloca instructions which only have loads and stores as uses. An alloca is transformed by using dominator frontiers to place phi nodes, then traversing the function in depth-first order to rewrite loads and stores as appropriate. This is just the standard SSA construction algorithm to construct “pruned” SSA form.
  https://stackoverflow.com/a/66082008
- SROA, Scalar Replacement of Aggregates, to remove local copies and alloca. Static indices access help.
  as mentioned in https://discourse.llvm.org/t/nvptx-calling-convention-for-aggregate-arguments-passed-by-value/

  https://github.com/llvm/llvm-project/issues/51734#issuecomment-981047833
  > Local loads/stores on GPU are expensive enough to be worth quite a few extra instructions.
- https://github.com/apc-llc/nvcc-llvm-ir

Note: The dead code/instructions elimination passes might remove the ASM not marked sideeffect/volatile

Ordering GVN before SROA: https://reviews.llvm.org/D111471

If we use "normal" instructions instead of inline assembly, this thread links to many LLVM internal discussions
on the passes that optimize to add-with-carry: https://github.com/llvm/llvm-project/issues/31102
We have:
- InstCombine, for instruction combining (see also: https://reviews.llvm.org/D8889, https://reviews.llvm.org/D124698, https://github.com/llvm/llvm-project/issues/39832)
- CodegenPrepare, for ISA specific codegen

### LLVM NVPTX or Nvidia libNVVM

https://docs.nvidia.com/cuda/libnvvm-api/index.html
https://docs.nvidia.com/pdf/libNVVM_API.pdf
https://docs.nvidia.com/cuda/nvvm-ir-spec/index.html
https://docs.nvidia.com/cuda/pdf/NVVM_IR_Specification.pdf

⚠ NVVM IR is based on LLVM 7.0.1 IR which dates from december 2018.
There are a couple of caveats:
- LLVM 7.0.1 is usually not available in repo, making installation difficult
- There was a ABI breaking bug making the 7.0.1 and 7.1.0 versions messy (https://www.phoronix.com/news/LLVM-7.0.1-Released)
- LLVM 7.0.1 does not have LLVMBuildCall2 and relies on the deprecated LLVMBuildCall meaning
  supporting that and latest LLVM (for AMDGPU and SPIR-V backends) will likely have heavy costs
- When generating a add-with-carry kernel with inline ASM calls from LLVM-14,
  if the LLVM IR is passed as bitcode,
  the kernel content is silently discarded, this does not happen with built-in add.
  It is unsure if it's call2 or inline ASM incompatibility that causes the issues
- When generating a add-with-carry kernel with inline ASM calls from LLVM-14,
  if the LLVM IR is passed as testual IR, the code is refused with NVVM_ERROR_INVALID_IR

Hence, using LLVM NVPTX backend instead of libNVVM is likely the sustainable way forward

### Register pressure

See this AMD paper https://dl.acm.org/doi/pdf/10.1145/3368826.3377918
However if we want to reduce register pressure we need to store to local memory which is also expensive.

## Parallel reductions

Batch elliptic point addition `r = P₀ + P₁ + ... + Pₙ` and
multi-scalar multiplication (MSM) `r = [k₀]P₀ + [k₁]P₁ + ... + [kₙ]Pₙ`
are reduction operations.

There is a wealth of resources regarding optimized implementations of those.
The baseline is provided by: [Optimizing Parallel Reduction in CUDA, Mark harris](https://developer.download.nvidia.com/assets/cuda/files/reduction.pdf)
Then on later architectures:
- https://developer.nvidia.com/blog/faster-parallel-reductions-kepler/
- https://www.irisa.fr/alf/downloads/collange/talks/collange_warp_synchronous_19.pdf

Other interesting resources:
- https://on-demand.gputechconf.com/gtc/2017/presentation/s7622-Kyrylo-perelygin-robust-and-scalable-cuda.pdf \
  This explains in great details the cooperative group features
  and examples in reduction kernels
- https://github.com/umfranzw/cuda-reduction-example \
  This explains and uses overlapping streams for latency hiding
- https://vccvisualization.org/teaching/CS380/CS380_fall2020_lecture_25.pdf
  SHFL instruction
- https://unum.cloud/post/2022-01-28-reduce/
  - https://github.com/ashvardanian/ParallelReductionsBenchmark \
  This provides an overview and benchmark code across CPU (AVX2, OpenMP, TBB), OpenCL, Cuda (Cublas, Thrust, Cub)
- https://diglib.eg.org/bitstream/handle/10.2312/egt20211037/CUDA_day2.pdf
  - https://cuda-tutorial.github.io/part3_22.pdf
  - https://github.com/CUDA-Tutorial/CodeSamples