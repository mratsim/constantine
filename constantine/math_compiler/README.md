# Cryptography primitive compiler

This implements a cryptography compiler that can be used to produce
- high-performance JIT code for GPUs
- or assembly files, for CPUs when we want to ensure
  there are no side-channel regressions for secret data
- or vectorized assembly file, as LLVM IR is significantly
  more convenient to model vector operation

There are also LLVM IR => FPGA translators that might be useful
in the future.

## Platforms limitations

- X86 cannot use dual carry-chain ADCX/ADOX easily.
  - no native support for clearing a flag with `xor`
    and keeping it clear.
  - inline assembly cannot use the raw ASM printer.
    so workflow will need to compile -> decompile.
- Nvidia GPUs cannot lower types larger than 64-bit, hence we cannot use i256 for example.
- AMD GPUs have a 1/4 throughput for i32 MUL compared to f32 MUL or i24 MUL
- non-x86 targets may not be as optimized for matching
  pattern for addcarry and subborrow, even with @llvm.usub.with.overflow

## ABI

Internal functions are:
- prefixed with `_`
- Linkage: internal
- calling convention: "fast"
- mark `hot` for field arithmetic functions

Internal global constants are:
- prefixed with `_`
- Linkage: linkonce_odr (so they are merged with globals of the same name)

External functions use default convention.

We ensure parameters / return value fit in registers:
- https://llvm.org/docs/Frontend/PerformanceTips.html

TODO:
- function alignment: look into
  - https://www.bazhenov.me/posts/2024-02-performance-roulette/
  - https://lkml.org/lkml/2015/5/21/443
- function multiversioning
- aggregate alignment (via datalayout)

Naming convention for internal procedures:
- _big_add_u64x4
- _finalsub_mayo_u64x4 -> final substraction may overflow
- _finalsub_noo_u64x4  -> final sub no overflow
- _mod_add_u64x4
- _mod_add2x_u64x8 -> FpDbl backend
- _mty_mulur_u64x4b2 -> unreduced Montgomery multiplication (unreduced result valid iff 2 spare bits)
- _mty_mul_u64x4b1  -> reduced Montgomery multiplication (result valid iff at least 1 spare bit)
- _mty_mul_u64x4  -> reduced Montgomery multiplication
- _mty_nsqrur_u64x4b2 -> unreduced square n times
- _mty_nsqr_u64x4b1 -> reduced square n times
- _mty_sqr_u64x4 -> square
- _mty_red_u64x4 -> reduction u64x4 <- u64x8
- _pmp_red_mayo_u64x4 -> Pseudo-Mersenne Prime partial reduction may overflow (secp256k1)
- _pmp_red_noo_u64x4 -> Pseudo-Mersenne Prime partial reduction no overflow
- _secp256k1_red -> special reduction
- _fp2x_sqr2x_u64x4 -> Fp2 complex, Fp -> FpDbl lazy reduced squaring
- _fp2g_sqr2x_u64x4 -> Fp2 generic/non-complex (do we pass the mul-non-residue as parameter?)
- _fp2_sqr_u64x4 -> Fp2 (pass the mul-by-non-residue function as parameter)
- _fp4o2_mulnr1pi_u64x4 -> Fp4 over Fp2 mul with (1+i) non-residue optimization
- _fp4o2_mulbynr_u64x4
- _fp12_add_u64x4
- _fp12o4o2_mul_u64x4 -> Fp12 over Fp4 over Fp2
- _ecg1swjac_adda0_u64x4 -> Shortweierstrass G1 jacobian addition a=0
- _ecg1swjac_add_u64x4_var -> Shortweierstrass G1 jacobian vartime addition
- _ectwprj_add_u64x4 -> Twisted Edwards Projective addition

Vectorized:
- _big_add_u64x4v4
- _big_add_u32x8v8

Naming for external procedures:
- bls12_381_fp_add
- bls12_381_fr_add
- bls12_381_fp12_add
