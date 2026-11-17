#!/bin/bash
# Rebuild schematic, board, and JLCPCB order files from scripts/design.py
set -e
cd "$(dirname "$0")/scripts"
KICAD=/Applications/KiCad/KiCad.app/Contents
KPY=$KICAD/Frameworks/Python.framework/Versions/Current/bin/python3
KCLI=$KICAD/MacOS/kicad-cli
FREEROUTING_JAR=${FREEROUTING_JAR:-$HOME/.local/share/freerouting/freerouting.jar}   # v2.5.0, needs Java 25+
JAVA=${JAVA:-/opt/homebrew/opt/openjdk/bin/java}
Q() { grep -v -E "Fontconfig|wxApp|Debug: Adding" || true; }

python3 gen_sch.py
$KPY gen_pcb.py place 2>&1 | Q
rm -f ../build/bootwarmer.ses
$JAVA -Djava.awt.headless=true -jar "$FREEROUTING_JAR" -de ../build/bootwarmer.dsn -do ../build/bootwarmer.ses -mp 60 --gui.enabled=false > ../build/freerouting.log 2>&1
grep -E "Auto-routing pass|finished with state" ../build/freerouting.log | tail -2 | cut -c40-200
$KPY gen_pcb.py finish 2>&1 | Q
$KPY gen_pcb.py pour 2>&1 | Q
cd ../bootwarmer
cp ../build/unrouted.kicad_pro bootwarmer.kicad_pro
$KCLI sch erc --severity-all -o ../build/erc.rpt bootwarmer.kicad_sch 2>&1 | Q
$KCLI pcb drc --severity-all --format json -o ../build/drc.json bootwarmer.kicad_pcb 2>&1 | Q
python3 ../scripts/drcsum.py ../build/drc.json
python3 ../scripts/verify.py
$KCLI sch export pdf -o bootwarmer-schematic.pdf bootwarmer.kicad_sch 2>&1 | Q
python3 ../scripts/make_fab.py
