# Assembly code generator for mathematical primitives

This folder holds code generators for inline assembly in Nim and LLVM IR.

Inline assembly is necessary for security, ensure constant-time from a high-level language, and performance as certain instructions cannot be emitted by a compiler (ADOX/ADCX) despite offering a large performance advantage (up to 70% for ADOX/ADCX).

Even when using LLVM IR and in the case where all instructions can be emitted (ARM64),
and the number of compute instructions between inline assembly and LLVM IR is the same
stack usage might be significantly worse due to bad register allocation and regular stack spill.

For example on ARM64, with LLVM IR that mirrors inline assembly we get the following
breakdown on 6 limbs (CodeGenLevelDefault):
-  inline ASM     vs pure LLVM IR
-  64 bytes stack vs      368
-   4 stp         vs       23
-  10 ldp         vs       35
-   6 ldr         vs       61
-   6 str         vs       43
-   6 mov         vs       24
-  78 mul         vs       78
-  72 umulh       vs       72
-  17 adds        vs       17
- 103 adcs        vs      103
-  23 adc         vs       12   -> the ADC have become cset to save the carry/borrow flag in register
-   6 cmn         vs        6
-   0 cset        vs       11

And generating single instruction in LLVM inline assembly doesn't solve register spilling to the stack.