#!/usr/bin/env bash
# Build the tt-riscv-npu tools image.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cp "$root/test/requirements.txt" "$root/tools/requirements.txt"
docker build -t tt-riscv-npu-tools "$root/tools"
