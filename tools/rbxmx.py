#!/usr/bin/env python3
"""rbxmx.py — convert between the binary (``.rbxm``) and XML (``.rbxmx``) model formats.

``.rbxm`` is a packed binary file: open it in a text editor and you only get
binary noise.  ``.rbxmx`` is the same model written as XML, so every script
inside it is visible as ordinary text and can be edited in VS Code, Notepad, or
anything else.  Roblox Studio reads both formats.

Command line::

    python3 tools/rbxmx.py Eclipse-Animator-Open.rbxm  Eclipse-Animator-Open.rbxmx
    python3 tools/rbxmx.py Eclipse-Animator-Open.rbxmx Eclipse-Animator-Open.rbxm

The direction is picked from the file extension.  As a library::

    import rbxm, rbxmx
    model = rbxm.decode_model(rbxm.read_file("plugin.rbxm"))
    open("plugin.rbxmx", "w", encoding="utf-8").write(rbxmx.model_to_xml(model))
"""

from __future__ import annotations

import base64
import hashlib
import os
import struct
import sys
import xml.etree.ElementTree as ET
from typing import Any, Dict, List, Optional, Sequence

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rbxm  # noqa: E402

XML_HEADER = '<?xml version="1.0" encoding="utf-8"?>\n'
ROBLOX_OPEN = (
    '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
    'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
)

# Properties whose binary "String" payload is really raw bytes (BinaryString).
BINARY_STRING_PROPS = {
    "AttributesSerialize", "Tags", "CollisionGroupData", "SlimHash",
    "SerializedOverrides", "ModelMeshData", "PhysicsData", "MaterialColors",
    "MeshData", "BinaryString",
}
# Properties whose binary "String" payload is really a ContentId URI.
CONTENT_ID_PROPS = {"LinkedSource", "SourceAssetIdContent"}
# Properties whose binary "Int32" payload is really a BrickColor number.
BRICKCOLOR_PROPS = {"BrickColor", "Color"}


# --------------------------------------------------------------------------
# number / text formatting
# --------------------------------------------------------------------------

def fmt_float32(value: float) -> str:
    import math

    if math.isnan(value):
        return "NAN"
    if math.isinf(value):
        return "INF" if value > 0 else "-INF"
    for digits in (7, 9, 10):
        text = "%.*g" % (digits, value)
        try:
            if struct.unpack(">f", struct.pack(">f", float(text)))[0] == value:
                return text
        except (ValueError, OverflowError):
            continue
    return repr(value)


def fmt_float64(value: float) -> str:
    import math

    if math.isnan(value):
        return "NAN"
    if math.isinf(value):
        return "INF" if value > 0 else "-INF"
    return repr(value)


def parse_float(text: str) -> float:
    text = (text or "").strip()
    upper = text.upper()
    if upper in ("INF", "+INF"):
        return float("inf")
    if upper == "-INF":
        return float("-inf")
    if upper == "NAN":
        return float("nan")
    if not text:
        return 0.0
    return float(text)


def escape(text: str) -> str:
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                .replace('"', "&quot;"))


def cdata(raw: bytes) -> str:
    """Wrap bytes in CDATA, splitting any accidental ``]]>`` sequence."""
    text = raw.decode("utf-8", "surrogateescape")
    parts = text.split("]]>")
    if len(parts) == 1:
        return "<![CDATA[%s]]>" % text
    return "]]>]]&gt;<![CDATA[".join(parts).join(("<![CDATA[", "]]>"))


def decode_text(text: Optional[str]) -> bytes:
    return (text or "").encode("utf-8", "surrogateescape")


def md5_label(raw: bytes) -> str:
    return base64.b64encode(hashlib.md5(raw).digest()).decode("ascii")


# --------------------------------------------------------------------------
# model -> XML
# --------------------------------------------------------------------------

