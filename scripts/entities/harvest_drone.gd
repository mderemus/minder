extends Node2D
class_name HarvestDroneEntity
## Autonomous Sentinel 3 support drone: harvests resources between Harvestable and
## ResourceDropPoint, or repairs damaged barriers when toggled into Repair Mode.

signal harvest_completed(cash_amount: int, energy_amount: float)
signal barrier_repaired(barrier: BarrierEntity, amount: float)

enum State { TO_FIELD, HARVESTING, TO_DROP, TO_REPAIR, REPAIRING }

const SPEED := 85.0

var drop_point: Vector2 = Vector2(620, 111)
var field_point: Vector2 = Vector2(578, 269)
var repair_mode: bool = false

var _state: State = State.TO_FIELD
var _work_timer: float = 0.0
var _heading: Vector2 = Vector2.DOWN
var _tex: Texture2D = null
var _barriers_ref: Array = []
var _active_barrier: BarrierEntity = null


func setup(p_drop: Vector2, p_field: Vector2, barriers: Array) -> void:
	drop_point = p_drop
	field_point = p_field
	_barriers_ref = barriers
	position = drop_point
	_state = State.TO_FIELD
	_tex = GameData.get_atlas_texture("turrets_sheet", 58) # row 7 col 2
	z_index = 32
	queue_redraw()


func set_repair_mode(enabled: bool) -> void:
	repair_mode = enabled
	if repair_mode:
		_pick_damaged_barrier()
	else:
		_active_barrier = null
		_state = State.TO_FIELD
	queue_redraw()


func _pick_damaged_barrier() -> void:
	_active_barrier = null
	var lowest_ratio := 1.0
	for item in _barriers_ref:
		if not is_instance_valid(item):
			continue
		var b: BarrierEntity = item as BarrierEntity
		if b != null and not b.destroyed and b.hp < b.max_hp:
			var r: float = b.hp / b.max_hp
			if r < lowest_ratio:
				lowest_ratio = r
				_active_barrier = b
	if _active_barrier != null:
		_state = State.TO_REPAIR
	else:
		_state = State.TO_FIELD


func _process(delta: float) -> void:
	if repair_mode and (not is_instance_valid(_active_barrier) or _active_barrier.destroyed or _active_barrier.hp >= _active_barrier.max_hp):
		_pick_damaged_barrier()

	match _state:
		State.TO_FIELD:
			if _move_toward(field_point, delta):
				_state = State.HARVESTING
				_work_timer = 1.4
		State.HARVESTING:
			_work_timer -= delta
			if _work_timer <= 0.0:
				_state = State.TO_DROP
		State.TO_DROP:
			if _move_toward(drop_point, delta):
				harvest_completed.emit(5, 6.0)
				if repair_mode:
					_pick_damaged_barrier()
				else:
					_state = State.TO_FIELD
		State.TO_REPAIR:
			if not is_instance_valid(_active_barrier) or _active_barrier.destroyed:
				_state = State.TO_FIELD
			elif _move_toward(_active_barrier.position + Vector2(0, -14), delta):
				_state = State.REPAIRING
				_work_timer = 1.0
		State.REPAIRING:
			_work_timer -= delta
			if _work_timer <= 0.0:
				if is_instance_valid(_active_barrier) and not _active_barrier.destroyed:
					_active_barrier.repair(25.0)
					barrier_repaired.emit(_active_barrier, 25.0)
				_work_timer = 1.0
	queue_redraw()


func _move_toward(target: Vector2, delta: float) -> bool:
	var diff := target - position
	var dist := diff.length()
	if dist > 0.1:
		_heading = diff / dist
	var step := SPEED * delta
	if step >= dist:
		position = target
		return true
	position += _heading * step
	return false


func _draw() -> void:
	draw_circle(Vector2(2, 12), 8.0, Color(0, 0, 0, 0.25))

	if _state == State.HARVESTING:
		var beam_col := Color(0.3, 0.95, 1.0, 0.75)
		draw_line(Vector2.ZERO, Vector2(0, 14), beam_col, 3.0)
		draw_circle(Vector2(0, 14), 5.0, Color(0.7, 1.0, 1.0, 0.85))
	elif _state == State.REPAIRING and is_instance_valid(_active_barrier):
		draw_line(Vector2.ZERO, _active_barrier.position - position, Color(0.35, 1.0, 0.55, 0.8), 3.0)

	if _tex != null:
		draw_set_transform(Vector2.ZERO, _heading.angle(), Vector2.ONE)
		draw_texture_rect(_tex, Rect2(-14, -14, 28, 28), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(Vector2.ZERO, 9.0, Color(0.3, 0.9, 1.0))

	if _state == State.TO_DROP:
		draw_circle(Vector2(0, -10), 3.5, Color(1.0, 0.85, 0.25))
