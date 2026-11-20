# Building Sentinel 3: Homeworld in Godot 4 — Developer Deep-Dive & Field Manual

> This documentation lives inside `docs/`, which includes an empty `.gdignore` file so Godot ignores the directory completely and never bundles it with game imports or exports. For the interactive version (with live wave HP calculator and filterable tower table), open [`index.html`](index.html) in any browser.

---

## 1. Overview & Numbers

Rather than approximating wave scaling or upgrade values by feel, this clone combines **static ELF binary analysis** of the Android native library (`lib/x86/libSentinel3Android.so` inside `Sentinel-3-Homeworld-v1-4-2.apk`) with an automated **Python asset-extraction pipeline** (`tools/extract_apk_assets.py`) feeding a lightweight **Godot 4.7.2** engine (`gl_compatibility` renderer for both desktop and mobile).

- **35** campaign missions decoded across Campaign 1 and Campaign 2 (`assets/data/campaign_data.json`)
- **20** wave pattern tables × 30 waves
- **29** `.tmx` maps parsed into `assets/data/maps.json`
- **86** PNG sprite sheets extracted (`assets/textures/`) + **58** atlas definitions (`assets/data/sprite_regions.json`)
- **51** `.ogg` sound effects and music tracks (`assets/audio/`)
- **42** automated end-to-end gameplay assertions (`tests/verify_gameplay.tscn` / `tests/verify_gameplay.gd`)

---

## 2. Reverse Engineering `libSentinel3Android.so`

The Android native library shipped with unstripped C++ symbol names, letting us inspect the exact functions and `.rodata`/`.data` tables:

| Original Symbol / Offset | Decoded Logic / Table | Where Used |
| --- | --- | --- |
| `g_CampaignData` @ `0x1e208c` | 35 mission entries × 60 bytes: title/briefing pointers, map index, wave pattern index, wave count, cash, energy, and `[easy, medium, hard, psycho]` float multipliers | `tools/extract_apk_assets.py` → `assets/data/campaign_data.json` |
| `g_EnemyWavePatternData` @ `0x1e3ab0` | 20 wave patterns × 30 waves (600 bytes), indexing enemy types `0..19` | `assets/data/campaign_data.json` |
| `EnemyManager::SpawnEnemy` @ `0x110d50` | Quadratic scaling via `MthPow2(x) = x²`, per-enemy speeds, melee damage, attack intervals, flying flags, resistances | `GameData.ENEMY_DEFS` & `get_wave_spawn_spec()` |
| `TowerManager::InitTowerProperties` @ `0x11bd90` | 4-tier cost tables (`0x19e2d0`) and damage tables (`0x19e4a0`) across all 9 tower types | `GameData.TOWER_DEFS` in `scripts/game_data.gd` |
| `TowerManager::GetTowerSellPrice` @ `0x11b150` | `0.80` refund multiplier on cumulative build + upgrade spend | `SELL_REFUND_RATIO := 0.80` |
| `PlayerManager::AddMoneyInterest` @ `0x119560` | `int((cash / 100.0) * 5.0)` end-of-wave interest | `_on_wave_cleared()` in `scripts/game_manager.gd` |

### Exact Wave HP & Bounty Formulas

```gdscript
var w := float(wave_idx) # 0-based wave index
var hp: float = (float(edef["base_hp"]) + pow(float(edef["hp_scale"]) * w, 2.0)) * diff_mult
var reward: int = maxi(1, int(float(edef["reward_base"]) + pow(float(edef["reward_scale"]) * w, 2.0)))
```

### APK Texture & XML Quirks
1. **PNGs disguised as `.mp3`:** Over 80 sprite sheets in `assets/*.mp3` actually start with `\x89PNG\r\n\x1a\n`. The original developers used `.mp3` extensions so older Android APK packaging wouldn't compress or reject them. `extract_apk_assets.py` checks file signatures and writes real `.png` files.
2. **Normalized XML UV coordinates:** XML region files contain `value` attributes (`0.0..1.0`) alongside `pix` hints. Multiplying normalized UVs by the actual decoded PNG width/height ensures half-res textures like `Behemoth.png` slice accurately.

---

## 3. Reused vs. Mapped vs. Built New

