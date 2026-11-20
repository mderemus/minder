extends Node2D
class_name MapRenderer
## Renders Sentinel 3 .tmx tile layers and provides an interactive placement/path overlay.

const TILE_SIZE := GameData.TILE_SIZE
const MAP_COLS := GameData.MAP_COLS
const MAP_ROWS := GameData.MAP_ROWS

var map_data: Dictionary = {}
var _tilesets: Array = []
var _tileset_textures: Array = []

# Overlay state updated by GameManager during placement / path preview
var show_build_grid: bool = false
var show_path_preview: bool = true
var path_pulse_time: float = 0.0
var hover_tile: Vector2i = Vector2i(-1, -1)
var hover_footprint: int = 1
var hover_range: float = 0.0
var hover_valid: bool = false
var occupied_cells: Dictionary = {} # Vector2i -> true (towers + eggs)

var _overlay_node: Node2D


func _ready() -> void:
	_overlay_node = Node2D.new()
	_overlay_node.z_index = 5
	_overlay_node.draw.connect(_draw_overlay)
	add_child(_overlay_node)


func load_map(map_id: String) -> void:
	map_data = GameData.maps.get(map_id, {})
	_tilesets = map_data.get("tilesets", [])
	_tileset_textures.clear()
	for ts in _tilesets:
		var tex_name: String = ts.get("resolved_texture", "TS_BaseBG6")
		_tileset_textures.append(GameData.get_texture(tex_name))
	queue_redraw()
	if _overlay_node:
		_overlay_node.queue_redraw()


func set_placement_preview(active: bool, tile: Vector2i, footprint: int, range_px: float, valid: bool) -> void:
	show_build_grid = active
	hover_tile = tile
	hover_footprint = footprint
	hover_range = range_px
	hover_valid = valid
	if _overlay_node:
		_overlay_node.queue_redraw()


func set_path_preview(enabled: bool) -> void:
	show_path_preview = enabled
	if _overlay_node:
		_overlay_node.queue_redraw()


func refresh_overlay() -> void:
	if _overlay_node:
		_overlay_node.queue_redraw()


func _process(delta: float) -> void:
	if show_path_preview:
		path_pulse_time += delta
		if _overlay_node:
			_overlay_node.queue_redraw()


func is_tile_buildable(gx: int, gy: int) -> bool:
	if gx < 0 or gy < 0 or gx >= MAP_COLS or gy >= MAP_ROWS:
		return false
	if map_data.is_empty():
		return false
	var idx := gy * MAP_COLS + gx
	var path_grid: Array = map_data.get("path_grid", [])
	var res_grid: Array = map_data.get("reserved_grid", [])
	if idx < path_grid.size() and int(path_grid[idx]) != 0:
		return false
	if idx < res_grid.size() and int(res_grid[idx]) != 0:
		return false
	if occupied_cells.has(Vector2i(gx, gy)):
		return false
	return true


func can_place_footprint(gx: int, gy: int, footprint: int) -> bool:
	for dy in range(footprint):
		for dx in range(footprint):
			if not is_tile_buildable(gx + dx, gy + dy):
				return false
	return true


func world_to_grid(pos: Vector2, footprint: int = 1) -> Vector2i:
	if footprint == 2:
		# Snap center of 2x2 to tile intersection
		var gx := int(round(pos.x / float(TILE_SIZE))) - 1
		var gy := int(round(pos.y / float(TILE_SIZE))) - 1
		return Vector2i(clampi(gx, 0, MAP_COLS - 2), clampi(gy, 0, MAP_ROWS - 2))
	var tx := int(floor(pos.x / float(TILE_SIZE)))
	var ty := int(floor(pos.y / float(TILE_SIZE)))
	return Vector2i(tx, ty)


func grid_to_world_center(gx: int, gy: int, footprint: int = 1) -> Vector2:
	var half := float(footprint * TILE_SIZE) * 0.5
	return Vector2(float(gx * TILE_SIZE) + half, float(gy * TILE_SIZE) + half)


