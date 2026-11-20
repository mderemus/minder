extends Node
## Autoload singleton holding extracted Sentinel 3: Homeworld data,
## reverse-engineered tower/enemy formulas, and cached texture/audio loaders.

const TILE_SIZE := 32
const MAP_COLS := 21
const MAP_ROWS := 16
const MAP_WIDTH := MAP_COLS * TILE_SIZE   # 672
const MAP_HEIGHT := MAP_ROWS * TILE_SIZE # 512
const SELL_REFUND_RATIO := 0.80
const INTEREST_RATE := 0.05

var campaign_levels: Array = []
var wave_patterns: Array = []
var maps: Dictionary = {}
var sprite_regions: Dictionary = {}

var _tex_cache: Dictionary = {}
var _atlas_cache: Dictionary = {}
var _audio_cache: Dictionary = {}

const TOWER_ORDER: Array[String] = [
	"laser", "bomb", "slow", "booster", "missile", "disease", "artillery", "beam", "sniper"
]

const TOWER_DEFS: Dictionary = {
	"laser": {
		"id": "laser",
		"name": "Laser",
		"short": "LASER",
		"footprint": 1,
		"targets_air": true,
		"targets_ground": true,
		"costs": [20, 20, 20, 60],
		"damage": [1.0, 2.0, 4.0, 15.0],
		"reload": [0.10, 0.10, 0.10, 0.20],
		"range": 71.0,
		"splash": 0.0,
		"slow_pct": 0.0,
		"dot_dps": 0.0,
		"buff_pool": 0.0,
		"dmg_type": "laser",
		"sheet_row": 0,
		"color": Color(0.24, 0.82, 1.0),
		"sfx": "Fire_LaserTower",
		"desc": "Rapid-fire laser targeting ground and air."
	},
	"bomb": {
		"id": "bomb",
		"name": "Bomb",
		"short": "BOMB",
		"footprint": 1,
		"targets_air": false,
		"targets_ground": true,
		"costs": [50, 50, 50, 150],
		"damage": [16.0, 45.0, 80.0, 200.0],
		"reload": [1.50, 1.50, 1.50, 1.50],
		"range": 95.0,
		"splash": 48.0,
		"slow_pct": 0.0,
		"dot_dps": 0.0,
		"buff_pool": 0.0,
		"dmg_type": "explosive",
		"sheet_row": 1,
		"color": Color(1.0, 0.58, 0.2),
		"sfx": "Fire_BombTower",
		"desc": "Splash explosives vs ground. L4 Cluster Bomb!"
	},
	"slow": {
		"id": "slow",
		"name": "Slow",
		"short": "SLOW",
		"footprint": 1,
		"targets_air": false,
		"targets_ground": true,
		"costs": [60, 50, 50, 100],
		"damage": [4.0, 8.0, 14.0, 25.0],
		"reload": [3.50, 3.50, 3.50, 3.50],
		"range": 78.0,
		"splash": 78.0,
		"slow_pct": [0.20, 0.25, 0.30, 0.35],
		"slow_dur": 3.0,
		"dot_dps": 0.0,
		"buff_pool": 0.0,
		"dmg_type": "slow",
		"sheet_row": 2,
		"color": Color(0.35, 0.68, 1.0),
		"sfx": "Fire_SlowTower",
		"desc": "EMP pulse slowing all nearby ground creeps."
	},
	"booster": {
		"id": "booster",
		"name": "Booster",
		"short": "BOOST",
		"footprint": 1,
		"targets_air": false,
		"targets_ground": false,
		"costs": [50, 60, 80, 300],
		"damage": [0.0, 0.0, 0.0, 0.0],
		"reload": [1.0, 1.0, 1.0, 1.0],
		"range": 68.0,
		"splash": 0.0,
		"slow_pct": 0.0,
		"dot_dps": 0.0,
		"buff_pool": [0.35, 1.00, 2.20, 9.00],
		"dmg_type": "support",
		"sheet_row": 5,
		"color": Color(0.28, 1.0, 0.75),
		"sfx": "Upgrade",
		"desc": "Boosts damage, fire rate, and range of nearby towers."
	},
	"missile": {
		"id": "missile",
		"name": "Missile",
		"short": "MISSILE",
		"footprint": 1,
		"targets_air": true,
		"targets_ground": true,
		"costs": [40, 50, 60, 180],
		"damage": [20.0, 30.0, 35.0, 40.0],
		"reload": [1.00, 1.00, 1.00, 0.85],
		"range": 134.0,
		"splash": 28.0,
		"slow_pct": 0.0,
		"dot_dps": 0.0,
		"buff_pool": 0.0,
		"dmg_type": "explosive",
		"sheet_row": 6,
		"color": Color(1.0, 0.85, 0.25),
		"sfx": "Fire_Missiles",
		"desc": "Long-range homing missiles vs air & ground."
	},
	"disease": {
		"id": "disease",
		"name": "Poison",
		"short": "POISON",
		"footprint": 2,
		"targets_air": false,
		"targets_ground": true,
		"costs": [70, 150, 200, 450],
		"damage": [4.0, 12.0, 24.0, 40.0],
		"reload": [0.80, 0.80, 0.80, 0.80],
		"range": 96.0,
		"splash": 42.0,
		"slow_pct": 0.0,
		"dot_dps": [5.0, 25.0, 50.0, 80.0],
		"dot_dur": 4.0,
		"buff_pool": 0.0,
		"dmg_type": "fire",
		"native_sheet": "PoisonNormal",
		"native_max_sheet": "PoisonMax",
		"color": Color(0.45, 0.95, 0.35),
		"sfx": "Fire_Disease",
		"desc": "2x2 bio-toxin tower inflicting heavy DoT."
	},
	"artillery": {
		"id": "artillery",
		"name": "Artillery",
		"short": "ARTY",
		"footprint": 2,
		"targets_air": false,
		"targets_ground": true,
		"costs": [100, 150, 150, 500],
		"damage": [30.0, 100.0, 220.0, 300.0],
		"reload": [1.80, 1.80, 1.80, 1.50],
		"range": 200.0,
		"splash": 64.0,
		"slow_pct": 0.0,
		"dot_dps": 0.0,
		"buff_pool": 0.0,
		"dmg_type": "explosive",
		"native_sheet": "ArtilleryNormal",
		"native_max_sheet": "ArtilleryMax",
		"color": Color(1.0, 0.45, 0.25),
		"sfx": "Fire_Artillery",
		"desc": "2x2 long-range heavy siege mortar."
	},
	"beam": {
		"id": "beam",
		"name": "Beam",
		"short": "BEAM",
		"footprint": 1,
		"targets_air": true,
		"targets_ground": true,
		"costs": [200, 250, 250, 600],
		"damage": [300.0, 900.0, 1400.0, 1800.0],
		"reload": [1.60, 1.60, 1.60, 1.40],
		"range": 110.0,
		"splash": 0.0,
		"slow_pct": 0.0,
		"dot_dps": 0.0,
		"buff_pool": 0.0,
		"dmg_type": "laser",
		"sheet_row": 3,
		"color": Color(0.75, 0.38, 1.0),
		"sfx": "Fire_BeamTower",
		"desc": "High-intensity beam vs tough & flying targets."
	},
	"sniper": {
		"id": "sniper",
		"name": "Sniper",
		"short": "SNIPER",
		"footprint": 1,
		"targets_air": true,
		"targets_ground": true,
		"costs": [250, 300, 300, 500],
		"damage": [300.0, 700.0, 1100.0, 1800.0],
		"reload": [3.00, 3.00, 3.00, 1.50],
		"range": 245.0,
		"splash": 0.0,
		"slow_pct": 0.0,
		"dot_dps": 0.0,
		"buff_pool": 0.0,
		"dmg_type": "kinetic",
		"sheet_row": 4,
		"color": Color(1.0, 0.28, 0.35),
		"sfx": "Fire_SniperTower",
		"desc": "Extreme-range armor-piercing cannon."
	}
}

