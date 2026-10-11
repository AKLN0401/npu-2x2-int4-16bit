#!/usr/bin/env bash
# Run a command inside the tools image with the repo mounted at /work.
# Runs in the container path matching your current directory (must be inside the repo).
# Examples: cd test && ../tools/run.sh make      tools/run.sh   (interactive shell)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
rel="$(realpath --relative-to="$root" "$PWD")"
case "$rel" in ..*) rel=. ;; esac
tty=(); [ -t 0 ] && tty=(-it)
# Mount the SKY130 PDK that LibreLane downloaded (for GATES=yes sims) as /pdk
pdk=(); pdk_dir="$(ls -dt "$HOME"/.ciel/ciel/sky130/versions/*/ 2>/dev/null | head -1 || true)"
[ -n "$pdk_dir" ] && pdk=(-v "$pdk_dir:/pdk:ro,z" -e PDK_ROOT=/pdk)
# bash -c so that $PWD is set (the cocotb Makefile depends on it)
exec docker run --rm "${tty[@]}" --userns=keep-id -v "$root:/work:z" -w "/work/$rel" "${pdk[@]}" \
    tt-riscv-npu-tools bash -c 'exec "$@"' _ "${@:-bash}"
