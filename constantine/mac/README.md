# Message Authentication Codes

Note:

We prefix the filename with "mac" to prevents name collision between a modulename and the types
which leads to confusing error messages

```Nim
# in mac_poly1305
type poly1305* = Poly1305_CTX
```