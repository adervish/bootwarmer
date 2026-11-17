import sys, symlib
for lid in sys.argv[1:]:
    try:
        s = symlib.get(lid)
    except Exception as e:
        print("MISSING", lid, repr(e)); continue
    ps = symlib.pins(s)
    print("##", lid, "|", " ".join("%s=%s" % (p['num'], p['name']) for p in sorted(ps, key=lambda p: (len(p['num']), p['num']))))
