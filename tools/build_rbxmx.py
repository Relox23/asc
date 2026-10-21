#!/usr/bin/env python3
"""Pack the Luau sources into Roblox model files.

  src/IslandMapGenerator -> dist/IslandMapGenerator.rbxmx
      In Studio: right-click ServerStorage > Insert from File... > pick the .rbxmx.
  src/IntroCutscene      -> dist/IntroCutscene.rbxmx
      In Studio: right-click ReplicatedStorage > Insert from File... > pick the .rbxmx
      (docs/intro/DESIGN.md §7). Its Server script has RunContext = Server, so it runs from
      ReplicatedStorage.

File naming: init.luau is the folder's ModuleScript itself, X.luau a ModuleScript,
X.client.luau a LocalScript, X.server.luau a Script with RunContext = Server.
"""
import itertools
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACKAGES = [
    (ROOT / "src" / "IslandMapGenerator", ROOT / "dist" / "IslandMapGenerator.rbxmx"),
    (ROOT / "src" / "IntroCutscene", ROOT / "dist" / "IntroCutscene.rbxmx"),
]
RUN_CONTEXT_SERVER = 1  # Enum.RunContext: Legacy 0, Server 1, Client 2, Plugin 3

_ref = itertools.count()


def cdata(text: str) -> str:
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def item(cls: str, name: str, source: str | None, children: list[str], indent: int, run_context: int | None = None) -> str:
    pad = "\t" * indent
    props = [f'{pad}\t\t<string name="Name">{name}</string>']
    if source is not None:
        props.append(f'{pad}\t\t<ProtectedString name="Source">{cdata(source)}</ProtectedString>')
    if cls in ("LocalScript", "Script"):
        props.append(f'{pad}\t\t<bool name="Disabled">false</bool>')
    if run_context is not None:
        props.append(f'{pad}\t\t<token name="RunContext">{run_context}</token>')
    body = "\n".join(props)
    kids = "\n".join(children)
    return (
        f'{pad}<Item class="{cls}" referent="RBX{next(_ref):08X}">\n'
        f"{pad}\t<Properties>\n{body}\n{pad}\t</Properties>\n"
        + (kids + "\n" if kids else "")
        + f"{pad}</Item>"
    )


def build_dir(path: pathlib.Path, indent: int) -> list[str]:
    out = []
    for f in sorted(path.iterdir()):
        if f.is_dir():
            out.append(item("Folder", f.name, None, build_dir(f, indent + 1), indent))
        elif f.name.endswith(".client.luau"):
            out.append(item("LocalScript", f.name[: -len(".client.luau")], f.read_text(), [], indent))
        elif f.name.endswith(".server.luau"):
            out.append(item("Script", f.name[: -len(".server.luau")], f.read_text(), [], indent, RUN_CONTEXT_SERVER))
        elif f.name.endswith(".luau") and f.name != "init.luau":
            out.append(item("ModuleScript", f.name[: -len(".luau")], f.read_text(), [], indent))
    return out


def build(src: pathlib.Path, out: pathlib.Path):
    root = item("ModuleScript", src.name, (src / "init.luau").read_text(), build_dir(src, 2), 1)
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
        "\t<External>null</External>\n\t<External>nil</External>\n" + root + "\n</roblox>\n"
    )
    out.parent.mkdir(exist_ok=True)
    out.write_text(xml, encoding="utf-8")
    print(f"wrote {out} ({len(xml) // 1024} KB)")


def main():
    for src, out in PACKAGES:
        if (src / "init.luau").exists():
            build(src, out)


if __name__ == "__main__":
    main()