def property_element(name: str, type_id: int, payload: Any,
                     shared_ids: Dict[bytes, int]) -> str:
    """Render one property as an XML element (attributes excluded)."""
    tag_attr = ' name="%s"' % escape(name)

    if type_id in (rbxm.T_STRING, rbxm.T_BYTECODE):
        if name == "Source" or name == "Bytecode":
            return "<ProtectedString%s>%s</ProtectedString>" % (tag_attr, cdata(payload))
        if name in BINARY_STRING_PROPS:
            return "<BinaryString%s>%s</BinaryString>" % (
                tag_attr, base64.b64encode(payload).decode("ascii"))
        if name in CONTENT_ID_PROPS:
            if not payload:
                return "<Content%s><null></null></Content>" % tag_attr
            return "<Content%s><url>%s</url></Content>" % (
                tag_attr, escape(payload.decode("utf-8", "replace")))
        return "<string%s>%s</string>" % (tag_attr, escape(payload.decode("utf-8", "replace")))

    if type_id == rbxm.T_BOOL:
        return "<bool%s>%s</bool>" % (tag_attr, "true" if payload else "false")
    if type_id == rbxm.T_INT32:
        if name in BRICKCOLOR_PROPS:
            return "<int%s>%d</int>" % (tag_attr, payload)
        return "<int%s>%d</int>" % (tag_attr, payload)
    if type_id == rbxm.T_INT64:
        return "<int64%s>%d</int64>" % (tag_attr, payload)
    if type_id == rbxm.T_FLOAT32:
        return "<float%s>%s</float>" % (tag_attr, fmt_float32(payload))
    if type_id == rbxm.T_FLOAT64:
        return "<double%s>%s</double>" % (tag_attr, fmt_float64(payload))
    if type_id == rbxm.T_UDIM:
        scale, offset = payload
        return ("<UDim%s><S>%s</S><O>%d</O></UDim>"
                % (tag_attr, fmt_float32(scale), offset))
    if type_id == rbxm.T_UDIM2:
        xs, xo, ys, yo = payload
        return ("<UDim2%s><XS>%s</XS><XO>%d</XO><YS>%s</YS><YO>%d</YO></UDim2>"
                % (tag_attr, fmt_float32(xs), xo, fmt_float32(ys), yo))
    if type_id == rbxm.T_RAY:
        origin, direction = payload
        return ("<Ray%s><origin><X>%s</X><Y>%s</Y><Z>%s</Z></origin>"
                "<direction><X>%s</X><Y>%s</Y><Z>%s</Z></direction></Ray>"
                % (tag_attr, fmt_float32(origin[0]), fmt_float32(origin[1]),
                   fmt_float32(origin[2]), fmt_float32(direction[0]),
                   fmt_float32(direction[1]), fmt_float32(direction[2])))
    if type_id == rbxm.T_FACES:
        return "<Faces%s><faces>%d</faces></Faces>" % (tag_attr, payload)
    if type_id == rbxm.T_AXES:
        return "<Axes%s><axes>%d</axes></Axes>" % (tag_attr, payload)
    if type_id == rbxm.T_BRICKCOLOR:
        return "<int%s>%d</int>" % (tag_attr, payload)
    if type_id == rbxm.T_COLOR3:
        return ("<Color3%s><R>%s</R><G>%s</G><B>%s</B></Color3>"
                % (tag_attr, fmt_float32(payload[0]), fmt_float32(payload[1]),
                   fmt_float32(payload[2])))
    if type_id == rbxm.T_COLOR3UINT8:
        red, green, blue = payload
        packed = (0xFF << 24) | (red << 16) | (green << 8) | blue
        return "<Color3uint8%s>%d</Color3uint8>" % (tag_attr, packed)
    if type_id == rbxm.T_VECTOR2:
        return ("<Vector2%s><X>%s</X><Y>%s</Y></Vector2>"
                % (tag_attr, fmt_float32(payload[0]), fmt_float32(payload[1])))
    if type_id == rbxm.T_VECTOR3:
        return ("<Vector3%s><X>%s</X><Y>%s</Y><Z>%s</Z></Vector3>"
                % (tag_attr, fmt_float32(payload[0]), fmt_float32(payload[1]),
                   fmt_float32(payload[2])))
    if type_id == rbxm.T_VECTOR3INT16:
        return ("<Vector3int16%s><X>%d</X><Y>%d</Y><Z>%d</Z></Vector3int16>"
                % (tag_attr, payload[0], payload[1], payload[2]))
    if type_id == rbxm.T_CFRAME:
        position, matrix = payload
        parts = ["<CoordinateFrame%s>" % tag_attr,
                 "<X>%s</X>" % fmt_float32(position[0]),
                 "<Y>%s</Y>" % fmt_float32(position[1]),
                 "<Z>%s</Z>" % fmt_float32(position[2])]
        for row in range(3):
            for column in range(3):
                parts.append("<R%d%d>%s</R%d%d>"
                             % (row, column, fmt_float32(matrix[row][column]), row, column))
        parts.append("</CoordinateFrame>")
        return "".join(parts)
    if type_id == rbxm.T_OPTIONAL_CFRAME:
        cframe, present = payload
        if not present:
            return "<OptionalCoordinateFrame%s></OptionalCoordinateFrame>" % tag_attr
        inner = property_element("", rbxm.T_CFRAME, cframe[1], shared_ids)
        inner = inner.replace(" name=\"\"", "", 1)
        inner = "<CFrame%s" % inner[len("<CoordinateFrame"):]
        inner = inner.replace("</CoordinateFrame>", "</CFrame>")
        return "<OptionalCoordinateFrame%s>%s</OptionalCoordinateFrame>" % (tag_attr, inner)
    if type_id == rbxm.T_ENUM:
        return "<token%s>%d</token>" % (tag_attr, payload)
    if type_id == rbxm.T_REF:
        if payload is None or payload < 0:
            return "<Ref%s>null</Ref>" % tag_attr
        return "<Ref%s>%d</Ref>" % (tag_attr, payload)
    if type_id == rbxm.T_NUMBERSEQUENCE:
        values = " ".join(
            "%s %s %s" % (fmt_float32(t), fmt_float32(value), fmt_float32(envelope))
            for t, value, envelope in payload)
        return "<NumberSequence%s>%s </NumberSequence>" % (tag_attr, values)
    if type_id == rbxm.T_COLORSEQUENCE:
        values = " ".join(
            "%s %s %s %s %s" % (fmt_float32(t), fmt_float32(r), fmt_float32(g),
                                fmt_float32(b), fmt_float32(envelope))
            for t, r, g, b, envelope in payload)
        return "<ColorSequence%s>%s </ColorSequence>" % (tag_attr, values)
    if type_id == rbxm.T_NUMBERRANGE:
        return "<NumberRange%s>%s %s </NumberRange>" % (
            tag_attr, fmt_float32(payload[0]), fmt_float32(payload[1]))
    if type_id == rbxm.T_RECT:
        (minx, miny), (maxx, maxy) = payload
        return ("<Rect2D%s><min><X>%s</X><Y>%s</Y></min>"
                "<max><X>%s</X><Y>%s</Y></max></Rect2D>"
                % (tag_attr, fmt_float32(minx), fmt_float32(miny),
                   fmt_float32(maxx), fmt_float32(maxy)))
    if type_id == rbxm.T_PHYSICALPROPERTIES:
        flag, custom = payload
        parts = ["<PhysicalProperties%s>" % tag_attr,
                 "<CustomPhysics>%s</CustomPhysics>" % ("true" if flag & 1 else "false")]
        if flag & 1 and custom:
            for label, value in zip(
                ("Density", "Friction", "Elasticity", "FrictionWeight",
                 "ElasticityWeight", "AcousticAbsorption"), custom):
                parts.append("<%s>%s</%s>" % (label, fmt_float32(value), label))
        parts.append("</PhysicalProperties>")
        return "".join(parts)
    if type_id == rbxm.T_SHAREDSTRING:
        label = shared_ids.get(payload, "")
        return "<SharedString%s>%s</SharedString>" % (tag_attr, label)
    if type_id == rbxm.T_UNIQUEID:
        index, time, random = payload
        unsigned = random & 0xFFFFFFFFFFFFFFFF
        rolled = ((unsigned << 1) | (unsigned >> 63)) & 0xFFFFFFFFFFFFFFFF
        blob = struct.pack(">Q", rolled) + struct.pack(">I", time) + struct.pack(">I", index)
        return "<UniqueId%s>%s</UniqueId>" % (
            tag_attr, base64.b16encode(blob).decode("ascii").lower())
    if type_id == rbxm.T_FONT:
        family, weight, style, cached = payload
        parts = ["<Font%s>" % tag_attr,
                 "<Family><url>%s</url></Family>" % escape(family.decode("utf-8", "replace")),
                 "<Weight>%d</Weight>" % weight,
                 "<Style>%s</Style>" % ("Italic" if style == 1 else "Normal")]
        if cached:
            parts.append("<CachedFaceId><url>%s</url></CachedFaceId>"
                         % escape(cached.decode("utf-8", "replace")))
        parts.append("</Font>")
        return "".join(parts)
    if type_id == rbxm.T_SECURITYCAPABILITIES:
        return "<SecurityCapabilities%s>%d</SecurityCapabilities>" % (tag_attr, payload)
    if type_id == rbxm.T_CONTENT:
        kind, uri, ref, _externals = payload
        if kind == 1 and uri is not None:
            return "<Content%s><uri>%s</uri></Content>" % (
                tag_attr, escape(uri.decode("utf-8", "replace")))
        if kind == 2 and ref is not None:
            return "<Content%s><Ref>%d</Ref></Content>" % (tag_attr, ref)
        return "<Content%s><null></null></Content>" % tag_attr

    raise rbxm.RbxmError("cannot write property %s (type 0x%02x) as XML" % (name, type_id))


