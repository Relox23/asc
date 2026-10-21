#!/usr/bin/env python3
"""Bundle the Luau sources + the Roblox mock into one Luau file so it can run
under the standalone `luau` interpreter for testing.

usage: bundle.py <driver.luau> <out.luau>

Source trees (each becomes an instance tree like inserting the .rbxmx):
  src/IslandMapGenerator -> ServerStorage.IslandMapGenerator   (global GENERATOR)
  src/IntroCutscene      -> ReplicatedStorage.IntroCutscene     (global INTRO, nil if the folder is missing)

`init.luau` is the tree's root ModuleScript, `X.luau` a ModuleScript,
`X.client.luau` a LocalScript and `X.server.luau` a Script with
RunContext = Server. Globals for drivers:
  mockRequire(moduleScript)  require() as the modules see it
  runScript(script, force)   runs a bundled Script/LocalScript like the engine
                             would (new thread, client/server context); returns
                             the thread, or nil if Roblox wouldn't run it there
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOCK = ROOT / "tools" / "mock" / "roblox_mock.luau"

# (directory, root instance name, service, key prefix, driver global)
TREES = [
    (ROOT / "src" / "IslandMapGenerator", "IslandMapGenerator", "ServerStorage", "", "GENERATOR"),
    (ROOT / "src" / "IntroCutscene", "IntroCutscene", "ReplicatedStorage", "@IntroCutscene", "INTRO"),
]


def long_string(text: str) -> str:
    level = 1
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{text}]{eq}]"


def module_entries(src: pathlib.Path, prefix: str):
    """Yield (key, kind, file) for every source file of one tree.

    Keys are the instance path inside the tree joined with "/", prefixed for
    every tree but the generator (whose keys stay exactly as before)."""
    for f in sorted(src.rglob("*.luau")):
        rel = f.relative_to(src)
        parts = list(rel.parts)
        name = parts[-1]
        if name == "init.luau":
            parts = parts[:-1]
            kind = "ModuleScript"
        elif name.endswith(".client.luau"):
            parts[-1] = name[: -len(".client.luau")]
            kind = "LocalScript"
        elif name.endswith(".server.luau"):
            parts[-1] = name[: -len(".server.luau")]
            kind = "Script"
        else:
            parts[-1] = name[: -len(".luau")]
            kind = "ModuleScript"
        key = "/".join(parts)
        if prefix:
            key = prefix + ("/" + key if key else "")
        yield key, kind, f


BUILD = r'''
-- Build the instance trees, like inserting the .rbxmx files
local function buildTree(prefix, rootName, serviceName)
	local keys = {}
	for k, tp in pairs(TREE_OF) do
		if tp == prefix then
			table.insert(keys, k)
		end
	end
	if #keys == 0 then
		return nil
	end
	local service = game:GetService(serviceName)
	local root = Instance.new(KINDS[prefix] or "Folder")
	root.Name = rootName
	root:SetAttribute("__path", prefix)
	root.Parent = service
	local byPath = { [prefix] = root }
	table.sort(keys, function(a, b)
		local _, ca = a:gsub("/", "")
		local _, cb = b:gsub("/", "")
		if ca ~= cb then
			return ca < cb
		end
		return a < b
	end)
	local function split(path)
		local parentPath, name = path:match("^(.*)/([^/]+)$")
		if not parentPath then
			parentPath, name = "", path
		end
		return parentPath, name
	end
	local function ensureFolder(path)
		if byPath[path] then
			return byPath[path]
		end
		local parentPath, name = split(path)
		local parent = ensureFolder(parentPath)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
		byPath[path] = f
		return f
	end
	for _, p in ipairs(keys) do
		if p ~= prefix then
			local parentPath, name = split(p)
			local parent = ensureFolder(parentPath)
			local inst = Instance.new(KINDS[p])
			inst.Name = name
			inst:SetAttribute("__path", p)
			if KINDS[p] ~= "ModuleScript" then
				inst.Source = SOURCES[p]
			end
			if KINDS[p] == "Script" then
				inst.RunContext = Enum.RunContext.Server
			end
			inst.Parent = parent
			byPath[p] = inst
		end
	end
	return root
end
local cache = {}
local loading = {}
local function mockRequire(inst)
	assert(MOCK.isInstance(inst), "require expects a ModuleScript, got " .. typeof(inst))
	local provided = MOCK.mockModuleOf(inst)
	if provided then
		if cache[inst] == nil then
			cache[inst] = provided()
		end
		return cache[inst]
	end
	assert(inst:IsA("ModuleScript"), "require expects a ModuleScript, got " .. inst.ClassName .. " " .. inst:GetFullName())
	local p = inst:GetAttribute("__path")
	assert(p ~= nil, "require of a non-module")
	if cache[p] ~= nil then
		return cache[p]
	end
	assert(not loading[p], "circular require: " .. p)
	loading[p] = true
	local fn = SOURCES[p]
	local result = fn(inst, mockRequire)
	loading[p] = nil
	if result == nil then
		error("Module code did not return exactly one value: " .. inst:GetFullName())
	end
	cache[p] = result
	return result
end
local function runScript(inst, force)
	local p = inst:GetAttribute("__path")
	local body = p and SCRIPTS[p]
	assert(body, "runScript: no bundled source for " .. inst:GetFullName())
	return MOCK.startScript(inst, function()
		body(inst, mockRequire)
	end, force)
end
'''


def main():
    driver = pathlib.Path(sys.argv[1]).read_text()
    out = pathlib.Path(sys.argv[2])
    chunks = [
        "--!nocheck",
        "local MOCK = (function()",
        MOCK.read_text(),
        "end)()",
        "local SOURCES = {}",
        "local SCRIPTS = {}",
        "local KINDS = {}",
        "local TREE_OF = {}",
    ]
    present = []
    for src, root_name, service, prefix, glob in TREES:
        if not src.is_dir():
            continue
        entries = list(module_entries(src, prefix))
        if not entries:
            continue
        present.append((prefix, root_name, service, glob))
        for key, kind, f in entries:
            text = f.read_text()
            chunks.append(f"KINDS[{key!r}] = {kind!r}")
            chunks.append(f"TREE_OF[{key!r}] = {prefix!r}")
            if kind == "ModuleScript":
                chunks.append(f"SOURCES[{key!r}] = function(script, require)\n{text}\nend")
            else:
                chunks.append(f"SOURCES[{key!r}] = {long_string(text)}")
                chunks.append(f"SCRIPTS[{key!r}] = function(script, require)\n{text}\nend")
    chunks.append(BUILD)
    for prefix, root_name, service, glob in present:
        if glob == "GENERATOR":
            chunks.append(f"{glob} = buildTree({prefix!r}, {root_name!r}, {service!r})")
        else:
            # trees after the generator don't count towards the generator's instance statistics
            chunks.append(
                "do\n"
                "\tlocal n, counts = MOCK.instanceCount, table.clone(MOCK.classCounts)\n"
                f"\t{glob} = buildTree({prefix!r}, {root_name!r}, {service!r})\n"
                "\tMOCK.instanceCount, MOCK.classCounts = n, counts\n"
                "end"
            )
    chunks.append("mockRequire = mockRequire\nrunScript = runScript")
    chunks.append(driver)
    out.write_text("\n".join(chunks))


if __name__ == "__main__":
    main()
