# Deal with platform mess
# --------------------------------------------------------------------
when defined(windows):
  when sizeof(int) == 8:
    const DLL_SSL_Name* = "(libssl-1_1-x64|ssleay64|libssl64).dll"
  else:
    const DLL_SSL_Name* = "(libssl-1_1|ssleay32|libssl32).dll"
else:
  when defined(macosx) or defined(macos) or defined(ios):
    const versions = "(.1.1|.38|.39|.41|.43|.44|.45|.46|.47|.48|.10|.1.0.2|.1.0.1|.1.0.0|.0.9.9|.0.9.8|)"
  else:
    const versions = "(.1.1|.1.0.2|.1.0.1|.1.0.0|.0.9.9|.0.9.8|.48|.47|.46|.45|.44|.43|.41|.39|.38|.10|)"

  when defined(macosx) or defined(macos) or defined(ios):
    const DLL_SSL_Name* = "libssl" & versions & ".dylib"
  elif defined(genode):
    const DLL_SSL_Name* = "libssl.lib.so"
  else:
    const DLL_SSL_Name* = "libssl.so" & versions

# OpenSSL wrapper
# --------------------------------------------------------------------

# OpenSSL removed direct use of their SHA256 function. https://github.com/openssl/openssl/commit/4d49b68504cc494e552bce8e0b82ec8b501d5abe
# It isn't accessible anymore in Windows CI on Github Action.
# But the new API isn't expose on Linux :/

# TODO: fix Windows
when not defined(windows):
  proc SHA256[T: byte|char](
        msg: openarray[T],
        digest: ptr array[32, byte] = nil
      ): ptr array[32, byte] {.noconv, dynlib: DLL_SSL_Name, importc.}

  # proc EVP_Q_digest[T: byte|char](
  #                 ossl_libctx: pointer,
  #                 algoName: cstring,
  #                 propq: cstring,
  #                 data: openArray[T],
  #                 digest: var array[32, byte],
  #                 size: ptr uint): int32 {.noconv, dynlib: DLL_SSL_Name, importc.}

  proc SHA256_OpenSSL*[T: byte|char](
        digest: var array[32, byte],
        s: openArray[T]) =
    discard SHA256(s, digest.addr)
    # discard EVP_Q_digest(nil, "SHA256", nil, s, digest, nil)

  proc RIPEMD160[T: byte|char](
        msg: openarray[T],
        digest: ptr array[20, byte] = nil
      ): ptr array[20, byte] {.noconv, dynlib: DLL_SSL_Name, importc.}

  proc RIPEMD160_OpenSSL*[T: byte|char](
        digest: var array[20, byte],
        s: openArray[T]) =
    discard RIPEMD160(s, digest.addr)

type
  BIGNUM_Obj* = object
  EC_KEY_Obj* = object
  EC_GROUP_Obj* = object

  EVP_PKEY_Obj* = object
  EVP_MD_CTX_Obj* = object
  EVP_PKEY_CTX_Obj* = object

  EVP_PKEY* = ptr EVP_PKEY_Obj
  EVP_MD_CTX* = ptr EVP_MD_CTX_Obj
  EVP_PKEY_CTX* = ptr EVP_PKEY_CTX_Obj

  BIGNUM* = ptr BIGNUM_Obj
  EC_KEY* = ptr EC_KEY_Obj
  EC_GROUP* = ptr EC_GROUP_Obj

  BIO_Obj* = object
  BIO* = ptr BIO_Obj

  OSSL_ENCODER_CTX_Obj*  = object
  OSSL_ENCODER_CTX* = ptr OSSL_ENCODER_CTX_Obj

  OSSL_LIB_CTX_Obj* = object
  OSSL_PROVIDER_Obj* = object
  OSSL_LIB_CTX* = ptr OSSL_LIB_CTX_Obj
  OSSL_PROVIDER* = ptr OSSL_PROVIDER_Obj
  OSSL_PARAM_Obj* = object
  OSSL_PARAM* = ptr OSSL_PARAM_Obj

  OSSL_PARAM_BLD_Obj* = object
  OSSL_PARAM_BLD* = ptr OSSL_PARAM_BLD_Obj

