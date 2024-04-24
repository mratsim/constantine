#Parameters
p = 52435875175126190479447740508185965837690552500527637822603658699938581184513
Fp = GF(p)

# BaseField2Adicity = 32  #see https://github.com/crate-crypto/go-ipa/blob/408dbffb2041271c95979a3fb79d98b268bf2880/bandersnatch/fp/sqrt.go#L22
# ret[] is an array of size BaseField2Adicity + 1. Instead of using an array in sage we work with a variable "a" and "temp" and updating them as required 
# a should be equal to 10238227357739495823651030575849232062558860180284477541189508159991286009131 (see https://github.com/crate-crypto/go-ipa/blob/408dbffb2041271c95979a3fb79d98b268bf2880/bandersnatch/fp/sqrt.go#L46)
a = 10238227357739495823651030575849232062558860180284477541189508159991286009131

print('p  : ' + p.hex())
print(hex(a))

# function sqrtPrecomp_PrimitiveDyadicRoots:
for i in range(0, 32):
    temp = Fp(a^2)
    print(hex(temp))
    a = temp
