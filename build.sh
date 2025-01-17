#!/bin/bash

set -x

ninja -j$(nproc) -C out/Release-riscv64 chrome  |& tee build-$(date +'%m%d-%H%M%S').log
