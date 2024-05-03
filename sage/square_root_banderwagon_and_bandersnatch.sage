#Parameters
p = 52435875175126190479447740508185965837690552500527637822603658699938581184513
Fp = GF(p)

# BaseField2Adicity = 32  #see https://github.com/crate-crypto/go-ipa/blob/408dbffb2041271c95979a3fb79d98b268bf2880/bandersnatch/fp/sqrt.go#L22
# sqrtPrecomp_PrimitiveDyadicRoots[] is an array of size BaseField2Adicity + 1.
# sqrtPrecomp_PrimitiveDyadicRoots[0] should be equal to 10238227357739495823651030575849232062558860180284477541189508159991286009131 (see https://github.com/crate-crypto/go-ipa/blob/408dbffb2041271c95979a3fb79d98b268bf2880/bandersnatch/fp/sqrt.go#L46)
sqrtPrecomp_PrimitiveDyadicRoots = {}
sqrtPrecomp_PrimitiveDyadicRoots[0] = 10238227357739495823651030575849232062558860180284477541189508159991286009131

print('p  : ' + p.hex())

print('\n\nPrimitive Dyadic Roots:\n')
# function sqrtPrecomp_PrimitiveDyadicRoots:
print(hex(sqrtPrecomp_PrimitiveDyadicRoots[0]))
for i in range(0, 32):
    sqrtPrecomp_PrimitiveDyadicRoots[i+1] = Fp(sqrtPrecomp_PrimitiveDyadicRoots[i]^2)
    print(hex(sqrtPrecomp_PrimitiveDyadicRoots[i+1]))

sqrtPrecomp_ReconstructionDyadicRoot = sqrtPrecomp_PrimitiveDyadicRoots[24]

# function sqrtPrecomp_PrecomputedBlocks:
block = {}
print('\n\nPrecomputed Blocks:\n')
for i in range (0, 4):
    block[i] = {}
    block[i][0] = 1
    print("\nFor i = " + str(i) + ":")
    for j in range (1, 256):
        block[i][j] = Fp(block[i][j-1] * sqrtPrecomp_PrimitiveDyadicRoots[i * 8])
        print(hex(block[i][j]))


# function sqrtPrecomp_dlogLUT:
LUTSize = 256
sqrtPrecomp_dlogLUT = {}

rootOfUnity = 1

print('\n\nsqrtPrecomp_ReconstructionDyadicRoot = ' + hex(sqrtPrecomp_ReconstructionDyadicRoot) + '\n')

for i in range(LUTSize):
    mask = LUTSize - 1
    sqrtPrecomp_dlogLUT[rootOfUnity & 0xFFFF] = (-i) & mask
    rootOfUnity = rootOfUnity * sqrtPrecomp_ReconstructionDyadicRoot

for i in sqrtPrecomp_dlogLUT:
    print(i + ' : ' + sqrtPrecomp_dlogLUT[i])

