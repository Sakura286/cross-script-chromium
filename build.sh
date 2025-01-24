#!/bin/bash

set -x

ninja -j$(nproc) -C out/Release-riscv64 chrome chrome_sandbox content_shell chromedriver |& tee build-$(date +'%m%d-%H%M%S').log
