extends Node2D
class_name BarrierEntity
## Tactical barrier / base gate positioned on Destroyables objects in the .tmx map.

signal barrier_damaged(barrier: BarrierEntity)
signal barrier_destroyed(barrier: BarrierEntity)

var barrier_index: int = 0
var barrier_name: String = "Barrier"
var barrier_type: String = "Normal" # "Normal", "Base", "Energy", "Factory"
var direction: String = "Right"

var max_hp: float = 500.0
var hp: float = 500.0
var destroyed: bool = false

var _hit_flash: float = 0.0
var _pulse: float = 0.0
var _tex: Texture2D = null


func setup(data: Dictionary) -> void:
	barrier_index = int(data.get("index", 0))
	barrier_name = String(data.get("name", "Barrier"))
	barrier_type = String(data.get("type", "Normal"))
	direction = String(data.get("direction", "Right"))
	position = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))

	max_hp = 1000.0 if barrier_type == "Base" else 500.0
	hp = max_hp
	destroyed = false

	var col_idx := 57 if barrier_type == "Base" else 56 # row 7 col 1 / col 0
	_tex = GameData.get_atlas_texture("turrets_sheet", col_idx)
	z_index = 10
	queue_redraw()


func take_damage(amount: float) -> void:
	if destroyed:
		return
	hp = maxf(0.0, hp - amount)
	_hit_flash = 0.16
	barrier_damaged.emit(self)
	if hp <= 0.0:
		destroyed = true
		barrier_destroyed.emit(self)
	queue_redraw()


func repair(amount: float) -> void:
	if destroyed and barrier_type == "Base":
		return
	if destroyed:
		# Allow orbital repair beam to restore breached forward barriers
		destroyed = false
	hp = minf(max_hp, hp + amount)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta * 3.0
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
	queue_redraw()


func _draw() -> void:
	if destroyed:
		# Scorched rubble footprint
		draw_rect(Rect2(-14, -22, 28, 44), Color(0.15, 0.12, 0.12, 0.65))
		draw_rect(Rect2(-10, -18, 20, 36), Color(0.28, 0.22, 0.20, 0.7), false, 1.5)
		return

	var mod := Color(1.0, 0.45, 0.45) if _hit_flash > 0.0 else Color.WHITE
	if _tex != null:
		var flip_x := -1.0 if direction == "Left" else 1.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(flip_x, 1.0))
		draw_texture_rect(_tex, Rect2(-24, -24, 48, 48), false, mod)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_rect(Rect2(-10, -24, 20, 48), Color(0.2, 0.8, 1.0, 0.8) * mod)

	# Shimmering energy shield line
	var shield_alpha := 0.28 + 0.18 * sin(_pulse)
	var shield_col := Color(0.3, 1.0, 0.72, shield_alpha) if barrier_type == "Base" else Color(0.25, 0.85, 1.0, shield_alpha)
	draw_line(Vector2(0, -22), Vector2(0, 22), shield_col, 3.0)

	# Health bar
	var ratio := clampf(hp / max_hp, 0.0, 1.0)
	var bar_w := 38.0
	var bar_pos := Vector2(-bar_w * 0.5, -30.0)
	draw_rect(Rect2(bar_pos - Vector2(1, 1), Vector2(bar_w + 2, 7)), Color(0.05, 0.07, 0.1, 0.88))
	var fill_col := Color(0.22, 0.95, 0.55) if ratio > 0.5 else (Color(1.0, 0.78, 0.2) if ratio > 0.25 else Color(1.0, 0.25, 0.25))
	draw_rect(Rect2(bar_pos, Vector2(bar_w * ratio, 5)), fill_col)
