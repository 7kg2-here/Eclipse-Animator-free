"""
rbxm.py — a complete, dependency-free reader/writer for the Roblox binary model
format (``.rbxm`` / ``.rbxl``), written for the Eclipse Animator source archive.

Nothing about the format is hidden: every chunk is decompressed (LZ4 or ZSTD),
every property type is decoded and re-encoded, so a ``.rbxm`` can be turned into
plain readable files (``unpack.py``) and rebuilt after editing (``repack.py``).

Format reference: rojo-rbx/rbx-dom ``docs/binary.md`` (unofficial spec).
"""

from __future__ import annotations

import base64
import hashlib
import json
import struct
import zlib
from typing import Any, Dict, List, Optional, Sequence, Tuple

# --------------------------------------------------------------------------
# file header / chunk framing
# --------------------------------------------------------------------------

MAGIC = b"<roblox!\x89\xff\r\n\x1a\n\x00\x00"
END_MAGIC = b"</roblox>"

ZSTD_MAGIC = b"\x28\xb5\x2f\xfd"

CHUNK_META = "META"
CHUNK_SSTR = "SSTR"
CHUNK_INST = "INST"
CHUNK_PROP = "PROP"
CHUNK_PRNT = "PRNT"
CHUNK_END = "END"


class RbxmError(Exception):
    pass


# --------------------------------------------------------------------------
# LZ4 block codec (the format Roblox uses inside chunk payloads)
# --------------------------------------------------------------------------

def lz4_decompress(src: bytes, expected: Optional[int] = None) -> bytes:
    out = bytearray()
    i = 0
    n = len(src)
    while i < n:
        token = src[i]
        i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                b = src[i]
                i += 1
                lit += b
                if b != 255:
                    break
        out += src[i:i + lit]
        i += lit
        if i >= n:
            break
        offset = src[i] | (src[i + 1] << 8)
        i += 2
        if offset == 0 or offset > len(out):
            raise RbxmError("corrupt LZ4 stream (bad offset)")
        match = (token & 0xF) + 4
        if (token & 0xF) == 15:
            while True:
                b = src[i]
                i += 1
                match += b
                if b != 255:
                    break
        start = len(out) - offset
        for k in range(match):
            out.append(out[start + k])
    if expected is not None and len(out) != expected:
        raise RbxmError(
            "LZ4 length mismatch: got %d, expected %d" % (len(out), expected)
        )
    return bytes(out)


def lz4_compress(src: bytes) -> bytes:
    """Emit a valid LZ4 block.  Offsets stay inside the 64 KiB window and the
    last 12 bytes are always literals, as the LZ4 block format requires."""
    n = len(src)
    out = bytearray()
    mask = (1 << 16) - 1

    def write_lengths(token_pos: int, value: int, shift: int) -> None:
        if value >= 15:
            out[token_pos] |= 15 << shift
            rest = value - 15
            while rest >= 255:
                out.append(255)
                rest -= 255
            out.append(rest)
        else:
            out[token_pos] |= value << shift

    if n >= 13:
        table: Dict[int, List[int]] = {}
        anchor = 0
        i = 0
        limit = n - 12
        while i < limit:
            seq = src[i:i + 4]
            h = ((int.from_bytes(seq, "little") * 2654435761) & 0xFFFFFFFF) >> 16
            h &= mask
            bucket = table.get(h)
            cand = -1
            if bucket:
                # keep the most recent candidates only; longest match wins
                best_len = 0
                for previous in bucket:
                    if 0 < i - previous <= 65535 and src[previous:previous + 4] == seq:
                        length = 4
                        while (
                            i + length < n - 1
                            and src[previous + length] == src[i + length]
                            and length < 65535 + 18
                        ):
                            length += 1
                        if length > best_len:
                            best_len = length
                            cand = previous
                bucket.insert(0, i)
                del bucket[4:]
            else:
                table[h] = [i]
            if cand >= 0 and 0 < i - cand <= 65535 and src[cand:cand + 4] == seq:
                match_len = 4
                while (
                    i + match_len < n - 1
                    and src[cand + match_len] == src[i + match_len]
                    and match_len < 65535 + 18
                ):
                    match_len += 1
                token_pos = len(out)
                out.append(0)
                write_lengths(token_pos, i - anchor, 4)
                out.extend(src[anchor:i])
                offset = i - cand
                out.append(offset & 0xFF)
                out.append((offset >> 8) & 0xFF)
                write_lengths(token_pos, match_len - 4, 0)
                i += match_len
                anchor = i
            else:
                i += 1
    else:
        anchor = 0

    token_pos = len(out)
    out.append(0)
    write_lengths(token_pos, n - anchor, 4)
    out.extend(src[anchor:])
    return bytes(out)


def _zstd_decompress(data: bytes, expected: int) -> bytes:
    for mod in ("zstandard", "pyzstd"):
        try:
            if mod == "zstandard":
                import zstandard  # type: ignore

                return zstandard.ZstdDecompressor().decompress(
                    data, max_output_size=expected
                )
            import pyzstd  # type: ignore

            return pyzstd.decompress(data)
        except ImportError:
            continue
    raise RbxmError(
        "chunk uses ZSTD compression; install 'zstandard' (pip install zstandard)"
    )


