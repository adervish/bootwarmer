"""Generate bootwarmer.kicad_sch from design.py (label-per-pin style schematic)."""
import sys, uuid, os
import design, symlib
from sexpr import dump, Sym, find, first

OUT = sys.argv[1] if len(sys.argv) > 1 else "../bootwarmer/bootwarmer.kicad_sch"
PROJECT = "bootwarmer"
ROOT_UUID = str(uuid.uuid5(uuid.NAMESPACE_DNS, "bootwarmer.root"))
G = 2.54
STUB = 2.54


def uid(*k):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, "bootwarmer." + ".".join(str(i) for i in k)))


def snap(v):
    return round(round(v / 1.27) * 1.27, 2)


def resolve_pins(comp, pinlist):
    """Map every symbol pin to a net (or None). Raises on unmapped pins/keys."""
    used = set()
    out = {}
    for p in pinlist:
        if p['num'] in comp['pins']:
            out[p['num']] = comp['pins'][p['num']]; used.add(p['num'])
        elif p['name'] in comp['pins']:
            out[p['num']] = comp['pins'][p['name']]; used.add(p['name'])
        else:
            raise SystemExit("%s: pin %s (%s) has no net assignment" % (comp['ref'], p['num'], p['name']))
    missing = set(comp['pins']) - used
    if missing:
        raise SystemExit("%s: pin keys %s not found in symbol" % (comp['ref'], missing))
    return out


def eff(size=1.27, justify=None, hide=False):
    e = [Sym('effects'), [Sym('font'), [Sym('size'), size, size]]]
    if justify:
        e.append([Sym('justify')] + [Sym(j) for j in justify.split()])
    if hide:
        e.append([Sym('hide'), Sym('yes')])
    return e


