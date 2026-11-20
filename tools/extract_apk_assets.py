#!/usr/bin/env python3
"""
Extracts and converts Sentinel 3: Homeworld assets and reverse-engineered game tables
from the user-supplied Android APK (and optional downloaded cache packs) into Godot-ready assets.
"""

import argparse
import json
import math
import os
import struct
import sys
import xml.etree.ElementTree as ET
import zipfile
import zlib
from pathlib import Path

WORKSPACE = Path(__file__).resolve().parent.parent
DOWNLOADS_DIR = Path.home() / "Downloads"
DEFAULT_APK_NAMES = ("Sentinel-3-Homeworld-v1-4-2.apk",)

OUT_ASSETS = WORKSPACE / "assets"
OUT_TEXTURES = OUT_ASSETS / "textures"
OUT_GENERATED = OUT_TEXTURES / "generated"
OUT_MAPS = OUT_ASSETS / "maps"
OUT_AUDIO = OUT_ASSETS / "audio"
OUT_DATA = OUT_ASSETS / "data"

PNG_SIG = b"\x89PNG\r\n\x1a\n"

# Fallback tilesets for Campaign 1 maps when the optional 67 MB OBB/cache pack isn't present.
# All Sentinel 3 tilesets share the exact same 256x256 (BaseBG) and 512x512 (BGSet / BGElements) tile layout.
TILESET_FALLBACKS = {
    "BaseBG1": "TS_BaseBG6",
    "BaseBG2": "TS_BaseBG6",
    "BaseBG3": "TS_BaseBG6",
    "BaseBG4": "TS_BaseBG6",
    "BaseBG5": "TS_BaseBG6",
    "BGSet01": "TS_BGSet06",
    "BGSet02": "TS_BGSet06Alt",
    "BGSet03": "TS_BGSet06",
    "BGSet04": "TS_BGSet05",
    "BGSet05": "TS_BGSet05",
    "BGElements01": "TS_BGElements06",
    "BGElements02": "TS_BGElements06",
    "BGElements03": "TS_BGElements07",
    "BGElements04": "TS_BGElements07",
    "BGElements05": "TS_BGElements07",
}

UNIFORM_SHEET_CELLS = {
    "MutantWalkerL1": 64,
    "MutantWalkerL2": 64,
    "MutantWalker": 64,
    "ArachnidL1": 64,
    "ArachnidL2": 64,
    "Arachnid": 64,
    "ArtilleryNormal": 128,
    "ArtilleryMax": 128,
    "PoisonNormal": 128,
    "PoisonMax": 128,
    "Hero": 96,
    "IONSphere_Base": 64,
    "IONSphere_Beam": 128,
}


def ensure_dirs() -> None:
    for d in (OUT_TEXTURES, OUT_GENERATED, OUT_MAPS, OUT_AUDIO, OUT_DATA):
        d.mkdir(parents=True, exist_ok=True)


def get_png_size(data: bytes) -> tuple[int, int]:
    return struct.unpack(">II", data[16:24])


def parse_region_xml(xml_bytes: bytes, img_w: int, img_h: int) -> list[list[int]]:
    root = ET.fromstring(xml_bytes.decode("utf-8"))
    regions: list[list[int]] = []
    for reg in root.findall("region"):
        coords = [float(c.attrib["value"]) for c in reg.findall("coord")]
        xs = coords[0::2]
        ys = coords[1::2]
        x1 = int(round(min(xs) * img_w))
        y1 = int(round(min(ys) * img_h))
        x2 = int(round(max(xs) * img_w))
        y2 = int(round(max(ys) * img_h))
        w = max(1, x2 - x1)
        h = max(1, y2 - y1)
        regions.append([x1, y1, w, h])
    return regions