class Chunk:
    """A chunk plus, optionally, its original compressed payload.

    ``packed`` lets tools copy untouched chunks byte-for-byte out of the source
    file instead of re-compressing them.
    """

    __slots__ = ("name", "data", "packed")

    def __init__(self, name: str, data: bytes, packed: Optional[bytes] = None):
        self.name = name
        self.data = data
        self.packed = packed

    def __repr__(self) -> str:  # pragma: no cover - debug helper
        return "Chunk(%r, %d bytes)" % (self.name, len(self.data))


def read_chunks(blob: bytes):
    """Return ``(class_count, instance_count, chunks)`` for a binary model."""
    if blob[:16] != MAGIC:
        raise RbxmError("not a binary Roblox model (bad magic)")
    class_count, instance_count = struct.unpack_from("<II", blob, 16)
    pos = 32
    chunks: List[Chunk] = []
    while pos < len(blob):
        name = blob[pos:pos + 4].decode("latin-1").rstrip("\0")
        comp_len, uncomp_len, _reserved = struct.unpack_from("<III", blob, pos + 4)
        pos += 16
        body_len = comp_len if comp_len != 0 else uncomp_len
        body = blob[pos:pos + body_len]
        pos += body_len
        if name == CHUNK_END:
            chunks.append(Chunk(name, body))
            break
        if comp_len == 0:
            data = body
            packed = None
        else:
            packed = body
            if body[:4] == ZSTD_MAGIC:
                data = _zstd_decompress(body, uncomp_len)
            else:
                data = lz4_decompress(body, uncomp_len)
        chunks.append(Chunk(name, data, packed))
    return class_count, instance_count, chunks


def write_chunks(
    class_count: int,
    instance_count: int,
    chunks: Sequence[Chunk],
    compress: bool = True,
) -> bytes:
    out = bytearray(MAGIC)
    out += struct.pack("<II", class_count, instance_count) + b"\0" * 8
    for chunk in chunks:
        body = chunk.data
        payload = chunk.packed
        if payload is None and compress and chunk.name != CHUNK_END and len(body) > 16:
            packed = lz4_compress(body)
            if len(packed) < len(body):
                payload = packed
        if payload is None:
            out += chunk.name.encode("latin-1").ljust(4, b"\0")
            out += struct.pack("<III", 0, len(body), 0)
            out += body
        else:
            out += chunk.name.encode("latin-1").ljust(4, b"\0")
            out += struct.pack("<III", len(payload), len(body), 0)
            out += payload
    return bytes(out)


# --------------------------------------------------------------------------
# primitive codecs
# --------------------------------------------------------------------------

def untransform_i32(value: int) -> int:
    return (value >> 1) ^ -(value & 1)


def transform_i32(value: int) -> int:
    return ((value << 1) ^ (value >> 31)) & 0xFFFFFFFF


def untransform_i64(value: int) -> int:
    return (value >> 1) ^ -(value & 1)


def transform_i64(value: int) -> int:
    return ((value << 1) ^ (value >> 63)) & 0xFFFFFFFFFFFFFFFF


def _as_i64(value: int) -> int:
    """Interpret a Python int as a signed 64-bit value."""
    value &= 0xFFFFFFFFFFFFFFFF
    return value - (1 << 64) if value >= (1 << 63) else value


def roblox_f32(bits_be: int) -> float:
    """Roblox stores f32 with the sign bit last; ``bits_be`` are the 4 bytes
    read big-endian from the file."""
    ieee = ((bits_be >> 1) | ((bits_be & 1) << 31)) & 0xFFFFFFFF
    return struct.unpack(">f", struct.pack(">I", ieee))[0]


def roblox_f32_bits(value: float) -> int:
    ieee = struct.unpack(">I", struct.pack(">f", value))[0]
    return ((ieee << 1) | (ieee >> 31)) & 0xFFFFFFFF


def _column_major(items: Sequence[bytes]) -> bytes:
    """Interleave an array of equally sized byte strings, column by column."""
    if not items:
        return b""
    width = len(items[0])
    out = bytearray()
    for column in range(width):
        for item in items:
            out.append(item[column])
    return bytes(out)


def _deinterleave(data: bytes, pos: int, count: int, width: int) -> List[bytes]:
    out = []
    for row in range(count):
        out.append(bytes(data[pos + column * count + row] for column in range(width)))
    return out


# --------------------------------------------------------------------------
# property type ids
# --------------------------------------------------------------------------

T_STRING = 0x01
T_BOOL = 0x02
T_INT32 = 0x03
T_FLOAT32 = 0x04
T_FLOAT64 = 0x05
T_UDIM = 0x06
T_UDIM2 = 0x07
T_RAY = 0x08
T_FACES = 0x09
T_AXES = 0x0A
T_BRICKCOLOR = 0x0B
T_COLOR3 = 0x0C
T_VECTOR2 = 0x0D
T_VECTOR3 = 0x0E
T_CFRAME = 0x10
T_ENUM = 0x12
T_REF = 0x13
T_VECTOR3INT16 = 0x14
T_NUMBERSEQUENCE = 0x15
T_COLORSEQUENCE = 0x16
T_NUMBERRANGE = 0x17
T_RECT = 0x18
T_PHYSICALPROPERTIES = 0x19
T_COLOR3UINT8 = 0x1A
T_INT64 = 0x1B
T_SHAREDSTRING = 0x1C
T_BYTECODE = 0x1D
T_OPTIONAL_CFRAME = 0x1E
T_UNIQUEID = 0x1F
T_FONT = 0x20
T_SECURITYCAPABILITIES = 0x21
T_CONTENT = 0x22

