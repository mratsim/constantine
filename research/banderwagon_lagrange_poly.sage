p = Integer('0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001')
r = Integer('0x1cfb69d4ca675f520cce760202687600ff8f87007419047174fd06b52876e7e1')
primitive_root = GF(r).multiplicative_generator()
roots = [primitive_root^((r-1)//(1 << i)) for i in range(9)]

print(f'p-1 factors: {factor(r-1)}')
print(f'primitive root of unity: {primitive_root}')
for degree, root in enumerate(roots):
    print(f'degree: {2**degree}, root: {hex(root)}')
    print(f'  check root^{2**degree} (mod r) = {hex(pow(root, 2**degree, r))}')

