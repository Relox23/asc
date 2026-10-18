#!/usr/bin/env python3
"""Stand-in for the IslandAssets model Studio makes when importing the asset library.

Studio's 3D importer turns every mesh in assets/IslandAssets.fbx into a MeshPart
named after it, sized to the mesh's bounds and placed at the bounds' centre.
This reads the matching OBJ export (same meshes and names) and writes Luau that
recreates those MeshParts in the mock, so the generator's mesh code paths can be
tested without Studio. The meshes themselves (for previews) come from load().

    library_fixture.py <IslandAssets.obj> > fixture.luau

The Luau defines LIBRARY_FIXTURE (one entry per mesh) and
makeLibrary(transform, scale), which builds ServerStorage.IslandAssets as if the
importer had rotated/scaled the file by `transform` and `scale`.
"""
import sys

import numpy as np


def load(path):
    """{object name: (vertices Nx3, triangles Mx3)} in OBJ coordinates."""
    objects, order = {}, []
    verts = []
    cur = None
    with open(path) as f:
        for line in f:
            if line.startswith("v "):
                verts.append([float(x) for x in line.split()[1:4]])
            elif line.startswith("o "):
                cur = line[2:].strip()
                objects[cur] = []
                order.append(cur)
            elif line.startswith("f ") and cur is not None:
                idx = [int(tok.split("/")[0]) for tok in line.split()[1:]]
                for k in range(1, len(idx) - 1):
                    objects[cur].append((idx[0], idx[k], idx[k + 1]))
    verts = np.array(verts)
    out = {}
    for name in order:
        tris = np.array(objects[name], dtype=np.int64) - 1
        used = np.unique(tris)
        remap = np.full(len(verts), -1, dtype=np.int64)
        remap[used] = np.arange(len(used))
        out[name] = (verts[used], remap[tris])
    return out


def bounds(v):
    lo, hi = v.min(axis=0), v.max(axis=0)
    size = np.maximum(hi - lo, 0.01)
    return (lo + hi) / 2, size


def fixture_luau(objects):
    lines = ["LIBRARY_FIXTURE = {"]
    for name, (v, _) in objects.items():
        c, s = bounds(v)
        lines.append('\t{ name = "%s", center = Vector3.new(%.5f, %.5f, %.5f), size = Vector3.new(%.5f, %.5f, %.5f) },' % (name, *c, *s))
    lines.append("}")
    lines.append(
        """
function makeLibrary(transform, scale)
	local storage = game:GetService("ServerStorage")
	local old = storage:FindFirstChild("IslandAssets")
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "IslandAssets"
	for _, f in ipairs(LIBRARY_FIXTURE) do
		local p = Instance.new("MeshPart")
		p.Name = f.name
		p.MeshId = "fixture://" .. f.name
		p.Size = f.size * scale
		p.CFrame = transform * CFrame.new(f.center * scale)
		p.Parent = m
	end
	m.Parent = storage
	return m
end
"""
    )
    return "\n".join(lines)


if __name__ == "__main__":
    print(fixture_luau(load(sys.argv[1])))
