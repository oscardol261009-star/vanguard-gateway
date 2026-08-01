#!/usr/bin/env python3
"""
Génère AdvancedPhysics.rbxmx : un modèle Roblox unique contenant toute
l'arborescence, à glisser dans Studio sans installer Rojo.

    python3 tools/build-rbxmx.py

Le .rbxmx est du XML : chaque ModuleScript est un <Item class="ModuleScript">
dont la source vit dans une propriété ProtectedString "Source".

À relancer après toute modification des fichiers .luau.
"""

import os
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHARED = os.path.join(ROOT, "src", "shared", "AdvancedPhysics")

# Arborescence à reproduire dans Studio.
# ("nom", "classe", "chemin source ou None", [enfants])
TREE = (
    "AdvancedPhysics_Install",
    "Folder",
    None,
    [
        (
            "AdvancedPhysics",
            "ModuleScript",
            os.path.join(SHARED, "init.luau"),
            [
                ("Config", "ModuleScript", os.path.join(SHARED, "Config.luau"), []),
                ("Types", "ModuleScript", os.path.join(SHARED, "Types.luau"), []),
                (
                    "Util",
                    "Folder",
                    None,
                    [
                        ("VectorUtil", "ModuleScript", os.path.join(SHARED, "Util", "VectorUtil.luau"), []),
                        ("RaycastUtil", "ModuleScript", os.path.join(SHARED, "Util", "RaycastUtil.luau"), []),
                        ("Spring", "ModuleScript", os.path.join(SHARED, "Util", "Spring.luau"), []),
                    ],
                ),
                (
                    "Solvers",
                    "Folder",
                    None,
                    [
                        ("Integrator", "ModuleScript", os.path.join(SHARED, "Solvers", "Integrator.luau"), []),
                        ("Aerodynamics", "ModuleScript", os.path.join(SHARED, "Solvers", "Aerodynamics.luau"), []),
                        ("Buoyancy", "ModuleScript", os.path.join(SHARED, "Solvers", "Buoyancy.luau"), []),
                    ],
                ),
                (
                    "Modules",
                    "Folder",
                    None,
                    [
                        ("GravityField", "ModuleScript", os.path.join(SHARED, "Modules", "GravityField.luau"), []),
                        (
                            "CharacterController",
                            "ModuleScript",
                            os.path.join(SHARED, "Modules", "CharacterController.luau"),
                            [],
                        ),
                        (
                            "AnimationController",
                            "ModuleScript",
                            os.path.join(SHARED, "Modules", "AnimationController.luau"),
                            [],
                        ),
                        ("CameraEffects", "ModuleScript", os.path.join(SHARED, "Modules", "CameraEffects.luau"), []),
                        (
                            "FirstPersonView",
                            "ModuleScript",
                            os.path.join(SHARED, "Modules", "FirstPersonView.luau"),
                            [],
                        ),
                        (
                            "ProjectileSystem",
                            "ModuleScript",
                            os.path.join(SHARED, "Modules", "ProjectileSystem.luau"),
                            [],
                        ),
                        (
                            "VehicleController",
                            "ModuleScript",
                            os.path.join(SHARED, "Modules", "VehicleController.luau"),
                            [],
                        ),
                        ("VerletRope", "ModuleScript", os.path.join(SHARED, "Modules", "VerletRope.luau"), []),
                        ("ForceEffects", "ModuleScript", os.path.join(SHARED, "Modules", "ForceEffects.luau"), []),
                    ],
                ),
            ],
        ),
        (
            "PhysicsServer",
            "Script",
            os.path.join(ROOT, "src", "server", "PhysicsServer.server.luau"),
            [],
        ),
        (
            "PhysicsClient",
            "LocalScript",
            os.path.join(ROOT, "src", "client", "PhysicsClient.client.luau"),
            [],
        ),
    ],
)

_counter = 0


def next_referent():
    global _counter
    _counter += 1
    return f"RBX{_counter}"


def build_item(parent, node):
    name, class_name, source_path, children = node

    item = ET.SubElement(parent, "Item", {"class": class_name, "referent": next_referent()})
    properties = ET.SubElement(item, "Properties")

    name_element = ET.SubElement(properties, "string", {"name": "Name"})
    name_element.text = name

    if source_path:
        with open(source_path, "r", encoding="utf-8") as handle:
            source = handle.read()
        if "]]>" in source:
            raise SystemExit(f"{source_path} contient ']]>' : impossible de l'encoder en CDATA")
        source_element = ET.SubElement(properties, "ProtectedString", {"name": "Source"})
        # marqueur remplacé par un bloc CDATA après sérialisation
        source_element.text = f"\x00CDATA\x00{source}\x00ENDCDATA\x00"

    for child in children:
        build_item(item, child)

    return item


def main():
    root = ET.Element(
        "roblox",
        {
            "xmlns:xmime": "http://www.w3.org/2005/05/xmlmime",
            "xmlns:xsi": "http://www.w3.org/2001/XMLSchema-instance",
            "xsi:noNamespaceSchemaLocation": "http://www.roblox.com/roblox.xsd",
            "version": "4",
        },
    )
    ET.SubElement(root, "External").text = "null"
    ET.SubElement(root, "External").text = "nil"

    build_item(root, TREE)

    xml = ET.tostring(root, encoding="unicode")

    # ElementTree échappe le texte ; on restaure les blocs CDATA bruts.
    xml = xml.replace("\x00CDATA\x00", "<![CDATA[").replace("\x00ENDCDATA\x00", "]]>")

    # Les entités introduites par ElementTree à l'intérieur des CDATA doivent
    # être re-converties, sinon le code Luau arrive avec des &lt; à la place des <.
    out = []
    index = 0
    while True:
        start = xml.find("<![CDATA[", index)
        if start == -1:
            out.append(xml[index:])
            break
        end = xml.find("]]>", start)
        out.append(xml[index:start])
        block = xml[start + 9 : end]
        block = block.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"').replace("&amp;", "&")
        out.append("<![CDATA[" + block + "]]>")
        index = end + 3
    xml = "".join(out)

    destination = os.path.join(ROOT, "AdvancedPhysics.rbxmx")
    with open(destination, "w", encoding="utf-8") as handle:
        handle.write('<?xml version="1.0" encoding="utf-8"?>\n')
        handle.write(xml)
        handle.write("\n")

    print(f"écrit : {destination} ({os.path.getsize(destination)} octets, {_counter} instances)")


if __name__ == "__main__":
    sys.exit(main())
