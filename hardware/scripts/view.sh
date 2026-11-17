#!/bin/bash
# view.sh <name> <layers> [x0 x1] : render board layers to build/<name>.png (optionally only board x-range in mm)
cd "$(dirname "$0")/../build"
KC=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli
$KC pcb export svg --layers "$2" --page-size-mode 2 --exclude-drawing-sheet --mode-single -o "$1.svg" ../bootwarmer/bootwarmer.kicad_pcb >/dev/null 2>&1
python3 - "$1" "${3:-0}" "${4:-107}" <<'PY'
import fitz, sys
name, x0, x1 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
d = fitz.open(name + ".svg"); p = d[0]
r = p.rect; sx = r.width / 107.0
clip = fitz.Rect(x0 * sx, 0, x1 * sx, r.height)
z = 2400 / clip.width
p.get_pixmap(matrix=fitz.Matrix(z, z), clip=clip, alpha=False).save(name + ".png")
PY
