extends Node2D
class_name CommanderEntity
## Sentinel Commander hero mech: movable battlefield unit with Morale Aura (+25% tower dmg),
## ranged laser, close-quarters melee, shockwave stomp, and drop-pod respawn.

signal moved(commander: CommanderEntity)
signal sfx_requested(sfx_name: String)
signal beam_fx_requested(from_pos: Vector2, to_pos: Vector2, color: Color, width: float, duration: float)
signal shockwave_requested(center: Vector2, radius: float, color: Color)

const AURA_RANGE := 96.0
const RANGED_RANGE := 115.0
const MELEE_RANGE := 32.0
const MOVE_SPEED := 115.0

var max_hp: float = 300.0
var hp: float = 300.0
var selected: bool = false

var _home_pos: Vector2 = Vector2(460, 144)
var _target_pos: Vector2 = Vector2(460, 144)
var _is_moving: bool = false
var _respawn_timer: float = 0.0
var _out_of_combat_timer: float = 0.0
var _ranged_cd: float = 0.0
var _melee_cd: float = 0.0
var _stomp_cd: float = 0.0
var _heading: Vector2 = Vector2.LEFT
var _anim_t: float = 0.0
var _hit_flash: float = 0.0

var _enemies_ref: Array = []


func setup(spawn_pos: Vector2, enemies_list: Array) -> void:
	_home_pos = spawn_pos
	_target_pos = spawn_pos
	position = spawn_pos
	_enemies_ref = enemies_list
	hp = max_hp
	_respawn_timer = 0.0
	z_index = 28
	queue_redraw()


func is_alive() -> bool:
	return _respawn_timer <= 0.0 and hp > 0.0


func order_move(dest: Vector2) -> void:
	if not is_alive():
		return
	_target_pos = Vector2(
		clampf(dest.x, 16.0, GameData.MAP_WIDTH - 16.0),
		clampf(dest.y, 16.0, GameData.MAP_HEIGHT - 16.0)
	)
	_is_moving = position.distance_to(_target_pos) > 4.0
	if _is_moving:
		sfx_requested.emit("Com_Jump")
	queue_redraw()


func trigger_stomp() -> bool:
	if not is_alive() or _stomp_cd > 0.0:
		return false
	_stomp_cd = 12.0
	sfx_requested.emit("Com_Stomp")
	shockwave_requested.emit(position, 82.0, Color(0.35, 0.9, 1.0))
	for e in _enemies_ref:
		if is_instance_valid(e) and not e.is_dead and not e.flying:
			if position.distance_to(e.position) <= 82.0:
				e.take_damage(65.0, "kinetic")
				e.apply_slow(0.50, 2.5)
	return true


func get_stomp_cooldown() -> float:
	return _stomp_cd


func take_damage(amount: float) -> void:
	if not is_alive():
		return
	hp = maxf(0.0, hp - amount)
	_out_of_combat_timer = 0.0
	_hit_flash = 0.14
	if hp <= 0.0:
		_respawn_timer = 12.0
		_is_moving = false
		sfx_requested.emit("Com_Death")
		moved.emit(self)
	queue_redraw()


func _process(delta: float) -> void:
	_anim_t += delta
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
	if _stomp_cd > 0.0:
		_stomp_cd = maxf(0.0, _stomp_cd - delta)

	if _respawn_timer > 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			hp = max_hp
			position = _home_pos
			_target_pos = _home_pos
			sfx_requested.emit("DropPod")
			shockwave_requested.emit(position, 48.0, Color(0.35, 1.0, 0.8))
			moved.emit(self)
		queue_redraw()
		return

	_out_of_combat_timer += delta
	if _out_of_combat_timer >= 3.0 and hp < max_hp:
		hp = minf(max_hp, hp + 10.0 * delta)

	if _is_moving:
		var diff := _target_pos - position
		var dist := diff.length()
		var step := MOVE_SPEED * delta
		if dist > 0.01:
			_heading = diff / dist
		if step >= dist:
			position = _target_pos
			_is_moving = false
		else:
			position += _heading * step
		moved.emit(self)

	_ranged_cd = maxf(0.0, _ranged_cd - delta)
	_melee_cd = maxf(0.0, _melee_cd - delta)

	var nearest: EnemyEntity = null
	var best_dist := RANGED_RANGE
	for e in _enemies_ref:
		if not is_instance_valid(e) or e.is_dead:
			continue
		var d := position.distance_to(e.position)
		if d <= best_dist:
			best_dist = d
			nearest = e

	if nearest != null:
		var dir := nearest.position - position
		if dir.length() > 0.1:
			_heading = dir.normalized()
		if best_dist <= MELEE_RANGE and not nearest.flying and _melee_cd <= 0.0:
			_melee_cd = 0.55
			_out_of_combat_timer = 0.0
			nearest.take_damage(26.0, "kinetic")
			sfx_requested.emit("Com_Swords")
			beam_fx_requested.emit(position, nearest.position, Color(0.95, 0.9, 0.35), 4.0, 0.10)
		elif _ranged_cd <= 0.0:
			_ranged_cd = 0.42
			_out_of_combat_timer = 0.0
			nearest.take_damage(12.0, "laser")
			sfx_requested.emit("Fire_LaserRanger")
			beam_fx_requested.emit(position + _heading * 14.0, nearest.position, Color(0.3, 0.95, 1.0), 2.5, 0.09)

	queue_redraw()


func _draw() -> void:
	if not is_alive():
		draw_circle(Vector2.ZERO, 14.0, Color(0.2, 0.25, 0.3, 0.55))
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU * clampf(1.0 - _respawn_timer / 12.0, 0.0, 1.0), 24, Color(0.3, 0.9, 1.0), 2.5)
		return

	# Morale Aura ring
	var aura_alpha := 0.22 if selected else 0.11
	draw_circle(Vector2.ZERO, AURA_RANGE, Color(0.25, 0.85, 1.0, aura_alpha * 0.35))
	draw_arc(Vector2.ZERO, AURA_RANGE, 0.0, TAU, 56, Color(0.3, 0.92, 1.0, aura_alpha + 0.15), 1.5 if selected else 1.0)

	if _is_moving:
		var rel_t := _target_pos - position
		draw_line(Vector2.ZERO, rel_t, Color(0.3, 0.95, 1.0, 0.45), 1.5)
		draw_circle(rel_t, 5.0, Color(0.3, 0.95, 1.0, 0.7))

	# Shadow
	draw_circle(Vector2(2, 7), 14.0, Color(0, 0, 0, 0.35))

	# Extracted Hero1 sprite sheet
	var frame := (int(_anim_t * 8.0) % 8) if _is_moving else 0
	var tex := GameData.get_atlas_texture("Hero1", frame)
	var mod := Color(1.7, 0.65, 0.65) if _hit_flash > 0.0 else Color.WHITE
	if tex != null:
		draw_set_transform(Vector2.ZERO, _heading.angle() + PI * 0.5, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-22, -22, 44, 44), false, mod)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(Vector2.ZERO, 14.0, Color(0.25, 0.75, 1.0) * mod)

	if selected:
		draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 32, Color(0.35, 1.0, 0.85, 0.95), 2.0)

	# HP bar
	var ratio := clampf(hp / max_hp, 0.0, 1.0)
	var bw := 32.0
	draw_rect(Rect2(-bw * 0.5 - 1, -27, bw + 2, 6), Color(0, 0, 0, 0.82))
	draw_rect(Rect2(-bw * 0.5, -26, bw * ratio, 4), Color(0.3, 0.95, 1.0))
