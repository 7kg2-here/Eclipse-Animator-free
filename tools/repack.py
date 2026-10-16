#!/usr/bin/env python3
"""repack.py — rebuild a Roblox binary model (``.rbxm``) from unpacked sources.

Sources edited in ``src/`` are written back into the binary file.  Only the
``Source`` property chunks that actually changed are re-encoded; every other
chunk is copied out of the source file byte-for-byte, so an edit to a script can
never disturb the rest of the model.

Usage::

    python3 tools/repack.py                      # src/ -> EclipseAnimator.rbxm
    python3 tools/repack.py --src src --out build.rbxm
    python3 tools/repack.py --full               # re-encode every chunk
    python3 tools/repack.py --verify-only        # just check src/ vs the model
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rbxm  # noqa: E402
from unpack import collect  # noqa: E402


def load_manifest(src_dir: str) -> dict:
    with open(os.path.join(src_dir, "manifest.json"), encoding="utf-8") as handle:
        return json.load(handle)


def read_sources(src_dir: str, manifest: dict):
    """referent -> source bytes (only for files that were found on disk)."""
    sources = {}
    missing = []
    for entry in manifest["scripts"]:
        path = os.path.join(src_dir, entry["file"])
        if not os.path.exists(path):
            missing.append(entry["file"])
            continue
        with open(path, "rb") as handle:
            sources[entry["referent"]] = handle.read()
    return sources, missing


def build_prop_chunk(model: rbxm.Model, record: rbxm.ClassRecord,
                     prop_name: str, values) -> bytes:
    body = bytearray()
    body += struct.pack("<I", record.class_id)
    name = prop_name.encode("utf-8")
    body += struct.pack("<I", len(name)) + name
    body.append(rbxm.T_STRING)
    body += rbxm.encode_property_values(rbxm.T_STRING, values)
    return bytes(body)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--src", default="src", help="unpacked source directory")
    parser.add_argument("--from", dest="source_file", default=None,
                        help="original .rbxm (defaults to manifest source_file)")
    parser.add_argument("--out", default="EclipseAnimator.rbxm", help="output .rbxm")
    parser.add_argument("--full", action="store_true",
                        help="re-encode every chunk instead of patching sources")
    parser.add_argument("--no-compress", action="store_true",
                        help="write chunk bodies uncompressed")
    parser.add_argument("--verify-only", action="store_true",
                        help="do not write a file, only report differences")
    args = parser.parse_args()

    manifest = load_manifest(args.src)
    source_file = args.source_file or manifest["source_file"]
    blob = rbxm.read_file(source_file)
    model = rbxm.decode_model(blob)
    paths, class_by_ref, props, _scripts = collect(model)

    sources, missing = read_sources(args.src, manifest)
    if missing:
        print("warning: %d source files are missing on disk, keeping the packed "
              "version for them (e.g. %s)" % (len(missing), missing[0]))

    changed = 0
    for entry in manifest["scripts"]:
        ref = entry["referent"]
        new = sources.get(ref)
        if new is None:
            continue
        old = props.get(ref, {}).get("Source")
        old_bytes = old[1] if old else b""
        if old_bytes != new:
            changed += 1
    print("%d/%d scripts differ from the packed model" % (changed, len(manifest["scripts"])))

    if args.verify_only:
        return 0

    if args.full:
        for record in model.classes:
            for prop in record.properties:
                if prop.name != "Source":
                    continue
                prop.values = [
                    rbxm.v_string(sources.get(ref, value[1]))
                    for ref, value in zip(record.referents, prop.values)
                ]
        out = rbxm.encode_model(model, compress=not args.no_compress)
    else:
        _, _, chunks = rbxm.read_chunks(blob)
        class_by_id = {record.class_id: record for record in model.classes}
        out_chunks = []
        for chunk in chunks:
            if chunk.name == rbxm.CHUNK_PROP:
                reader = rbxm.ByteReader(chunk.data)
                class_id = reader.u32()
                name = reader.string()
                if name == b"Source" and reader.remaining:
                    record = class_by_id[class_id]
                    values = [props.get(ref, {}).get("Source") for ref in record.referents]
                    new_values = [
                        rbxm.v_string(sources.get(ref, value[1]))
                        for ref, value in zip(record.referents, values)
                    ]
                    body = build_prop_chunk(model, record, "Source", new_values)
                    if body != chunk.data:
                        out_chunks.append(rbxm.Chunk(rbxm.CHUNK_PROP, body))
                        continue
            out_chunks.append(chunk)
        out = rbxm.write_chunks(model.class_count, model.instance_count,
                                out_chunks, compress=not args.no_compress)

    rbxm.write_file(args.out, out)

    # ---- verification: read the file we just wrote back in --------------
    check = rbxm.decode_model(out)
    check_paths, check_classes, check_props, _ = collect(check)
    problems = 0
    for entry in manifest["scripts"]:
        ref = entry["referent"]
        expected = sources.get(ref)
        if expected is None or check_classes.get(ref) != entry["class"]:
            if expected is not None:
                print("ERROR: class changed for %s" % entry["file"])
                problems += 1
            continue
        got = check_props.get(ref, {}).get("Source")
        if (got[1] if got else b"") != expected:
            print("ERROR: source mismatch after repack: %s" % entry["file"])
            problems += 1
    if check.parents != model.parents or check.shared_strings != model.shared_strings:
        print("ERROR: structure changed during repack")
        problems += 1

    print("wrote %s (%d bytes, %d scripts checked, %d problems)"
          % (args.out, len(out), len(manifest["scripts"]), problems))
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