TYPE_NAMES = {
    T_STRING: "String", T_BOOL: "Bool", T_INT32: "Int32", T_FLOAT32: "Float32",
    T_FLOAT64: "Float64", T_UDIM: "UDim", T_UDIM2: "UDim2", T_RAY: "Ray",
    T_FACES: "Faces", T_AXES: "Axes", T_BRICKCOLOR: "BrickColor",
    T_COLOR3: "Color3", T_VECTOR2: "Vector2", T_VECTOR3: "Vector3",
    T_CFRAME: "CFrame", T_ENUM: "Enum", T_REF: "Ref",
    T_VECTOR3INT16: "Vector3int16", T_NUMBERSEQUENCE: "NumberSequence",
    T_COLORSEQUENCE: "ColorSequence", T_NUMBERRANGE: "NumberRange",
    T_RECT: "Rect", T_PHYSICALPROPERTIES: "PhysicalProperties",
    T_COLOR3UINT8: "Color3uint8", T_INT64: "Int64",
    T_SHAREDSTRING: "SharedString", T_BYTECODE: "Bytecode",
    T_OPTIONAL_CFRAME: "OptionalCoordinateFrame", T_UNIQUEID: "UniqueId",
    T_FONT: "Font", T_SECURITYCAPABILITIES: "SecurityCapabilities",
    T_CONTENT: "Content",
}

# CFrame rotation presets (id -> 3x3 matrix, row per axis vector).
BASIC_ROTATIONS: Dict[int, Tuple[Tuple[float, ...], ...]] = {
    0x02: ((1, 0, 0), (0, 1, 0), (0, 0, 1)),
    0x03: ((1, 0, 0), (0, 0, -1), (0, 1, 0)),
    0x05: ((1, 0, 0), (0, -1, 0), (0, 0, -1)),
    0x06: ((1, 0, 0), (0, 0, 1), (0, -1, 0)),
    0x07: ((0, 1, 0), (1, 0, 0), (0, 0, -1)),
    0x09: ((0, 0, 1), (1, 0, 0), (0, 1, 0)),
    0x0A: ((0, -1, 0), (1, 0, 0), (0, 0, 1)),
    0x0C: ((0, 0, -1), (1, 0, 0), (0, -1, 0)),
    0x0D: ((0, 1, 0), (0, 0, 1), (1, 0, 0)),
    0x0E: ((0, 0, -1), (0, 1, 0), (1, 0, 0)),
    0x10: ((0, -1, 0), (0, 0, -1), (1, 0, 0)),
    0x11: ((0, 0, 1), (0, -1, 0), (1, 0, 0)),
    0x14: ((-1, 0, 0), (0, 1, 0), (0, 0, -1)),
    0x15: ((-1, 0, 0), (0, 0, 1), (0, 1, 0)),
    0x17: ((-1, 0, 0), (0, -1, 0), (0, 0, 1)),
    0x18: ((-1, 0, 0), (0, 0, -1), (0, -1, 0)),
    0x19: ((0, 1, 0), (-1, 0, 0), (0, 0, 1)),
    0x1B: ((0, 0, -1), (-1, 0, 0), (0, 1, 0)),
    0x1C: ((0, -1, 0), (-1, 0, 0), (0, 0, -1)),
    0x1E: ((0, 0, 1), (-1, 0, 0), (0, -1, 0)),
    0x1F: ((0, 1, 0), (0, 0, -1), (-1, 0, 0)),
    0x20: ((0, 0, 1), (0, 1, 0), (-1, 0, 0)),
    0x22: ((0, -1, 0), (0, 0, 1), (-1, 0, 0)),
    0x23: ((0, 0, -1), (0, -1, 0), (-1, 0, 0)),
}
ROTATION_IDS = {tuple(map(tuple, matrix)): key for key, matrix in BASIC_ROTATIONS.items()}


# --------------------------------------------------------------------------
# value containers — plain tagged tuples keep the code obvious
# --------------------------------------------------------------------------

def v_string(data: bytes): return ("String", data)
def v_bool(value: bool): return ("Bool", bool(value))
def v_int32(value: int): return ("Int32", value)
def v_float32(value: float): return ("Float32", value)
def v_float64(value: float): return ("Float64", value)
def v_udim(scale: float, offset: int): return ("UDim", (scale, offset))
def v_udim2(xs, xo, ys, yo): return ("UDim2", (xs, xo, ys, yo))
def v_ray(origin, direction): return ("Ray", (tuple(origin), tuple(direction)))
def v_faces(mask: int): return ("Faces", mask)
def v_axes(mask: int): return ("Axes", mask)
def v_brickcolor(number: int): return ("BrickColor", number)
def v_color3(r: float, g: float, b: float): return ("Color3", (r, g, b))
def v_vector2(x: float, y: float): return ("Vector2", (x, y))
def v_vector3(x: float, y: float, z: float): return ("Vector3", (x, y, z))
def v_cframe(position, matrix): return ("CFrame", (tuple(position), tuple(map(tuple, matrix))))
def v_enum(value: int): return ("Enum", value)
def v_ref(referent: int): return ("Ref", referent)
def v_vector3int16(x: int, y: int, z: int): return ("Vector3int16", (x, y, z))
def v_numbersequence(points): return ("NumberSequence", [tuple(p) for p in points])
def v_colorsequence(points): return ("ColorSequence", [tuple(p) for p in points])
def v_numberrange(low: float, high: float): return ("NumberRange", (low, high))
def v_rect(minv, maxv): return ("Rect", (tuple(minv), tuple(maxv)))
def v_physicalproperties(flag: int, custom): return ("PhysicalProperties", (flag, custom))
def v_color3uint8(r: int, g: int, b: int): return ("Color3uint8", (r, g, b))
def v_int64(value: int): return ("Int64", value)
def v_sharedstring(index: int): return ("SharedString", index)
def v_bytecode(data: bytes): return ("Bytecode", data)
def v_optional_cframe(value, present: bool): return ("OptionalCFrame", (value, bool(present)))
def v_uniqueid(index: int, time: int, random: int): return ("UniqueId", (index, time, random))
def v_font(family: bytes, weight: int, style: int, cached: bytes):
    return ("Font", (family, weight, style, cached))
