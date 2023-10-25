#!/bin/bash

# Due to cryptographic secrets, deriving Debug is absolutely forbidden.
# Some resources are non-copyable non-clonable:
# - Threadpools
# - Contexts holding sessions
bindgen \
  include/constantine.h \
  -o constantine-rust/constantine-sys/src/bindings.rs \
  --default-enum-style rust \
  --use-core \
  --no-derive-debug \
  --default-visibility private \
  --enable-function-attribute-detection \
  -- -Iinclude


# --must-use-type "ctt_.*_status" is not needed with function attribute detection
