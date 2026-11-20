extends Node2D
class_name TowerEntity
## Defensive turret unit supporting 1x1 & 2x2 footprints, 4 upgrade tiers,
## Booster/Commander/Energizer buffs, and authentic Sentinel 3 weapon behavior.

signal upgraded(tower: TowerEntity)
signal sfx_requested(sfx_name: String)
signal instant_beam_fx(from_pos: Vector2, to_pos: Vector2, color: Color, width: float, duration: float)
signal projectile_requested(from_pos: Vector2, target: EnemyEntity, target_pos: Vector2, spec: Dictionary)
signal shockwave_fx(center: Vector2, radius: float, color: Color)

var tower_id: String = "laser"
var def: Dictionary = {}
var grid_pos: Vector2i = Vector2i.ZERO
var footprint: int = 1
var level: int = 1
var total_invested: int = 20

var turret_angle: float = 0.0
var selected: bool = false

# Buff state recalculated by GameManager
var booster_dmg_mult: float = 0.0
var booster_rate_mult: float = 0.0
var booster_range_mult: float = 0.0
var commander_buffed: bool = false
var energizer_timer: float = 0.0
var boosted_tower_positions: Array[Vector2] = []

var _cooldown: float = 0.0
var _recoil: float = 0.0
var _beam_active_timer: float = 0.0
var _beam_target_pos: Vector2 = Vector2.ZERO
var _enemies_ref: Array = []


func setup(p_tower_id: String, p_grid_pos: Vector2i, world_center: Vector2, enemies_list: Array) -> void:
	tower_id = p_tower_id
	def = GameData.TOWER_DEFS[tower_id]
	grid_pos = p_grid_pos
	footprint = int(def["footprint"])
	level = 1
	total_invested = int(def["costs"][0])
	position = world_center
	_enemies_ref = enemies_list
	_cooldown = 0.15
	z_index = 15
	queue_redraw()


func can_upgrade() -> bool:
	return level < 4


func get_upgrade_cost() -> int:
	return GameData.get_tower_upgrade_cost(tower_id, level)


func upgrade() -> bool:
	if not can_upgrade():
		return false
	var cost := get_upgrade_cost()
	level += 1
	total_invested += cost
	upgraded.emit(self)
	queue_redraw()
	return true


func get_sell_price() -> int:
	return int(floor(float(total_invested) * GameData.SELL_REFUND_RATIO))


func get_effective_range() -> float:
	return float(def["range"]) * (1.0 + booster_range_mult)


func get_effective_damage() -> float:
	var base := float(def["damage"][level - 1])
	var mult := 1.0 + booster_dmg_mult + (0.25 if commander_buffed else 0.0)
	return base * mult


func get_effective_reload() -> float:
	var base := float(def["reload"][level - 1])
	var rate_mult := 1.0 + booster_rate_mult + (0.20 if commander_buffed else 0.0) + (0.50 if energizer_timer > 0.0 else 0.0)
	return maxf(0.05, base / rate_mult)


func get_booster_pool() -> float:
	if tower_id != "booster":
		return 0.0
	return float(def["buff_pool"][level - 1])


func apply_energizer(duration: float) -> void:
	energizer_timer = maxf(energizer_timer, duration)
	queue_redraw()


static func get_native_dir_idx(angle_rad: float) -> int:
	# Native 32-direction turret sheets are ordered CCW starting from Left (PI):
	# 0 = Left (PI), 8 = Down (+PI/2), 16 = Right (0), 24 = Up (-PI/2)
	var ang := wrapf(PI - angle_rad, 0.0, TAU)
	return posmod(int(round(ang / TAU * 32.0)), 32)


func _process(delta: float) -> void:
	if energizer_timer > 0.0:
		energizer_timer = maxf(0.0, energizer_timer - delta)
	if _recoil > 0.0:
		_recoil = maxf(0.0, _recoil - delta * 6.0)
	if _beam_active_timer > 0.0:
		_beam_active_timer = maxf(0.0, _beam_active_timer - delta)

	if tower_id == "booster":
		queue_redraw()
		return

	_cooldown -= delta
	var eff_range := get_effective_range()
	var target := _acquire_target(eff_range)

	if target != null:
		var desired := (target.position - position).angle()
		turret_angle = lerp_angle(turret_angle, desired, minf(1.0, delta * 18.0))
		if _cooldown <= 0.0 and absf(angle_difference(turret_angle, desired)) <= 0.28:
			_fire_at(target)
			_cooldown = get_effective_reload()

	queue_redraw()


func _acquire_target(eff_range: float) -> EnemyEntity:
	var best: EnemyEntity = null
	var best_prog := -1.0
	var air_ok := bool(def["targets_air"])
	var ground_ok := bool(def["targets_ground"])
	var range_sq := eff_range * eff_range

	for e in _enemies_ref:
		if not is_instance_valid(e) or e.is_dead:
			continue
		if e.flying and not air_ok:
			continue
		if (not e.flying) and not ground_ok:
			continue
		if position.distance_squared_to(e.position) <= range_sq:
			if e.progress > best_prog:
				best_prog = e.progress
				best = e
	return best


