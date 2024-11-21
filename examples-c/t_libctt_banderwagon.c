// This is a test to ensure Constantine's modular arithmetic is consistent with GMP.
// While not intended as a tutorial, it showcases serialization, deserialization and computation.


#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

#include <gmp.h>
#include <constantine.h>

// https://gmplib.org/manual/Integer-Import-and-Export.html
const int GMP_WordLittleEndian = -1;
const int GMP_WordNativeEndian = 0;
const int GMP_WordBigEndian = 1;

const int GMP_MostSignificantWordFirst = 1;
const int GMP_LeastSignificantWordFirst = -1;

#define Curve "Banderwagon"
#define BitLength 253 //check
#define ByteLength ((BitLength + 7) / 8)
#define Modulus "0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001"
#define Iter 24

// Beware of convention, Constantine serialization returns true/'1' for success
// but top-level program status code returns 0 for success
#define CHECK(fn_call)                \
            do {                      \
                int status = fn_call; \
                /* printf("status %d for '%s'\n", status, #fn_call); */ \
                if (status != 0) {    \
                    return 1;         \
                }                     \
            } while (0)

int prologue(
       gmp_randstate_t gmp_rng,
       mpz_ptr a, mpz_ptr b,
       mpz_ptr p,
       banderwagon_fp* a_ctt, banderwagon_fp* b_ctt,
       byte a_buf[ByteLength], byte b_buf[ByteLength]) {

  // Generate random value in the range [0, 2^(bits-1))
  mpz_urandomb(a, gmp_rng, BitLength);
  mpz_urandomb(b, gmp_rng, BitLength);

  // Set modulus to curve modulus
  mpz_set_str(p, Modulus, 0);

  // Restrict to [0, p)
  mpz_mod(a, a, p);
  mpz_mod(b, b, p);

  // GMP -> Constantine
  size_t aW, bW;
  mpz_export(a_buf, &aW, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, a);
  mpz_export(b_buf, &bW, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, b);

  assert(ByteLength >= aW);
  assert(ByteLength >= bW);

  CHECK(!ctt_banderwagon_fp_unmarshalBE(a_ctt, a_buf, aW));
  CHECK(!ctt_banderwagon_fp_unmarshalBE(b_ctt, b_buf, bW));

  return 0;
}

void dump_hex(byte a[ByteLength]){
  printf("0x");
  for (int i = 0; i < ByteLength; ++i){
    printf("%.02x", a[i]);
  }
}

int epilogue(
       mpz_ptr r, mpz_ptr a, mpz_ptr b,
       banderwagon_fp* r_ctt, banderwagon_fp* a_ctt, banderwagon_fp* b_ctt,
       char* operation) {

  byte r_raw_gmp[ByteLength];
  byte r_raw_ctt[ByteLength];

  // GMP -> Raw
  size_t rW; // number of words written
  mpz_export(r_raw_gmp, &rW, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, r);

  // Constantine -> Raw
  CHECK(!ctt_banderwagon_fp_marshalBE(r_raw_ctt, ByteLength, r_ctt));

  // Check
  for (int g = 0, c = ByteLength-rW; g < rW; g+=1, c+=1) {
    if (r_raw_gmp[g] != r_raw_ctt[c]) {
      // reexport for debugging
      byte a_buf[ByteLength], b_buf[ByteLength];
      size_t aW, bW;
      mpz_export(a_buf, &aW, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, a);
      mpz_export(b_buf, &bW, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, b);
      printf("\nModular %s on curve %s with operands", operation, Curve);
      printf("\n  a:   "); dump_hex(a_buf);
      printf("\n  b:   "); dump_hex(b_buf);
      printf("\nfailed:");
      printf("\n  GMP:         "); dump_hex(r_raw_gmp);
      printf("\n  Constantine: "); dump_hex(r_raw_ctt);
      printf("\n(Note that GMP aligns bytes left while constantine aligns bytes right)\n");
      exit(1);
    }
  }
  printf(".");
  return 0;
}

int main(){
  gmp_randstate_t gmpRng;
  gmp_randinit_mt(gmpRng);
  // The GMP seed varies between run so that
  // test coverage increases as the library gets tested.
  // This requires to dump the seed in the console or the function inputs
  // to be able to reproduce a bug
  int seed = 0xDEADBEEF;
  printf("GMP seed: 0x%.04x\n", seed);
  gmp_randseed_ui(gmpRng, seed);

  mpz_t a, b, p, r;
  mpz_init(a);
  mpz_init(b);
  mpz_init(p);
  mpz_init(r);

  banderwagon_fp a_ctt, b_ctt, r_ctt;
  byte a_buf[ByteLength], b_buf[ByteLength];

  for (int i = 0; i < Iter; ++i){
    CHECK(prologue(
      gmpRng,
      a, b, p,
      &a_ctt, &b_ctt,
      a_buf, b_buf
    ));

    mpz_neg(r, a);
    mpz_mod(r, r, p);
    ctt_banderwagon_fp_neg(&r_ctt, &a_ctt);

    CHECK(epilogue(
      r, a, b,
      &r_ctt, &a_ctt, &b_ctt,
      "negation"
    ));
  }
  printf(" SUCCESS negation\n");

  for (int i = 0; i < Iter; ++i){
    CHECK(prologue(
      gmpRng,
      a, b, p,
      &a_ctt, &b_ctt,
      a_buf, b_buf
    ));

    mpz_add(r, a, b);
    mpz_mod(r, r, p);
    ctt_banderwagon_fp_sum(&r_ctt, &a_ctt, &b_ctt);

    CHECK(epilogue(
      r, a, b,
      &r_ctt, &a_ctt, &b_ctt,
      "addition"
    ));
  }
  printf(" SUCCESS addition\n");

  for (int i = 0; i < Iter; ++i){
    CHECK(prologue(
      gmpRng,
      a, b, p,
      &a_ctt, &b_ctt,
      a_buf, b_buf
    ));

    mpz_mul(r, a, b);
    mpz_mod(r, r, p);
    ctt_banderwagon_fp_prod(&r_ctt, &a_ctt, &b_ctt);

    CHECK(epilogue(
      r, a, b,
      &r_ctt, &a_ctt, &b_ctt,
      "multiplication"
    ));
  }
  printf(" SUCCESS multiplication\n");

  for (int i = 0; i < Iter; ++i){
    CHECK(prologue(
      gmpRng,
      a, b, p,
      &a_ctt, &b_ctt,
      a_buf, b_buf
    ));

    mpz_invert(r, a, p);
    ctt_banderwagon_fp_inv(&r_ctt, &a_ctt);

    CHECK(epilogue(
      r, a, b,
      &r_ctt, &a_ctt, &b_ctt,
      "inversion"
    ));
  }
  printf(" SUCCESS inversion\n");

  for (int i = 0; i < Iter; ++i){
    CHECK(prologue(
      gmpRng,
      a, b, p,
      &a_ctt, &b_ctt,
      a_buf, b_buf
    ));

    int is_square_gmp = mpz_legendre(a, p) == -1 ? 0:1;
    int is_square_ctt = ctt_banderwagon_fp_is_square(&a_ctt);

    assert(is_square_gmp == is_square_ctt);
  }
  printf(" SUCCESS Legendre symbol / is_square\n");

  mpz_clear(r);
  mpz_clear(p);
  mpz_clear(b);
  mpz_clear(a);

  return 0;

}