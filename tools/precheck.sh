#!/usr/bin/env bash
# Local Tiny Tapeout precheck (tt/precheck/precheck.py: Magic DRC, KLayout FEOL/BEOL/offgrid,
# pin/boundary/power-pin/layer/cell-name/urpm checks) on a LibreLane run, inside the LibreLane image.
# The local harden skips KLayout DRC; this runs the same checks as the GitHub precheck action.
# Usage: tools/precheck.sh [run_dir]        default: runs/wokwi
# The image is Nix-based: gdstk's wheel needs libstdc++ from the store (LD_LIBRARY_PATH below).
# Python deps (gdstk, numpy, yaml, yowasp-yosys) live in tools/.precheck-py, installed with:
#   uv pip install --target tools/.precheck-py --python-version 3.13 \
#     --python-platform x86_64-manylinux_2_28 gdstk numpy pyyaml yowasp-yosys
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
run="$(cd "$root/${1:-runs/wokwi}" && pwd)"
top=$(python3 -c "import yaml;print(yaml.safe_load(open('$root/info.yaml'))['project']['top_module'])")
# tt/ and tools/.precheck-py may be symlinks out of the repo (npu1x1 shares them with the parent): mount the targets
tt="$(realpath "$root/tt")"
pyd="$(realpath "$root/tools/.precheck-py")"
pdk_root="$HOME/.ciel/ciel/sky130/versions/$(ls "$HOME/.ciel/ciel/sky130/versions" | head -1)"

# Same file set as tt_tool.py --create-tt-submission: <top>.gds/.lef/.v side by side
stage="$run/precheck"
rm -rf "$stage" && mkdir -p "$stage"
cp "$run/final/gds/$top.gds" "$run/final/lef/$top.lef" "$stage/"
cp "$run/final/pnl/$top.pnl.v" "$stage/$top.v"
rm -rf "$tt/precheck/reports" && mkdir -p "$tt/precheck/reports"

status=0
# Repo and ~/.ciel are already labeled container_file_t:s0, so no :z/:Z relabel here.
docker run --rm \
  -v "$root:$root" -v "$tt:$tt" -v "$pyd:$pyd" -v "$pdk_root:$pdk_root:ro" \
  -e PDK_ROOT="$pdk_root" -e PDK=sky130A \
  -e PYTHONPATH="$pyd" \
  -w "$tt/precheck" \
  ghcr.io/librelane/librelane:3.0.14 \
  bash -c 'export LD_LIBRARY_PATH=$(dirname /nix/store/*-gcc-*-lib/lib/libstdc++.so.6 | head -1)
           # uv wrote host-python shebangs into tools/.precheck-py/bin; shim the yosys entry point
           mkdir -p /tmp/shim && printf "#!/bin/sh\nexec python3 -c \"import sys; from yowasp_yosys import _run_yosys_argv as r; sys.argv[0]=\x27yowasp-yosys\x27; sys.exit(r())\" \"\$@\"\n" > /tmp/shim/yowasp-yosys
           chmod +x /tmp/shim/yowasp-yosys && export PATH=/tmp/shim:$PATH
           exec python3 precheck.py --gds "$0"' "$stage/$top.gds" || status=$?
cp -r "$tt/precheck/reports" "$stage/reports"
cat "$stage/reports/results.md"
exit $status
