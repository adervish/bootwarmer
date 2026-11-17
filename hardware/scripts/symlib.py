import os, copy
from sexpr import parse, find, first, Sym
SYMDIR = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols/"
_cache = {}

def _lib(lib):
    if lib not in _cache:
        p = SYMDIR + lib + ".kicad_sym"
        if os.path.isdir(p):  # KiCad 10 may split libs into dirs
            syms = {}
            for f in os.listdir(p):
                t = parse(open(os.path.join(p, f)).read())
                for s in find(t, 'symbol'):
                    syms[s[1]] = s
        else:
            t = parse(open(p).read())
            syms = {s[1]: s for s in find(t, 'symbol')}
        _cache[lib] = syms
    return _cache[lib]

def get(libid):
    """Return flattened symbol s-expr (extends resolved), named lib:name."""
    lib, name = libid.split(":")
    syms = _lib(lib)
    s = copy.deepcopy(syms[name])
    ext = first(s, 'extends')
    if ext:
        base = copy.deepcopy(syms[ext[1]])
        props = {p[1]: p for p in find(s, 'property')}
        out = [base[0], name]
        for item in base[2:]:
            if isinstance(item, list) and item[0] == 'property' and item[1] in props:
                out.append(props.pop(item[1]))
            elif isinstance(item, list) and item[0] == 'symbol':
                item[1] = item[1].replace(ext[1], name, 1)
                out.append(item)
            else:
                out.append(item)
        s = out
    s[1] = libid
    return s

def pins(sym):
    """[(number, name, x, y, angle, length)] for unit 1 / common."""
    res = []
    for sub in find(sym, 'symbol'):
        for p in find(sub, 'pin'):
            at = first(p, 'at')
            res.append(dict(num=first(p, 'number')[1], name=first(p, 'name')[1],
                            x=float(at[1]), y=float(at[2]), ang=int(float(at[3])) if len(at) > 3 else 0,
                            len=float(first(p, 'length')[1]), etype=str(p[1]),
                            hide=any(i == Sym('hide') or (isinstance(i, list) and i[0] == 'hide' and i[1] == 'yes') for i in p)))
    return res
