# Constant-time primitives

This folder holds:

- the constant-time primitives, implemented as distinct types
  to have the compiler enforce proper usage
- extended precision multiplication and division primitives
- assembly or builtin int128 primitives
- SIMD intrinsics
- assemblers for x86 and LLVM IR
- a code generator for Nvidia GPU from LLVM IR
- runtime CPU features detection
- a threadpool

## Runtimes

Constantine strongly avoid any runtime so that it can be used even where garbage collection, dynamic memory allocation
are not allowed. That also avoids secrets remaining in heap memory.

At runtime, Constantine may:
- detect the CPU features at the start of the application (in Nim) or after calling `ctt_myprotocol_init_NimMain()` for the C (or any other language) bindings.

And offers the following opt-in features with use dynamic allocation:
- a threadpool, only for explicitly tagged parallel primitives.
- use LLVM and Cuda, and configure code to run computation on GPUs.

## Security

⚠: **Hardware assumptions**

  Constantine assumes that multiplication is implemented
  constant-time in hardware.

  If this is not the case,
  you SHOULD **strongly reconsider** your hardware choice or
  reimplement multiplication with constant-time guarantees
  (at the cost of speed and code-size)

Division is (naively) implemented in constant-time,
as no hardware provides constant-time division
While extremely slow, Constantine internals are built to avoid costly constant-time divisions.

## Assembler

For both security and performance purposes, Constantine uses inline assembly for field arithmetic.

### Assembly Security

General purposes compiler can and do rewrite code as long as any observable effect is maintained. Unfortunately timing is not considered an observable effect and as general purpose compiler gets smarter and branch prediction on processor gets also smarter, compilers recognize and rewrite increasingly more initial branchless code to code with branches, potentially exposing secret data.

A typical example is conditional mov which is required to be constant-time any time secrets are involved (https://tools.ietf.org/html/draft-irtf-cfrg-hash-to-curve-08#section-4)
The paper `What you get is what you C: Controlling side effects in mainstream C compilers` (https://www.cl.cam.ac.uk/~rja14/Papers/whatyouc.pdf) exposes how compiler "improvements" are detrimental to cryptography
![image](https://user-images.githubusercontent.com/22738317/83965485-60cf4f00-a8b4-11ea-866f-4cc8e742f7a8.png)

Another example is secure erasing secret data, which is often elided as an optimization.

Those are not theoretical exploits as explained in the `When constant-time doesn't save you` article (https://research.kudelskisecurity.com/2017/01/16/when-constant-time-source-may-not-save-you/) which explains an attack against Curve25519 which was designed to be easily implemented in a constant-time manner.
This attacks is due to an "optimization" in MSVC compiler
> **every code compiled in 32-bit with MSVC on 64-bit architectures will call llmul every time a 64-bit multiplication is executed.**
- [When Constant-Time Source Yields Variable-Time Binary: Exploiting Curve25519-donna Built with MSVC 2015.](https://infoscience.epfl.ch/record/223794/files/32_1.pdf)

#### Verification of Assembly

The assembly code generated needs special tooling for formal verification that is different from the C code in https://github.com/mratsim/constantine/issues/6.
Recently Microsoft Research introduced Vale:
- Vale: Verifying High-Performance  Cryptographic Assembly Code\
  Barry Bond and Chris Hawblitzel, Microsoft Research; Manos Kapritsos,  University of Michigan; K. Rustan M. Leino and Jacob R. Lorch, Microsoft Research;  Bryan Parno, Carnegie Mellon University; Ashay Rane, The University of Texas at Austin;Srinath Setty, Microsoft Research; Laure Thompson, Cornell University\
  https://www.usenix.org/system/files/conference/usenixsecurity17/sec17-bond.pdf
  https://github.com/project-everest/vale
Vale can be used to verify assembly crypto code against the architecture and also detect timing attacks.

### Assembly Performance

Beyond security, compilers do not expose several primitives that are necessary for necessary for multiprecision arithmetic.

#### Add with carry, sub with borrow

The most egregious example is add with carry which led to the GMP team to implement everything in Assembly even though this is a most basic need and almost all processor have an ADC instruction, some like the 6502 from 30 years ago only have ADC and no ADD.
See:
- https://gmplib.org/manual/Assembly-Carry-Propagation.html
-
![image](https://user-images.githubusercontent.com/22738317/83965806-8f4e2980-a8b6-11ea-9fbb-719e42d119dc.png)

Some specific platforms might expose add with carry, for example x86 but even then the code generation might be extremely poor: https://gcc.godbolt.org/z/2h768y
```C
#include <stdint.h>
#include <x86intrin.h>

void add256(uint64_t a[4], uint64_t b[4]){
  uint8_t carry = 0;
  for (int i = 0; i < 4; ++i)
    carry = _addcarry_u64(carry, a[i], b[i], &a[i]);
}
```
GCC
```asm
add256:
        movq    (%rsi), %rax
        addq    (%rdi), %rax
        setc    %dl
        movq    %rax, (%rdi)
        movq    8(%rdi), %rax
        addb    $-1, %dl
        adcq    8(%rsi), %rax
        setc    %dl
        movq    %rax, 8(%rdi)
        movq    16(%rdi), %rax
        addb    $-1, %dl
        adcq    16(%rsi), %rax
        setc    %dl
        movq    %rax, 16(%rdi)
        movq    24(%rsi), %rax
        addb    $-1, %dl
        adcq    %rax, 24(%rdi)
        ret
```
Clang
```asm
add256:
        movq    (%rsi), %rax
        addq    %rax, (%rdi)
        movq    8(%rsi), %rax
        adcq    %rax, 8(%rdi)
        movq    16(%rsi), %rax
        adcq    %rax, 16(%rdi)
        movq    24(%rsi), %rax
        adcq    %rax, 24(%rdi)
        retq
```
(Reported fixed but it is not? https://gcc.gnu.org/bugzilla/show_bug.cgi?id=67317)

And no way to use ADC for ARM architectures with GCC.
Clang does offer `__builtin_addcll` which might work now or [not](https://stackoverflow.com/questions/33690791/producing-good-add-with-carry-code-from-clang) as fixing the add with carry for x86 took years. Alternatively Clang does offer new arbitrary width integer since a month ago, called ExtInt http://blog.llvm.org/2020/04/the-new-clang-extint-feature-provides.html it is unknown however if code is guaranted to be constant-time.

See also: https://stackoverflow.com/questions/29029572/multi-word-addition-using-the-carry-flag/29212615