| Component | Source | Details |
| --- | --- | --- |
| **Maps & Waypoints** | Reused from APK | All 29 `.tmx` maps, tile layers, `EnemyPath` / `FlyingEnemyPath` chains, `Destroyables` barriers, `SpecialGameObjects` |
| **Audio** | Reused from APK | All 51 `.ogg` SFX & music tracks |
| **Heavy Turrets, Hero & Enemies** | Reused from APK | `ArtilleryNormal/Max`, `PoisonNormal/Max`, `Hero1`, `EggMound`, all Mutant/Arachnid/Flyer/Resistant/Boss sheets |
| **Campaign 1 Map Tilesets** | Remapped | Campaign 1 textures (`BaseBG1..5`, `BGSet01..05`, `BGElements01..05`) lived in the optional ~67 MB external cache. Since Sentinel 3 reuses exact 256×256 and 512×512 grid layouts, `TILESET_FALLBACKS` remaps them to APK-included Campaign 2 tilesets (with automatic override if cache packs are present in `Downloads`) |
| **1×1 Turrets, Barriers, Drones** | Built in Python | `generate_turret_and_barrier_sheets()` in `tools/extract_apk_assets.py` renders `assets/textures/generated/turrets_sheet.png` (512×512 RGBA via pure Python + `zlib`, no `Pillow` needed) |
| **Game Engine & UI** | Built New in GDScript | `scripts/game_data.gd`, `scripts/map_renderer.gd`, `scripts/game_manager.gd`, `scripts/entities/*.gd`, `scenes/main.tscn`, `tests/verify_gameplay.gd` |

---

## 4. Technical Decisions & Engineering War Stories

### Architecture Decisions
- **JSON Compilation Step (`assets/data/*.json`):** Parsing `.tmx` XML and ELF structs once in Python avoids runtime parsing cost and lets the HUD switch cleanly among all 35 campaign missions.
- **Direct `CanvasItem._draw()` Rendering:** Towers, enemies, health bars, range rings, Booster energy lines, and VFX render inside lightweight `Node2D` scripts rather than spawning heavy node hierarchies per unit.
- **Unified Desktop & Mobile Input (`960×540` Canvas):** `project.godot` enables `canvas_items` stretch with `expand` and bidirectional touch/mouse emulation so both tap-to-place and drag-and-drop run through the same `_input()` path in `scripts/game_manager.gd`.
- **Testable Simulation Loop:** Separating `step_simulation(dt)` from `_process(delta)` lets `tests/verify_gameplay.gd` simulate combat and waves deterministically in milliseconds.

### Key Bugs Found & Fixed
1. **Frozen Missile & Poison Orbs (`scripts/game_manager.gd`):**
   - `projectiles` held target references `p["target"]`. When an enemy died and was freed (`queue_free()`) mid-flight, `var tgt: EnemyEntity = p["target"]` failed a typed runtime assignment before `is_instance_valid(tgt)` ran, halting `_update_projectiles()` every frame.
   - **Fix:** Null out dead targets in `_on_enemy_died()` / `_on_enemy_reached_end()`, check `is_instance_valid(tgt_var)` on an untyped `Variant` first, and expire projectiles cleanly with a `4.0s` `ttl`.
2. **Artillery & Poison Facing the Wrong Way (`scripts/entities/tower.gd`):**
   - The native 64-frame sheets order frames `0..31` counter-clockwise starting from **Left** (`0 = Left`, `8 = Down`, `16 = Right`, `24 = Up`) and put muzzle-flash firing frames at `32..63`.
   - **Fix:** Implemented `TowerEntity.get_native_dir_idx()` using `wrapf(PI - angle_rad, 0.0, TAU)`, showed frames `32..63` only during active recoil (`_recoil > 0.35`), and required towers to turn within `0.28 rad` before firing. Also updated `EnemyEntity._draw()` to match the `16×5` heading-row / walk-column layout of `MutantWalker` and `Arachnid` sheets.
3. **Godot 4.7 Strict Variant Inference & Autoload Tests:**
   - Replaced `:=` on untyped dictionary/array lookups with explicit types, and changed `tests/verify_gameplay.gd` from `extends SceneTree` (`-s`) to a `Node` inside `tests/verify_gameplay.tscn` so `GameData` initializes normally.

---

## 5. How to Play & Tactical Tips

### Controls
- **Build Turret:** Click/tap a turret button on the right panel, then tap any valid highlighted green tile (or drag from the sidebar onto the map).
- **Upgrade / Sell:** Click/tap an existing tower to inspect its buffed DPS/range, upgrade (`L1 → L4`), or sell for **80% refund**.
- **Commander:** Tap the Commander (or click `MOVE CMDR`), then tap anywhere on the map to reposition. Use `STOMP` for AoE damage + 50% slow (12s cooldown).
- **Orbital Weapons:** Click `LASER`, `ION`, `CHARGE`, or `REPAIR`, then tap the target sector on the map.
- **Shortcuts:** `Space` = Next Wave, `Esc` / Right-Click = cancel mode & clear selection.

