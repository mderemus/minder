extends Node2D
class_name EnemyEntity
## Alien creep unit implementing Sentinel 3 waypoint movement, barrier melee,
## Commander engagement, status effects (slow / poison DoT), and sprite animation.

signal died(enemy: EnemyEntity, killed_by_player: bool)
signal reached_end(enemy: EnemyEntity)

var enemy_type: int = 0
var enemy_name: String = "Mutant"
var max_hp: float = 10.0
var hp: float = 10.0
var speed: float = 50.0
var melee_dmg: float = 1.0
var atk_rate: float = 0.5
var reward: int = 3
var flying: bool = false
var resist: String = ""
var sheet_name: String = "MutantWalkerL1"
var grid_16dir: bool = true
var death_sfx: String = "Death_Mutant"
var draw_size: float = 36.0

var waypoints: Array = []
var wp_idx: int = 1
var progress: float = 0.0
var is_dead: bool = false

var _barriers_ref: Array = []
var _commander_ref: Node2D = null
var _attacking_barrier: BarrierEntity = null
var _atk_timer: float = 0.0
var _heading: Vector2 = Vector2.RIGHT
var _anim_timer: float = 0.0
var _hit_flash: float = 0.0

# Status effects
var slow_timer: float = 0.0
var slow_pct: float = 0.0
var dot_timer: float = 0.0
var dot_dps: float = 0.0


func setup(spec: Dictionary, path_waypoints: Array, barriers: Array, commander: Node2D) -> void:
	enemy_type = int(spec["enemy_type"])
	enemy_name = String(spec["name"])
	max_hp = float(spec["hp"])
	hp = max_hp
	speed = float(spec["speed"])
	melee_dmg = float(spec["melee_dmg"])
	atk_rate = float(spec["atk_rate"])
	reward = int(spec["reward"])
	flying = bool(spec["flying"])
	resist = String(spec["resist"])
	sheet_name = String(spec["sheet"])
	grid_16dir = bool(spec["grid_16dir"])
	death_sfx = String(spec["death_sfx"])
	draw_size = float(spec["size"])

	waypoints = path_waypoints
	_barriers_ref = barriers
	_commander_ref = commander
	wp_idx = 1 if waypoints.size() > 1 else 0
	is_dead = false

	if waypoints.size() > 0:
		position = Vector2(float(waypoints[0]["x"]), float(waypoints[0]["y"]))
		if waypoints.size() > 1:
			var next_p := Vector2(float(waypoints[1]["x"]), float(waypoints[1]["y"]))
			var d := next_p - position
			if d.length() > 0.01:
				_heading = d.normalized()

	z_index = 35 if flying else 20
	queue_redraw()


func take_damage(amount: float, dmg_type: String = "kinetic") -> void:
	if is_dead:
		return
	var mult := 1.0
	if resist != "" and resist == dmg_type:
		mult = 0.25
	hp -= amount * mult
	_hit_flash = 0.10
	if hp <= 0.0:
		is_dead = true
		died.emit(self, true)
		queue_free()
	else:
		queue_redraw()


func apply_slow(pct: float, duration: float) -> void:
	if is_dead:
		return
	var eff := pct * (0.20 if resist == "slow" else 1.0)
	if eff >= slow_pct or slow_timer <= 0.0:
		slow_pct = clampf(eff, 0.0, 0.70)
		slow_timer = maxf(slow_timer, duration)


func apply_dot(dps: float, duration: float) -> void:
	if is_dead:
		return
	var eff := dps * (0.25 if resist == "fire" else 1.0)
	dot_dps = maxf(dot_dps, eff)
	dot_timer = maxf(dot_timer, duration)