def v_securitycapabilities(bits: int): return ("SecurityCapabilities", bits)
def v_content(types, uris, objects, externals):
    return ("Content", (list(types), list(uris), list(objects), bytes(externals)))


# --------------------------------------------------------------------------
# decoding
# --------------------------------------------------------------------------

class ByteReader:
    def __init__(self, data: bytes, pos: int = 0):
        self.data = data
        self.pos = pos

    @property
    def remaining(self) -> int:
        return len(self.data) - self.pos

    def take(self, n: int) -> bytes:
        out = self.data[self.pos:self.pos + n]
        if len(out) != n:
            raise RbxmError("unexpected end of chunk data")
        self.pos += n
        return out

    def u8(self) -> int:
        return self.take(1)[0]

    def u16(self) -> int:
        return struct.unpack("<H", self.take(2))[0]

    def u32(self) -> int:
        return struct.unpack("<I", self.take(4))[0]

    def i32(self) -> int:
        return struct.unpack("<i", self.take(4))[0]

    def i64(self) -> int:
        return struct.unpack("<q", self.take(8))[0]

    def f32(self) -> float:
        return struct.unpack("<f", self.take(4))[0]

    def f64(self) -> float:
        return struct.unpack("<d", self.take(8))[0]

    def string(self) -> bytes:
        return self.take(self.u32())

    def interleaved(self, count: int, width: int) -> List[bytes]:
        return _deinterleave(self.take(count * width), 0, count, width)

    # -- arrays ------------------------------------------------------------
    def i32_array(self, count: int) -> List[int]:
        rows = self.interleaved(count, 4)
        return [untransform_i32(int.from_bytes(row, "big", signed=False)) for row in rows]

    def i64_array(self, count: int) -> List[int]:
        rows = self.interleaved(count, 8)
        return [
            untransform_i64(int.from_bytes(row, "big", signed=False)) for row in rows
        ]

    def u32_array(self, count: int) -> List[int]:
        rows = self.interleaved(count, 4)
        return [int.from_bytes(row, "big", signed=False) for row in rows]

    def f32_array(self, count: int) -> List[float]:
        rows = self.interleaved(count, 4)
        return [roblox_f32(int.from_bytes(row, "big", signed=False)) for row in rows]

    def referent_array(self, count: int) -> List[int]:
        out = []
        last = 0
        for delta in self.i32_array(count):
            last += delta
            out.append(last)
        return out


