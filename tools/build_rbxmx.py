#!/usr/bin/env python3
"""Pack src/IslandMapGenerator into a Roblox model file (dist/IslandMapGenerator.rbxmx).

In Studio: right-click ServerStorage > Insert from File... > pick the .rbxmx.
"""
import itertools
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src" / "IslandMapGenerator"
OUT = ROOT / "dist" / "IslandMapGenerator.rbxmx"

_ref = itertools.count()


def cdata(text: str) -> str:
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def item(cls: str, name: str, source: str | None, children: list[str], indent: int) -> str:
    pad = "\t" * indent
    props = [f'{pad}\t\t<string name="Name">{name}</string>']
    if source is not None:
        props.append(f'{pad}\t\t<ProtectedString name="Source">{cdata(source)}</ProtectedString>')
    if cls == "LocalScript":
        props.append(f'{pad}\t\t<bool name="Disabled">false</bool>')
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
        elif f.name.endswith(".luau") and f.name != "init.luau":
            out.append(item("ModuleScript", f.name[: -len(".luau")], f.read_text(), [], indent))
    return out


def main():
    root = item("ModuleScript", "IslandMapGenerator", (SRC / "init.luau").read_text(), build_dir(SRC, 2), 1)
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
        "\t<External>null</External>\n\t<External>nil</External>\n" + root + "\n</roblox>\n"
    )
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(xml, encoding="utf-8")
    print(f"wrote {OUT} ({len(xml) // 1024} KB)")


if __name__ == "__main__":
    main()
