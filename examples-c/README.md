# C bindings examples

This folder holds tests (prefixed with `t_`) and examples for the C bindings.

Headers are located in `include/` and the static and dynamic libraries
in `lib/`.

To compile and run an example or test case, for example:

```sh
git clone https://github.com/mratsim/constantine
CC=clang nimble make_lib
cd examples-c
clang ethereum_bls_signatures.c -o ethereum_bls_signatures -I../include -L../lib -lconstantine
```

For the `t_libctt_bls12_381` and `t_libctt_banderwagon` test cases, you also need to link in `-lgmp`.

To run the final binary, you need to specify where
`libconstantine.so` can be found if it's not installed globally:

```sh
LD_LIBRARY_PATH=../lib ./ethereum_bls_signatures
```
