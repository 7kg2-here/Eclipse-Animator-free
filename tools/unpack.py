#!/usr/bin/env python3
"""unpack.py — turn a Roblox binary model (``.rbxm``) into plain, editable files.

Everything the file contains becomes ordinary text on disk:

* one ``.luau`` file per ``Script`` / ``LocalScript`` / ``ModuleScript``,
  laid out as a directory tree that mirrors the plugin hierarchy
* ``manifest.json`` — referent, class, path and checksum of every script, so the
  model can be packed back up (``repack.py``) or diffed
* ``_tree.txt`` — the full instance tree with class names
* optionally ``_model.json`` — every instance and every property value

Usage::

    python3 tools/unpack.py Eclipse-Animator-inspect.rbxm src
    python3 tools/unpack.py Eclipse-Animator-inspect.rbxm src --model-json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rbxm  # noqa: E402

SCRIPT_CLASSES = {"Script", "LocalScript", "ModuleScript"}
BAD_CHARS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


def safe_name(name: str) -> str:
    cleaned = BAD_CHARS.sub("_", name).strip().rstrip(".")
    return cleaned or "unnamed"


def script_extension(class_name: str) -> str:
    return ".server.luau" if class_name == "Script" else ".luau"


def collect(model: rbxm.Model):
    """Return ``(paths, classes_by_ref, properties_by_ref, scripts)``."""
    paths = rbxm.instance_paths(model)
    props = rbxm.property_map(model)
    class_by_ref = {}
    for record in model.classes:
        for ref in record.referents:
            class_by_ref[ref] = record.name
    scripts = [
        (ref, class_by_ref[ref])
        for ref in sorted(paths)
        if class_by_ref.get(ref) in SCRIPT_CLASSES
    ]
    return paths, class_by_ref, props, scripts


def write_tree(model: rbxm.Model, paths, class_by_ref, target: str) -> None:
    children = {}
    for child, parent in model.prnt_pairs:
        children.setdefault(parent, []).append(child)
    lines = []

    def walk(ref: int, depth: int) -> None:
        name = paths[ref].split("/")[-1]
        lines.append("%s%s (%s)" % ("    " * depth, name, class_by_ref[ref]))
        for kid in children.get(ref, []):
            walk(kid, depth + 1)

    for child, parent in model.prnt_pairs:
        if parent == -1:
            walk(child, 0)
    with open(target, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input", help="binary .rbxm/.rbxl file")
    parser.add_argument("output", help="directory for the unpacked source tree")
    parser.add_argument("--model-json", action="store_true",
                        help="also dump every instance and property to _model.json")
    parser.add_argument("--no-sources", action="store_true",
                        help="only write manifest/tree, skip script sources")
    args = parser.parse_args()

    blob = rbxm.read_file(args.input)
    model = rbxm.decode_model(blob)
    paths, class_by_ref, props, scripts = collect(model)

    os.makedirs(args.output, exist_ok=True)
    entries = []
    used = set()

    for ref, class_name in scripts:
        path = paths[ref]
        parts = [safe_name(part) for part in path.split("/")]
        directory = os.path.join(args.output, *parts[:-1])
        stem = safe_name(parts[-1]) + script_extension(class_name)
        target = os.path.join(directory, stem)
        suffix = 2
        while target in used:
            target = os.path.join(directory, "%s_%d%s" % (
                safe_name(parts[-1]), suffix, script_extension(class_name)))
            suffix += 1
        used.add(target)
        source = props.get(ref, {}).get("Source")
        raw = source[1] if source else b""
        if not args.no_sources:
            os.makedirs(directory, exist_ok=True)
            with open(target, "wb") as handle:
                handle.write(raw)
        entries.append({
            "referent": ref,
            "class": class_name,
            "path": path,
            "name": parts[-1],
            "file": os.path.relpath(target, args.output),
            "bytes": len(raw),
            "sha256": hashlib.sha256(raw).hexdigest(),
        })

    manifest = {
        "source_file": os.path.basename(args.input),
        "generated_by": "tools/unpack.py",
        "instances": model.instance_count,
        "classes": len(model.classes),
        "shared_strings": len(model.shared_strings),
        "metadata": [[k.decode("utf-8", "replace"), v.decode("utf-8", "replace")]
                     for k, v in model.metadata],
        "scripts": entries,
    }
    with open(os.path.join(args.output, "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1, ensure_ascii=False)
        handle.write("\n")
    write_tree(model, paths, class_by_ref, os.path.join(args.output, "_tree.txt"))

    if args.model_json:
        dump = []
        for ref in sorted(paths):
            record = {
                "referent": ref,
                "class": class_by_ref[ref],
                "path": paths[ref],
                "parent": model.parents.get(ref, -1),
                "properties": {},
            }
            for name, value in sorted(props.get(ref, {}).items()):
                record["properties"][name] = rbxm.to_jsonable(value)
            dump.append(record)
        with open(os.path.join(args.output, "_model.json"), "w", encoding="utf-8") as handle:
            json.dump(dump, handle, indent=1, ensure_ascii=False)

    total = sum(entry["bytes"] for entry in entries)
    print("unpacked %d scripts (%d bytes) from %d instances into %s"
          % (len(entries), total, model.instance_count, args.output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
