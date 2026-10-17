#!/usr/bin/env python3
"""Turn assets/PleiadesWatchtower.obj into Luau that recreates each mesh as a
box-shaped MeshPart with the same name and bounds, to test the import path."""
import pathlib
import sys

obj = pathlib.Path(sys.argv[1]).read_text().splitlines()
objects, cur, verts = {}, None, []
for line in obj:
    if line.startswith("o "):
        cur = line[2:].strip()
        objects[cur] = []
    elif line.startswith("v "):
        v = tuple(float(x) for x in line.split()[1:4])
        verts.append(v)
        objects[cur].append(v)
out = ["IMPORT_FIXTURE = {"]
for name, vs in objects.items():
    lo = [min(v[i] for v in vs) for i in range(3)]
    hi = [max(v[i] for v in vs) for i in range(3)]
    c = [(a + b) / 2 for a, b in zip(lo, hi)]
    s = [max(b - a, 0.05) for a, b in zip(lo, hi)]
    out.append('\t{ name = "%s", center = Vector3.new(%f, %f, %f), size = Vector3.new(%f, %f, %f) },' % (name, *c, *s))
out.append("}")
print("\n".join(out))
