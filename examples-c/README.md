# C bindings examples

This folder holds tests (prefixed with `t_`) and examples for the C bindings.

Headers are located in `include/` and the static and dynamic libraries
in `lib/`.

To compile and run the example / test case, for example:

```sh
clang ethereum_bls_signatures.c -o ethereum_bls_signatures -I../include -L../lib -lconstantine
```

For the test case, you also need to link in `-lgmp`.

And depending on your setup you might need to specify where
`libconstantine.so` can be found:

```sh
LD_LIBRARY_PATH=../lib ./ethereum_bls_signatures
```

(in case you compile and run from this directory).

The above of course assumes you have already compiled
`libconstantine.so` (using `nimble make_lib` from the root directory
of the repository).