## Push the pragmas to clean up the code a bit
{.push noconv, importc, dynlib: DLL_SSL_Name.}
proc EVP_MD_CTX_new*(): EVP_MD_CTX
proc EVP_MD_CTX_free*(ctx: EVP_MD_CTX)

proc EVP_sha256*(): pointer

proc EVP_DigestSignInit*(ctx: EVP_MD_CTX,
                       pctx: ptr EVP_PKEY_CTX,
                       typ: pointer,
                       e: pointer,
                       pkey: EVP_PKEY): cint


proc EVP_MD_fetch*(ctx: OSSL_LIB_CTX, algorithm: cstring, properties: cstring): pointer

proc EVP_DigestSign*(ctx: EVP_MD_CTX,
                    sig: ptr byte,
                    siglen: ptr uint,
                    tbs: ptr byte,
                    tbslen: uint): cint

proc BN_bin2bn*(s: ptr byte, len: cint, ret: BIGNUM): BIGNUM
proc BN_new*(): BIGNUM
proc BN_free*(bn: BIGNUM)

proc EC_KEY_new_by_curve_name*(nid: cint): EC_KEY
proc EC_KEY_set_private_key*(key: EC_KEY, priv: BIGNUM): cint

proc EC_KEY_get0_group*(key: EC_KEY): EC_GROUP
proc EC_KEY_generate_key*(key: EC_KEY): cint

proc EVP_PKEY_new*(): EVP_PKEY

## NOTE: This is _also_ now outdated and one should use the `EVP_PKEY_fromdata` function
## in theory:
## https://docs.openssl.org/master/man3/EVP_PKEY_fromdata/
proc EVP_PKEY_set1_EC_KEY*(pkey: EVP_PKEY, key: EC_KEY): cint

proc BIO_new_file*(filename: cstring, mode: cstring): BIO
proc BIO_free*(bio: BIO): cint
{.pop.}

proc initPrivateKeyOpenSSL*(pkey: var EVP_PKEY, rawKey: openArray[byte]) =
  ## Initializes an OpenSSL private key of `EVP_PKEY` type from a given
  ## raw private key in bytes.
  let bn = BN_new()
  discard BN_bin2bn(unsafeAddr rawKey[0], rawKey.len.cint, bn)

  let eckey = EC_KEY_new_by_curve_name(714) # NID_secp256k1
  discard EC_KEY_set_private_key(eckey, bn)

  pkey = EVP_PKEY_new()
  discard EVP_PKEY_set1_EC_KEY(pkey, eckey)

  BN_free(bn)

proc signMessageOpenSSL*(sig: var array[72, byte], msg: openArray[byte], key: EVP_PKEY) =
  ## Sign a message with OpenSSL and return the resulting DER encoded signature in `sig`.
  let ctx = EVP_MD_CTX_new()
  var pctx: EVP_PKEY_CTX

  let md = EVP_MD_fetch(nil, "KECCAK-256", nil)
  if md.isNil:
    raise newException(Exception, "Failed to fetch KECCAK-256")


  if EVP_DigestSignInit(ctx, addr pctx, md, nil, key) <= 0:
    raise newException(Exception, "Signing init failed")

  # Get required signature length
  var sigLen: uint
  if EVP_DigestSign(ctx, nil, addr sigLen, nil, 0.uint) <= 0:
    raise newException(Exception, "Getting sig length failed")

  doAssert sigLen.int == 72

  if EVP_DigestSign(ctx, addr sig[0], addr sigLen,
                    unsafeAddr msg[0], msg.len.uint) <= 0:
    raise newException(Exception, "Signing failed")

  EVP_MD_CTX_free(ctx)
