# Minder

A cross-platform sci-fi tactical tower defense engine built in **Godot 4.7.2** (`GL Compatibility` renderer for desktop and mobile), paired with a reverse-engineered asset & data extraction pipeline for **Sentinel 3: Homeworld**.

> **Disclaimer:** *Minder is an open-source, non-commercial Godot 4 engine reimplementation and game-preservation project built for educational purposes. No proprietary assets from Sentinel 3: Homeworld are distributed in this repository; users must supply their own copy of the original Android APK via `tools/extract_apk_assets.py`.*

---

## Features

- **Full Campaign Support:** Decodes all 35 campaign missions across Campaign 1 & Campaign 2, 20 wave patterns, quadratic enemy HP/reward scaling, and all 29 `.tmx` tactical maps directly from the APK.
- **9 Tower Classes (L1–L4 Tiers):** Laser, Bomb (with L4 Cluster Bombs), Slow, Booster (shared buff pool + range aura), Missile (homing), 2×2 Poison (heavy DoT), 2×2 Artillery (long-range splash), Beam, and Sniper, with an authentic **80% sell refund** and **5% end-of-wave interest**.
- **Hero Commander & Harvest Drone:** Repositionable Commander mech with ranged plasma, melee blades, Ground Stomp stun/slow, and a 96px Morale Aura (`+25%` damage / `+20%` fire rate), plus an autonomous Harvest Drone toggling between resource harvesting (`+$5` & `+6 Energy`) and Barrier repair.
- **Sentinel Orbital Weapons:** Orbital Laser, Ion Bomb, Turret Energizer, and Repair Beam powered by Ship Energy.
- **Desktop & Mobile Unified Controls:** Single responsive `960×540` canvas with touch/mouse emulation, tap-to-place, drag-and-drop placement, and keyboard shortcuts (`Space`, `Esc`).

---

## Step-by-Step Local Setup Guide

Follow these steps to extract the assets from your own copy of the APK and run the game locally:

### Step 1: Prerequisites
- **[Python 3.9+](https://www.python.org/downloads/)** (uses only the Python standard library — no `pip install` dependencies required)
- **[Godot Engine 4.7.2](https://godotengine.org/download/)** (or Godot 4.3+ supporting `GL Compatibility`)

### Step 2: Clone the Repository
```bash
git clone https://github.com/mderemus/minder.git
cd minder
```

### Step 3: Supply the APK
1. Download **`Sentinel-3-Homeworld-v1-4-2.apk`** from:
   <https://pdalife.com/sentinel-3-homeworld-android-a1646.html>
2. Place `Sentinel-3-Homeworld-v1-4-2.apk` in either:
   - Your `Downloads` folder (`~/Downloads/` or `%USERPROFILE%\Downloads\`), **or**
   - The cloned `minder/` project root folder (`./Sentinel-3-Homeworld-v1-4-2.apk`).

*(Optional)* If you also have any companion HD/OBB cache `.zip`/`.obb` packs, leave them in `Downloads` alongside the APK and the script will automatically pick them up too.

### Step 4: Extract Game Assets & Data Tables
Run the extractor from the repository root:

```bash
python tools/extract_apk_assets.py
```

Or specify an explicit path to the APK:

```bash
python tools/extract_apk_assets.py --apk /path/to/Sentinel-3-Homeworld-v1-4-2.apk
```

This unpacks and generates:
- `assets/textures/` (86 PNG sprite sheets + procedurally generated `generated/turrets_sheet.png`)
- `assets/audio/` (51 `.ogg` SFX and music tracks)
- `assets/maps/` (29 `.tmx` map files)
- `assets/data/` (`campaign_data.json`, `maps.json`, `sprite_regions.json`)

*(Note: `assets/textures/`, `assets/audio/`, `assets/maps/`, and `assets/data/` are `.gitignore`d so extracted files stay strictly local.)*

### Step 5: Import & Run in Godot

**Option 1 — Using the Godot Editor GUI:**
1. Open Godot Engine and click **Import**.
2. Browse to the cloned `minder/` folder and select `project.godot`.
3. Wait a moment for Godot to import the extracted textures/audio, then press **Play** (`F5`).

**Option 2 — Using the Command Line:**
```bash
# First-time headless asset import (recommended once after running the extractor)
godot --headless --path . --import --quit

# Launch the playable game
godot --path .
```

### Step 6: Run the Automated Test Suite (Optional)
Verify all 42 gameplay assertions (economy, upgrades, buffs, wave combat, orbitals, and turret alignment):

```bash
godot --path . res://tests/verify_gameplay.tscn
```

Expected output ends with `ALL_TESTS_PASSED`.

---

## Controls

| Action | Desktop / Mobile |
| --- | --- |
| **Build Turret** | Click/tap a turret in the right sidebar, then click/tap a green map tile (or drag & release onto the map). |
| **Upgrade / Sell** | Click/tap any built turret to open the Tactical Inspector (Upgrade tiers 1–4, or Sell for 80% refund). |
| **Move Commander** | Click/tap the Commander (or `MOVE CMDR`), then tap any map tile. Use `STOMP` for AoE damage + slow. |
| **Harvest Drone** | Click `HARVEST` to toggle between gathering `$Credits/+Energy` and repairing damaged Barriers. |
| **Orbital Strike** | Click an Orbital Weapon (`LASER`, `ION`, `CHARGE`, `REPAIR`), then tap the target location. |
| **Shortcuts** | `Space` = Next Wave · `Esc` / Right-Click = Cancel active placement / deselect. |

---

## Developer Deep-Dive & Modding Guide

Curious how `libSentinel3Android.so` was reverse engineered, how the APK's disguised PNG-as-`.mp3` files and 64-frame turret sheets work, or how to mod new towers and maps?

- **Interactive Web Guide:** Open `docs/index.html` in your browser (offline mini-site with architecture diagram, Wave HP Calculator, and searchable tower table).
- **Markdown Guide:** Read [docs/MAKING_OF_SENTINEL3.md](docs/MAKING_OF_SENTINEL3.md).