def decode_property_values(
    data: bytes, type_id: int, count: int, reader: ByteReader
) -> List[Any]:
    r = reader
    values: List[Any] = []

    if type_id in (T_STRING, T_BYTECODE):
        for _ in range(count):
            raw = r.string()
            values.append(v_bytecode(raw) if type_id == T_BYTECODE else v_string(raw))
    elif type_id == T_BOOL:
        values = [v_bool(byte != 0) for byte in r.take(count)]
    elif type_id == T_INT32:
        values = [v_int32(v) for v in r.i32_array(count)]
    elif type_id == T_INT64:
        values = [v_int64(v) for v in r.i64_array(count)]
    elif type_id == T_FLOAT32:
        values = [v_float32(v) for v in r.f32_array(count)]
    elif type_id == T_FLOAT64:
        values = [v_float64(r.f64()) for _ in range(count)]
    elif type_id == T_UDIM:
        scales = r.f32_array(count)
        offsets = r.i32_array(count)
        values = [v_udim(scales[i], offsets[i]) for i in range(count)]
    elif type_id == T_UDIM2:
        xs = r.f32_array(count)
        ys = r.f32_array(count)
        xo = r.i32_array(count)
        yo = r.i32_array(count)
        values = [v_udim2(xs[i], xo[i], ys[i], yo[i]) for i in range(count)]
    elif type_id == T_RAY:
        for _ in range(count):
            values.append(v_ray((r.f32(), r.f32(), r.f32()), (r.f32(), r.f32(), r.f32())))
    elif type_id in (T_FACES, T_AXES):
        make = v_faces if type_id == T_FACES else v_axes
        values = [make(byte) for byte in r.take(count)]
    elif type_id == T_BRICKCOLOR:
        values = [v_brickcolor(v) for v in r.u32_array(count)]
    elif type_id == T_COLOR3:
        reds = r.f32_array(count)
        greens = r.f32_array(count)
        blues = r.f32_array(count)
        values = [v_color3(reds[i], greens[i], blues[i]) for i in range(count)]
    elif type_id == T_COLOR3UINT8:
        reds = r.take(count)
        greens = r.take(count)
        blues = r.take(count)
        values = [v_color3uint8(reds[i], greens[i], blues[i]) for i in range(count)]
    elif type_id == T_VECTOR2:
        xs = r.f32_array(count)
        ys = r.f32_array(count)
        values = [v_vector2(xs[i], ys[i]) for i in range(count)]
    elif type_id == T_VECTOR3:
        xs = r.f32_array(count)
        ys = r.f32_array(count)
        zs = r.f32_array(count)
        values = [v_vector3(xs[i], ys[i], zs[i]) for i in range(count)]
    elif type_id == T_VECTOR3INT16:
        for _ in range(count):
            x, y, z = struct.unpack("<hhh", r.take(6))
            values.append(v_vector3int16(x, y, z))
    elif type_id in (T_CFRAME, T_OPTIONAL_CFRAME):
        if type_id == T_OPTIONAL_CFRAME:
            marker = r.u8()
            if marker != T_CFRAME:
                raise RbxmError("bad OptionalCoordinateFrame marker 0x%02x" % marker)
        rotations = []
        for _ in range(count):
            rotation_id = r.u8()
            if rotation_id == 0:
                matrix = tuple(
                    (r.f32(), r.f32(), r.f32()) for _ in range(3)
                )
            else:
                if rotation_id not in BASIC_ROTATIONS:
                    raise RbxmError("unknown CFrame rotation id 0x%02x" % rotation_id)
                matrix = BASIC_ROTATIONS[rotation_id]
            rotations.append(matrix)
        xs = r.f32_array(count)
        ys = r.f32_array(count)
        zs = r.f32_array(count)
        if type_id == T_OPTIONAL_CFRAME:
            marker = r.u8()
            if marker != T_BOOL:
                raise RbxmError("bad OptionalCoordinateFrame bool marker 0x%02x" % marker)
            present = [byte != 0 for byte in r.take(count)]
        else:
            present = [True] * count
        for i in range(count):
            cf = v_cframe((xs[i], ys[i], zs[i]), rotations[i])
            values.append(cf if type_id == T_CFRAME else v_optional_cframe(cf, present[i]))
    elif type_id == T_ENUM:
        values = [v_enum(v) for v in r.u32_array(count)]
    elif type_id == T_REF:
        values = [v_ref(v) for v in r.referent_array(count)]
    elif type_id == T_NUMBERSEQUENCE:
        for _ in range(count):
            keypoints = r.u32()
            points = []
            for _ in range(keypoints):
                points.append((r.f32(), r.f32(), r.f32()))
            values.append(v_numbersequence(points))
    elif type_id == T_COLORSEQUENCE:
        for _ in range(count):
            keypoints = r.u32()
            points = []
            for _ in range(keypoints):
                points.append((r.f32(), r.f32(), r.f32(), r.f32(), r.f32()))
            values.append(v_colorsequence(points))
    elif type_id == T_NUMBERRANGE:
        for _ in range(count):
            values.append(v_numberrange(r.f32(), r.f32()))
    elif type_id == T_RECT:
        minx = r.f32_array(count)
        miny = r.f32_array(count)
        maxx = r.f32_array(count)
        maxy = r.f32_array(count)
        values = [
            v_rect((minx[i], miny[i]), (maxx[i], maxy[i])) for i in range(count)
        ]
    elif type_id == T_PHYSICALPROPERTIES:
        for _ in range(count):
            flag = r.u8()
            custom = None
            if flag & 1:
                fields = [r.f32() for _ in range(5)]
                fields.append(r.f32() if flag & 2 else 1.0)
                custom = tuple(fields)
            values.append(v_physicalproperties(flag, custom))
    elif type_id == T_SHAREDSTRING:
        values = [v_sharedstring(v) for v in r.u32_array(count)]
    elif type_id == T_UNIQUEID:
        rows = r.interleaved(count, 16)
        for row in rows:
            index = int.from_bytes(row[0:4], "big")
            time = int.from_bytes(row[4:8], "big")
            random = int.from_bytes(row[8:16], "big", signed=True)
            values.append(v_uniqueid(index, time, random))
    elif type_id == T_FONT:
        for _ in range(count):
            family = r.string()
            weight = r.u16()
            style = r.u8()
            cached = r.string()
            values.append(v_font(family, weight, style, cached))
    elif type_id == T_SECURITYCAPABILITIES:
        values = [v_securitycapabilities(v & 0xFFFFFFFFFFFFFFFF) for v in r.i64_array(count)]
    elif type_id == T_CONTENT:
        types = r.i32_array(count)
        uri_count = r.u32()
        uris = [r.string() for _ in range(uri_count)]
        object_count = r.u32()
        objects = r.referent_array(object_count)
        external_count = r.u32()
        externals = r.take(external_count * 4)
        values = [v_content(types, uris, objects, externals)] * count
    else:
        raise RbxmError("unsupported property type 0x%02x" % type_id)
    return values


# --------------------------------------------------------------------------
# encoding
# --------------------------------------------------------------------------

def _enc_interleaved(rows: Sequence[bytes]) -> bytes:
    return _column_major(list(rows))