def model_to_xml(model: rbxm.Model, indent: str = "  ") -> str:
    """Serialise a decoded model to Roblox XML (``.rbxmx``) text."""
    shared_labels = {index: md5_label(raw) for index, raw in enumerate(model.shared_strings)}

    children: Dict[int, List[int]] = {}
    for child, parent in model.prnt_pairs:
        children.setdefault(parent, []).append(child)

    class_by_ref: Dict[int, str] = {}
    values: Dict[tuple, Dict[int, tuple]] = {}   # (class, prop) -> ref -> value
    order: Dict[str, List[rbxm.PropChunk]] = {}  # class -> property chunks
    for record in model.classes:
        order[record.name] = record.properties
        for prop in record.properties:
            slot = values.setdefault((record.name, prop.name), {})
            for ref, value in zip(record.referents, prop.values):
                slot[ref] = value
        for ref in record.referents:
            class_by_ref[ref] = record.name

    rows: List[str] = [XML_HEADER, ROBLOX_OPEN, "\n"]
    for key, value in model.metadata:
        rows.append('%s<Meta name="%s">%s</Meta>\n'
                    % (indent, escape(key.decode("utf-8", "replace")),
                       escape(value.decode("utf-8", "replace"))))
    rows.append("%s<External>null</External>\n" % indent)
    rows.append("%s<External>nil</External>\n" % indent)

    def emit(ref: int, depth: int) -> None:
        pad = indent * depth
        class_name = class_by_ref[ref]
        rows.append('%s<Item class="%s" referent="%d">\n' % (pad, escape(class_name), ref))
        rows.append("%s<Properties>\n" % (pad + indent))
        for prop in order.get(class_name, []):
            value = values[(class_name, prop.name)].get(ref)
            if value is None:
                continue
            rows.append("%s%s\n" % (
                pad + indent * 2,
                property_element(prop.name, prop.type_id, value[1], shared_labels)))
        rows.append("%s</Properties>\n" % (pad + indent))
        for kid in children.get(ref, []):
            emit(kid, depth + 1)
        rows.append("%s</Item>\n" % pad)

    for child, parent in model.prnt_pairs:
        if parent == -1:
            emit(child, 1)

    if model.shared_strings:
        rows.append("%s<SharedStrings>\n" % indent)
        for index, raw in enumerate(model.shared_strings):
            rows.append('%s<SharedString md5="%s">%s</SharedString>\n'
                        % (indent * 2, shared_labels[index],
                           base64.b64encode(raw).decode("ascii")))
        rows.append("%s</SharedStrings>\n" % indent)

    rows.append("</roblox>\n")
    return "".join(rows)


