#!/bin/sh
# Exporteert alle printbare onderdelen naar ../stl en maakt previews in ../images.
# Gebruik: ./export.sh [extra openscad-opties], bijv. ./export.sh -D 'tilt_servo="SG90"'
set -e
cd "$(dirname "$0")"
mkdir -p ../stl ../images
for p in base pan cradle camholder head head_lid; do
    openscad -o "../stl/$p.stl" -D "part=\"$p\"" "$@" launcher.scad
done
if command -v xvfb-run >/dev/null; then RUN="xvfb-run -a"; else RUN=""; fi
$RUN openscad -o ../images/assembly.png --imgsize=1200,900 --colorscheme=Tomorrow \
    --camera=0,0,70,62,0,35,480 "$@" launcher.scad
$RUN openscad -o ../images/assembly_servo_side.png --imgsize=1200,900 --colorscheme=Tomorrow \
    --camera=0,0,70,75,0,200,480 -D pan_angle=0 "$@" launcher.scad
