# Constant-time primitives

This folder holds:

- the constant-time primitives, implemented as distinct types
  to have the compiler enforce proper usage
- extended precision multiplication and division primitives
- assembly primitives
- intrinsics

## Security

⚠: **Hardware assumptions**

  Constantine assumes that multiplication is implemented
  constant-time in hardware.

  If this is not the case,
  you SHOULD **strongly reconsider** your hardware choice or
  reimplement multiplication with constant-time guarantees
  (at the cost of speed and code-size)

⚠: Currently division and modulo operations are `unsafe`
  and uses hardware division.
  No known CPU implements division in constant-time.
  A constant-time alternative will be provided.

While extremely slow, division and modulo are only used
on random or user inputs to constrain them to the prime field
of the elliptic curves.
Constantine internals are built to avoid costly constant-time divisions.

## Performance and code size

It is recommended to prefer Clang, MSVC or ICC over GCC if possible.
GCC code is significantly slower and bigger for multiprecision arithmetic
even when using dedicated intrinsics.

See https://gcc.godbolt.org/z/2h768y
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

### Inline assembly

Using inline assembly will sacrifice code readability, portability, auditability and maintainability.
That said the performance might be worth it.
