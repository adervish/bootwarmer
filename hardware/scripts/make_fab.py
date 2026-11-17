"""Produce the JLCPCB order files from bootwarmer.kicad_pcb + design.py.

Outputs (in hardware/fab/):
  bootwarmer-gerbers.zip   Gerbers + drill files           -> "Add gerber file"
  bootwarmer-bom.csv       Comment, Designator, Footprint, LCSC Part #
  bootwarmer-cpl.csv       Designator, Mid X, Mid Y, Layer, Rotation
"""
import csv, os, subprocess, zipfile, shutil, collections
import design

HERE = os.path.dirname(os.path.abspath(__file__))
PCB = os.path.join(HERE, "..", "bootwarmer", "bootwarmer.kicad_pcb")
FAB = os.path.join(HERE, "..", "fab")
KC = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"


def run(*args):
    r = subprocess.run([KC] + list(args), capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(r.stdout + r.stderr)


def main():
    gdir = os.path.join(FAB, "gerbers")
    shutil.rmtree(FAB, ignore_errors=True)
    os.makedirs(gdir)
    run("pcb", "export", "gerbers", "--no-protel-ext", "--subtract-soldermask",
        "--layers", "F.Cu,B.Cu,F.Paste,B.Paste,F.SilkS,B.SilkS,F.Mask,B.Mask,Edge.Cuts",
        "-o", gdir + "/", PCB)
    run("pcb", "export", "drill", "--format", "excellon", "--excellon-units", "mm",
        "--excellon-separate-th", "--generate-map", "--map-format", "gerberx2", "-o", gdir + "/", PCB)
    with zipfile.ZipFile(os.path.join(FAB, "bootwarmer-gerbers.zip"), "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(os.listdir(gdir)):
            if not f.endswith(".gbrjob") and "drl_map" not in f:
                z.write(os.path.join(gdir, f), f)

    # ---- BOM (only parts JLCPCB places)
    groups = collections.OrderedDict()
    for c in design.COMPONENTS:
        if not c['assemble']:
            continue
        key = (c['lcsc'], c['mpn'], c['fp'].split(":")[1])
        groups.setdefault(key, []).append(c['ref'])
    with open(os.path.join(FAB, "bootwarmer-bom.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Comment", "Designator", "Footprint", "LCSC Part #"])
        for (lcsc, mpn, fp), refs in groups.items():
            w.writerow([mpn, ",".join(refs), fp, lcsc])

    # ---- placement file
    pos = os.path.join(FAB, "pos.csv")
    run("pcb", "export", "pos", "--format", "csv", "--units", "mm", "--side", "front",
        "--exclude-dnp", "-o", pos, PCB)
    placed = {c['ref'] for c in design.COMPONENTS if c['assemble']}
    rows = list(csv.DictReader(open(pos)))
    with open(os.path.join(FAB, "bootwarmer-cpl.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
        n = 0
        for r in rows:
            if r["Ref"] in placed:
                w.writerow([r["Ref"], r["PosX"] + "mm", r["PosY"] + "mm", "Top", r["Rot"]])
                n += 1
    os.remove(pos)
    missing = placed - {r["Ref"] for r in rows}
    if missing:
        raise SystemExit("parts missing from placement file: %s" % sorted(missing))
    print("gerbers: %d files, BOM: %d lines / %d parts, CPL: %d placements"
          % (len(os.listdir(gdir)), len(groups), len(placed), n))


if __name__ == "__main__":
    main()