func _process(delta: float) -> void:
	if is_dead:
		return

	_anim_timer += delta * (1.0 - slow_pct * 0.6)
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)

	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_pct = 0.0

	if dot_timer > 0.0:
		dot_timer -= delta
		hp -= dot_dps * delta
		if hp <= 0.0:
			is_dead = true
			died.emit(self, true)
			queue_free()
			return
		if dot_timer <= 0.0:
			dot_dps = 0.0

	# Check close-quarters melee engagement with Commander (ground units only)
	if not flying and is_instance_valid(_commander_ref) and _commander_ref.is_alive():
		var dist_cmd := position.distance_to(_commander_ref.position)
		if dist_cmd <= 26.0:
			_heading = (_commander_ref.position - position).normalized() if dist_cmd > 0.1 else _heading
			_atk_timer -= delta
			if _atk_timer <= 0.0:
				_atk_timer = atk_rate
				_commander_ref.take_damage(melee_dmg)
			queue_redraw()
			return

	# Check if currently attacking a barrier
	if is_instance_valid(_attacking_barrier):
		if _attacking_barrier.destroyed:
			_attacking_barrier = null
		else:
			var dist_b := position.distance_to(_attacking_barrier.position)
			if dist_b > 26.0:
				var dir_b := (_attacking_barrier.position - position).normalized()
				_heading = dir_b
				position += dir_b * speed * (1.0 - slow_pct) * delta
			else:
				_heading = (_attacking_barrier.position - position).normalized()
				_atk_timer -= delta
				if _atk_timer <= 0.0:
					_atk_timer = atk_rate
					_attacking_barrier.take_damage(melee_dmg)
			queue_redraw()
			return
	else:
		_attacking_barrier = null

	# Follow EnemyPath waypoints
	if wp_idx >= waypoints.size():
		is_dead = true
		reached_end.emit(self)
		queue_free()
		return

	var wp: Dictionary = waypoints[wp_idx]
	var target := Vector2(float(wp["x"]), float(wp["y"]))
	var move_speed := speed * (1.0 - slow_pct)
	var step := move_speed * delta
	var to_target := target - position
	var dist := to_target.length()

	if dist > 0.01:
		_heading = to_target / dist

	if step >= dist:
		position = target
		var linked_idx: int = int(wp.get("linked_destroyable", -1))
		if linked_idx >= 0 and linked_idx < _barriers_ref.size():
			var b_var: Variant = _barriers_ref[linked_idx]
			if is_instance_valid(b_var):
				var b: BarrierEntity = b_var as BarrierEntity
				if b != null and not b.destroyed:
					if (not flying) or b.barrier_type == "Base":
						_attacking_barrier = b
						_atk_timer = 0.1
						wp_idx += 1
						progress = float(wp_idx)
						queue_redraw()
						return
		wp_idx += 1
		progress = float(wp_idx)
	else:
		position += _heading * step
		var prev_wp := Vector2(float(waypoints[maxi(0, wp_idx - 1)]["x"]), float(waypoints[maxi(0, wp_idx - 1)]["y"]))
		var seg_len := maxf(1.0, prev_wp.distance_to(target))
		progress = float(wp_idx - 1) + clampf(1.0 - (dist - step) / seg_len, 0.0, 1.0)

	queue_redraw()


func _draw() -> void:
	var regions: Array = GameData.sprite_regions.get(sheet_name, [])
	var frame_idx := 0
	var rot := 0.0
	var flip_x := 1.0

	if grid_16dir and regions.size() >= 80:
		var dir_row := clampi(int(round(acos(clampf(-_heading.y, -1.0, 1.0)) / PI * 4.0)), 0, 4)
		var anim_col := int(_anim_timer * 18.0) % 16
		frame_idx = dir_row * 16 + anim_col
		flip_x = -1.0 if _heading.x < -0.08 else 1.0
	elif regions.size() > 0:
		var cycle_len := mini(8, regions.size())
		frame_idx = int(_anim_timer * 10.0) % cycle_len
		rot = _heading.angle() + PI * 0.5

	var tex := GameData.get_atlas_texture(sheet_name, frame_idx)
	var mod := Color.WHITE
	if _hit_flash > 0.0:
		mod = Color(1.7, 0.75, 0.75)
	elif dot_timer > 0.0:
		mod = Color(0.55, 1.0, 0.45)
	elif slow_timer > 0.0:
		mod = Color(0.5, 0.82, 1.25)

	# Shadow
	var shadow_off := Vector2(3, 18) if flying else Vector2(2, 6)
	draw_circle(shadow_off, draw_size * 0.30, Color(0, 0, 0, 0.32))

	if tex != null:
		var half := draw_size * 0.5
		var visual_pos := Vector2(0, -10) if flying else Vector2.ZERO
		draw_set_transform(visual_pos, rot, Vector2(flip_x, 1.0))
		draw_texture_rect(tex, Rect2(-half, -half, draw_size, draw_size), false, mod)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(Vector2.ZERO, draw_size * 0.32, Color(0.8, 0.25, 0.25) * mod)

	# Health bar (shown when damaged or for bosses)
	if hp < max_hp or enemy_type >= 13:
		var ratio := clampf(hp / max_hp, 0.0, 1.0)
		var bw := clampf(draw_size * 0.75, 22.0, 44.0)
		var by := -draw_size * 0.55 - (10.0 if flying else 2.0)
		draw_rect(Rect2(-bw * 0.5 - 1, by - 1, bw + 2, 5), Color(0, 0, 0, 0.78))
		var hcol := Color(0.25, 0.95, 0.45) if ratio > 0.5 else (Color(1.0, 0.8, 0.2) if ratio > 0.25 else Color(1.0, 0.25, 0.25))
		draw_rect(Rect2(-bw * 0.5, by, bw * ratio, 3), hcol)