def resolve_apk_path(cli_apk: str | None = None) -> Path | None:
    if cli_apk:
        p = Path(cli_apk).expanduser()
        return p if p.is_file() and zipfile.is_zipfile(p) else None

    env_apk = os.environ.get("SENTINEL3_APK", "").strip()
    if env_apk:
        p = Path(env_apk).expanduser()
        if p.is_file() and zipfile.is_zipfile(p):
            return p

    search_dirs = [WORKSPACE, WORKSPACE / "apk", DOWNLOADS_DIR]
    for d in search_dirs:
        if not d.exists():
            continue
        for fname in DEFAULT_APK_NAMES:
            cand = d / fname
            if cand.is_file() and zipfile.is_zipfile(cand):
                return cand
    for d in search_dirs:
        if not d.exists():
            continue
        for p in sorted(d.iterdir()):
            if p.is_file() and p.suffix.lower() == ".apk" and "sentinel" in p.name.lower():
                if zipfile.is_zipfile(p):
                    return p
    return None


def find_source_zips(apk_path: Path) -> list[Path]:
    zips = [apk_path]
    seen = {apk_path.resolve()}
    for d in (apk_path.parent, WORKSPACE, WORKSPACE / "apk", DOWNLOADS_DIR):
        if not d.exists():
            continue
        for p in sorted(d.iterdir()):
            if not p.is_file():
                continue
            rp = p.resolve()
            if rp in seen:
                continue
            low = p.name.lower()
            if low.endswith((".zip", ".apk", ".obb")) and (
                "sentinel" in low or "required" in low or "hdaddon" in low or "campaign2hd" in low
            ):
                if zipfile.is_zipfile(p):
                    seen.add(rp)
                    zips.append(p)
    return zips


def extract_archives(zip_paths: list[Path]) -> tuple[dict[str, tuple[int, int]], dict[str, list[list[int]]], bytes]:
    texture_sizes: dict[str, tuple[int, int]] = {}
    xml_raw: dict[str, bytes] = {}
    so_bytes = b""

    for zp in zip_paths:
        print(f"[extract] Reading archive: {zp.name}")
        with zipfile.ZipFile(zp, "r") as z:
            for name in z.namelist():
                if name == "lib/x86/libSentinel3Android.so" and not so_bytes:
                    so_bytes = z.read(name)
                    continue
                if not name.startswith("assets/"):
                    continue
                rel = name[len("assets/"):]
                if not rel or "/" in rel:
                    continue
                stem, ext = os.path.splitext(rel)
                ext_low = ext.lower()
                data = z.read(name)

                if ext_low == ".mp3" and data[:8] == PNG_SIG:
                    out_file = OUT_TEXTURES / f"{stem}.png"
                    out_file.write_bytes(data)
                    texture_sizes[stem] = get_png_size(data)
                elif ext_low == ".png" and data[:8] == PNG_SIG:
                    out_file = OUT_TEXTURES / f"{stem}.png"
                    out_file.write_bytes(data)
                    texture_sizes[stem] = get_png_size(data)
                elif ext_low == ".xml":
                    xml_raw[stem] = data
                elif ext_low == ".tmx":
                    (OUT_MAPS / rel).write_bytes(data)
                elif ext_low == ".ogg":
                    (OUT_AUDIO / rel).write_bytes(data)

    regions_map: dict[str, list[list[int]]] = {}
    for stem, xml_data in xml_raw.items():
        if stem in texture_sizes:
            w, h = texture_sizes[stem]
            regions_map[stem] = parse_region_xml(xml_data, w, h)

    for stem, cell in UNIFORM_SHEET_CELLS.items():
        if stem in texture_sizes and stem not in regions_map:
            w, h = texture_sizes[stem]
            cols = w // cell
            rows = h // cell
            regions_map[stem] = [
                [c * cell, r * cell, cell, cell]
                for r in range(rows)
                for c in range(cols)
            ]

    return texture_sizes, regions_map, so_bytes


def resolve_tileset_texture(ts_name: str, texture_sizes: dict[str, tuple[int, int]]) -> str:
    candidates = [ts_name, f"TS_{ts_name}"]
    for cand in candidates:
        if cand in texture_sizes:
            return cand
    fb = TILESET_FALLBACKS.get(ts_name)
    if fb and fb in texture_sizes:
        return fb
    return "TS_BaseBG6"


