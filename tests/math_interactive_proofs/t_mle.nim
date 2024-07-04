import
  constantine/boolean_hypercube/multilinear_extensions,
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/io/io_fields,
  helpers/prng_unsafe

# Compile with -d:CTT_TEST_CURVES to define F5

func toF5[N: static int](a: array[N, SomeUnsignedInt]): array[N, Fp[F5]] =
  for i in 0 ..< N:
    result[i] = Fp[F5].fromUint(a[i])

# - https://people.cs.georgetown.edu/jthaler/IPsandextensions.pdf\
#   Note: first row is
#     1 2 3 4 0 not 1 2 3 4 5 (though 5 ≡ 0 (mod 5) so arguably not wrong)
# - https://people.cs.georgetown.edu/jthaler/ProofsArgsAndZK.pdf
#   Chapter 3.5

let evals = [uint32 1, 2, 1, 4].toF5()
let mle_evals = [
      [byte 1, 2, 3, 4, 0],
      [byte 1, 4, 2, 0, 3],
      [byte 1, 1, 1, 1, 1],
      [byte 1, 3, 0, 2, 4],
      [byte 1, 0, 4, 3, 2],
]

let mle = MultilinearExtension[Fp[F5]].new(2, evals)

for i in 0'u32 .. 4:
  var row: array[5, byte]
  for j in 0'u32 .. 4:
    var r: Fp[F5]
    r.evalMultilinearExtensionAt_reference(mle, [Fp[F5].fromUint(i), Fp[F5].fromUint(j)])
    var buf: array[1, byte]
    buf.marshal(r, bigEndian)
    row[j] = buf[0]

  echo row
  doAssert row == mle_evals[i]
