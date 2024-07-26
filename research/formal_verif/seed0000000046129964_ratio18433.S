.text
.intel_syntax noprefix

.global cryptopt_bls12_381_fp_mul_18433

cryptopt_bls12_381_fp_mul_18433:
sub rsp, 424
mov rax, rdx
mov rdx, [ rdx + 0x8 ]
mulx r11, r10, [ rsi + 0x0 ]
mov rdx, [ rax + 0x10 ]
mulx r8, rcx, [ rsi + 0x20 ]
mov rdx, [ rax + 0x10 ]
mov [ rsp - 0x80 ], rbx
mulx rbx, r9, [ rsi + 0x0 ]
mov rdx, [ rax + 0x20 ]
mov [ rsp - 0x78 ], rbp
mov [ rsp - 0x70 ], r12
mulx r12, rbp, [ rsi + 0x8 ]
mov rdx, [ rsi + 0x18 ]
mov [ rsp - 0x68 ], r13
mov [ rsp - 0x60 ], r14
mulx r14, r13, [ rax + 0x8 ]
mov rdx, [ rsi + 0x10 ]
mov [ rsp - 0x58 ], r15
mov [ rsp - 0x50 ], rdi
mulx rdi, r15, [ rax + 0x0 ]
mov rdx, [ rsi + 0x0 ]
mov [ rsp - 0x48 ], r15
mov [ rsp - 0x40 ], r12
mulx r12, r15, [ rax + 0x0 ]
xor rdx, rdx
adox r10, r12
mov rdx, [ rsi + 0x0 ]
mov [ rsp - 0x38 ], r10
mulx r10, r12, [ rax + 0x28 ]
mov rdx, [ rsi + 0x20 ]
mov [ rsp - 0x30 ], rbp
mov [ rsp - 0x28 ], r15
mulx r15, rbp, [ rax + 0x0 ]
adox r9, r11
mov rdx, [ rax + 0x8 ]
mov [ rsp - 0x20 ], rbp
mulx rbp, r11, [ rsi + 0x20 ]
adcx r11, r15
adcx rcx, rbp
mov rdx, [ rsi + 0x20 ]
mulx rbp, r15, [ rax + 0x18 ]
adcx r15, r8
mov rdx, [ rsi + 0x0 ]
mov [ rsp - 0x18 ], r15
mulx r15, r8, [ rax + 0x18 ]
adox r8, rbx
mov rdx, [ rax + 0x20 ]
mov [ rsp - 0x10 ], rcx
mulx rcx, rbx, [ rsi + 0x0 ]
mov rdx, [ rsi + 0x20 ]
mov [ rsp - 0x8 ], r11
mov [ rsp + 0x0 ], r8
mulx r8, r11, [ rax + 0x20 ]
adox rbx, r15
adox r12, rcx
mov rdx, [ rax + 0x28 ]
mulx rcx, r15, [ rsi + 0x20 ]
adcx r11, rbp
mov rdx, [ rax + 0x10 ]
mov [ rsp + 0x8 ], r11
mulx r11, rbp, [ rsi + 0x28 ]
adcx r15, r8
mov rdx, [ rsi + 0x28 ]
mov [ rsp + 0x10 ], r15
mulx r15, r8, [ rax + 0x0 ]
mov rdx, [ rax + 0x8 ]
mov [ rsp + 0x18 ], r8
mov [ rsp + 0x20 ], r12
mulx r12, r8, [ rsi + 0x28 ]
mov rdx, 0x0
adcx rcx, rdx
adox r10, rdx
test al, al
adox r8, r15
adox rbp, r12
mov rdx, [ rax + 0x8 ]
mulx r12, r15, [ rsi + 0x10 ]
mov rdx, [ rsi + 0x10 ]
mov [ rsp + 0x28 ], rbp
mov [ rsp + 0x30 ], r8
mulx r8, rbp, [ rax + 0x10 ]
adcx r15, rdi
adcx rbp, r12
mov rdx, [ rax + 0x18 ]
mulx r12, rdi, [ rsi + 0x28 ]
adox rdi, r11
mov rdx, [ rax + 0x18 ]
mov [ rsp + 0x38 ], rdi
mulx rdi, r11, [ rsi + 0x10 ]
adcx r11, r8
mov rdx, [ rax + 0x28 ]
mov [ rsp + 0x40 ], rcx
mulx rcx, r8, [ rsi + 0x10 ]
mov rdx, [ rax + 0x20 ]
mov [ rsp + 0x48 ], r11
mov [ rsp + 0x50 ], rbp
mulx rbp, r11, [ rsi + 0x10 ]
mov rdx, [ rsi + 0x18 ]
mov [ rsp + 0x58 ], r15
mov [ rsp + 0x60 ], r10
mulx r10, r15, [ rax + 0x0 ]
adcx r11, rdi
adcx r8, rbp
mov rdx, [ rsi + 0x18 ]
mulx rbp, rdi, [ rax + 0x10 ]
mov rdx, 0x0
adcx rcx, rdx
clc
adcx r13, r10
adcx rdi, r14
mov rdx, [ rax + 0x18 ]
mulx r10, r14, [ rsi + 0x18 ]
adcx r14, rbp
mov rdx, 0x89f3fffcfffcfffd
mov [ rsp + 0x68 ], r14
mulx r14, rbp, [ rsp - 0x28 ]
mov rdx, [ rax + 0x20 ]
mov [ rsp + 0x70 ], rdi
mulx rdi, r14, [ rsi + 0x18 ]
mov rdx, 0xb9feffffffffaaab
mov [ rsp + 0x78 ], r13
mov [ rsp + 0x80 ], r15
mulx r15, r13, rbp
mov rdx, [ rsi + 0x28 ]
mov [ rsp + 0x88 ], rcx
mov [ rsp + 0x90 ], r8
mulx r8, rcx, [ rax + 0x20 ]
mov rdx, 0x1eabfffeb153ffff
mov [ rsp + 0x98 ], r11
mov [ rsp + 0xa0 ], rbx
mulx rbx, r11, rbp
adcx r14, r10
mov rdx, [ rsi + 0x18 ]
mov [ rsp + 0xa8 ], r14
mulx r14, r10, [ rax + 0x28 ]
adox rcx, r12
adcx r10, rdi
mov rdx, [ rax + 0x8 ]
mulx rdi, r12, [ rsi + 0x8 ]
mov rdx, [ rsi + 0x28 ]
mov [ rsp + 0xb0 ], rcx
mov [ rsp + 0xb8 ], r10
mulx r10, rcx, [ rax + 0x28 ]
adox rcx, r8
mov rdx, 0x0
adox r10, rdx
adc r14, 0x0
mov rdx, [ rax + 0x10 ]
mov [ rsp + 0xc0 ], r10
mulx r10, r8, [ rsi + 0x8 ]
mov rdx, [ rax + 0x0 ]
mov [ rsp + 0xc8 ], rcx
mov [ rsp + 0xd0 ], r14
mulx r14, rcx, [ rsi + 0x8 ]
test al, al
adox r12, r14
mov rdx, 0x6730d2a0f6b0f624
mov [ rsp + 0xd8 ], r12
mulx r12, r14, rbp
adcx r11, r15
adcx r14, rbx
adox r8, rdi
mov r15, 0x64774b84f38512bf
mov rdx, r15
mulx rbx, r15, rbp
mov rdi, 0x4b1ba7b6434bacd7
mov rdx, rbp
mov [ rsp + 0xe0 ], r8
mulx r8, rbp, rdi
adcx r15, r12
adcx rbp, rbx
mov r12, 0x1a0111ea397fe69a
mulx rdi, rbx, r12
mov rdx, [ rax + 0x18 ]
mov [ rsp + 0xe8 ], rbp
mulx rbp, r12, [ rsi + 0x8 ]
adox r12, r10
adcx rbx, r8
mov rdx, [ rax + 0x28 ]
mulx r8, r10, [ rsi + 0x8 ]
adox rbp, [ rsp - 0x30 ]
adox r10, [ rsp - 0x40 ]
mov rdx, 0x0
adcx rdi, rdx
adox r8, rdx
mov [ rsp + 0xf0 ], r8
xor r8, r8
adox r13, [ rsp - 0x28 ]
adox r11, [ rsp - 0x38 ]
adcx rcx, r11
adox r14, r9
adox r15, [ rsp + 0x0 ]
adcx r14, [ rsp + 0xd8 ]
adcx r15, [ rsp + 0xe0 ]
mov rdx, [ rsp + 0xa0 ]
adox rdx, [ rsp + 0xe8 ]
adox rbx, [ rsp + 0x20 ]
adox rdi, [ rsp + 0x60 ]
adcx r12, rdx
adcx rbp, rbx
mov r13, 0x89f3fffcfffcfffd
mov rdx, r13
mulx r9, r13, rcx
adcx r10, rdi
mov r9, 0xb9feffffffffaaab
mov rdx, r9
mulx r11, r9, r13
seto bl
movzx rbx, bl
adcx rbx, [ rsp + 0xf0 ]
mov rdi, 0x1eabfffeb153ffff
mov rdx, r13
mulx r8, r13, rdi
mov rdi, -0x2
inc rdi
adox r13, r11
mov r11, 0x6730d2a0f6b0f624
mov [ rsp + 0xf8 ], rbx
mulx rbx, rdi, r11
adox rdi, r8
setc r8b
clc
adcx r9, rcx
mov r9, 0x64774b84f38512bf
mulx r11, rcx, r9
adcx r13, r14
adox rcx, rbx
mov r14, 0x4b1ba7b6434bacd7
mulx r9, rbx, r14
adcx rdi, r15
adox rbx, r11
mov r15, 0x1a0111ea397fe69a
mulx r14, r11, r15
adcx rcx, r12
adox r11, r9
adcx rbx, rbp
adcx r11, r10
mov r12, 0x0
adox r14, r12
mov rbp, -0x3
inc rbp
adox r13, [ rsp - 0x48 ]
adox rdi, [ rsp + 0x58 ]
adox rcx, [ rsp + 0x50 ]
mov rdx, 0x89f3fffcfffcfffd
mulx r9, r10, r13
adox rbx, [ rsp + 0x48 ]
adox r11, [ rsp + 0x98 ]
adcx r14, [ rsp + 0xf8 ]
movzx r9, r8b
adcx r9, r12
adox r14, [ rsp + 0x90 ]
mov r8, 0xb9feffffffffaaab
mov rdx, r10
mulx r12, r10, r8
mov rbp, 0x6730d2a0f6b0f624
mulx r8, r15, rbp
clc
adcx r10, r13
mov r10, 0x1eabfffeb153ffff
mulx rbp, r13, r10
adox r9, [ rsp + 0x88 ]
seto r10b
mov [ rsp + 0x100 ], r9
mov r9, -0x2
inc r9
adox r13, r12
adox r15, rbp
adcx r13, rdi
adcx r15, rcx
mov rdi, 0x64774b84f38512bf
mulx r12, rcx, rdi
adox rcx, r8
mov r8, 0x4b1ba7b6434bacd7
mulx r9, rbp, r8
adcx rcx, rbx
mov rbx, 0x1a0111ea397fe69a
mulx rdi, r8, rbx
adox rbp, r12
adox r8, r9
mov rdx, 0x0
adox rdi, rdx
adcx rbp, r11
adcx r8, r14
adcx rdi, [ rsp + 0x100 ]
movzx r11, r10b
adc r11, 0x0
test al, al
adox r13, [ rsp + 0x80 ]
mov r14, 0x89f3fffcfffcfffd
mov rdx, r14
mulx r10, r14, r13
mov r10, 0xb9feffffffffaaab
mov rdx, r10
mulx r12, r10, r14
adox r15, [ rsp + 0x78 ]
mov r9, 0x1eabfffeb153ffff
mov rdx, r9
mulx rbx, r9, r14
adox rcx, [ rsp + 0x70 ]
adox rbp, [ rsp + 0x68 ]
adox r8, [ rsp + 0xa8 ]
adcx r10, r13
mov r10, 0x6730d2a0f6b0f624
mov rdx, r14
mulx r13, r14, r10
setc r10b
clc
adcx r9, r12
adox rdi, [ rsp + 0xb8 ]
adox r11, [ rsp + 0xd0 ]
adcx r14, rbx
seto r12b
mov rbx, 0x0
dec rbx
movzx r10, r10b
adox r10, rbx
adox r15, r9
adox r14, rcx
mov rcx, 0x64774b84f38512bf
mulx r9, r10, rcx
adcx r10, r13
mov r13, 0x4b1ba7b6434bacd7
mulx rcx, rbx, r13
adcx rbx, r9
adox r10, rbp
adox rbx, r8
mov rbp, 0x1a0111ea397fe69a
mulx r9, r8, rbp
adcx r8, rcx
adox r8, rdi
mov rdx, 0x0
adcx r9, rdx
adox r9, r11
movzx rdi, r12b
adox rdi, rdx
xor r12, r12
adox r15, [ rsp - 0x20 ]
mov rdx, 0x89f3fffcfffcfffd
mulx rcx, r11, r15
adox r14, [ rsp - 0x8 ]
mov rdx, r11
mulx rcx, r11, rbp
adox r10, [ rsp - 0x10 ]
adox rbx, [ rsp - 0x18 ]
adox r8, [ rsp + 0x8 ]
mov r12, 0xb9feffffffffaaab
mulx r13, rbp, r12
adox r9, [ rsp + 0x10 ]
adcx rbp, r15
mov rbp, 0x1eabfffeb153ffff
mulx r12, r15, rbp
adox rdi, [ rsp + 0x40 ]
setc bpl
clc
adcx r15, r13
seto r13b
mov [ rsp + 0x108 ], rdi
mov rdi, -0x1
inc rdi
mov rdi, -0x1
movzx rbp, bpl
adox rbp, rdi
adox r14, r15
mov rbp, 0x6730d2a0f6b0f624
mulx rdi, r15, rbp
adcx r15, r12
adox r15, r10
mov r10, 0x64774b84f38512bf
mulx rbp, r12, r10
adcx r12, rdi
adox r12, rbx
mov rbx, 0x4b1ba7b6434bacd7
mulx r10, rdi, rbx
adcx rdi, rbp
adcx r11, r10
adox rdi, r8
adox r11, r9
setc dl
clc
adcx r14, [ rsp + 0x18 ]
movzx r8, dl
lea r8, [ r8 + rcx ]
mov rcx, 0x89f3fffcfffcfffd
mov rdx, rcx
mulx r9, rcx, r14
mov r9, 0xb9feffffffffaaab
mov rdx, rcx
mulx rbp, rcx, r9
adcx r15, [ rsp + 0x30 ]
adcx r12, [ rsp + 0x28 ]
adcx rdi, [ rsp + 0x38 ]
adcx r11, [ rsp + 0xb0 ]
adox r8, [ rsp + 0x108 ]
movzx r10, r13b
mov rbx, 0x0
adox r10, rbx
adcx r8, [ rsp + 0xc8 ]
mov r13, 0x4b1ba7b6434bacd7
mulx r9, rbx, r13
mov r13, 0x1eabfffeb153ffff
mov [ rsp + 0x110 ], r8
mov [ rsp + 0x118 ], r11
mulx r11, r8, r13
adcx r10, [ rsp + 0xc0 ]
mov r13, -0x2
inc r13
adox rcx, r14
setc cl
clc
adcx r8, rbp
adox r8, r15
mov r14, 0x6730d2a0f6b0f624
mulx r15, rbp, r14
adcx rbp, r11
adox rbp, r12
mov r12, 0x64774b84f38512bf
mulx r13, r11, r12
adcx r11, r15
adcx rbx, r13
mov r15, 0x1a0111ea397fe69a
mulx r12, r13, r15
adox r11, rdi
adcx r13, r9
adox rbx, [ rsp + 0x118 ]
adox r13, [ rsp + 0x110 ]
mov rdx, 0x0
adcx r12, rdx
adox r12, r10
movzx rdi, cl
adox rdi, rdx
mov r9, r8
mov rcx, 0xb9feffffffffaaab
sub r9, rcx
mov r10, rbp
mov rdx, 0x1eabfffeb153ffff
sbb r10, rdx
mov r15, r11
sbb r15, r14
mov r14, rbx
mov rdx, 0x64774b84f38512bf
sbb r14, rdx
mov rdx, r13
mov rcx, 0x4b1ba7b6434bacd7
sbb rdx, rcx
mov rcx, r12
mov [ rsp + 0x120 ], r15
mov r15, 0x1a0111ea397fe69a
sbb rcx, r15
sbb rdi, 0x00000000
cmovc rcx, r12
cmovc r14, rbx
cmovc rdx, r13
mov rdi, [ rsp - 0x50 ]
mov [ rdi + 0x28 ], rcx
cmovc r10, rbp
mov [ rdi + 0x20 ], rdx
cmovc r9, r8
mov [ rdi + 0x8 ], r10
mov [ rdi + 0x0 ], r9
mov r8, [ rsp + 0x120 ]
cmovc r8, r11
mov [ rdi + 0x10 ], r8
mov [ rdi + 0x18 ], r14
mov rbx, [ rsp - 0x80 ]
mov rbp, [ rsp - 0x78 ]
mov r12, [ rsp - 0x70 ]
mov r13, [ rsp - 0x68 ]
mov r14, [ rsp - 0x60 ]
mov r15, [ rsp - 0x58 ]
add rsp, 424
ret