### Strategy Tips
1. **Bank in $100 Multiples:** Wave clear gives `+$10` bonus plus **5% interest** (`floor(cash / 100) * 5`). Holding off a small upgrade until right after wave clear maximizes compound income.
2. **Move Your Commander Often:** Commander's 96px **Morale Aura** gives nearby non-Booster towers **+25% damage and +20% fire rate**, plus self-healing after 3s out of combat.
3. **Pair Slow + DoT + Splash:** Slow turrets (`20%–35%`) hold ground creeps inside Poison's 4-second burn (up to `80 DPS` at L4) and Artillery splash radii (`64px`).
4. **Exploit Boosters:** A Booster divides its pool (`35%` L1 → `900%` L4) across towers in `68px` range while also extending their reach (`+12%`..`+24%`).
5. **Switch Drone Modes:** Leave the Harvest Drone farming (`+$5` and `+6` Energy per trip) unless a Barrier is critically damaged, then toggle `HARVEST` into Repair mode (`+25 HP` ticks).
6. **Watch Damage Resistances & Air Waves:** Bombs, Slows, Poison, and Artillery only target Ground units. Resistant enemies take only **25% damage** from their matching type (`laser`, `fire`, `slow`), so keep Laser/Missile/Sniper/Explosive coverage balanced.

### Quick Tower Reference

| Tower | Footprint | Targets | Costs (L1–L4) | Damage / Role | Range |
| --- | --- | --- | --- | --- | --- |
| Laser | 1×1 | Ground + Air | `$20 / 20 / 20 / 60` | `1 / 2 / 4 / 15` rapid laser (`0.10-0.20s`) | `71 px` |
| Bomb | 1×1 | Ground | `$50 / 50 / 50 / 150` | `16 / 45 / 80 / 200` (`48px` splash; L4 Cluster) | `95 px` |
| Slow | 1×1 | Ground | `$60 / 50 / 50 / 100` | `4 / 8 / 14 / 25` + `20%–35%` EMP slow (`3s`) | `78 px` |
| Booster | 1×1 | Aura | `$50 / 60 / 80 / 300` | Shares `35% / 100% / 220% / 900%` pool + range | `68 px` |
| Missile | 1×1 | Ground + Air | `$40 / 50 / 60 / 180` | `20 / 30 / 35 / 40` homing (`28px` splash) | `134 px` |
| Poison | 2×2 | Ground | `$70 / 150 / 200 / 450` | `4–40` hit + `5 / 25 / 50 / 80` DPS DoT (`4s`) | `96 px` |
| Artillery | 2×2 | Ground | `$100 / 150 / 150 / 500` | `30 / 100 / 220 / 300` (`64px` splash) | `200 px` |
| Beam | 1×1 | Ground + Air | `$200 / 250 / 250 / 600` | `300 / 900 / 1400 / 1800` heavy beam | `110 px` |
| Sniper | 1×1 | Ground + Air | `$250 / 300 / 300 / 500` | `300 / 700 / 1100 / 1800` armor-piercing | `245 px` |

---

## 6. Modding Cookbook

- **Edit Tower Stats / Add a Tower:** Modify `TOWER_ORDER` and `TOWER_DEFS` in [`scripts/game_data.gd`](../scripts/game_data.gd) and add any custom firing behavior in [`scripts/entities/tower.gd`](../scripts/entities/tower.gd) (`_fire_at()`).
- **Tune Economy / Wave Formulas:** Adjust `INTEREST_RATE`, `SELL_REFUND_RATIO`, `ENEMY_DEFS`, or `get_wave_spawn_spec()` in [`scripts/game_data.gd`](../scripts/game_data.gd).
- **Modify Campaigns / Maps:** Edit `assets/data/campaign_data.json` or open `assets/maps/*.tmx` in Tiled (`21×16` grid, `32×32` tiles) and re-run `python tools/extract_apk_assets.py`. (If you drop an official external cache `.obb`/`.zip` into `Downloads`, re-running the extractor picks up original Campaign 1 tiles automatically.)

### Running Tests After Edits

```bash
godot --path . res://tests/verify_gameplay.tscn
```

Expected output ends with `ALL_TESTS_PASSED` and exit code `0`.