# --------------------------------------------------------------------------
# XML -> model
# --------------------------------------------------------------------------

ELEMENT_TO_TYPE = {
    "string": rbxm.T_STRING,
    "ProtectedString": rbxm.T_STRING,
    "BinaryString": rbxm.T_STRING,
    "bool": rbxm.T_BOOL,
    "int": rbxm.T_INT32,
    "int64": rbxm.T_INT64,
    "float": rbxm.T_FLOAT32,
    "double": rbxm.T_FLOAT64,
    "UDim": rbxm.T_UDIM,
    "UDim2": rbxm.T_UDIM2,
    "Ray": rbxm.T_RAY,
    "Faces": rbxm.T_FACES,
    "Axes": rbxm.T_AXES,
    "Color3": rbxm.T_COLOR3,
    "Color3uint8": rbxm.T_COLOR3UINT8,
    "Vector2": rbxm.T_VECTOR2,
    "Vector3": rbxm.T_VECTOR3,
    "Vector3int16": rbxm.T_VECTOR3INT16,
    "CoordinateFrame": rbxm.T_CFRAME,
    "OptionalCoordinateFrame": rbxm.T_OPTIONAL_CFRAME,
    "token": rbxm.T_ENUM,
    "Ref": rbxm.T_REF,
    "NumberSequence": rbxm.T_NUMBERSEQUENCE,
    "ColorSequence": rbxm.T_COLORSEQUENCE,
    "NumberRange": rbxm.T_NUMBERRANGE,
    "Rect2D": rbxm.T_RECT,
    "PhysicalProperties": rbxm.T_PHYSICALPROPERTIES,
    "SharedString": rbxm.T_SHAREDSTRING,
    "NetAssetRef": rbxm.T_SHAREDSTRING,
    "UniqueId": rbxm.T_UNIQUEID,
    "Font": rbxm.T_FONT,
    "SecurityCapabilities": rbxm.T_SECURITYCAPABILITIES,
}

