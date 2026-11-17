"""Independent read-back: board pad nets and schematic netlist must both equal design.py."""
import sys, subprocess, re, os
import design, symlib
HERE = os.path.dirname(os.path.abspath(__file__))
KC = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"
want = {}
for c in design.COMPONENTS:
    for p in symlib.pins(symlib.get(c['sym'])):
        net = c['pins'].get(p['num'], c['pins'].get(p['name']))
        want[(c['ref'], p['num'])] = net
    for k, v in c['extra'].items():
        want[(c['ref'], k)] = v
# --- schematic netlist
xml = os.path.join(HERE, "..", "build", "netlist.xml")
subprocess.run([KC, "sch", "export", "netlist", "--format", "kicadxml", "-o", xml,
                os.path.join(HERE, "..", "bootwarmer", "bootwarmer.kicad_sch")], capture_output=True)
import xml.etree.ElementTree as ET
got = {}
for net in ET.parse(xml).getroot().iter("net"):
    name = net.get("name").lstrip("/")
    for n in net.iter("node"):
        got[(n.get("ref"), n.get("pin"))] = name
bad = 0
for k, v in want.items():
    if k[0].startswith("#"): continue
    g = got.get(k)
    is_extra = any(c['ref'] == k[0] and k[1] in c['extra'] for c in design.COMPONENTS)
    if is_extra: continue
    if v is None:
        if g is not None and not g.startswith("unconnected-"): print("SCH", k, "should be NC, is", g); bad += 1
    elif g != v:
        print("SCH", k, "want", v, "got", g); bad += 1
print("schematic: %d pins checked, %d mismatches" % (len(want), bad))
# --- board
txt = open(os.path.join(HERE, "..", "bootwarmer", "bootwarmer.kicad_pcb")).read()
from sexpr import parse, find, first
pcb = parse(txt)
bgot = {}
for fp in find(pcb, "footprint"):
    ref = [p[2] for p in find(fp, "property") if p[1] == "Reference"][0]
    for pad in find(fp, "pad"):
        if pad[1] == "": continue
        n = first(pad, "net")
        bgot.setdefault((ref, pad[1]), set()).add(n[-1] if n else None)
bbad = 0
for k, v in want.items():
    g = bgot.get(k)
    if g is None: print("PCB missing pad", k); bbad += 1
    elif g != {v}: print("PCB", k, "want", v, "got", g); bbad += 1
extra = set(bgot) - set(want)
print("board: %d pads checked, %d mismatches, %d pads not in design" % (len(want), bbad, len(extra)), sorted(extra)[:5])
sys.exit(1 if bad or bbad or extra else 0)