def encode_property_values(type_id: int, values: Sequence[Any]) -> bytes:
    out = bytearray()
    count = len(values)
    get = lambda v: v[1]  # noqa: E731 - value payload accessor

    if type_id in (T_STRING, T_BYTECODE):
        for value in values:
            raw = get(value)
            out += struct.pack("<I", len(raw)) + raw
    elif type_id == T_BOOL:
        out += bytes(1 if get(v) else 0 for v in values)
    elif type_id == T_INT32:
        out += _enc_interleaved(
            struct.pack(">I", transform_i32(get(v))) for v in values
        )
    elif type_id == T_INT64:
        out += _enc_interleaved(
            struct.pack(">Q", transform_i64(_as_i64(get(v)))) for v in values
        )
    elif type_id == T_FLOAT32:
        out += _enc_interleaved(
            struct.pack(">I", roblox_f32_bits(get(v))) for v in values
        )
    elif type_id == T_FLOAT64:
        for value in values:
            out += struct.pack("<d", get(value))
    elif type_id == T_UDIM:
        out += _enc_interleaved(
            struct.pack(">I", roblox_f32_bits(get(v)[0])) for v in values
        )
        out += _enc_interleaved(
            struct.pack(">I", transform_i32(get(v)[1])) for v in values
        )
    elif type_id == T_UDIM2:
        comps = (0, 2, 1, 3)  # X.Scale, Y.Scale, X.Offset, Y.Offset
        for idx in comps:
            if idx in (1, 3):
                out += _enc_interleaved(
                    struct.pack(">I", transform_i32(get(v)[idx]))
                    for v in values
                )
            else:
                out += _enc_interleaved(
                    struct.pack(">I", roblox_f32_bits(get(v)[idx])) for v in values
                )
    elif type_id == T_RAY:
        for value in values:
            origin, direction = get(value)
            out += struct.pack("<6f", *origin, *direction)
    elif type_id in (T_FACES, T_AXES):
        out += bytes(get(v) & 0xFF for v in values)
    elif type_id == T_BRICKCOLOR:
        out += _enc_interleaved(struct.pack(">I", get(v) & 0xFFFFFFFF) for v in values)
    elif type_id == T_COLOR3:
        for idx in range(3):
            out += _enc_interleaved(
                struct.pack(">I", roblox_f32_bits(get(v)[idx])) for v in values
            )
    elif type_id == T_COLOR3UINT8:
        for idx in range(3):
            out += bytes(get(v)[idx] & 0xFF for v in values)
    elif type_id == T_VECTOR2:
        for idx in range(2):
            out += _enc_interleaved(
                struct.pack(">I", roblox_f32_bits(get(v)[idx])) for v in values
            )
    elif type_id == T_VECTOR3:
        for idx in range(3):
            out += _enc_interleaved(
                struct.pack(">I", roblox_f32_bits(get(v)[idx])) for v in values
            )
    elif type_id == T_VECTOR3INT16:
        for value in values:
            out += struct.pack("<3h", *get(value))
    elif type_id in (T_CFRAME, T_OPTIONAL_CFRAME):
        if type_id == T_OPTIONAL_CFRAME:
            out.append(T_CFRAME)
        rotation_bytes = bytearray()
        positions = []
        presents = []
        for value in values:
            if type_id == T_OPTIONAL_CFRAME:
                cframe, present = get(value)
                _tag, (pos, matrix) = cframe
                presents.append(present)
            else:
                pos, matrix = get(value)
            positions.append(pos)
            key = tuple(map(tuple, matrix))
            preset = ROTATION_IDS.get(key)
            if preset is not None:
                rotation_bytes.append(preset)
            else:
                rotation_bytes.append(0)
                rotation_bytes += struct.pack("<9f", *[c for row in matrix for c in row])
        out += rotation_bytes
        for idx in range(3):
            out += _enc_interleaved(
                struct.pack(">I", roblox_f32_bits(pos[idx])) for pos in positions
            )
        if type_id == T_OPTIONAL_CFRAME:
            out.append(T_BOOL)
            out += bytes(1 if present else 0 for present in presents)
    elif type_id == T_ENUM:
        out += _enc_interleaved(struct.pack(">I", get(v) & 0xFFFFFFFF) for v in values)
    elif type_id == T_REF:
        last = 0
        deltas = []
        for value in values:
            ref = get(value)
            deltas.append(ref - last)
            last = ref
        out += _enc_interleaved(
            struct.pack(">I", transform_i32(d)) for d in deltas
        )
    elif type_id == T_NUMBERSEQUENCE:
        for value in values:
            points = get(value)
            out += struct.pack("<I", len(points))
            for point in points:
                out += struct.pack("<3f", *point)
    elif type_id == T_COLORSEQUENCE:
        for value in values:
            points = get(value)
            out += struct.pack("<I", len(points))
            for point in points:
                out += struct.pack("<5f", *point)
    elif type_id == T_NUMBERRANGE:
        for value in values:
            out += struct.pack("<2f", *get(value))
    elif type_id == T_RECT:
        lows = []
        highs = []
        for value in values:
            (minx, miny), (maxx, maxy) = get(value)
            lows.append((minx, miny))
            highs.append((maxx, maxy))
        for idx in range(2):
            out += _enc_interleaved(
                struct.pack(">I", roblox_f32_bits(lows[i][idx])) for i in range(count)
            )
            out += _enc_interleaved(
                struct.pack(">I", roblox_f32_bits(highs[i][idx])) for i in range(count)
            )
    elif type_id == T_PHYSICALPROPERTIES:
        for value in values:
            flag, custom = get(value)
            out.append(flag & 0xFF)
            if flag & 1:
                if custom is None:
                    raise RbxmError("PhysicalProperties flag says custom but no data")
                out += struct.pack("<6f", *custom)
    elif type_id == T_SHAREDSTRING:
        out += _enc_interleaved(struct.pack(">I", get(v) & 0xFFFFFFFF) for v in values)
    elif type_id == T_UNIQUEID:
        rows = []
        for value in values:
            index, time, random = get(value)
            rows.append(
                struct.pack(">I", index)
                + struct.pack(">I", time)
                + struct.pack(">Q", random & 0xFFFFFFFFFFFFFFFF)
            )
        out += _enc_interleaved(rows)
    elif type_id == T_FONT:
        for value in values:
            family, weight, style, cached = get(value)
            out += struct.pack("<I", len(family)) + family
            out += struct.pack("<HB", weight, style)
            out += struct.pack("<I", len(cached)) + cached
    elif type_id == T_SECURITYCAPABILITIES:
        out += _enc_interleaved(
            struct.pack(">Q", transform_i64(_as_i64(get(v)))) for v in values
        )
    elif type_id == T_CONTENT:
        types, uris, objects, externals = get(values[0])
        out += _enc_interleaved(
            struct.pack(">I", transform_i32(t)) for t in types
        )
        out += struct.pack("<I", len(uris))
        for uri in uris:
            out += struct.pack("<I", len(uri)) + uri
        out += struct.pack("<I", len(objects))
        last = 0
        deltas = []
        for ref in objects:
            deltas.append(ref - last)
            last = ref
        out += _enc_interleaved(
            struct.pack(">I", transform_i32(d)) for d in deltas
        )
        out += struct.pack("<I", len(externals) // 4)
        out += externals
    else:
        raise RbxmError("unsupported property type 0x%02x" % type_id)
    return bytes(out)


# --------------------------------------------------------------------------
# model
# --------------------------------------------------------------------------

class PropChunk:
    __slots__ = ("name", "type_id", "values")

    def __init__(self, name: str, type_id: int, values: List[Any]):
        self.name = name
        self.type_id = type_id
        self.values = values


class ClassRecord:
    __slots__ = ("class_id", "name", "object_format", "referents", "properties")

    def __init__(self, class_id: int, name: str, object_format: int):
        self.class_id = class_id
        self.name = name
        self.object_format = object_format
        self.referents: List[int] = []
        self.properties: List[PropChunk] = []


class Model:
    def __init__(self):
        self.class_count = 0
        self.instance_count = 0
        self.metadata: List[Tuple[bytes, bytes]] = []
        self.shared_strings: List[bytes] = []
        self.classes: List[ClassRecord] = []
        self.parents: Dict[int, int] = {}
        self.prnt_pairs: List[Tuple[int, int]] = []


def decode_model(blob: bytes, verify: bool = True) -> Model:
    class_count, instance_count, chunks = read_chunks(blob)
    model = Model()
    model.class_count = class_count
    model.instance_count = instance_count
    class_by_id: Dict[int, ClassRecord] = {}

    for chunk in chunks:
        if chunk.name == CHUNK_META:
            r = ByteReader(chunk.data)
            entries = r.u32()
            model.metadata = [(r.string(), r.string()) for _ in range(entries)]
            _check_consumed(r, chunk, verify)
        elif chunk.name == CHUNK_SSTR:
            r = ByteReader(chunk.data)
            version = r.u32()
            if version != 0:
                raise RbxmError("unsupported SSTR version %d" % version)
            count = r.u32()
            for _ in range(count):
                digest = r.take(16)
                value = r.string()
                if verify and digest != b"\0" * 16 and hashlib.md5(value).digest() != digest:
                    # Some third-party packers write dummy hashes; only warn.
                    print("warning: shared string %d has an incorrect md5" % len(model.shared_strings))
                model.shared_strings.append(value)
            _check_consumed(r, chunk, verify)
        elif chunk.name == CHUNK_INST:
            r = ByteReader(chunk.data)
            class_id = r.u32()
            name = r.string().decode("utf-8")
            object_format = r.u8()
            count = r.u32()
            record = ClassRecord(class_id, name, object_format)
            record.referents = r.referent_array(count)
            if object_format == 1:
                r.take(count)
            _check_consumed(r, chunk, verify)
            class_by_id[class_id] = record
            model.classes.append(record)
        elif chunk.name == CHUNK_PROP:
            r = ByteReader(chunk.data)
            class_id = r.u32()
            record = class_by_id.get(class_id)
            if record is None:
                raise RbxmError("PROP chunk before its INST chunk (%d)" % class_id)
            name = r.string()
            if r.remaining == 0:
                continue  # Roblox ignores property chunks with no type byte
            type_id = r.u8()
            values = decode_property_values(chunk.data, type_id, len(record.referents), r)
            _check_consumed(r, chunk, verify)
            if name.startswith(b"\x00"):
                name = name[1:]  # Roblox prefixes some property names with a NUL
            record.properties.append(PropChunk(name.decode("utf-8"), type_id, values))
        elif chunk.name == CHUNK_PRNT:
            r = ByteReader(chunk.data)
            version = r.u8()
            if version != 0:
                raise RbxmError("unsupported PRNT version %d" % version)
            count = r.u32()
            children = r.referent_array(count)
            parents = r.referent_array(count)
            _check_consumed(r, chunk, verify)
            model.prnt_pairs = list(zip(children, parents))
            model.parents = dict(model.prnt_pairs)
        elif chunk.name == CHUNK_END:
            pass
        else:
            raise RbxmError("unexpected chunk %r" % chunk.name)
    return model


def _check_consumed(reader: ByteReader, chunk: Chunk, verify: bool) -> None:
    if verify and reader.remaining != 0:
        raise RbxmError(
            "chunk %s not fully consumed (%d bytes left) — decoder out of sync"
            % (chunk.name, reader.remaining)
        )


def encode_model(model: Model, compress: bool = True) -> bytes:
    chunks: List[Chunk] = []
    if model.metadata:
        body = bytearray(struct.pack("<I", len(model.metadata)))
        for key, value in model.metadata:
            body += struct.pack("<I", len(key)) + key
            body += struct.pack("<I", len(value)) + value
        chunks.append(Chunk(CHUNK_META, bytes(body)))
    if model.shared_strings:
        body = bytearray(struct.pack("<II", 0, len(model.shared_strings)))
        for value in model.shared_strings:
            body += hashlib.md5(value).digest()
            body += struct.pack("<I", len(value)) + value
        chunks.append(Chunk(CHUNK_SSTR, bytes(body)))
    for record in model.classes:
        body = bytearray()
        body += struct.pack("<I", record.class_id)
        name = record.name.encode("utf-8")
        body += struct.pack("<I", len(name)) + name
        body.append(record.object_format)
        body += struct.pack("<I", len(record.referents))
        last = 0
        deltas = []
        for ref in record.referents:
            deltas.append(ref - last)
            last = ref
        body += _enc_interleaved(
            struct.pack(">I", transform_i32(d)) for d in deltas
        )
        if record.object_format == 1:
            body += b"\x01" * len(record.referents)
        chunks.append(Chunk(CHUNK_INST, bytes(body)))
    for record in model.classes:
        for prop in record.properties:
            body = bytearray()
            body += struct.pack("<I", record.class_id)
            name = prop.name.encode("utf-8")
            body += struct.pack("<I", len(name)) + name
            body.append(prop.type_id)
            body += encode_property_values(prop.type_id, prop.values)
            chunks.append(Chunk(CHUNK_PROP, bytes(body)))
    body = bytearray(b"\x00")
    pairs = list(model.prnt_pairs) if model.prnt_pairs else sorted(model.parents.items())
    body += struct.pack("<I", len(pairs))
    last = 0
    deltas = []
    for child, _parent in pairs:
        deltas.append(child - last)
        last = child
    body += _enc_interleaved(
        struct.pack(">I", transform_i32(d)) for d in deltas
    )
    last = 0
    deltas = []
    for _child, parent in pairs:
        deltas.append(parent - last)
        last = parent
    body += _enc_interleaved(
        struct.pack(">I", transform_i32(d)) for d in deltas
    )
    chunks.append(Chunk(CHUNK_PRNT, bytes(body)))
    chunks.append(Chunk(CHUNK_END, END_MAGIC))
    return write_chunks(model.class_count, model.instance_count, chunks, compress)


# --------------------------------------------------------------------------
# convenience helpers
# --------------------------------------------------------------------------

def instance_paths(model: Model) -> Dict[int, str]:
    """referent -> ``Container/Folder/Child`` style path."""
    names: Dict[int, str] = {}
    for record in model.classes:
        for prop in record.properties:
            if prop.name == "Name":
                for ref, value in zip(record.referents, prop.values):
                    raw = value[1]
                    names[ref] = raw.decode("utf-8", "replace") or "unnamed"
    paths: Dict[int, str] = {}

    def walk(ref: int, prefix: str) -> None:
        name = names.get(ref, "instance_%d" % ref)
        path = prefix + "/" + name if prefix else name
        if path in paths.values():  # pragma: no cover - rare duplicates
            path += "#%d" % ref
        paths[ref] = path
        for child, parent in model.parents.items():
            if parent == ref:
                walk(child, path)

    for child, parent in model.parents.items():
        if parent == -1:
            walk(child, "")
    return paths


def property_map(model: Model) -> Dict[int, Dict[str, Any]]:
    """referent -> {property name: value}"""
    out: Dict[int, Dict[str, Any]] = {}
    for record in model.classes:
        for prop in record.properties:
            for ref, value in zip(record.referents, prop.values):
                out.setdefault(ref, {})[prop.name] = value
    return out


def to_jsonable(value: Any) -> Any:
    tag, payload = value
    if tag in ("String", "Bytecode"):
        try:
            return {"type": tag, "text": payload.decode("utf-8")}
        except UnicodeDecodeError:
            return {"type": tag, "base64": base64.b64encode(payload).decode("ascii")}
    if isinstance(payload, bytes):
        return {"type": tag, "base64": base64.b64encode(payload).decode("ascii")}
    if isinstance(payload, tuple):
        return {"type": tag, "value": _json_tuple(payload)}
    if isinstance(payload, list):
        return {"type": tag, "value": _json_tuple(payload)}
    return {"type": tag, "value": payload}


def _json_tuple(payload: Sequence[Any]) -> Any:
    out = []
    for item in payload:
        if isinstance(item, bytes):
            out.append({"base64": base64.b64encode(item).decode("ascii")})
        elif isinstance(item, (tuple, list)):
            out.append(_json_tuple(item))
        else:
            out.append(item)
    return out


def read_file(path: str) -> bytes:
    with open(path, "rb") as handle:
        return handle.read()


def write_file(path: str, data: bytes) -> None:
    with open(path, "wb") as handle:
        handle.write(data)