DEFAULT_SEQUENCE = [[(0.0, 0.0, 0.0), (1.0, 0.0, 0.0)]]


def default_value(type_id: int):
    if type_id in (rbxm.T_STRING, rbxm.T_BYTECODE):
        return rbxm.v_string(b"")
    if type_id == rbxm.T_BOOL:
        return rbxm.v_bool(False)
    if type_id == rbxm.T_INT32:
        return rbxm.v_int32(0)
    if type_id == rbxm.T_INT64:
        return rbxm.v_int64(0)
    if type_id == rbxm.T_FLOAT32:
        return rbxm.v_float32(0.0)
    if type_id == rbxm.T_FLOAT64:
        return rbxm.v_float64(0.0)
    if type_id == rbxm.T_UDIM:
        return rbxm.v_udim(0.0, 0)
    if type_id == rbxm.T_UDIM2:
        return rbxm.v_udim2(0.0, 0, 0.0, 0)
    if type_id == rbxm.T_RAY:
        return rbxm.v_ray((0, 0, 0), (0, 0, 0))
    if type_id == rbxm.T_FACES:
        return rbxm.v_faces(0)
    if type_id == rbxm.T_AXES:
        return rbxm.v_axes(0)
    if type_id == rbxm.T_BRICKCOLOR:
        return rbxm.v_brickcolor(194)
    if type_id == rbxm.T_COLOR3:
        return rbxm.v_color3(0.0, 0.0, 0.0)
    if type_id == rbxm.T_COLOR3UINT8:
        return rbxm.v_color3uint8(0, 0, 0)
    if type_id == rbxm.T_VECTOR2:
        return rbxm.v_vector2(0.0, 0.0)
    if type_id == rbxm.T_VECTOR3:
        return rbxm.v_vector3(0.0, 0.0, 0.0)
    if type_id == rbxm.T_VECTOR3INT16:
        return rbxm.v_vector3int16(0, 0, 0)
    if type_id == rbxm.T_CFRAME:
        return rbxm.v_cframe((0.0, 0.0, 0.0), rbxm.BASIC_ROTATIONS[0x02])
    if type_id == rbxm.T_OPTIONAL_CFRAME:
        return rbxm.v_optional_cframe(rbxm.v_cframe((0.0, 0.0, 0.0),
                                                    rbxm.BASIC_ROTATIONS[0x02]), False)
    if type_id == rbxm.T_ENUM:
        return rbxm.v_enum(0)
    if type_id == rbxm.T_REF:
        return rbxm.v_ref(-1)
    if type_id == rbxm.T_NUMBERSEQUENCE:
        return rbxm.v_numbersequence(DEFAULT_SEQUENCE[0])
    if type_id == rbxm.T_COLORSEQUENCE:
        return rbxm.v_colorsequence([(0.0, 1, 1, 1, 0.0), (1.0, 1, 1, 1, 0.0)])
    if type_id == rbxm.T_NUMBERRANGE:
        return rbxm.v_numberrange(0.0, 1.0)
    if type_id == rbxm.T_RECT:
        return rbxm.v_rect((0.0, 0.0), (0.0, 0.0))
    if type_id == rbxm.T_PHYSICALPROPERTIES:
        return rbxm.v_physicalproperties(0, None)
    if type_id == rbxm.T_SHAREDSTRING:
        return rbxm.v_sharedstring(0)
    if type_id == rbxm.T_UNIQUEID:
        return rbxm.v_uniqueid(0, 0, 0)
    if type_id == rbxm.T_FONT:
        return rbxm.v_font(b"rbxasset://fonts/families/LegacyArial.json", 400, 0, b"")
    if type_id == rbxm.T_SECURITYCAPABILITIES:
        return rbxm.v_securitycapabilities(0)
    if type_id == rbxm.T_CONTENT:
        return rbxm.v_content(0)
    raise rbxm.RbxmError("no default for type 0x%02x" % type_id)


def _text(element: ET.Element) -> str:
    return "".join(element.itertext())


