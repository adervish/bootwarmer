"""Physical audit of the routed board (run with KiCad's python)."""
import pcbnew, sys, os, collections, math
from pcbnew import ToMM, FromMM
import design
HERE = os.path.dirname(os.path.abspath(__file__))
b = pcbnew.LoadBoard(os.path.join(HERE, "..", "bootwarmer", "bootwarmer.kicad_pcb"))
OX, OY = 100.0, 80.0
X = lambda v: ToMM(v) - OX
Y = lambda v: ToMM(v) - OY
F, B = pcbnew.F_Cu, pcbnew.B_Cu
tracks = [t for t in b.GetTracks() if t.Type() != pcbnew.PCB_VIA_T]
vias = [t for t in b.GetTracks() if t.Type() == pcbnew.PCB_VIA_T]
print("== board", "tracks", len(tracks), "vias", len(vias))
# 1. antenna keep-out
bad = [t for t in tracks if max(X(t.GetStart().x), X(t.GetEnd().x)) > design.ANTENNA_KEEPOUT_X]
badv = [v for v in vias if X(v.GetPosition().x) > design.ANTENNA_KEEPOUT_X - 0.3]
print("== antenna keep-out: tracks inside", len(bad), "vias inside", len(badv))
for z in b.Zones():
    if z.GetIsRuleArea(): continue
    l = z.GetLayer(); bb = z.GetFilledPolysList(l).BBox()
    print("   fill", z.GetNetname(), b.GetLayerName(l), "x[%.2f, %.2f] y[%.2f, %.2f] pieces %d" % (X(bb.GetLeft()), X(bb.GetRight()), Y(bb.GetTop()), Y(bb.GetBottom()), z.GetFilledPolysList(l).OutlineCount()))
# 2. widths per net
w = collections.defaultdict(list)
for t in tracks: w[t.GetNetname()].append(ToMM(t.GetWidth()))
print("== track widths (min / max mm) for power nets")
for n in ("CELL_P", "CELL_N", "PROT_MID", "HTR1_SW", "VSYS", "VBUS", "3V3", "GND"):
    print("   %-9s min %.2f max %.2f segments %d" % (n, min(w[n]), max(w[n]), len(w[n])))
print("   narrowest track on board: %.3f mm" % min(min(v) for v in w.values()))
# 3. drills
dr = collections.Counter()
for v in vias: dr["via %.2f/%.2f" % (ToMM(v.GetDrill()), ToMM(v.GetWidth(F)))] += 1
for fp in b.GetFootprints():
    for p in fp.Pads():
        if p.HasHole(): dr["%s hole %.2fx%.2f" % ("PTH" if p.GetAttribute() == pcbnew.PAD_ATTRIB_PTH else "NPTH", ToMM(p.GetDrillSize().x), ToMM(p.GetDrillSize().y))] += 1
print("== drills", dict(dr))
# 4. heater current loop continuity through pours
def piece(z, layer, x, y):
    ps = z.GetFilledPolysList(layer); pt = pcbnew.VECTOR2I(FromMM(OX + x), FromMM(OY + y))
    for i in range(ps.OutlineCount()):
        one = pcbnew.SHAPE_POLY_SET(); one.AddOutline(ps.Outline(i))
        for h in range(ps.HoleCount(i)): one.AddHole(ps.Hole(i, h))
        if one.Contains(pt): return i
    return None
for z in b.Zones():
    if z.GetIsRuleArea(): continue
    l = z.GetLayer()
    if z.GetNetname() == "GND" and l == B:
        print("== bottom ground pour piece index at heater-FET vias:", piece(z, l, 20.95, 16.4), piece(z, l, 22.05, 16.4), " at protection-FET vias:", piece(z, l, 70.3, 16.0), piece(z, l, 70.3, 17.2), " under module:", piece(z, l, 86.5, 13.7))
    if z.GetNetname() == "VSYS":
        print("== VSYS pour piece index at P-FET vias:", piece(z, l, 9.9, 6.9), piece(z, l, 9.9, 18.8), " heater conn via:", piece(z, l, 22.0, 10.75), " bulk cap via:", piece(z, l, 27.0, 10.1))
# 5. narrowest neck of the bottom ground spine between heater FET and protection FETs
for z in b.Zones():
    if z.GetIsRuleArea() or z.GetNetname() != "GND" or z.GetLayer() != B: continue
    ps = z.GetFilledPolysList(B)
    worst = 99
    x = 23.0
    while x < 70.0:
        run = 0; best = 0; y = 14.0
        while y < 20.0:
            if ps.Contains(pcbnew.VECTOR2I(FromMM(OX + x), FromMM(OY + y))): run += 0.1; best = max(best, run)
            else: run = 0
            y += 0.1
        worst = min(worst, best); x += 0.5
    print("== bottom ground spine: narrowest continuous width between x=23 and x=70 is %.1f mm" % worst)
# 6. footprint orientation summary for the parts where rotation matters
print("== placements (x, y, rot) and pin-1 position")
for fp in sorted(b.GetFootprints(), key=lambda f: f.GetReference()):
    r = fp.GetReference()
    if r[0] in "UQJ" or r.startswith("LED") or r.startswith("SW") or r == "BT1":
        p1 = [p for p in fp.Pads() if p.GetNumber() in ("1", "A1")]
        pp = p1[0].GetPosition() if p1 else fp.GetPosition()
        print("   %-5s %-28s at (%6.2f, %5.2f) rot %5.1f  side %s  pin1 at (%6.2f, %5.2f)" % (r, fp.GetValue()[:28], X(fp.GetPosition().x), Y(fp.GetPosition().y), fp.GetOrientationDegrees(), "B" if fp.IsFlipped() else "F", X(pp.x), Y(pp.y)))
