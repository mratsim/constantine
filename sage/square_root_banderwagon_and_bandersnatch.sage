#Parameters
p = 52435875175126190479447740508185965837690552500527637822603658699938581184513
Fp = GF(p)
BaseField2Adicity = 32  #see https://github.com/crate-crypto/go-ipa/blob/408dbffb2041271c95979a3fb79d98b268bf2880/bandersnatch/fp/sqrt.go#L22
ret[0] = 10238227357739495823651030575849232062558860180284477541189508159991286009131 #array of size BaseField2Adicity + 1
# hex(ret[0]) should be equal to "0x16a2a19edfe81f20d09b681922c813b4b63683508c2280b93829971f439f0d2b" (see https://github.com/mratsim/constantine/blob/master/constantine/math/constants/banderwagon_sqrt.nim#L175)

print('p  : ' + p.hex())
print('a  : ' + a.hex())
print('d  : ' + d.hex())

def sqrtPrecomp_PrimitiveDyadicRoots:
    for i in range(1, BaseField2Adicity+1):
        ret[i] = Fp(ret[i-1]^2)

flag = hex(ret[BaseField2Adicity-1]) == 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000000 
#flag should be true unless something is wrong with the dyadic roots of unity