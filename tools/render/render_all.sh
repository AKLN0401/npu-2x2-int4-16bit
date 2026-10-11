#!/usr/bin/env bash
# Render the layout of a hardening run and embed it in docs/overview.html.
#   1. KLayout (LibreLane image): full GDS with the PDK colours, metal routing on dark  -> runs/render/*.png
#   2. 3D stills: gen3d.py --raw + headless Firefox                                   -> runs/render/shot_*.png
#   3. build_overview.py: WebP images + gzipped 3D model + viewer into docs/overview.html
# Usage: tools/render/render_all.sh [run_dir]      (default runs/wokwi)
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
run="${1:-runs/wokwi}"
gds="$run/final/gds/tt_um_akln0401_npu.gds"
out=runs/render
py=tools/.venv/bin/python
mkdir -p "$out"
pdk_dir="$(ls -dt "$HOME"/.ciel/ciel/sky130/versions/*/ | head -1)"

docker run --rm --userns=keep-id -e HOME=/tmp -v "$root:/work:z" -v "$pdk_dir:/pdk:ro,z" -w /work \
    ghcr.io/librelane/librelane:3.0.14 bash -c "
  klayout -b -r tools/render/render_lyp.py -rd gds=$gds -rd lyp=/pdk/sky130A/libs.tech/klayout/tech/sky130A.lyp \
      -rd out=$out/npu1x1_gds.png -rd w=2400 -rd h=1660
  klayout -b -r tools/render/render.py -rd gds=$gds -rd out=$out/npu1x1_routing.png \
      -rd box=-2,-2,163,113.5 -rd w=2400 -rd h=1660"

$py tools/render/gen3d.py --raw "$gds" "$out/shot3d.html" "tt_um_akln0401_npu · GDS"
# Headless Firefox sometimes captures before the WebGL frame is presented: retry until the image has content
shot() {
    for _ in 1 2 3 4 5; do
        rm -f "$out/$1"; p=$(mktemp -d)
        MOZ_HEADLESS=1 timeout 90 firefox --headless --no-remote --profile "$p" --window-size=1400,900 \
            --screenshot "$root/$out/$1" "file://$root/$out/shot3d.html#$2" >/dev/null 2>&1 || true
        rm -rf "$p"
        [ -f "$out/$1" ] && [ "$(stat -c %s "$out/$1")" -gt 120000 ] && return 0
    done
    echo "3D screenshot $1 failed" >&2; return 1
}
shot shot_iso.png "view=iso&panel=0"
shot shot_close.png "view=close&panel=0"

$py tools/render/build_overview.py docs/overview.html "$gds" "$out"
