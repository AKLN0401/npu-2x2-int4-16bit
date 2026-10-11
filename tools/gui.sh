#!/usr/bin/env bash
# Open a hardening run (default: the last one, runs/wokwi) in a GUI, using the LibreLane container's tools.
# Usage: tools/gui.sh klayout [run_dir]     # GDS layout with SKY130 layer colours
#        tools/gui.sh openroad [run_dir]    # OpenROAD GUI: placement, routing, clock tree, timing
#        e.g. tools/gui.sh openroad runs/wokwi_6x2_38mhz_qspi50
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
top=tt_um_akln0401_npu
final="${2:-runs/wokwi}"; final="${final%/}/final"
image=ghcr.io/librelane/librelane:3.0.14
pdk_dir="$(ls -dt "$HOME"/.ciel/ciel/sky130/versions/*/ | head -1)"
[ -d "$root/$final" ] || { echo "No run found; run tools/harden.sh first" >&2; exit 1; }
: "${DISPLAY:?DISPLAY not set - run from a desktop session or ssh -X}"

# X11: share the socket and auth cookie; label=disable lets the container reach the X socket under SELinux
x11=(-e DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix --security-opt label=disable)
if [ -n "${XAUTHORITY:-}" ] && [ -f "$XAUTHORITY" ]; then
    x11+=(-v "$XAUTHORITY:/tmp/.Xauthority:ro" -e XAUTHORITY=/tmp/.Xauthority)
fi
run=(docker run --rm --userns=keep-id "${x11[@]}" -e HOME=/tmp
     -v "$root:/work" -v "$pdk_dir:/pdk:ro" -e PDK_ROOT=/pdk -w /work "$image")

case "${1:-klayout}" in
    klayout)
        exec "${run[@]}" klayout -nn /pdk/sky130A/libs.tech/klayout/tech/sky130A.lyt \
            -l /pdk/sky130A/libs.tech/klayout/tech/sky130A.lyp "$final/gds/$top.gds" ;;
    openroad)
        cat > "$root/runs/.gui.tcl" <<TCL
read_db $final/odb/$top.odb
read_liberty /pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_sdc $final/sdc/$top.sdc
TCL
        exec "${run[@]}" openroad -gui runs/.gui.tcl ;;
    *) echo "usage: $0 [klayout|openroad]" >&2; exit 1 ;;
esac