def parse_tmx_maps(texture_sizes: dict[str, tuple[int, int]]) -> dict[str, dict]:
    maps_out: dict[str, dict] = {}
    for tmx_path in sorted(OUT_MAPS.glob("*.tmx")):
        root = ET.fromstring(tmx_path.read_text(encoding="utf-8"))
        width = int(root.attrib["width"])
        height = int(root.attrib["height"])
        tile_w = int(root.attrib["tilewidth"])
        tile_h = int(root.attrib["tileheight"])

        map_props = {
            p.attrib["name"]: p.attrib["value"]
            for p in root.findall("./properties/property")
        }

        tilesets = []
        for ts in root.findall("tileset"):
            ts_name = ts.attrib["name"]
            firstgid = int(ts.attrib["firstgid"])
            img_el = ts.find("image")
            img_w = int(img_el.attrib["width"]) if img_el is not None else 256
            img_h = int(img_el.attrib["height"]) if img_el is not None else 256
            resolved = resolve_tileset_texture(ts_name, texture_sizes)
            tex_w, tex_h = texture_sizes.get(resolved, (img_w, img_h))
            cols_tmx = max(1, img_w // tile_w)
            rows_tmx = max(1, img_h // tile_h)
            tilesets.append({
                "name": ts_name,
                "firstgid": firstgid,
                "tmx_width": img_w,
                "tmx_height": img_h,
                "cols": cols_tmx,
                "rows": rows_tmx,
                "tile_count": cols_tmx * rows_tmx,
                "resolved_texture": resolved,
                "tex_width": tex_w,
                "tex_height": tex_h,
                "src_tile_w": tex_w // cols_tmx,
                "src_tile_h": tex_h // rows_tmx,
            })
        tilesets.sort(key=lambda t: t["firstgid"])

        layers = []
        path_grid = [0] * (width * height)
        reserved_grid = [0] * (width * height)

        for layer in root.findall("layer"):
            lname = layer.attrib["name"]
            visible = layer.attrib.get("visible", "1") != "0"
            lprops = {
                p.attrib["name"]: p.attrib["value"]
                for p in layer.findall("./properties/property")
            }
            tile_type = lprops.get("LayerTileType", "")
            tiles = [int(t.attrib["gid"]) for t in layer.findall("./data/tile")]
            if tile_type == "Path" or lname == "Path":
                for idx, gid in enumerate(tiles):
                    if gid != 0:
                        path_grid[idx] = 1
            elif tile_type == "Reserved" or lname in ("Reserved", "Nobuild"):
                for idx, gid in enumerate(tiles):
                    if gid != 0:
                        reserved_grid[idx] = 1
            else:
                if visible:
                    layers.append({"name": lname, "tiles": tiles})

        enemy_paths = []
        destroyables = []
        special_objects = []

        for og in root.findall("objectgroup"):
            og_name = og.attrib.get("name", "")
            og_props = {
                p.attrib["name"]: p.attrib["value"]
                for p in og.findall("./properties/property")
            }
            if og_name == "EnemyPath":
                wps = []
                for obj in og.findall("object"):
                    oprops = {
                        p.attrib["name"]: p.attrib["value"]
                        for p in obj.findall("./properties/property")
                    }
                    wps.append({
                        "x": float(obj.attrib["x"]),
                        "y": float(obj.attrib["y"]),
                        "linked_destroyable": int(oprops["LinkedDestroyable"]) if "LinkedDestroyable" in oprops else -1,
                    })
                enemy_paths.append({
                    "enemy_type": og_props.get("EnemyType", "Ground"),
                    "enemy_chance": float(og_props.get("EnemyChance", "1.0")),
                    "waypoints": wps,
                })
            elif og_name == "Destroyables":
                for idx, obj in enumerate(og.findall("object")):
                    oprops = {
                        p.attrib["name"]: p.attrib["value"]
                        for p in obj.findall("./properties/property")
                    }
                    destroyables.append({
                        "index": idx,
                        "name": obj.attrib.get("name", f"Barrier{idx + 1}"),
                        "type": obj.attrib.get("type", "Normal"),
                        "x": float(obj.attrib["x"]),
                        "y": float(obj.attrib["y"]),
                        "direction": oprops.get("Direction", "Right"),
                    })
            elif og_name == "SpecialGameObjects":
                for obj in og.findall("object"):
                    special_objects.append({
                        "name": obj.attrib.get("name", ""),
                        "type": obj.attrib.get("type", ""),
                        "x": float(obj.attrib["x"]),
                        "y": float(obj.attrib["y"]),
                    })

        maps_out[tmx_path.stem] = {
            "id": tmx_path.stem,
            "width": width,
            "height": height,
            "tilewidth": tile_w,
            "tileheight": tile_h,
            "fx_layer_type": map_props.get("FXLayerType", "Fog"),
            "tilesets": tilesets,
            "layers": layers,
            "path_grid": path_grid,
            "reserved_grid": reserved_grid,
            "enemy_paths": enemy_paths,
            "destroyables": destroyables,
            "special_objects": special_objects,
        }
    return maps_out


def extract_campaign_and_waves(so_bytes: bytes) -> dict:
    def read_cstr(addr: int) -> str:
        if addr <= 0 or addr >= len(so_bytes):
            return ""
        end = so_bytes.find(b"\x00", addr)
        if end == -1:
            return ""
        return so_bytes[addr:end].decode("ascii", errors="ignore")

    camp_off = 0x1E208C - 0x1000
    levels = []
    for i in range(35):
        row = so_bytes[camp_off + i * 60 : camp_off + (i + 1) * 60]
        p0, p1, p2, p3, p4, p5, b0, b1, b2, b3, waves, cash, energy, b4, b5, b6, b7, d0, d1, d2, d3 = struct.unpack(
            "<6I4B3i4B4f", row
        )
        campaign = 1 if i < 20 else 2
        map_key = f"Map{b0}" if campaign == 1 else f"C2Map{b0}"
        desc_lines = [read_cstr(ptr) for ptr in (p1, p2, p3, p4, p5) if read_cstr(ptr)]
        levels.append({
            "index": i,
            "campaign": campaign,
            "mission_number": (i + 1) if campaign == 1 else (i - 19),
            "title": read_cstr(p0),
            "description": " ".join(desc_lines),
            "map_id": map_key,
            "wave_pattern_index": b2,
            "waves": waves,
            "starting_cash": cash,
            "starting_energy": energy,
            "difficulty_mults": {
                "easy": round(d0, 2),
                "medium": round(d1, 2),
                "hard": round(d2, 2),
                "psycho": round(d3, 2),
            },
        })

    wave_off = 0x1E3AB0 - 0x1000
    wave_bytes = so_bytes[wave_off : wave_off + 600]
    wave_patterns = [
        list(wave_bytes[p * 30 : (p + 1) * 30])
        for p in range(20)
    ]

    return {
        "levels": levels,
        "wave_patterns": wave_patterns,
    }


# --- Pure-Python PNG RGBA Canvas for crisp generated tower/barrier sprites ---

class Canvas:
    def __init__(self, width: int, height: int) -> None:
        self.w = width
        self.h = height
        self.buf = bytearray(width * height * 4)

    def blend_px(self, x: int, y: int, r: int, g: int, b: int, a: int) -> None:
        if x < 0 or y < 0 or x >= self.w or y >= self.h or a <= 0:
            return
        idx = (y * self.w + x) * 4
        sa = a / 255.0
        da = self.buf[idx + 3] / 255.0
        out_a = sa + da * (1.0 - sa)
        if out_a <= 0.0:
            return
        self.buf[idx] = int(min(255, (r * sa + self.buf[idx] * da * (1.0 - sa)) / out_a))
        self.buf[idx + 1] = int(min(255, (g * sa + self.buf[idx + 1] * da * (1.0 - sa)) / out_a))
        self.buf[idx + 2] = int(min(255, (b * sa + self.buf[idx + 2] * da * (1.0 - sa)) / out_a))
        self.buf[idx + 3] = int(min(255, out_a * 255.0))

    def fill_circle(self, cx: float, cy: float, radius: float, color: tuple[int, int, int, int]) -> None:
        r, g, b, a = color
        x0 = max(0, int(cx - radius - 2))
        x1 = min(self.w - 1, int(cx + radius + 2))
        y0 = max(0, int(cy - radius - 2))
        y1 = min(self.h - 1, int(cy + radius + 2))
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
                if d <= radius + 0.7:
                    cov = max(0.0, min(1.0, radius + 0.7 - d))
                    self.blend_px(x, y, r, g, b, int(a * cov))

    def ring(self, cx: float, cy: float, radius: float, thickness: float, color: tuple[int, int, int, int]) -> None:
        r, g, b, a = color
        x0 = max(0, int(cx - radius - thickness - 2))
        x1 = min(self.w - 1, int(cx + radius + thickness + 2))
        y0 = max(0, int(cy - radius - thickness - 2))
        y1 = min(self.h - 1, int(cy + radius + thickness + 2))
        half = thickness * 0.5
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                d = abs(math.hypot(x + 0.5 - cx, y + 0.5 - cy) - radius)
                if d <= half + 0.7:
                    cov = max(0.0, min(1.0, half + 0.7 - d))
                    self.blend_px(x, y, r, g, b, int(a * cov))

    def fill_rect(self, x0: float, y0: float, x1: float, y1: float, color: tuple[int, int, int, int]) -> None:
        r, g, b, a = color
        ix0 = max(0, int(math.floor(x0)))
        iy0 = max(0, int(math.floor(y0)))
        ix1 = min(self.w - 1, int(math.ceil(x1)))
        iy1 = min(self.h - 1, int(math.ceil(y1)))
        for y in range(iy0, iy1 + 1):
            for x in range(ix0, ix1 + 1):
                if x0 <= x + 0.5 <= x1 and y0 <= y + 0.5 <= y1:
                    self.blend_px(x, y, r, g, b, a)

    def to_png_bytes(self) -> bytes:
        def chunk(tag: bytes, data: bytes) -> bytes:
            return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

        raw = bytearray()
        stride = self.w * 4
        for y in range(self.h):
            raw.append(0)
            raw.extend(self.buf[y * stride : (y + 1) * stride])
        ihdr = struct.pack(">IIBBBBB", self.w, self.h, 8, 6, 0, 0, 0)
        return PNG_SIG + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b"")


def generate_turret_and_barrier_sheets(regions_map: dict[str, list[list[int]]]) -> None:
    """
    Creates crisp, Sentinel 3-styled sci-fi sprite sheets for towers/barriers/drones
    whose textures live in the optional 67 MB OBB cache rather than the base APK.
    Layout of turrets_sheet.png (512x512, 8 cols x 8 rows of 64x64 cells):
      Row 0..6 (Laser, Bomb, Slow, Beam, Sniper, Booster, Missile):
        Col 0..3 = Base pedestals L1..L4
        Col 4..7 = Rotating turret heads L1..L4 (pointing RIGHT = +X, Godot rotation=0)
      Row 7:
        Col 0 = Barrier Normal, Col 1 = Barrier Base, Col 2 = Harvest Drone,
        Col 3 = Attack Drone, Col 4 = Barrier Shield Glow
    """
    cell = 64
    canvas = Canvas(512, 512)

    tower_themes = [
        ("laser", (60, 210, 255), "single"),
        ("bomb", (255, 145, 50), "mortar"),
        ("slow", (90, 175, 255), "tesla"),
        ("beam", (190, 95, 255), "prism"),
        ("sniper", (255, 70, 90), "rail"),
        ("booster", (70, 255, 190), "beacon"),
        ("missile", (255, 215, 65), "pod"),
    ]

    for row, (tname, accent, style) in enumerate(tower_themes):
        ar, ag, ab = accent
        for tier in range(4):
            # Base pedestal (col = tier)
            bx = tier * cell + 32
            by = row * cell + 32
            canvas.fill_circle(bx, by, 26, (18, 24, 34, 210))
            canvas.fill_circle(bx, by, 23, (56, 68, 86, 255))
            canvas.ring(bx, by, 22, 2.5, (110, 128, 152, 255))
            # Corner bolts / armor plates scale up with tier
            for k in range(4 + tier * 2):
                ang = k * (2 * math.pi / (4 + tier * 2))
                px = bx + math.cos(ang) * 18
                py = by + math.sin(ang) * 18
                canvas.fill_circle(px, py, 2.2, (ar, ag, ab, 230) if tier >= 2 else (175, 190, 210, 255))
            canvas.fill_circle(bx, by, 13, (34, 42, 54, 255))
            if tier == 3:
                canvas.ring(bx, by, 24.5, 2.0, (ar, ag, ab, 220))

            # Turret head pointing right (+X) (col = 4 + tier)
            tx = (4 + tier) * cell + 32
            ty = row * cell + 32
            if style == "single":
                barrels = 1 if tier < 2 else 2
                if barrels == 1:
                    canvas.fill_rect(tx + 2, ty - 4, tx + 26 + tier * 2, ty + 4, (145, 165, 185, 255))
                    canvas.fill_rect(tx + 12, ty - 2, tx + 27 + tier * 2, ty + 2, (ar, ag, ab, 255))
                else:
                    for off in (-6, 6):
                        canvas.fill_rect(tx + 2, ty + off - 3, tx + 28, ty + off + 3, (145, 165, 185, 255))
                        canvas.fill_rect(tx + 14, ty + off - 1.5, tx + 29, ty + off + 1.5, (ar, ag, ab, 255))
                canvas.fill_circle(tx - 2, ty, 12 + tier, (78, 96, 118, 255))
                canvas.fill_circle(tx - 2, ty, 6 + tier * 0.6, (ar, ag, ab, 255))
            elif style == "mortar":
                canvas.fill_circle(tx, ty, 14 + tier, (92, 86, 80, 255))
                canvas.fill_rect(tx + 2, ty - 7 - tier, tx + 24, ty + 7 + tier, (125, 120, 115, 255))
                canvas.fill_rect(tx + 18, ty - 6, tx + 26, ty + 6, (40, 38, 36, 255))
                canvas.fill_circle(tx - 2, ty, 7, (ar, ag, ab, 255))
            elif style == "tesla":
                canvas.fill_circle(tx, ty, 13 + tier, (64, 82, 110, 255))
                canvas.ring(tx, ty, 16 + tier * 1.5, 2.5, (ar, ag, ab, 230))
                canvas.fill_circle(tx, ty, 8, (180, 240, 255, 255))
            elif style == "prism":
                canvas.fill_rect(tx - 6, ty - 11, tx + 18 + tier * 2, ty + 11, (90, 74, 124, 255))
                canvas.fill_rect(tx + 6, ty - 4, tx + 28, ty + 4, (ar, ag, ab, 255))
                canvas.fill_circle(tx - 2, ty, 10, (240, 200, 255, 255))
            elif style == "rail":
                canvas.fill_rect(tx - 8, ty - 9, tx + 12, ty + 9, (74, 84, 98, 255))
                canvas.fill_rect(tx + 4, ty - 5, tx + 31, ty - 1.5, (185, 200, 220, 255))
                canvas.fill_rect(tx + 4, ty + 1.5, tx + 31, ty + 5, (185, 200, 220, 255))
                canvas.fill_rect(tx + 6, ty - 1.5, tx + 29, ty + 1.5, (ar, ag, ab, 255))
                canvas.fill_circle(tx - 3, ty, 8 + tier * 0.5, (ar, ag, ab, 255))
            elif style == "beacon":
                canvas.fill_circle(tx, ty, 14 + tier, (55, 95, 88, 255))
                canvas.ring(tx, ty, 11 + tier, 2.5, (ar, ag, ab, 255))
                canvas.fill_circle(tx, ty, 6 + tier, (195, 255, 235, 255))
            elif style == "pod":
                canvas.fill_rect(tx - 10, ty - 13 - tier, tx + 16, ty + 13 + tier, (92, 98, 108, 255))
                for oy in (-7, 0, 7):
                    canvas.fill_circle(tx + 12, ty + oy, 3.2, (ar, ag, ab, 255))
                canvas.fill_circle(tx - 4, ty, 6, (255, 230, 120, 255))

    # Row 7: Barriers & Drones
    # Col 0: Normal Barrier (vertical energy gate)
    bx, by = 32, 7 * cell + 32
    canvas.fill_rect(bx - 12, by - 28, bx + 12, by - 14, (85, 98, 116, 255))
    canvas.fill_rect(bx - 12, by + 14, bx + 12, by + 28, (85, 98, 116, 255))
    canvas.fill_rect(bx - 6, by - 16, bx + 6, by + 16, (40, 195, 255, 195))
    canvas.fill_rect(bx - 2, by - 16, bx + 2, by + 16, (200, 248, 255, 255))

    # Col 1: Base Barrier (heavy armored fortress gate)
    bx, by = cell + 32, 7 * cell + 32
    canvas.fill_rect(bx - 18, by - 30, bx + 18, by + 30, (70, 82, 102, 255))
    canvas.fill_rect(bx - 13, by - 25, bx + 13, by + 25, (110, 128, 152, 255))
    canvas.fill_rect(bx - 6, by - 22, bx + 6, by + 22, (60, 255, 180, 210))
    canvas.fill_circle(bx, by, 8, (180, 255, 230, 255))

    # Col 2: Harvest Drone
    bx, by = 2 * cell + 32, 7 * cell + 32
    canvas.fill_circle(bx, by, 14, (75, 95, 120, 255))
    canvas.ring(bx, by, 17, 2.2, (80, 235, 255, 230))
    canvas.fill_circle(bx + 4, by, 6, (160, 250, 255, 255))

    # Col 3: Attack Drone
    bx, by = 3 * cell + 32, 7 * cell + 32
    canvas.fill_circle(bx, by, 13, (110, 75, 75, 255))
    canvas.ring(bx, by, 16, 2.2, (255, 110, 80, 230))
    canvas.fill_rect(bx + 4, by - 3, bx + 20, by + 3, (255, 170, 90, 255))

    out_png = OUT_GENERATED / "turrets_sheet.png"
    out_png.write_bytes(canvas.to_png_bytes())

    regions_map["turrets_sheet"] = [
        [c * cell, r * cell, cell, cell]
        for r in range(8)
        for c in range(8)
    ]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract Sentinel 3: Homeworld assets and reverse-engineered data tables for Minder."
    )
    parser.add_argument(
        "--apk",
        help="Path to Sentinel-3-Homeworld-v1-4-2.apk (defaults to project root, ./apk/, ~/Downloads, or $SENTINEL3_APK).",
    )
    args = parser.parse_args()

    apk_path = resolve_apk_path(args.apk)
    if apk_path is None:
        print("[extract] ERROR: Sentinel 3: Homeworld APK not found.", file=sys.stderr)
        print("  1. Obtain Sentinel-3-Homeworld-v1-4-2.apk (e.g. https://pdalife.com/sentinel-3-homeworld-android-a1646.html)", file=sys.stderr)
        print(f"  2. Place it in '{WORKSPACE}', '{WORKSPACE / 'apk'}', or '{DOWNLOADS_DIR}', OR pass:", file=sys.stderr)
        print("     python tools/extract_apk_assets.py --apk /path/to/Sentinel-3-Homeworld-v1-4-2.apk", file=sys.stderr)
        sys.exit(1)

    print(f"[extract] Using APK: {apk_path}")
    ensure_dirs()
    zips = find_source_zips(apk_path)
    texture_sizes, regions_map, so_bytes = extract_archives(zips)
    if not so_bytes:
        print("[extract] ERROR: lib/x86/libSentinel3Android.so was not found inside the APK.", file=sys.stderr)
        sys.exit(1)

    generate_turret_and_barrier_sheets(regions_map)

    maps_data = parse_tmx_maps(texture_sizes)
    campaign_data = extract_campaign_and_waves(so_bytes)

    (OUT_DATA / "sprite_regions.json").write_text(json.dumps(regions_map, indent=2), encoding="utf-8")
    (OUT_DATA / "maps.json").write_text(json.dumps(maps_data, indent=2), encoding="utf-8")
    (OUT_DATA / "campaign_data.json").write_text(json.dumps(campaign_data, indent=2), encoding="utf-8")

    print(f"[extract] Done! Textures: {len(texture_sizes)}, Regions: {len(regions_map)}, Maps: {len(maps_data)}, Campaign Missions: {len(campaign_data['levels'])}")


if __name__ == "__main__":
    main()