# Reverse engineered from EnemyManager::SpawnEnemy (0x110d50) & g_EnemyWavePatternData (0x1e3ab0)
const ENEMY_DEFS: Dictionary = {
	0: {"name": "Mutant Scout", "sheet": "MutantWalkerL1", "grid_16dir": true, "base_hp": 6.0, "hp_scale": 0.50, "reward_base": 3.0, "reward_scale": 0.07, "speed": 50.0, "melee_dmg": 1.0, "atk_rate": 0.5, "flying": false, "resist": "", "death_sfx": "Death_Mutant", "size": 36.0},
	1: {"name": "Mutant Stalker", "sheet": "MutantWalkerL2", "grid_16dir": true, "base_hp": 8.0, "hp_scale": 0.55, "reward_base": 3.5, "reward_scale": 0.07, "speed": 52.0, "melee_dmg": 1.5, "atk_rate": 0.5, "flying": false, "resist": "", "death_sfx": "Death_Mutant", "size": 38.0},
	2: {"name": "Mutant Brute", "sheet": "MutantWalker", "grid_16dir": true, "base_hp": 11.0, "hp_scale": 0.62, "reward_base": 4.0, "reward_scale": 0.07, "speed": 48.0, "melee_dmg": 2.0, "atk_rate": 0.5, "flying": false, "resist": "", "death_sfx": "Death_Mutant", "size": 42.0},
	3: {"name": "Arachnid L1", "sheet": "ArachnidL1", "grid_16dir": true, "base_hp": 4.0, "hp_scale": 0.30, "reward_base": 3.0, "reward_scale": 0.07, "speed": 80.0, "melee_dmg": 1.0, "atk_rate": 0.5, "flying": false, "resist": "", "death_sfx": "Death_Arachnid", "size": 32.0},
	4: {"name": "Arachnid L2", "sheet": "ArachnidL2", "grid_16dir": true, "base_hp": 5.5, "hp_scale": 0.35, "reward_base": 3.5, "reward_scale": 0.07, "speed": 84.0, "melee_dmg": 1.2, "atk_rate": 0.5, "flying": false, "resist": "", "death_sfx": "Death_Arachnid", "size": 34.0},
	5: {"name": "Arachnid Swarm", "sheet": "Arachnid", "grid_16dir": true, "base_hp": 7.0, "hp_scale": 0.40, "reward_base": 4.0, "reward_scale": 0.07, "speed": 88.0, "melee_dmg": 1.5, "atk_rate": 0.5, "flying": false, "resist": "", "death_sfx": "Death_Arachnid", "size": 36.0},
	6: {"name": "Flyer L1", "sheet": "FlyerL1", "grid_16dir": false, "base_hp": 6.0, "hp_scale": 0.45, "reward_base": 3.0, "reward_scale": 0.07, "speed": 70.0, "melee_dmg": 2.0, "atk_rate": 0.5, "flying": true, "resist": "", "death_sfx": "Death_Flying", "size": 42.0},
	7: {"name": "Flyer L2", "sheet": "FlyerL2", "grid_16dir": false, "base_hp": 8.0, "hp_scale": 0.50, "reward_base": 3.5, "reward_scale": 0.07, "speed": 72.0, "melee_dmg": 2.5, "atk_rate": 0.5, "flying": true, "resist": "", "death_sfx": "Death_Flying", "size": 44.0},
	8: {"name": "Heavy Flyer", "sheet": "Flyer", "grid_16dir": false, "base_hp": 11.0, "hp_scale": 0.56, "reward_base": 4.0, "reward_scale": 0.07, "speed": 68.0, "melee_dmg": 3.0, "atk_rate": 0.5, "flying": true, "resist": "", "death_sfx": "Death_Flying", "size": 46.0},
	9: {"name": "Laser Resistant", "sheet": "ResistantLaser", "grid_16dir": false, "base_hp": 4.0, "hp_scale": 0.30, "reward_base": 4.0, "reward_scale": 0.07, "speed": 80.0, "melee_dmg": 1.5, "atk_rate": 0.5, "flying": false, "resist": "laser", "death_sfx": "Death_Resist", "size": 40.0},
	10: {"name": "Fire Resistant", "sheet": "ResistantFire", "grid_16dir": false, "base_hp": 4.0, "hp_scale": 0.30, "reward_base": 4.0, "reward_scale": 0.07, "speed": 80.0, "melee_dmg": 1.5, "atk_rate": 0.5, "flying": false, "resist": "fire", "death_sfx": "Death_Resist", "size": 40.0},
	11: {"name": "Slow Resistant", "sheet": "ResistantSlow", "grid_16dir": false, "base_hp": 4.0, "hp_scale": 0.30, "reward_base": 4.0, "reward_scale": 0.07, "speed": 80.0, "melee_dmg": 1.5, "atk_rate": 0.5, "flying": false, "resist": "slow", "death_sfx": "Death_Resist", "size": 40.0},
	12: {"name": "Slimer Walker", "sheet": "SlimerWalker", "grid_16dir": false, "base_hp": 12.0, "hp_scale": 0.60, "reward_base": 6.0, "reward_scale": 0.08, "speed": 55.0, "melee_dmg": 2.0, "atk_rate": 0.5, "flying": false, "resist": "", "death_sfx": "Death_Mutant", "size": 42.0},
	13: {"name": "Behemoth", "sheet": "Behemoth", "grid_16dir": false, "base_hp": 30.0, "hp_scale": 1.00, "reward_base": 120.0, "reward_scale": 0.20, "speed": 20.0, "melee_dmg": 15.0, "atk_rate": 1.0, "flying": false, "resist": "", "death_sfx": "Death_Behemoth", "size": 58.0},
	14: {"name": "Walker Boss", "sheet": "BossWalkerNormal", "grid_16dir": false, "base_hp": 250.0, "hp_scale": 2.60, "reward_base": 25.0, "reward_scale": 0.07, "speed": 20.0, "melee_dmg": 100.0, "atk_rate": 1.0, "flying": false, "resist": "", "death_sfx": "Death_Boss", "size": 62.0},
	15: {"name": "Tough Walker Boss", "sheet": "BossWalkerTough", "grid_16dir": false, "base_hp": 450.0, "hp_scale": 2.60, "reward_base": 35.0, "reward_scale": 0.07, "speed": 20.0, "melee_dmg": 100.0, "atk_rate": 1.0, "flying": false, "resist": "", "death_sfx": "Death_Boss", "size": 66.0},
	16: {"name": "Flyer Boss", "sheet": "BossFlyerNormal", "grid_16dir": false, "base_hp": 250.0, "hp_scale": 2.60, "reward_base": 25.0, "reward_scale": 0.07, "speed": 22.0, "melee_dmg": 100.0, "atk_rate": 1.0, "flying": true, "resist": "", "death_sfx": "Death_Boss", "size": 62.0},
	17: {"name": "Tough Flyer Boss", "sheet": "BossFlyerTough", "grid_16dir": false, "base_hp": 450.0, "hp_scale": 2.60, "reward_base": 35.0, "reward_scale": 0.07, "speed": 22.0, "melee_dmg": 100.0, "atk_rate": 1.0, "flying": true, "resist": "", "death_sfx": "Death_Boss", "size": 66.0},
	18: {"name": "Mother Boss", "sheet": "BossMother", "grid_16dir": false, "base_hp": 1200.0, "hp_scale": 3.50, "reward_base": 150.0, "reward_scale": 0.09, "speed": 18.0, "melee_dmg": 150.0, "atk_rate": 1.0, "flying": false, "resist": "", "death_sfx": "Death_Boss", "size": 74.0}
}