def build():
    items = []
    lib_syms = {}
    groups = {}
    for c in design.COMPONENTS:
        groups.setdefault(c['group'], []).append(c)

    y_cursor = 25.0
    for gname, comps in groups.items():
        # lay the group out in rows
        x = 30.0
        row_h = 0.0
        y0 = y_cursor + 10
        items.append([Sym('text'), gname.upper(), [Sym('at'), 15, snap(y_cursor), 0],
                      eff(3.0, 'left bottom'), [Sym('uuid'), uid('txt', gname)]])
        for c in comps:
            sym = symlib.get(c['sym'])
            lib_syms[c['sym']] = sym
            pl = symlib.pins(sym)
            nets = resolve_pins(c, pl)
            minx = min(p['x'] for p in pl); maxx = max(p['x'] for p in pl)
            miny = min(p['y'] for p in pl); maxy = max(p['y'] for p in pl)
            left_lab = max([len(nets[p['num']] or '') for p in pl if p['ang'] == 0] + [0])
            right_lab = max([len(nets[p['num']] or '') for p in pl if p['ang'] == 180] + [0])
            w_left = -minx + STUB + left_lab * 1.1 + 4
            w_right = maxx + STUB + right_lab * 1.1 + 4
            h_up = maxy + STUB + 9
            h_dn = -miny + STUB + 9
            if x + w_left + w_right > 395:
                x = 30.0; y0 += row_h + 4; row_h = 0.0
            X = snap(x + w_left); Y = snap(y0 + h_up)
            x += w_left + w_right + 6
            row_h = max(row_h, h_up + h_dn)

            s = [Sym('symbol'), [Sym('lib_id'), c['sym']], [Sym('at'), X, Y, 0], [Sym('unit'), 1],
                 [Sym('exclude_from_sim'), Sym('no')], [Sym('in_bom'), Sym('yes')],
                 [Sym('on_board'), Sym('yes')], [Sym('dnp'), Sym('no' if c['assemble'] else 'yes')],
                 [Sym('uuid'), uid('sym', c['ref'])]]
            props = [("Reference", c['ref'], (X + minx * 0 + 1.5, Y - maxy - 3.2), False),
                     ("Value", c['value'], (X + 1.5, Y - miny + 3.2), False),
                     ("Footprint", c['fp'], (X, Y), True),
                     ("Datasheet", "", (X, Y), True),
                     ("LCSC", c['lcsc'], (X, Y), True),
                     ("MPN", c['mpn'], (X, Y), True)]
            if abs(minx) < 0.01 and abs(maxx) < 0.01:      # vertical 2-pin part: text to the side
                props[0] = ("Reference", c['ref'], (X + 2.5, Y - 1.3), False)
                props[1] = ("Value", c['value'], (X + 2.5, Y + 1.3), False)
            for name, val, (px, py), hide in props:
                s.append([Sym('property'), name, val, [Sym('at'), snap(px), snap(py), 0],
                          eff(1.27, 'left', hide)])
            for p in pl:
                s.append([Sym('pin'), p['num'], [Sym('uuid'), uid('pin', c['ref'], p['num'], p['x'], p['y'])]])
            s.append([Sym('instances'), [Sym('project'), PROJECT,
                      [Sym('path'), "/" + ROOT_UUID, [Sym('reference'), c['ref']], [Sym('unit'), 1]]]])
            items.append(s)

            seen = set()
            for p in pl:
                ex, ey = snap(X + p['x']), snap(Y - p['y'])
                key = (ex, ey)
                net = nets[p['num']]
                if key in seen:
                    continue
                seen.add(key)
                if net is None:
                    items.append([Sym('no_connect'), [Sym('at'), ex, ey], [Sym('uuid'), uid('nc', c['ref'], p['num'])]])
                    continue
                dx, dy, lang, just = {0: (-STUB, 0, 180, 'right bottom'), 180: (STUB, 0, 0, 'left bottom'),
                                      90: (0, STUB, 270, 'right bottom'), 270: (0, -STUB, 90, 'left bottom')}[p['ang']]
                lx, ly = snap(ex + dx), snap(ey + dy)
                items.append([Sym('wire'), [Sym('pts'), [Sym('xy'), ex, ey], [Sym('xy'), lx, ly]],
                              [Sym('stroke'), [Sym('width'), 0], [Sym('type'), Sym('default')]],
                              [Sym('uuid'), uid('w', c['ref'], p['num'])]])
                items.append([Sym('label'), net, [Sym('at'), lx, ly, lang], eff(1.27, just),
                              [Sym('uuid'), uid('l', c['ref'], p['num'])]])
        y_cursor = y0 + row_h + 6

    # PWR_FLAGs so ERC knows which nets are sourced from connectors / the cell
    flag = symlib.get("power:PWR_FLAG")
    lib_syms["power:PWR_FLAG"] = flag
    fx = 30.0
    items.append([Sym('text'), "POWER FLAGS (ERC only)", [Sym('at'), 15, snap(y_cursor), 0],
                  eff(3.0, 'left bottom'), [Sym('uuid'), uid('txt', 'flags')]])
    for i, net in enumerate(["VBUS", "GND", "CELL_P", "CELL_N", "DW_VCC", "PROT_MID"]):
        X, Y = snap(fx + i * 25.4), snap(y_cursor + 12)
        s = [Sym('symbol'), [Sym('lib_id'), "power:PWR_FLAG"], [Sym('at'), X, Y, 0], [Sym('unit'), 1],
             [Sym('exclude_from_sim'), Sym('no')], [Sym('in_bom'), Sym('no')], [Sym('on_board'), Sym('no')],
             [Sym('dnp'), Sym('no')], [Sym('uuid'), uid('flag', net)],
             [Sym('property'), "Reference", "#FLG%d" % (i + 1), [Sym('at'), X, Y, 0], eff(1.27, None, True)],
             [Sym('property'), "Value", "PWR_FLAG", [Sym('at'), X, snap(Y - 5), 0], eff(1.27)],
             [Sym('property'), "Footprint", "", [Sym('at'), X, Y, 0], eff(1.27, None, True)],
             [Sym('property'), "Datasheet", "", [Sym('at'), X, Y, 0], eff(1.27, None, True)],
             [Sym('pin'), "1", [Sym('uuid'), uid('flagpin', net)]],
             [Sym('instances'), [Sym('project'), PROJECT,
              [Sym('path'), "/" + ROOT_UUID, [Sym('reference'), "#FLG%d" % (i + 1)], [Sym('unit'), 1]]]]]
        items.append(s)
        items.append([Sym('wire'), [Sym('pts'), [Sym('xy'), X, Y], [Sym('xy'), X, snap(Y + STUB)]],
                      [Sym('stroke'), [Sym('width'), 0], [Sym('type'), Sym('default')]],
                      [Sym('uuid'), uid('fw', net)]])
        items.append([Sym('label'), net, [Sym('at'), X, snap(Y + STUB), 270], eff(1.27, 'right bottom'),
                      [Sym('uuid'), uid('fl', net)]])

    sch = [Sym('kicad_sch'), [Sym('version'), 20231120], [Sym('generator'), "bootwarmer_gen"],
           [Sym('uuid'), ROOT_UUID], [Sym('paper'), "A2"],
           [Sym('title_block'), [Sym('title'), "Bootwarmer per-boot controller (ESP32-C6, integrated)"], [Sym('rev'), "C"],
            [Sym('comment'), 1, "Generated from hardware/scripts/design.py - edit that file, not this one"]],
           [Sym('lib_symbols')] + list(lib_syms.values())]
    sch += items
    sch.append([Sym('sheet_instances'), [Sym('path'), "/", [Sym('page'), "1"]]])
    return sch


if __name__ == "__main__":
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    open(OUT, "w").write(dump(build()) + "\n")
    print("wrote", OUT, "with", len(design.COMPONENTS), "components")
