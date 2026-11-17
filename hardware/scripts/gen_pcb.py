"""Build the Bootwarmer PCB from design.py.  Run with KiCad's bundled python.

  stage 1:  gen_pcb.py place  -> unrouted board + Specctra DSN for the autorouter
  stage 2:  gen_pcb.py finish -> import the routed SES, drop unused vias
  stage 3:  gen_pcb.py pour   -> pour zones, stitch the ground pours, save final board
"""
import sys, os, math
import pcbnew
from pcbnew import VECTOR2I, FromMM, ToMM
import design, symlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "..", "bootwarmer")
BUILD = os.path.join(HERE, "..", "build")
FPDIR = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints/"
OX, OY = 100.0, 80.0            # board origin on the KiCad page
W, H = design.BOARD_W, design.BOARD_H
X0 = design.BOARD_X0
F, B = pcbnew.F_Cu, pcbnew.B_Cu


def P(x, y):
    return VECTOR2I(FromMM(OX + x), FromMM(OY + y))


def pad_nets(comp):
    """pad number -> net name (None = unconnected) using the symbol's pin list."""
    sym = symlib.get(comp['sym'])
    m = {}
    for p in symlib.pins(sym):
        if p['num'] in comp['pins']:
            m[p['num']] = comp['pins'][p['num']]
        elif p['name'] in comp['pins']:
            m[p['num']] = comp['pins'][p['name']]
        else:
            raise SystemExit("%s pin %s unassigned" % (comp['ref'], p['num']))
    m.update(comp['extra'])
    return m


