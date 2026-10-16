# tools/ — Eclipse Animator source toolkit

Small, dependency-free Python 3 tools that open the Roblox binary model format
so the plugin in this repository can be read, edited and rebuilt.

Nothing here needs a Roblox account, Roblox Studio, or any pip package (ZSTD
chunks, which this file does not use, would need `pip install zstandard`).

## Unpack the plugin

```bash
python3 tools/unpack.py Eclipse-Animator-inspect.rbxm src
```

* `src/**/*.luau` — every `Script`, `LocalScript` and `ModuleScript`
* `src/manifest.json` — referent, class, path, size and SHA-256 per script
* `src/_tree.txt` — the whole instance tree with class names

Add `--model-json` to dump **every instance and every property value** (frames,
colors, CFrames, UI layout, keyframe data, …) into `src/_model.json`.

## Edit and rebuild

```bash
python3 tools/repack.py                 # src/ -> EclipseAnimator.rbxm
python3 tools/repack.py --out build.rbxm
python3 tools/repack.py --verify-only   # report which scripts differ
python3 tools/repack.py --full          # re-encode every chunk, not only sources
python3 tools/repack.py --no-compress   # store chunk bodies uncompressed
```

`repack.py` writes a new `.rbxm` that Studio can load. In the default patch mode
only the `Source` chunks that changed are re-encoded; everything else is copied
out of the original file untouched, so an edit to one script cannot disturb the
rest of the model. Afterwards the tool reads its own output back and checks all
362 scripts, the parent/child hierarchy and the shared-string table.

Re-packing an unmodified `src/` reproduces the original file byte-for-byte.

## Inspecting the format directly

```python
import sys; sys.path.insert(0, "tools")
import rbxm

model = rbxm.decode_model(rbxm.read_file("Eclipse-Animator-inspect.rbxm"))
paths = rbxm.instance_paths(model)          # referent -> "Container/Modules/Foo"
props = rbxm.property_map(model)            # referent -> {property: value}
print(paths[0], sorted(props[0])[:5])

blob = rbxm.encode_model(model)             # back to .rbxm, byte-for-byte values
```

`rbxm.py` implements the full format: `META`, `SSTR`, `INST`, `PROP`, `PRNT`,
`END`; LZ4 and ZSTD chunk compression; and every property type the format
defines (`String`, `Bool`, `Int32/64`, `Float32/64`, `UDim`, `UDim2`, `Ray`,
`Faces`, `Axes`, `BrickColor`, `Color3`, `Color3uint8`, `Vector2/3`,
`Vector3int16`, `CFrame`, `OptionalCoordinateFrame`, `Enum`, `Ref`,
`NumberSequence`, `ColorSequence`, `NumberRange`, `Rect`, `PhysicalProperties`,
`SharedString`, `Bytecode`, `UniqueId`, `Font`, `SecurityCapabilities`,
`Content`) including the integer transformation, byte interleaving, the
big-endian Roblox float layout and accumulative referent arrays.

Every chunk is checked to be consumed exactly while decoding, so a successful
decode is itself a proof that the file was parsed correctly.
