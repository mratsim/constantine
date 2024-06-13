# Architecture

## APIs

### Argument orders

Function calls have arguments ordered the following way:

1. Context arguments
2. Threadpool context
3. OUT arguments (only written to)
4. INOUT arguments
5. IN arguments

The first context argument should allow method call syntax

In C, length of arrays immediately follow the array, unless there are multiple array arguments with same length.
If an argument is associated with a label, for domain separation for example,
that label precedes the argument.

### Return values

Constantine avoids returning values bigger than the word size
and prefer mutable out parameters.

1. In some cases they introduce extra copies.
2. There is less guarantees over stack space usage.
3. Nim will zero the values without {.noInit.}
   and that zeroing might not be optimized away by the compiler
   on large inputs like `Fp12[BLS12_381]` 48\*12 bytes = 576 bytes.
4. As we sometimes return SecretBool or status code, this keeps the API consistent.

## Code organization

TBD