const ORBITAL_ORDER: Array[String] = [
	"orbital_laser", "ion_bomb", "turret_energizer", "repair_beam"
]

const ORBITAL_DEFS: Dictionary = {
	"orbital_laser": {
		"id": "orbital_laser",
		"name": "Orbital Laser",
		"short": "LASER",
		"cost": 50,
		"cooldown": 14.0,
		"radius": 68.0,
		"damage": 350.0,
		"sfx": "Fire_Orbital",
		"color": Color(0.3, 0.9, 1.0),
		"desc": "Sweeping orbital ion beam incinerating creeps."
	},
	"ion_bomb": {
		"id": "ion_bomb",
		"name": "Ion Bomb",
		"short": "ION",
		"cost": 35,
		"cooldown": 10.0,
		"radius": 78.0,
		"damage": 180.0,
		"sfx": "Fire_IONBomb",
		"color": Color(1.0, 0.65, 0.25),
		"desc": "Drops an explosive plasma cage across target area."
	},
	"turret_energizer": {
		"id": "turret_energizer",
		"name": "Energizer",
		"short": "CHARGE",
		"cost": 25,
		"cooldown": 12.0,
		"radius": 110.0,
		"duration": 10.0,
		"sfx": "Fire_Energizer",
		"color": Color(0.35, 1.0, 0.7),
		"desc": "Overcharges nearby turrets (+50% fire rate for 10s)."
	},
	"repair_beam": {
		"id": "repair_beam",
		"name": "Repair Beam",
		"short": "REPAIR",
		"cost": 30,
		"cooldown": 10.0,
		"radius": 80.0,
		"heal": 250.0,
		"sfx": "Com_Repair",
		"color": Color(0.45, 1.0, 0.5),
		"desc": "Repairs +250 HP to nearest barrier or Commander."
	}
}