def place():
    os.makedirs(OUTDIR, exist_ok=True)
    os.makedirs(BUILD, exist_ok=True)
    path = os.path.join(BUILD, "unrouted.kicad_pcb")
    for ext in (".kicad_pcb", ".kicad_pro", ".kicad_prl"):
        if os.path.exists(path[:-10] + ext):
            os.remove(path[:-10] + ext)
    board = pcbnew.NewBoard(path)
    ds = board.GetDesignSettings()
    ds.SetCopperLayerCount(2)
    ds.m_MinClearance = FromMM(0.127)
    ds.m_TrackMinWidth = FromMM(0.127)
    ds.m_CopperEdgeClearance = FromMM(0.3)
    ds.m_MinThroughDrill = FromMM(0.3)
    ds.m_ViasMinSize = FromMM(0.5)
    ns = ds.m_NetSettings
    dflt = ns.GetDefaultNetclass()
    dflt.SetClearance(FromMM(0.15)); dflt.SetTrackWidth(FromMM(design.SIGNAL_WIDTH))
    dflt.SetViaDiameter(FromMM(0.6)); dflt.SetViaDrill(FromMM(0.3))
    pw = pcbnew.NETCLASS("Power")
    pw.SetClearance(FromMM(0.2)); pw.SetTrackWidth(FromMM(design.POWER_WIDTH))
    pw.SetViaDiameter(FromMM(0.8)); pw.SetViaDrill(FromMM(0.4))
    ns.SetNetclass("Power", pw)
    for n in design.POWER_NETS:
        ns.SetNetclassPatternAssignment(n, "Power")

    nets = {}

    def net(name):
        if name not in nets:
            n = pcbnew.NETINFO_ITEM(board, name)
            board.Add(n)
            nets[name] = n
        return nets[name]

    # ---- footprints
    for c in design.COMPONENTS:
        lib, name = c['fp'].split(":")
        fp = pcbnew.FootprintLoad(FPDIR + lib + ".pretty", name)
        if fp is None:
            raise SystemExit("footprint not found: " + c['fp'])
        fp.SetFPID(pcbnew.LIB_ID(lib, name))
        fp.SetReference(c['ref'])
        fp.SetValue(c['value'])
        board.Add(fp)
        x, y, rot = c['pos']
        fp.SetPosition(P(x, y))
        if c['side'] == "B":
            fp.Flip(fp.GetPosition(), pcbnew.FLIP_DIRECTION_TOP_BOTTOM)
        fp.SetOrientationDegrees(rot)
        if not c['assemble']:
            fp.SetExcludedFromPosFiles(True)
            fp.SetExcludedFromBOM(True)
        m = pad_nets(c)
        for pad in fp.Pads():
            num = pad.GetNumber()
            # JLCPCB 2-layer minimum drill is 0.3 mm (module thermal vias ship as 0.2 mm)
            if pad.HasHole() and 0 < pad.GetDrillSize().x < FromMM(0.3):
                pad.SetDrillSize(VECTOR2I(FromMM(0.3), FromMM(0.3)))
            if num == "":
                continue
            if num not in m:
                raise SystemExit("%s: footprint pad '%s' has no net mapping" % (c['ref'], num))
            if m[num] is not None:
                pad.SetNet(net(m[num]))
        missing = set(k for k in m if k not in [p.GetNumber() for p in fp.Pads()])
        if missing:
            raise SystemExit("%s: symbol pins %s have no footprint pad" % (c['ref'], missing))
        # keep reference text small and out of the way
        fp.Reference().SetTextSize(VECTOR2I(FromMM(0.8), FromMM(0.8)))
        fp.Reference().SetTextThickness(FromMM(0.12))

    # ---- outline (rounded rectangle)
    r = 2.0

    def edge_line(x1, y1, x2, y2):
        s = pcbnew.PCB_SHAPE(board)
        s.SetShape(pcbnew.SHAPE_T_SEGMENT)
        s.SetStart(P(x1, y1)); s.SetEnd(P(x2, y2))
        s.SetLayer(pcbnew.Edge_Cuts); s.SetWidth(FromMM(0.1))
        board.Add(s)

    def edge_arc(cx, cy, a0):
        s = pcbnew.PCB_SHAPE(board)
        s.SetShape(pcbnew.SHAPE_T_ARC)
        pts = [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))) for a in (a0, a0 + 45, a0 + 90)]
        s.SetArcGeometry(P(*pts[0]), P(*pts[1]), P(*pts[2]))
        s.SetLayer(pcbnew.Edge_Cuts); s.SetWidth(FromMM(0.1))
        board.Add(s)

    edge_line(X0 + r, 0, W - r, 0); edge_line(W, r, W, H - r)
    edge_line(W - r, H, X0 + r, H); edge_line(X0, H - r, X0, r)
    edge_arc(X0 + r, r, 180); edge_arc(W - r, r, 270); edge_arc(W - r, H - r, 0); edge_arc(X0 + r, H - r, 90)

    # ---- hand-placed heavy copper for the battery / heater current loop
    def track(n, pts, w, layer=F):
        for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
            t = pcbnew.PCB_TRACK(board)
            t.SetStart(P(x1, y1)); t.SetEnd(P(x2, y2))
            t.SetWidth(FromMM(w)); t.SetLayer(layer); t.SetNet(net(n))
            board.Add(t)

    def via(n, x, y, dia=0.8, drill=0.4):
        v = pcbnew.PCB_VIA(board)
        v.SetViaType(pcbnew.VIATYPE_THROUGH)
        v.SetPosition(P(x, y))
        v.SetLayerPair(F, B)
        try:
            v.SetWidth(F, FromMM(dia))
        except TypeError:
            v.SetWidth(FromMM(dia))
        v.SetDrill(FromMM(drill))
        v.SetNet(net(n))
        board.Add(v)

    for item in design_copper():
        if item[0] == 'track':
            track(*item[1:])
        elif item[0] == 'btrack':
            track(*item[1:], layer=B)
        else:
            via(*item[1:])

    # ---- zones
    def zone(n, layer, pts, prio, clearance=0.3):
        z = pcbnew.ZONE(board)
        z.SetLayer(layer)
        z.SetNet(net(n))
        o = z.Outline(); o.NewOutline()
        for x, y in pts:
            o.Append(FromMM(OX + x), FromMM(OY + y))
        z.SetPadConnection(pcbnew.ZONE_CONNECTION_FULL)
        z.SetLocalClearance(FromMM(clearance))
        z.SetMinThickness(FromMM(0.2))
        z.SetAssignedPriority(prio)
        z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
        board.Add(z)
        return z

    full = [(X0, 0), (W, 0), (W, H), (X0, H)]
    zone("GND", F, full, 0)
    zone("GND", B, full, 0)
    zone("VSYS", B, design_vsys_zone(), 1)

    # antenna keep-out: no copper of any kind under / beside the module antenna
    k = pcbnew.ZONE(board)
    k.SetIsRuleArea(True)
    k.SetLayerSet(pcbnew.LSET.AllCuMask())
    o = k.Outline(); o.NewOutline()
    for x, y in [(design.ANTENNA_KEEPOUT_X, -1), (W + 1, -1), (W + 1, H + 1), (design.ANTENNA_KEEPOUT_X, H + 1)]:
        o.Append(FromMM(OX + x), FromMM(OY + y))
    k.SetDoNotAllowTracks(True); k.SetDoNotAllowVias(True); k.SetDoNotAllowPads(False)
    k.SetDoNotAllowFootprints(False)
    try:
        k.SetDoNotAllowZoneFills(True)
    except AttributeError:
        k.SetDoNotAllowCopperPour(True)
    board.Add(k)

    for poly in design.NO_POUR_TOP:
        k = pcbnew.ZONE(board)
        k.SetIsRuleArea(True)
        k.SetLayer(F)
        o = k.Outline(); o.NewOutline()
        for x, y in poly:
            o.Append(FromMM(OX + x), FromMM(OY + y))
        k.SetDoNotAllowTracks(False); k.SetDoNotAllowVias(False); k.SetDoNotAllowPads(False)
        k.SetDoNotAllowFootprints(False)
        try:
            k.SetDoNotAllowZoneFills(True)
        except AttributeError:
            k.SetDoNotAllowCopperPour(True)
        board.Add(k)

    for poly in design.BOTTOM_NO_ROUTE + design.EDGE_STRIPS:
        k = pcbnew.ZONE(board)
        k.SetIsRuleArea(True)
        if poly in design.EDGE_STRIPS:
            k.SetLayerSet(pcbnew.LSET.AllCuMask())
        else:
            k.SetLayer(B)
        o = k.Outline(); o.NewOutline()
        for x, y in poly:
            o.Append(FromMM(OX + x), FromMM(OY + y))
        k.SetDoNotAllowTracks(True); k.SetDoNotAllowVias(poly in design.EDGE_STRIPS); k.SetDoNotAllowPads(False)
        k.SetDoNotAllowFootprints(False)
        try:
            k.SetDoNotAllowZoneFills(False)
        except AttributeError:
            k.SetDoNotAllowCopperPour(False)
        board.Add(k)

    # ---- silkscreen labels
    def silk(txt, x, y, size=1.0, layer=pcbnew.F_SilkS, rot=0):
        t = pcbnew.PCB_TEXT(board)
        t.SetText(txt); t.SetPosition(P(x, y)); t.SetLayer(layer)
        t.SetTextSize(VECTOR2I(FromMM(size), FromMM(size)))
        t.SetTextThickness(FromMM(size * 0.15))
        t.SetTextAngleDegrees(rot)
        if layer == pcbnew.B_SilkS:
            t.SetMirrored(True)
        board.Add(t)

    for s in design.SILK:
        silk(*s)

    pcbnew.SaveBoard(path, board)
    ok = pcbnew.ExportSpecctraDSN(board, os.path.join(BUILD, "bootwarmer.dsn"))
    print("placed %d footprints, %d nets, dsn export: %s" % (len(design.COMPONENTS), len(nets), ok))
    for fp in board.GetFootprints():
        if fp.GetReference() in ("BT1", "J1"):
            print(fp.GetReference(), [(p.GetNumber(), round(ToMM(p.GetPosition().x) - OX, 2),
                                       round(ToMM(p.GetPosition().y) - OY, 2)) for p in fp.Pads()][:4])


