#!/usr/bin/env python3
"""Bundle the generator modules + the Roblox mock into one Luau file so it can
run under the standalone `luau` interpreter for testing.

usage: bundle.py <driver.luau> <out.luau>
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src" / "IslandMapGenerator"
MOCK = ROOT / "tools" / "mock" / "roblox_mock.luau"


def long_string(text: str) -> str:
    level = 1
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{text}]{eq}]"


def module_entries():
    """Yield (path inside the generator, kind, file) for every source file."""
    for f in sorted(SRC.rglob("*.luau")):
        rel = f.relative_to(SRC)
        parts = list(rel.parts)
        name = parts[-1]
        if name == "init.luau":
            parts = parts[:-1]
            kind = "ModuleScript"
        elif name.endswith(".client.luau"):
            parts[-1] = name[: -len(".client.luau")]
            kind = "LocalScript"
        else:
            parts[-1] = name[: -len(".luau")]
            kind = "ModuleScript"
        yield "/".join(parts), kind, f


def main():
    driver = pathlib.Path(sys.argv[1]).read_text()
    out = pathlib.Path(sys.argv[2])
    chunks = ["--!nocheck", "local MOCK = (function()", MOCK.read_text(), "end)()", "local SOURCES = {}", "local KINDS = {}"]
    for path, kind, f in module_entries():
        chunks.append(f"KINDS[{path!r}] = {kind!r}")
        if kind == "ModuleScript":
            chunks.append(f"SOURCES[{path!r}] = function(script, require)\n{f.read_text()}\nend")
        else:
            chunks.append(f"SOURCES[{path!r}] = {long_string(f.read_text())}")
    chunks.append(
        r'''
-- Build the instance tree in ServerStorage, like inserting the .rbxmx
local ServerStorage = game:GetService("ServerStorage")
local root = Instance.new("ModuleScript")
root.Name = "IslandMapGenerator"
root:SetAttribute("__path", "")
root.Parent = ServerStorage
local byPath = { [""] = root }
local paths = {}
for p in pairs(KINDS) do table.insert(paths, p) end
table.sort(paths, function(a, b)
	local _, ca = a:gsub("/", "")
	local _, cb = b:gsub("/", "")
	if ca ~= cb then return ca < cb end
	return a < b
end)
local function ensureFolder(path)
	if byPath[path] then return byPath[path] end
	local parentPath, name = path:match("^(.*)/([^/]+)$")
	if not parentPath then parentPath, name = "", path end
	local parent = ensureFolder(parentPath)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	byPath[path] = f
	return f
end
for _, p in ipairs(paths) do
	if p ~= "" then
		local parentPath, name = p:match("^(.*)/([^/]+)$")
		if not parentPath then parentPath, name = "", p end
		local parent = ensureFolder(parentPath)
		local inst = Instance.new(KINDS[p])
		inst.Name = name
		inst:SetAttribute("__path", p)
		if KINDS[p] == "LocalScript" then inst.Source = SOURCES[p] end
		inst.Parent = parent
		byPath[p] = inst
	end
end
local cache = {}
local loading = {}
local function mockRequire(inst)
	local p = inst:GetAttribute("__path")
	assert(p ~= nil, "require of a non-module")
	if cache[p] ~= nil then return cache[p] end
	assert(not loading[p], "circular require: " .. p)
	loading[p] = true
	local fn = SOURCES[p]
	local result = fn(inst, mockRequire)
	loading[p] = nil
	cache[p] = result
	return result
end
GENERATOR = root
mockRequire = mockRequire
'''
    )
    chunks.append(driver)
    out.write_text("\n".join(chunks))


if __name__ == "__main__":
    main()