func _ready() -> void:
	_load_json_files()


func _exit_tree() -> void:
	_tex_cache.clear()
	_atlas_cache.clear()
	_audio_cache.clear()


func _load_json_files() -> void:
	var camp: Variant = _read_json("res://assets/data/campaign_data.json")
	if typeof(camp) == TYPE_DICTIONARY:
		campaign_levels = camp.get("levels", [])
		wave_patterns = camp.get("wave_patterns", [])

	var m: Variant = _read_json("res://assets/data/maps.json")
	if typeof(m) == TYPE_DICTIONARY:
		maps = m

	var r: Variant = _read_json("res://assets/data/sprite_regions.json")
	if typeof(r) == TYPE_DICTIONARY:
		sprite_regions = r


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("GameData missing JSON (run 'python tools/extract_apk_assets.py' first): " + path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("GameData failed to parse JSON: " + path)
	return parsed


func get_texture(tex_name: String) -> Texture2D:
	if _tex_cache.has(tex_name):
		return _tex_cache[tex_name]
	var candidates := [
		"res://assets/textures/%s.png" % tex_name,
		"res://assets/textures/generated/%s.png" % tex_name,
	]
	for p in candidates:
		if ResourceLoader.exists(p):
			var tex: Texture2D = load(p)
			_tex_cache[tex_name] = tex
			return tex
	return null


func get_atlas_texture(sheet_name: String, region_idx: int) -> AtlasTexture:
	var key := "%s:%d" % [sheet_name, region_idx]
	if _atlas_cache.has(key):
		return _atlas_cache[key]
	var tex := get_texture(sheet_name)
	if tex == null:
		return null
	var regions: Array = sprite_regions.get(sheet_name, [])
	if region_idx < 0 or region_idx >= regions.size():
		return null
	var r: Array = regions[region_idx]
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	_atlas_cache[key] = atlas
	return atlas


func get_audio_stream(sfx_name: String) -> AudioStream:
	if _audio_cache.has(sfx_name):
		return _audio_cache[sfx_name]
	var p := "res://assets/audio/%s.ogg" % sfx_name
	if ResourceLoader.exists(p):
		var stream: AudioStream = load(p)
		_audio_cache[sfx_name] = stream
		return stream
	return null


func get_level_config(level_index: int) -> Dictionary:
	if level_index >= 0 and level_index < campaign_levels.size():
		return campaign_levels[level_index]
	return {}


func get_wave_spawn_spec(pattern_idx: int, wave_idx: int, diff_key: String, diff_mults: Dictionary) -> Dictionary:
	var pattern: Array = wave_patterns[clampi(pattern_idx, 0, wave_patterns.size() - 1)] if wave_patterns.size() > 0 else [0]
	var enemy_type: int = int(pattern[wave_idx % pattern.size()])
	var edef: Dictionary = ENEMY_DEFS.get(enemy_type, ENEMY_DEFS[0])
	var diff_mult: float = float(diff_mults.get(diff_key, 1.0))

	var count: int
	var interval: float
	if enemy_type >= 13:
		count = 1 + int(wave_idx / 30)
		interval = 4.0
	elif enemy_type >= 3 and enemy_type <= 5:
		count = mini(127, wave_idx + 12)
		interval = 0.25
	else:
		count = mini(127, wave_idx + 15)
		interval = 0.42

	var w := float(wave_idx)
	var hp: float = (float(edef["base_hp"]) + pow(float(edef["hp_scale"]) * w, 2.0)) * diff_mult
	var reward: int = maxi(1, int(float(edef["reward_base"]) + pow(float(edef["reward_scale"]) * w, 2.0)))

	return {
		"enemy_type": enemy_type,
		"name": edef["name"],
		"count": count,
		"interval": interval,
		"hp": hp,
		"reward": reward,
		"speed": float(edef["speed"]),
		"melee_dmg": float(edef["melee_dmg"]),
		"atk_rate": float(edef["atk_rate"]),
		"flying": bool(edef["flying"]),
		"resist": String(edef["resist"]),
		"sheet": String(edef["sheet"]),
		"grid_16dir": bool(edef["grid_16dir"]),
		"death_sfx": String(edef["death_sfx"]),
		"size": float(edef["size"]),
	}


func get_tower_build_cost(tower_id: String) -> int:
	return int(TOWER_DEFS[tower_id]["costs"][0])


func get_tower_upgrade_cost(tower_id: String, current_level: int) -> int:
	# current_level is 1..4; next upgrade cost is costs[current_level] when current_level < 4
	if current_level < 1 or current_level >= 4:
		return -1
	return int(TOWER_DEFS[tower_id]["costs"][current_level])