def design_copper():
    return design.COPPER


def design_vsys_zone():
    return design.VSYS_ZONE


def finish():
    src = os.path.join(BUILD, "unrouted.kicad_pcb")
    board = pcbnew.LoadBoard(src)
    ok = pcbnew.ImportSpecctraSES(board, os.path.join(BUILD, "bootwarmer.ses"))
    print("ses import:", ok)
    removed = remove_dangling_vias(board)
    print("unused autorouter vias removed:", removed)
    out = os.path.join(OUTDIR, "bootwarmer.kicad_pcb")
    pcbnew.SaveBoard(out, board)
    print("saved", out)


def pour():
    """Separate process from finish(): removing items invalidates pcbnew's Python wrappers."""
    out = os.path.join(OUTDIR, "bootwarmer.kicad_pcb")
    board = pcbnew.LoadBoard(out)
    # First pour keeps every island so the stitching pass can tie isolated
    # bottom-side ground (e.g. under the module) to the top pour; the final
    # pour then drops whatever is still unconnected.
    def set_islands(mode):
        for z in board.Zones():
            if not z.GetIsRuleArea():
                z.SetIslandRemovalMode(mode)

    set_islands(pcbnew.ISLAND_REMOVAL_MODE_NEVER)
    pcbnew.ZONE_FILLER(board).Fill(board.Zones())
    n = stitch_ground(board)
    set_islands(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
    pcbnew.ZONE_FILLER(board).Fill(board.Zones())
    m, orphans = rescue_islands(board)
    pcbnew.ZONE_FILLER(board).Fill(board.Zones())
    print("ground stitching vias added: %d grid + %d for isolated top-side patches" % (n, m))
    if orphans:
        print("WARNING: ground patches with no room for a via:", orphans)
    out = os.path.join(OUTDIR, "bootwarmer.kicad_pcb")
    pcbnew.SaveBoard(out, board)
    print("saved", out, "tracks:", len(board.GetTracks()))


def remove_dangling_vias(board):
    """Drop signal vias the autorouter left touching copper on only one layer."""
    poured = {z.GetNetname() for z in board.Zones() if not z.GetIsRuleArea()}
    segs = [t for t in board.GetTracks() if t.Type() != pcbnew.PCB_VIA_T]
    padpos = [(p.GetPosition(), p) for fp in board.GetFootprints() for p in fp.Pads() if p.HasHole()]
    n = 0
    for v in [t for t in board.GetTracks() if t.Type() == pcbnew.PCB_VIA_T]:
        if v.GetNetname() in poured:
            continue
        pos = v.GetPosition(); tol = FromMM(0.05)
        layers = {s.GetLayer() for s in segs if s.GetNetname() == v.GetNetname() and
                  any(abs(e.x - pos.x) <= tol and abs(e.y - pos.y) <= tol for e in (s.GetStart(), s.GetEnd()))}
        if len(layers) < 2 and not any(abs(pp.x - pos.x) < FromMM(0.5) and abs(pp.y - pos.y) < FromMM(0.5) for pp, _ in padpos):
            board.Remove(v); n += 1
    return n


def _obstacles(board, layer, inflate):
    """Everything on `layer` that is not ground, grown by `inflate`, as one polygon set."""
    poly = pcbnew.SHAPE_POLY_SET()
    err = FromMM(0.01)
    for fp in board.GetFootprints():
        for p in fp.Pads():
            if p.GetNetname() != "GND" and (p.IsOnLayer(layer) or p.HasHole()):
                p.TransformShapeToPolygon(poly, layer if p.IsOnLayer(layer) else F, inflate, err, pcbnew.ERROR_OUTSIDE)
    for t in board.GetTracks():
        if t.GetNetname() != "GND" and (t.Type() == pcbnew.PCB_VIA_T or t.GetLayer() == layer):
            t.TransformShapeToPolygon(poly, layer, inflate, err, pcbnew.ERROR_OUTSIDE)
    return poly


def rescue_islands(board, dia=0.6, drill=0.3, width=0.25):
    """Tie every top-side ground patch that has no via to the bottom ground pour.

    For each such patch, run a short straight track from one of its ground pads
    to the nearest spot where a via fits (clear of other top copper, and wholly
    inside the bottom ground fill).
    """
    gnd = board.FindNet("GND")
    fills = {}
    for z in board.Zones():
        if not z.GetIsRuleArea() and z.GetNetname() == "GND":
            fills[z.GetLayer()] = z.GetFilledPolysList(z.GetLayer())
    vias = [t.GetPosition() for t in board.GetTracks() if t.Type() == pcbnew.PCB_VIA_T and t.GetNetname() == "GND"]
    gpads = [p for fp in board.GetFootprints() for p in fp.Pads() if p.GetNetname() == "GND" and p.IsOnLayer(F)]
    no_track = _obstacles(board, F, FromMM(width / 2 + 0.2))
    no_via = _obstacles(board, F, FromMM(dia / 2 + 0.2))
    ring = [(math.cos(math.radians(a)), math.sin(math.radians(a))) for a in range(0, 360, 30)]
    vrad = FromMM(dia / 2 + 0.2)
    added, orphans = 0, []
    top = fills[F]
    for i in range(top.OutlineCount()):
        one = pcbnew.SHAPE_POLY_SET(); one.AddOutline(top.Outline(i))
        if any(one.Contains(v) for v in vias):
            continue
        found = None
        for p in [p for p in gpads if one.Contains(p.GetPosition())]:
            c = p.GetPosition()
            r = 0.9
            while r <= 6.0 and not found:
                for a in range(0, 360, 10):
                    vx = int(c.x + FromMM(r) * math.cos(math.radians(a)))
                    vy = int(c.y + FromMM(r) * math.sin(math.radians(a)))
                    v = VECTOR2I(vx, vy)
                    if ToMM(vx) - OX > design.ANTENNA_KEEPOUT_X - 0.6 or no_via.Contains(v):
                        continue
                    if not all(fills[B].Contains(VECTOR2I(int(vx + vrad * dx), int(vy + vrad * dy))) for dx, dy in ring):
                        continue
                    n = max(2, int(r / 0.1))
                    if any(no_track.Contains(VECTOR2I(int(c.x + (vx - c.x) * k / n), int(c.y + (vy - c.y) * k / n)))
                           for k in range(n + 1)):
                        continue
                    found = (c, v); break
                r += 0.2
            if found:
                break
        bb = top.Outline(i).BBox()
        if not found:
            orphans.append("(%.1f, %.1f)" % (ToMM(bb.GetLeft()) - OX, ToMM(bb.GetTop()) - OY)); continue
        c, v = found
        t = pcbnew.PCB_TRACK(board)
        t.SetStart(c); t.SetEnd(v); t.SetWidth(FromMM(width)); t.SetLayer(F); t.SetNet(gnd)
        board.Add(t)
        via = pcbnew.PCB_VIA(board)
        via.SetViaType(pcbnew.VIATYPE_THROUGH)
        via.SetPosition(v); via.SetLayerPair(F, B)
        try:
            via.SetWidth(F, FromMM(dia))
        except TypeError:
            via.SetWidth(FromMM(dia))
        via.SetDrill(FromMM(drill)); via.SetNet(gnd)
        board.Add(via); added += 1
        vias.append(v)
    return added, orphans


def stitch_ground(board, grid=2.0, dia=0.6, drill=0.3):
    """Tie the top and bottom ground pours together with a grid of vias.

    A via is only dropped where a 0.65 mm-radius disc sits wholly inside the
    filled ground copper on BOTH layers and is clear of every pad.
    """
    gnd = board.FindNet("GND")
    fills = {}
    for z in board.Zones():
        if z.GetIsRuleArea() or z.GetNetname() != "GND":
            continue
        fills[z.GetLayer()] = z.GetFilledPolysList(z.GetLayer())
    pads = []
    for fp in board.GetFootprints():
        for p in fp.Pads():
            bb = p.GetBoundingBox()
            pads.append((bb.GetLeft(), bb.GetTop(), bb.GetRight(), bb.GetBottom()))
    existing = [(t.GetPosition().x, t.GetPosition().y) for t in board.GetTracks() if t.Type() == pcbnew.PCB_VIA_T]
    ring = [(math.cos(math.radians(a)), math.sin(math.radians(a))) for a in range(0, 360, 30)]
    rad = FromMM(dia / 2 + 0.35)
    margin = FromMM(dia / 2 + 0.25)
    added = 0
    y = 1.2
    while y < H - 1.0:
        x = X0 + 1.2
        while x < design.ANTENNA_KEEPOUT_X - 1.0:
            c = P(x, y)
            pts = [c] + [VECTOR2I(int(c.x + rad * dx), int(c.y + rad * dy)) for dx, dy in ring]
            ok = all(fills[l].Contains(pt) for l in (F, B) for pt in pts)
            ok = ok and not any(l - margin < c.x < r + margin and t - margin < c.y < b + margin for l, t, r, b in pads)
            ok = ok and not any(abs(c.x - ex) < FromMM(1.2) and abs(c.y - ey) < FromMM(1.2) for ex, ey in existing)
            if ok:
                v = pcbnew.PCB_VIA(board)
                v.SetViaType(pcbnew.VIATYPE_THROUGH)
                v.SetPosition(c); v.SetLayerPair(F, B)
                try:
                    v.SetWidth(F, FromMM(dia))
                except TypeError:
                    v.SetWidth(FromMM(dia))
                v.SetDrill(FromMM(drill)); v.SetNet(gnd)
                board.Add(v)
                added += 1
            x += grid
        y += grid
    return added


if __name__ == "__main__":
    {"place": place, "finish": finish, "pour": pour}[sys.argv[1]]()