def parse_property_element(element: ET.Element, shared_lookup: Dict[str, int],
                           name: str):
    """Return ``(type_id, payload)`` for one XML property element."""
    tag = element.tag

    if tag in ("string", "ProtectedString", "BinaryString"):
        if tag == "BinaryString":
            return rbxm.T_STRING, base64.b64decode(_text(element) or b"")
        return rbxm.T_STRING, decode_text(_text(element))
    if tag == "Content":
        child = list(element)
        if not child:
            return (rbxm.T_CONTENT, (0, None, None, b"")) if name not in CONTENT_ID_PROPS \
                else (rbxm.T_STRING, b"")
        inner = child[0]
        if name in CONTENT_ID_PROPS:
            if inner.tag == "url":
                return rbxm.T_STRING, decode_text(_text(inner))
            return rbxm.T_STRING, b""
        if inner.tag == "url":
            return rbxm.T_STRING, decode_text(_text(inner))
        if inner.tag == "uri":
            return rbxm.T_CONTENT, (1, decode_text(_text(inner)), None, b"")
        if inner.tag == "Ref":
            return rbxm.T_CONTENT, (2, None, int(_text(inner) or 0), b"")
        return rbxm.T_CONTENT, (0, None, None, b"")
    if tag == "bool":
        return rbxm.T_BOOL, _text(element).strip().lower() == "true"
    if tag == "int":
        value = int(_text(element) or 0)
        if name in BRICKCOLOR_PROPS:
            return rbxm.T_BRICKCOLOR, value
        return rbxm.T_INT32, value
    if tag == "int64":
        return rbxm.T_INT64, int(_text(element) or 0)
    if tag == "float":
        return rbxm.T_FLOAT32, parse_float(_text(element))
    if tag == "double":
        return rbxm.T_FLOAT64, parse_float(_text(element))
    if tag == "token":
        return rbxm.T_ENUM, int(_text(element) or 0)
    if tag == "Ref":
        text = _text(element).strip()
        if text in ("", "null"):
            return rbxm.T_REF, -1
        return rbxm.T_REF, parse_referent(text)
    if tag == "UDim":
        return rbxm.T_UDIM, (parse_float(element.findtext("S", "0")),
                             int(element.findtext("O", "0") or 0))
    if tag == "UDim2":
        return rbxm.T_UDIM2, (parse_float(element.findtext("XS", "0")),
                              int(element.findtext("XO", "0") or 0),
                              parse_float(element.findtext("YS", "0")),
                              int(element.findtext("YO", "0") or 0))
    if tag == "Vector2":
        return rbxm.T_VECTOR2, (parse_float(element.findtext("X", "0")),
                                parse_float(element.findtext("Y", "0")))
    if tag == "Vector3":
        return rbxm.T_VECTOR3, (parse_float(element.findtext("X", "0")),
                                parse_float(element.findtext("Y", "0")),
                                parse_float(element.findtext("Z", "0")))
    if tag == "Vector3int16":
        return rbxm.T_VECTOR3INT16, (int(element.findtext("X", "0") or 0),
                                     int(element.findtext("Y", "0") or 0),
                                     int(element.findtext("Z", "0") or 0))
    if tag == "Color3":
        return rbxm.T_COLOR3, (parse_float(element.findtext("R", "0")),
                               parse_float(element.findtext("G", "0")),
                               parse_float(element.findtext("B", "0")))
    if tag == "Color3uint8":
        packed = int(_text(element) or 0)
        return rbxm.T_COLOR3UINT8, ((packed >> 16) & 0xFF, (packed >> 8) & 0xFF, packed & 0xFF)
    if tag == "CoordinateFrame":
        position = (parse_float(element.findtext("X", "0")),
                    parse_float(element.findtext("Y", "0")),
                    parse_float(element.findtext("Z", "0")))
        matrix = tuple(
            tuple(parse_float(element.findtext("R%d%d" % (row, column), "0"))
                  for column in range(3))
            for row in range(3))
        return rbxm.T_CFRAME, (position, matrix)
    if tag == "OptionalCoordinateFrame":
        child = element.find("CFrame")
        if child is None:
            return rbxm.T_OPTIONAL_CFRAME, (
                rbxm.v_cframe((0.0, 0.0, 0.0), rbxm.BASIC_ROTATIONS[0x02]), False)
        position = (parse_float(child.findtext("X", "0")),
                    parse_float(child.findtext("Y", "0")),
                    parse_float(child.findtext("Z", "0")))
        matrix = tuple(
            tuple(parse_float(child.findtext("R%d%d" % (row, column), "0"))
                  for column in range(3))
            for row in range(3))
        return rbxm.T_OPTIONAL_CFRAME, (rbxm.v_cframe(position, matrix), True)
    if tag == "NumberSequence":
        numbers = [parse_float(part) for part in _text(element).split()]
        points = [(numbers[i], numbers[i + 1], numbers[i + 2])
                  for i in range(0, len(numbers) - 2, 3)]
        return rbxm.T_NUMBERSEQUENCE, points or DEFAULT_SEQUENCE[0]
    if tag == "ColorSequence":
        numbers = [parse_float(part) for part in _text(element).split()]
        points = [(numbers[i], numbers[i + 1], numbers[i + 2], numbers[i + 3],
                   numbers[i + 4] if i + 4 < len(numbers) else 0.0)
                  for i in range(0, len(numbers) - 4, 5)]
        return rbxm.T_COLORSEQUENCE, points or [(0.0, 1, 1, 1, 0.0), (1.0, 1, 1, 1, 0.0)]
    if tag == "NumberRange":
        numbers = [parse_float(part) for part in _text(element).split()]
        return rbxm.T_NUMBERRANGE, (numbers[0], numbers[1] if len(numbers) > 1 else numbers[0])
    if tag == "Rect2D":
        low = element.find("min")
        high = element.find("max")
        return rbxm.T_RECT, (
            ((parse_float(low.findtext("X", "0")), parse_float(low.findtext("Y", "0")))
             if low is not None else (0.0, 0.0)),
            ((parse_float(high.findtext("X", "0")), parse_float(high.findtext("Y", "0")))
             if high is not None else (0.0, 0.0)))
    if tag == "PhysicalProperties":
        custom = (element.findtext("CustomPhysics", "false") or "").strip().lower() == "true"
        if not custom:
            # Roblox flags non-custom properties with 0b10 ("has acoustic absorption")
            return rbxm.T_PHYSICALPROPERTIES, (2, None)
        values = [parse_float(element.findtext(label, "1"))
                  for label in ("Density", "Friction", "Elasticity", "FrictionWeight",
                                "ElasticityWeight", "AcousticAbsorption")]
        flag = 1 | (2 if element.find("AcousticAbsorption") is not None else 0)
        return rbxm.T_PHYSICALPROPERTIES, (flag, tuple(values))
    if tag == "Faces":
        return rbxm.T_FACES, int(element.findtext("faces", "0") or 0)
    if tag == "Axes":
        return rbxm.T_AXES, int(element.findtext("axes", "0") or 0)
    if tag == "Ray":
        origin = element.find("origin")
        direction = element.find("direction")

        def vec(node):
            if node is None:
                return (0.0, 0.0, 0.0)
            return (parse_float(node.findtext("X", "0")),
                    parse_float(node.findtext("Y", "0")),
                    parse_float(node.findtext("Z", "0")))

        return rbxm.T_RAY, (vec(origin), vec(direction))
    if tag in ("SharedString", "NetAssetRef"):
        label = _text(element).strip()
        if label not in shared_lookup:
            raise rbxm.RbxmError("SharedString %r is not defined in <SharedStrings>" % label)
        return rbxm.T_SHAREDSTRING, shared_lookup[label]
    if tag == "UniqueId":
        blob = bytes.fromhex(_text(element).strip() or "00" * 16)
        if len(blob) < 16:
            blob = blob + b"\0" * (16 - len(blob))
        rolled = int.from_bytes(blob[0:8], "big")
        random = ((rolled >> 1) | ((rolled & 1) << 63)) & 0xFFFFFFFFFFFFFFFF
        if random >= 1 << 63:
            random -= 1 << 64
        return rbxm.T_UNIQUEID, (int.from_bytes(blob[12:16], "big"),
                                 int.from_bytes(blob[8:12], "big"), random)
    if tag == "Font":
        family = element.find("Family")
        cached = element.find("CachedFaceId")
        return rbxm.T_FONT, (
            decode_text(family.findtext("url", "") if family is not None else ""),
            int(element.findtext("Weight", "400") or 400),
            1 if (element.findtext("Style", "Normal") or "").strip().lower() == "italic" else 0,
            decode_text(cached.findtext("url", "") if cached is not None else ""))
    if tag == "SecurityCapabilities":
        return rbxm.T_SECURITYCAPABILITIES, int(_text(element) or 0)
    raise rbxm.RbxmError("unsupported XML property element <%s>" % tag)