func _fire_at(target: EnemyEntity) -> void:
	var dmg := get_effective_damage()
	var dmg_type := String(def["dmg_type"])
	var col: Color = def["color"]
	turret_angle = (target.position - position).angle()
	_recoil = 1.0
	sfx_requested.emit(String(def["sfx"]))

	var muzzle: Vector2
	if tower_id == "artillery":
		muzzle = position + Vector2(0.0, -14.0) + Vector2(cos(turret_angle) * 16.0, sin(turret_angle) * 10.0)
	elif tower_id == "disease":
		muzzle = position + Vector2(0.0, -4.0) + Vector2.from_angle(turret_angle) * 20.0
	else:
		muzzle = position + Vector2.from_angle(turret_angle) * 16.0

	match tower_id:
		"laser":
			target.take_damage(dmg, dmg_type)
			instant_beam_fx.emit(muzzle, target.position, col, 2.2 + float(level) * 0.4, 0.08)
		"sniper":
			target.take_damage(dmg, dmg_type)
			instant_beam_fx.emit(muzzle, target.position, Color(1.0, 0.35, 0.38), 3.0, 0.16)
		"beam":
			target.take_damage(dmg, dmg_type)
			_beam_active_timer = 0.35
			_beam_target_pos = target.position
			instant_beam_fx.emit(muzzle, target.position, Color(0.82, 0.42, 1.0), 4.2 + float(level) * 0.8, 0.32)
		"slow":
			var slow_pct: float = float(def["slow_pct"][level - 1])
			var slow_dur: float = float(def["slow_dur"])
			var rng := get_effective_range()
			for e in _enemies_ref:
				if is_instance_valid(e) and not e.is_dead and not e.flying:
					if position.distance_to(e.position) <= rng:
						e.apply_slow(slow_pct, slow_dur)
						e.take_damage(dmg, dmg_type)
			shockwave_fx.emit(position, rng, col)
		"bomb", "missile", "artillery", "disease":
			var dot_dps := 0.0
			var dot_dur := 0.0
			if tower_id == "disease":
				dot_dps = float(def["dot_dps"][level - 1]) * (1.0 + booster_dmg_mult + (0.25 if commander_buffed else 0.0))
				dot_dur = float(def["dot_dur"])
			projectile_requested.emit(muzzle, target, target.position, {
				"tower_id": tower_id,
				"damage": dmg,
				"dmg_type": dmg_type,
				"splash": float(def["splash"]),
				"speed": 340.0 if tower_id == "missile" else (240.0 if tower_id == "artillery" else 280.0),
				"homing": tower_id == "missile",
				"cluster": tower_id == "bomb" and level >= 4,
				"dot_dps": dot_dps,
				"dot_dur": dot_dur,
				"color": col,
			})


func _draw() -> void:
	var pixel_size := float(footprint * GameData.TILE_SIZE)
	var half := pixel_size * 0.5

	# Booster energy tether lines (drawn under towers via low local coord)
	if tower_id == "booster":
		for target_pos in boosted_tower_positions:
			var rel := target_pos - position
			draw_line(Vector2.ZERO, rel, Color(0.25, 1.0, 0.78, 0.48), 2.0)
			draw_line(Vector2.ZERO, rel, Color(0.85, 1.0, 0.95, 0.65), 1.0)

	# Selection / Range indicator
	if selected:
		var rng := get_effective_range()
		draw_circle(Vector2.ZERO, rng, Color(0.3, 0.85, 1.0, 0.09))
		draw_arc(Vector2.ZERO, rng, 0.0, TAU, 56, Color(0.35, 0.9, 1.0, 0.75), 1.6)
		draw_rect(Rect2(-half, -half, pixel_size, pixel_size), Color(0.35, 0.95, 1.0, 0.9), false, 1.8)

	# Draw native APK sprite sheets for Artillery & Disease (2x2)
	if def.has("native_sheet"):
		var sheet_name: String = String(def["native_max_sheet"]) if level >= 4 else String(def["native_sheet"])
		var dir_idx := get_native_dir_idx(turret_angle)
		var frame_idx := dir_idx + (32 if _recoil > 0.35 else 0)
		var tex := GameData.get_atlas_texture(sheet_name, frame_idx)
		if tex != null:
			var draw_w := pixel_size * 1.18
			draw_texture_rect(tex, Rect2(-draw_w * 0.5, -draw_w * 0.5, draw_w, draw_w), false)
	else:
		var row: int = int(def.get("sheet_row", 0))
		var base_tex := GameData.get_atlas_texture("turrets_sheet", row * 8 + (level - 1))
		var top_tex := GameData.get_atlas_texture("turrets_sheet", row * 8 + 4 + (level - 1))
		if base_tex != null:
			draw_texture_rect(base_tex, Rect2(-18, -18, 36, 36), false)
		if top_tex != null:
			var kick := Vector2.from_angle(turret_angle) * (-_recoil * 3.0)
			draw_set_transform(kick, turret_angle, Vector2.ONE)
			draw_texture_rect(top_tex, Rect2(-18, -18, 36, 36), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Upgrade pips (L1..L4) at bottom corner
	for i in range(level):
		var pip_x := -half + 5.0 + float(i) * 6.0
		var pip_y := half - 5.0
		var pip_col := Color(1.0, 0.85, 0.25) if level == 4 else Color(0.3, 0.92, 1.0)
		draw_circle(Vector2(pip_x, pip_y), 2.1, pip_col)

	# Buff / Energizer indicators
	if energizer_timer > 0.0:
		draw_arc(Vector2.ZERO, half * 0.85, 0.0, TAU, 24, Color(0.35, 1.0, 0.72, 0.75), 1.8)
	elif commander_buffed or booster_dmg_mult > 0.0:
		draw_circle(Vector2(half - 5.0, -half + 5.0), 3.0, Color(0.3, 1.0, 0.75, 0.95))