func _draw() -> void:
	draw_rect(Rect2(0, 0, GameData.MAP_WIDTH, GameData.MAP_HEIGHT), Color(0.06, 0.08, 0.11))
	if map_data.is_empty():
		return
	var layers: Array = map_data.get("layers", [])
	for layer in layers:
		var tiles: Array = layer.get("tiles", [])
		for idx in range(tiles.size()):
			var raw_gid: int = int(tiles[idx])
			if raw_gid == 0:
				continue
			var gid := raw_gid & 0x1FFFFFFF
			var ts_idx := _find_tileset_index(gid)
			if ts_idx < 0:
				continue
			var tex: Texture2D = _tileset_textures[ts_idx]
			if tex == null:
				continue
			var ts: Dictionary = _tilesets[ts_idx]
			var local_id: int = gid - int(ts["firstgid"])
			var cols: int = int(ts["cols"])
			var stw: int = int(ts["src_tile_w"])
			var sth: int = int(ts["src_tile_h"])
			var sx: int = (local_id % cols) * stw
			var sy: int = int(local_id / cols) * sth
			var gx: int = idx % MAP_COLS
			var gy: int = int(idx / MAP_COLS)
			var dst := Rect2(gx * TILE_SIZE, gy * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			var src := Rect2(sx, sy, stw, sth)
			draw_texture_rect_region(tex, dst, src)


func _find_tileset_index(gid: int) -> int:
	var found := -1
	for i in range(_tilesets.size()):
		if gid >= int(_tilesets[i]["firstgid"]):
			found = i
		else:
			break
	return found


func _draw_overlay() -> void:
	if map_data.is_empty():
		return

	# Tactical EnemyPath preview (amber glowing lanes + moving chevrons)
	if show_path_preview:
		var paths: Array = map_data.get("enemy_paths", [])
		for p in paths:
			var wps: Array = p.get("waypoints", [])
			if wps.size() < 2:
				continue
			var is_air := String(p.get("enemy_type", "")) == "Flying"
			var line_col := Color(0.98, 0.72, 0.20, 0.55) if not is_air else Color(0.40, 0.85, 1.0, 0.45)
			var pts := PackedVector2Array()
			for wp in wps:
				pts.append(Vector2(float(wp["x"]), float(wp["y"])))
			_overlay_node.draw_polyline(pts, line_col, 2.5, true)
			# Draw moving pulse dots along segments
			for s in range(pts.size() - 1):
				var a := pts[s]
				var b := pts[s + 1]
				var seg_len := a.distance_to(b)
				if seg_len < 4.0:
					continue
				var dir := (b - a) / seg_len
				var offset := fmod(path_pulse_time * 36.0, 36.0)
				while offset < seg_len:
					var pos := a + dir * offset
					_overlay_node.draw_circle(pos, 2.6, Color(1.0, 0.9, 0.45, 0.75) if not is_air else Color(0.6, 0.95, 1.0, 0.65))
					offset += 36.0

	# Placement grid highlight
	if show_build_grid:
		for gy in range(MAP_ROWS):
			for gx in range(MAP_COLS):
				var rect := Rect2(gx * TILE_SIZE + 1, gy * TILE_SIZE + 1, TILE_SIZE - 2, TILE_SIZE - 2)
				if is_tile_buildable(gx, gy):
					_overlay_node.draw_rect(rect, Color(0.20, 0.95, 0.55, 0.16), true)
					_overlay_node.draw_rect(rect, Color(0.20, 0.95, 0.55, 0.45), false, 1.0)
		if hover_tile.x >= 0 and hover_tile.y >= 0 and hover_tile.x < MAP_COLS and hover_tile.y < MAP_ROWS:
			var footprint_rect := Rect2(
				hover_tile.x * TILE_SIZE,
				hover_tile.y * TILE_SIZE,
				hover_footprint * TILE_SIZE,
				hover_footprint * TILE_SIZE
			)
			var col := Color(0.2, 1.0, 0.45, 0.42) if hover_valid else Color(1.0, 0.25, 0.25, 0.45)
			var border := Color(0.3, 1.0, 0.6, 0.95) if hover_valid else Color(1.0, 0.35, 0.35, 0.95)
			_overlay_node.draw_rect(footprint_rect, col, true)
			_overlay_node.draw_rect(footprint_rect, border, false, 2.0)
			if hover_range > 0.0:
				var center := grid_to_world_center(hover_tile.x, hover_tile.y, hover_footprint)
				_overlay_node.draw_circle(center, hover_range, Color(border.r, border.g, border.b, 0.09))
				_overlay_node.draw_arc(center, hover_range, 0.0, TAU, 48, Color(border.r, border.g, border.b, 0.75), 1.6)
