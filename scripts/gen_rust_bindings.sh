#!/bin/bash

# Due to cryptographic secrets:
#   deriving Debug is absolutely forbidden,
#   except for status/error enums
# Some resources are non-clonable:
# - Threadpools
# - Contexts holding sessions
# Some resources use thread-local dtorage and cannot be moved across threads:
# - Threadpools
#
# Note:
#   Rust regex (used by bindgen) does not support negative lookahead
#   and auto insert ^regex$ anchors,
#   ideally we want no derive(Debug) for anything except _status enums
#      ^.*?(?!_status)$

bindgen \
  include/constantine.h \
  -o constantine-rust/constantine-sys/src/bindings64.rs \
  --default-enum-style rust \
  --use-core \
  --no-copy ctt_threadpool \
  --no-derive-debug \
  --with-derive-custom-enum ".*?_status"=Debug \
  --with-derive-custom-enum ".*?_format"=Debug \
  --with-derive-custom-struct ctt_threadpool=Debug \
  --default-visibility private \
  --enable-function-attribute-detection \
  -- -Iinclude

# --must-use-type ".*?_status" is not needed with function attribute detection

bindgen \
  include/constantine.h \
  -o constantine-rust/constantine-sys/src/bindings32.rs \
  --default-enum-style rust \
  --use-core \
  --no-copy ctt_threadpool \
  --no-derive-debug \
  --with-derive-custom-enum ".*?_status"=Debug \
  --with-derive-custom-enum ".*?_format"=Debug \
  --with-derive-custom-struct ctt_threadpool=Debug \
  --default-visibility private \
  --enable-function-attribute-detection \
  -- -m32 -Iinclude