def parse_referent(text: str) -> int:
    text = text.strip()
    if text.startswith("RBX"):
        tail = text[3:]
        return int(tail, 16) if tail and all(c in "0123456789abcdefABCDEF" for c in tail) \
            else abs(hash(text)) % (2 ** 31)
    return int(text)


def xml_to_model(text: str) -> rbxm.Model:
    root = ET.fromstring(text)
    if root.tag != "roblox":
        raise rbxm.RbxmError("expected a <roblox> root element")

    model = rbxm.Model()
    shared_lookup: Dict[str, int] = {}
    definitions = root.find("SharedStrings")
    if definitions is not None:
        for element in definitions.findall("SharedString"):
            label = element.get("md5", "")
            model.shared_strings.append(base64.b64decode(_text(element) or b""))
            shared_lookup[label] = len(model.shared_strings) - 1

    for meta in root.findall("Meta"):
        model.metadata.append((decode_text(meta.get("name", "")), decode_text(_text(meta))))

    items: List[tuple] = []  # (referent, class, parent, Properties element)
    counter = [0]

    def take_referent(element: ET.Element) -> int:
        raw = element.get("referent")
        if raw is None:
            value = counter[0]
        else:
            try:
                value = parse_referent(raw)
            except ValueError:
                value = counter[0]
        counter[0] = max(counter[0], value) + 1
        return value

    def walk(element: ET.Element, parent: int) -> None:
        referent = take_referent(element)
        items.append((referent, element.get("class", "Instance"), parent,
                      element.find("Properties")))
        for child in element.findall("Item"):
            walk(child, referent)

    for element in root.findall("Item"):
        walk(element, -1)

    model.prnt_pairs = [(ref, parent) for ref, _cls, parent, _props in items]
    model.parents = dict(model.prnt_pairs)
    model.instance_count = len(items)
    if not model.instance_count:
        raise rbxm.RbxmError("the XML file contains no <Item> instances")

    by_class: Dict[str, List[int]] = {}
    for position, (ref, cls, _parent, _props) in enumerate(items):
        by_class.setdefault(cls, []).append(position)

    properties_by_class: Dict[str, List[tuple]] = {}
    for cls, positions in by_class.items():
        names: List[str] = []
        seen = set()
        for position in positions:
            props = items[position][3]
            if props is None:
                continue
            for element in props:
                name = element.get("name") or element.get("Name") or "UnknownProperty"
                key = (name, element.tag)
                if key not in seen:
                    seen.add(key)
                    names.append(key)
        properties_by_class[cls] = names

    for class_id, (cls, positions) in enumerate(by_class.items()):
        record = rbxm.ClassRecord(class_id, cls, 0)
        record.referents = [items[position][0] for position in positions]
        for name, tag in properties_by_class[cls]:
            values = []
            type_id = None
            for position in positions:
                props = items[position][3]
                found = None
                if props is not None:
                    for element in props:
                        if (element.get("name") or element.get("Name") or
                                "UnknownProperty") == name and element.tag == tag:
                            found = element
                            break
                if found is None:
                    values.append(None)
                    continue
                parsed_type, payload = parse_property_element(found, shared_lookup, name)
                type_id = parsed_type if type_id is None else type_id
                full = rbxm.TYPE_NAMES.get(parsed_type)
                values.append((parsed_type, full, payload))
            if type_id is None:
                continue
            resolved = []
            for entry in values:
                if entry is None:
                    resolved.append(default_value(type_id))
                else:
                    _parsed, full, payload = entry
                    resolved.append((full, payload))
            record.properties.append(rbxm.PropChunk(name, type_id, resolved))
        model.classes.append(record)

    model.class_count = len(model.classes)
    return model


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def main(argv: Sequence[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip().split("Command line::")[0].strip())
        print("\nusage: rbxmx.py <input .rbxm|.rbxmx> <output .rbxmx|.rbxm>")
        return 2
    source, target = argv[1], argv[2]
    data = rbxm.read_file(source)

    if source.lower().endswith((".rbxmx", ".rbxlx")) or data[:5] == b"<?xml":
        model = xml_to_model(data.decode("utf-8"))
        blob = rbxm.encode_model(model)
        rbxm.write_file(target, blob)
        print("wrote %s (%d bytes, %d instances, %d scripts)"
              % (target, len(blob), model.instance_count,
                 sum(len(c.referents) for c in model.classes
                     if c.name in ("Script", "LocalScript", "ModuleScript"))))
    else:
        model = rbxm.decode_model(data)
        text = model_to_xml(model)
        with open(target, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        print("wrote %s (%.1f MB of readable XML, %d instances, %d scripts)"
              % (target, len(text.encode("utf-8")) / 1e6, model.instance_count,
                 sum(len(c.referents) for c in model.classes
                     if c.name in ("Script", "LocalScript", "ModuleScript"))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
