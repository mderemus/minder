extends Control
class_name GameManager
## Main Sentinel 3: Homeworld game controller, wave/economy manager,
## VFX/projectile system, audio manager, and Desktop/Mobile responsive HUD.

const DIFF_KEYS: Array[String] = ["easy", "medium", "hard", "psycho"]
const DIFF_LABELS: Array[String] = ["Easy", "Medium", "Hard", "Psycho"]

# State
var current_level_index: int = 0
var current_diff_key: String = "medium"
var level_cfg: Dictionary = {}
var map_cfg: Dictionary = {}

var cash: int = 80
var ship_energy: float = 100.0
var max_ship_energy: float = 100.0
var score: int = 0
var current_wave: int = 0 # 1-based once started; 0 before Wave 1
var total_waves: int = 10
var game_speed: float = 1.0
var paused: bool = false
var game_over: bool = false
var victory: bool = false
var muted: bool = false
var auto_wave: bool = false

# Wave spawning state
var wave_active: bool = false
var _spawn_remaining: int = 0
var _spawn_timer: float = 0.0
var _current_wave_spec: Dictionary = {}
var _wave_countdown: float = 0.0

# Entities
var barriers: Array[BarrierEntity] = []
var enemies: Array[EnemyEntity] = []
var towers: Array[TowerEntity] = []
var commander: CommanderEntity = null
var harvest_drone: HarvestDroneEntity = null
var egg_nodes: Array[Dictionary] = [] # {pos, tile, hp, max_hp}

# Active projectiles & VFX
var projectiles: Array[Dictionary] = []
var beam_fxs: Array[Dictionary] = []
var shockwave_fxs: Array[Dictionary] = []
var explosion_fxs: Array[Dictionary] = []
var float_texts: Array[Dictionary] = []
var orbital_cooldowns: Dictionary = {"orbital_laser": 0.0, "ion_bomb": 0.0, "turret_energizer": 0.0, "repair_beam": 0.0}

# Interaction state (tap-to-place, drag-to-place, commander move, orbital targeting)
var pending_tower_id: String = ""
var pending_orbital_id: String = ""
var dragging_tower: bool = false
var commander_move_armed: bool = false
var selected_tower: TowerEntity = null

# Scene Nodes
var world_root: Node2D
var map_renderer: MapRenderer
var entities_layer: Node2D
var vfx_layer: Node2D

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_idx: int = 0
var _music_player: AudioStreamPlayer
var _current_music: String = ""

# HUD References
var _lbl_wave: Label
var _lbl_cash: Label
var _lbl_energy: Label
var _lbl_score: Label
var _lbl_base_hp: Label
var _lbl_status: Label
var _btn_next_wave: Button
var _btn_speed: Button
var _btn_mute: Button
var _btn_auto_wave: Button
var _btn_drone_mode: Button
var _btn_cmd_move: Button
var _btn_cmd_stomp: Button
var _opt_mission: OptionButton
var _opt_diff: OptionButton
var _tower_buttons: Dictionary = {}
var _orbital_buttons: Dictionary = {}

var _inspector_title: Label
var _inspector_stats: Label
var _btn_upgrade: Button
var _btn_sell: Button
var _btn_cancel_mode: Button
var _end_overlay: PanelContainer
var _end_title: Label
var _end_body: Label


func _ready() -> void:
	_build_scene_hierarchy()
	_build_hud()
	_setup_audio()
	load_mission(0, "medium")


func _build_scene_hierarchy() -> void:
	# Dark sci-fi frame background
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# WorldRoot scales the 672x512 map cleanly to fit left side under 36px top bar
	world_root = Node2D.new()
	world_root.name = "WorldRoot"
	world_root.position = Vector2(6.0, 38.0)
	world_root.scale = Vector2(0.982, 0.974)
	add_child(world_root)

	map_renderer = MapRenderer.new()
	map_renderer.name = "MapRenderer"
	world_root.add_child(map_renderer)

	entities_layer = Node2D.new()
	entities_layer.name = "EntitiesLayer"
	entities_layer.z_index = 10
	world_root.add_child(entities_layer)

	vfx_layer = Node2D.new()
	vfx_layer.name = "VfxLayer"
	vfx_layer.z_index = 50
	vfx_layer.draw.connect(_draw_vfx)
	world_root.add_child(vfx_layer)


func _setup_audio() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -10.0
	add_child(_music_player)
	for i in range(10):
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_sfx_players.append(p)


func _exit_tree() -> void:
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null
	for p in _sfx_players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null


func _play_sfx(sfx_name: String) -> void:
	if muted or sfx_name == "":
		return
	var stream := GameData.get_audio_stream(sfx_name)
	if stream == null:
		return
	var p := _sfx_players[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_players.size()
	p.stream = stream
	p.play()


func _play_music(track_name: String) -> void:
	if _current_music == track_name and _music_player.playing:
		return
	_current_music = track_name
	if muted:
		return
	var stream := GameData.get_audio_stream(track_name)
	if stream != null:
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		_music_player.stream = stream
		_music_player.play()


func _build_hud() -> void:
	# --- Top Bar (y = 0..36, width = 960) ---
	var top_bar := PanelContainer.new()
	top_bar.position = Vector2(0, 0)
	top_bar.size = Vector2(960, 36)
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.08, 0.11, 0.16, 0.96)
	top_style.border_color = Color(0.2, 0.55, 0.78, 0.7)
	top_style.border_width_bottom = 2
	top_bar.add_theme_stylebox_override("panel", top_style)
	add_child(top_bar)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 6)
	top_bar.add_child(top_hbox)

	_opt_mission = OptionButton.new()
	_opt_mission.custom_minimum_size = Vector2(150, 28)
	for i in range(GameData.campaign_levels.size()):
		var lv: Dictionary = GameData.campaign_levels[i]
		var prefix := "C1" if int(lv["campaign"]) == 1 else "C2"
		_opt_mission.add_item("%s-%d %s" % [prefix, int(lv["mission_number"]), String(lv["title"])], i)
	_opt_mission.item_selected.connect(func(idx: int): load_mission(idx, current_diff_key))
	top_hbox.add_child(_opt_mission)

	_opt_diff = OptionButton.new()
	_opt_diff.custom_minimum_size = Vector2(82, 28)
	for i in range(DIFF_LABELS.size()):
		_opt_diff.add_item(DIFF_LABELS[i], i)
	_opt_diff.selected = 1
	_opt_diff.item_selected.connect(func(idx: int): load_mission(current_level_index, DIFF_KEYS[idx]))
	top_hbox.add_child(_opt_diff)

	_lbl_wave = _make_hud_label("WAVE 0/10", Color(0.95, 0.85, 0.35), 88)
	top_hbox.add_child(_lbl_wave)

	_lbl_cash = _make_hud_label("$80", Color(0.35, 1.0, 0.55), 72)
	top_hbox.add_child(_lbl_cash)

	_lbl_energy = _make_hud_label("E: 100", Color(0.35, 0.88, 1.0), 66)
	top_hbox.add_child(_lbl_energy)

	_lbl_base_hp = _make_hud_label("BASE 100%", Color(0.45, 0.95, 0.72), 86)
	top_hbox.add_child(_lbl_base_hp)

	_lbl_score = _make_hud_label("SCR 0", Color(0.85, 0.9, 1.0), 74)
	top_hbox.add_child(_lbl_score)

	_btn_next_wave = Button.new()
	_btn_next_wave.text = "NEXT WAVE"
	_btn_next_wave.custom_minimum_size = Vector2(92, 28)
	_btn_next_wave.pressed.connect(start_next_wave)
	top_hbox.add_child(_btn_next_wave)

	_btn_auto_wave = Button.new()
	_btn_auto_wave.text = "AUTO"
	_btn_auto_wave.toggle_mode = true
	_btn_auto_wave.custom_minimum_size = Vector2(52, 28)
	_btn_auto_wave.toggled.connect(func(on: bool): auto_wave = on)
	top_hbox.add_child(_btn_auto_wave)

	_btn_speed = Button.new()
	_btn_speed.text = "1x"
	_btn_speed.custom_minimum_size = Vector2(40, 28)
	_btn_speed.pressed.connect(_cycle_speed)
	top_hbox.add_child(_btn_speed)

	_btn_mute = Button.new()
	_btn_mute.text = "SFX"
	_btn_mute.custom_minimum_size = Vector2(42, 28)
	_btn_mute.pressed.connect(_toggle_mute)
	top_hbox.add_child(_btn_mute)

	var btn_restart := Button.new()
	btn_restart.text = "RST"
	btn_restart.custom_minimum_size = Vector2(40, 28)
	btn_restart.pressed.connect(func(): load_mission(current_level_index, current_diff_key))
	top_hbox.add_child(btn_restart)

	# --- Right Tactical Command Panel (x = 672..958, y = 38..538) ---
	var side_panel := PanelContainer.new()
	side_panel.position = Vector2(672, 38)
	side_panel.size = Vector2(286, 500)
	var side_style := StyleBoxFlat.new()
	side_style.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	side_style.border_color = Color(0.22, 0.58, 0.82, 0.65)
	side_style.set_border_width_all(2)
	side_style.set_corner_radius_all(6)
	side_style.set_content_margin_all(7)
	side_panel.add_theme_stylebox_override("panel", side_style)
	add_child(side_panel)

	var side_vbox := VBoxContainer.new()
	side_vbox.add_theme_constant_override("separation", 5)
	side_panel.add_child(side_vbox)

	# Section: Ground Turrets
	side_vbox.add_child(_make_section_header("GROUND TURRETS (Tap or Drag)"))
	var turret_grid := GridContainer.new()
	turret_grid.columns = 3
	turret_grid.add_theme_constant_override("h_separation", 4)
	turret_grid.add_theme_constant_override("v_separation", 4)
	side_vbox.add_child(turret_grid)

	for tid in GameData.TOWER_ORDER:
		var tdef: Dictionary = GameData.TOWER_DEFS[tid]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(86, 42)
		btn.text = "%s\n$%d" % [String(tdef["short"]), int(tdef["costs"][0])]
		btn.add_theme_font_size_override("font_size", 11)
		btn.tooltip_text = "%s (%dx%d): %s" % [String(tdef["name"]), int(tdef["footprint"]), int(tdef["footprint"]), String(tdef["desc"])]
		btn.button_down.connect(_on_turret_button_down.bind(tid))
		btn.pressed.connect(_on_turret_button_pressed.bind(tid))
		turret_grid.add_child(btn)
		_tower_buttons[tid] = btn

	# Section: Commander & Support Drone
	side_vbox.add_child(_make_section_header("COMMANDER & DRONE"))
	var cmd_row := HBoxContainer.new()
	cmd_row.add_theme_constant_override("separation", 4)
	side_vbox.add_child(cmd_row)

	_btn_cmd_move = Button.new()
	_btn_cmd_move.text = "MOVE CMDR"
	_btn_cmd_move.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_cmd_move.custom_minimum_size = Vector2(0, 32)
	_btn_cmd_move.add_theme_font_size_override("font_size", 11)
	_btn_cmd_move.pressed.connect(_arm_commander_move)
	cmd_row.add_child(_btn_cmd_move)

	_btn_cmd_stomp = Button.new()
	_btn_cmd_stomp.text = "STOMP"
	_btn_cmd_stomp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_cmd_stomp.custom_minimum_size = Vector2(0, 32)
	_btn_cmd_stomp.add_theme_font_size_override("font_size", 11)
	_btn_cmd_stomp.pressed.connect(_trigger_commander_stomp)
	cmd_row.add_child(_btn_cmd_stomp)

	_btn_drone_mode = Button.new()
	_btn_drone_mode.text = "HARVEST"
	_btn_drone_mode.toggle_mode = true
	_btn_drone_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_drone_mode.custom_minimum_size = Vector2(0, 32)
	_btn_drone_mode.add_theme_font_size_override("font_size", 11)
	_btn_drone_mode.toggled.connect(_on_drone_mode_toggled)
	cmd_row.add_child(_btn_drone_mode)

	# Section: Orbital Weapons
	side_vbox.add_child(_make_section_header("SENTINEL ORBITAL WEAPONS"))
	var orb_grid := GridContainer.new()
	orb_grid.columns = 2
	orb_grid.add_theme_constant_override("h_separation", 4)
	orb_grid.add_theme_constant_override("v_separation", 4)
	side_vbox.add_child(orb_grid)

	for oid in GameData.ORBITAL_ORDER:
		var odef: Dictionary = GameData.ORBITAL_DEFS[oid]
		var obtn := Button.new()
		obtn.custom_minimum_size = Vector2(130, 34)
		obtn.text = "%s (%dE)" % [String(odef["short"]), int(odef["cost"])]
		obtn.add_theme_font_size_override("font_size", 11)
		obtn.tooltip_text = String(odef["desc"])
		obtn.pressed.connect(_arm_orbital.bind(oid))
		orb_grid.add_child(obtn)
		_orbital_buttons[oid] = obtn

	# Section: Context Inspector
	side_vbox.add_child(_make_section_header("TACTICAL INSPECTOR"))
	var insp_box := PanelContainer.new()
	insp_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var insp_style := StyleBoxFlat.new()
	insp_style.bg_color = Color(0.05, 0.07, 0.11, 0.9)
	insp_style.border_color = Color(0.18, 0.36, 0.52, 0.7)
	insp_style.set_border_width_all(1)
	insp_style.set_corner_radius_all(4)
	insp_style.set_content_margin_all(6)
	insp_box.add_theme_stylebox_override("panel", insp_style)
	side_vbox.add_child(insp_box)

	var insp_v := VBoxContainer.new()
	insp_v.add_theme_constant_override("separation", 4)
	insp_box.add_child(insp_v)

	_inspector_title = Label.new()
	_inspector_title.text = "Ready for Deployment"
	_inspector_title.add_theme_font_size_override("font_size", 13)
	_inspector_title.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	insp_v.add_child(_inspector_title)

	_inspector_stats = Label.new()
	_inspector_stats.text = "Select a turret to build or tap a built tower to upgrade/sell."
	_inspector_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspector_stats.add_theme_font_size_override("font_size", 11)
	_inspector_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	insp_v.add_child(_inspector_stats)

	var insp_btns := HBoxContainer.new()
	insp_btns.add_theme_constant_override("separation", 6)
	insp_v.add_child(insp_btns)

	_btn_upgrade = Button.new()
	_btn_upgrade.text = "UPGRADE"
	_btn_upgrade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_upgrade.custom_minimum_size = Vector2(0, 32)
	_btn_upgrade.visible = false
	_btn_upgrade.pressed.connect(_on_upgrade_pressed)
	insp_btns.add_child(_btn_upgrade)

	_btn_sell = Button.new()
	_btn_sell.text = "SELL"
	_btn_sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_sell.custom_minimum_size = Vector2(0, 32)
	_btn_sell.visible = false
	_btn_sell.pressed.connect(_on_sell_pressed)
	insp_btns.add_child(_btn_sell)

	_btn_cancel_mode = Button.new()
	_btn_cancel_mode.text = "CANCEL ACTION"
	_btn_cancel_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_cancel_mode.custom_minimum_size = Vector2(0, 30)
	_btn_cancel_mode.visible = false
	_btn_cancel_mode.pressed.connect(_clear_interaction_modes)
	insp_btns.add_child(_btn_cancel_mode)

	_lbl_status = Label.new()
	_lbl_status.position = Vector2(12, 514)
	_lbl_status.size = Vector2(650, 22)
	_lbl_status.add_theme_font_size_override("font_size", 12)
	_lbl_status.add_theme_color_override("font_color", Color(0.85, 0.94, 1.0, 0.9))
	add_child(_lbl_status)

	# --- Victory / Defeat Overlay ---
	_end_overlay = PanelContainer.new()
	_end_overlay.position = Vector2(180, 155)
	_end_overlay.size = Vector2(360, 200)
	_end_overlay.visible = false
	var end_style := StyleBoxFlat.new()
	end_style.bg_color = Color(0.06, 0.09, 0.14, 0.96)
	end_style.border_color = Color(0.35, 0.92, 1.0, 0.9)
	end_style.set_border_width_all(2)
	end_style.set_corner_radius_all(8)
	end_style.set_content_margin_all(16)
	_end_overlay.add_theme_stylebox_override("panel", end_style)
	add_child(_end_overlay)

	var end_v := VBoxContainer.new()
	end_v.alignment = BoxContainer.ALIGNMENT_CENTER
	end_v.add_theme_constant_override("separation", 10)
	_end_overlay.add_child(end_v)

	_end_title = Label.new()
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_title.add_theme_font_size_override("font_size", 22)
	end_v.add_child(_end_title)

	_end_body = Label.new()
	_end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_v.add_child(_end_body)

	var end_btns := HBoxContainer.new()
	end_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	end_btns.add_theme_constant_override("separation", 12)
	end_v.add_child(end_btns)

	var btn_replay := Button.new()
	btn_replay.text = "PLAY AGAIN"
	btn_replay.custom_minimum_size = Vector2(120, 36)
	btn_replay.pressed.connect(func(): load_mission(current_level_index, current_diff_key))
	end_btns.add_child(btn_replay)

	var btn_next_lvl := Button.new()
	btn_next_lvl.text = "NEXT MISSION"
	btn_next_lvl.custom_minimum_size = Vector2(120, 36)
	btn_next_lvl.pressed.connect(func():
		var next_idx := mini(current_level_index + 1, GameData.campaign_levels.size() - 1)
		load_mission(next_idx, current_diff_key)
	)
	end_btns.add_child(btn_next_lvl)


func _make_hud_label(text: String, col: Color, min_w: float) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(min_w, 26)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", col)
	return lbl


func _make_section_header(title: String) -> Label:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.58, 0.80, 0.96))
	return lbl


func load_mission(level_index: int, diff_key: String = "medium") -> void:
	current_level_index = clampi(level_index, 0, maxi(0, GameData.campaign_levels.size() - 1))
	current_diff_key = diff_key
	level_cfg = GameData.get_level_config(current_level_index)
	var map_id: String = String(level_cfg.get("map_id", "Map1"))
	map_cfg = GameData.maps.get(map_id, {})

	if _opt_mission and _opt_mission.selected != current_level_index:
		_opt_mission.selected = current_level_index
	var diff_idx := DIFF_KEYS.find(diff_key)
	if _opt_diff and diff_idx >= 0 and _opt_diff.selected != diff_idx:
		_opt_diff.selected = diff_idx

	# Clear previous entities
	for child in entities_layer.get_children():
		child.queue_free()
	barriers.clear()
	enemies.clear()
	towers.clear()
	egg_nodes.clear()
	projectiles.clear()
	beam_fxs.clear()
	shockwave_fxs.clear()
	explosion_fxs.clear()
	float_texts.clear()
	commander = null
	harvest_drone = null
	_clear_interaction_modes()

	map_renderer.occupied_cells.clear()
	map_renderer.load_map(map_id)
	map_renderer.set_path_preview(true)

	# Reset economy & wave state
	cash = int(level_cfg.get("starting_cash", 80))
	ship_energy = float(level_cfg.get("starting_energy", 100))
	max_ship_energy = maxf(100.0, ship_energy)
	score = 0
	current_wave = 0
	total_waves = int(level_cfg.get("waves", 10))
	wave_active = false
	_spawn_remaining = 0
	_wave_countdown = 0.0
	game_over = false
	victory = false
	paused = false
	for k in orbital_cooldowns.keys():
		orbital_cooldowns[k] = 0.0
	if _end_overlay:
		_end_overlay.visible = false

	# Instantiate Barriers from Destroyables
	var dest_list: Array = map_cfg.get("destroyables", [])
	for d in dest_list:
		var b := BarrierEntity.new()
		b.setup(d)
		b.barrier_destroyed.connect(_on_barrier_destroyed)
		entities_layer.add_child(b)
		barriers.append(b)
		# Reserve barrier tile so towers cannot be placed inside barriers
		var bg := map_renderer.world_to_grid(b.position, 1)
		map_renderer.occupied_cells[bg] = true

	# Instantiate Commander near Base barrier (slightly forward along path)
	var cmd_pos := Vector2(460, 144)
	if barriers.size() > 0:
		var base_b := barriers[barriers.size() - 1]
		cmd_pos = base_b.position + Vector2(-42.0, 0.0)
	commander = CommanderEntity.new()
	commander.setup(cmd_pos, enemies)
	commander.moved.connect(func(_c): recalculate_tower_buffs())
	commander.sfx_requested.connect(_play_sfx)
	commander.beam_fx_requested.connect(_spawn_beam_fx)
	commander.shockwave_requested.connect(_spawn_shockwave_fx)
	entities_layer.add_child(commander)

	# Instantiate Harvest Drone & Special Objects (Eggs)
	var drop_pt := Vector2(620, 111)
	var field_pt := Vector2(578, 269)
	for sp in map_cfg.get("special_objects", []):
		var sptype := String(sp.get("type", ""))
		var spos := Vector2(float(sp["x"]), float(sp["y"]))
		if sptype == "ResourceDropPoint":
			drop_pt = spos
		elif sptype == "Harvestable":
			field_pt = spos
		elif sptype == "Egg":
			var eg := map_renderer.world_to_grid(spos, 1)
			map_renderer.occupied_cells[eg] = true
			egg_nodes.append({"pos": spos, "tile": eg, "hp": 120.0, "max_hp": 120.0})

	harvest_drone = HarvestDroneEntity.new()
	harvest_drone.setup(drop_pt, field_pt, barriers)
	harvest_drone.harvest_completed.connect(_on_harvest_completed)
	harvest_drone.barrier_repaired.connect(func(b, amt):
		_spawn_float_text(b.position + Vector2(0, -18), "+%d HP" % int(amt), Color(0.4, 1.0, 0.55))
	)
	entities_layer.add_child(harvest_drone)

	if GameData.campaign_levels.is_empty():
		_set_status("Assets not extracted yet — run: python tools/extract_apk_assets.py")
	else:
		_play_music("InGameMusic_Low")
		_set_status("%s (%s) — %s" % [String(level_cfg.get("title", "Mission")), map_id, String(level_cfg.get("description", ""))])
	_update_hud()
	_refresh_inspector()


func _process(delta: float) -> void:
	if paused or game_over or victory:
		return

	var sim_dt := delta * game_speed
	step_simulation(sim_dt)


func step_simulation(dt: float) -> void:
	if game_over or victory:
		return

	# Passive energy trickle (+1.5 E/sec) and orbital cooldowns
	ship_energy = minf(max_ship_energy, ship_energy + 1.5 * dt)
	for k in orbital_cooldowns.keys():
		if float(orbital_cooldowns[k]) > 0.0:
			orbital_cooldowns[k] = maxf(0.0, float(orbital_cooldowns[k]) - dt)

	# Wave spawning
	if wave_active:
		if _spawn_remaining > 0:
			_spawn_timer -= dt
			if _spawn_timer <= 0.0:
				_spawn_one_enemy()
				_spawn_timer = float(_current_wave_spec.get("interval", 0.42))
		elif enemies.is_empty():
			_on_wave_cleared()
	elif auto_wave and current_wave < total_waves:
		_wave_countdown -= dt
		if _wave_countdown <= 0.0:
			start_next_wave()

	# Update projectiles & VFX
	_update_projectiles(dt)
	_update_vfx(dt)

	# Update tower placement preview on hover
	if pending_tower_id != "":
		var local_pos := world_root.get_local_mouse_position()
		var tdef: Dictionary = GameData.TOWER_DEFS[pending_tower_id]
		var fp := int(tdef["footprint"])
		var tile := map_renderer.world_to_grid(local_pos, fp)
		var valid := map_renderer.can_place_footprint(tile.x, tile.y, fp) and cash >= int(tdef["costs"][0])
		map_renderer.set_placement_preview(true, tile, fp, float(tdef["range"]), valid)
	else:
		map_renderer.set_placement_preview(false, Vector2i(-1, -1), 1, 0.0, false)

	_update_hud()


func start_next_wave() -> void:
	if game_over or victory or wave_active or current_wave >= total_waves:
		return
	var wave_zero_idx := current_wave
	current_wave += 1
	var pat_idx := int(level_cfg.get("wave_pattern_index", 0))
	var dmults: Dictionary = level_cfg.get("difficulty_mults", {"medium": 1.0})
	_current_wave_spec = GameData.get_wave_spawn_spec(pat_idx, wave_zero_idx, current_diff_key, dmults)
	_spawn_remaining = int(_current_wave_spec["count"])
	_spawn_timer = 0.05
	wave_active = true
	map_renderer.set_path_preview(false)

	var etype := int(_current_wave_spec["enemy_type"])
	if etype >= 13:
		_play_music("BossMusic_Low")
		_set_status("WARNING: BOSS WAVE %d/%d — %s!" % [current_wave, total_waves, String(_current_wave_spec["name"])])
	else:
		_play_music("InGameMusic_Low")
		_set_status("Wave %d/%d incoming: %dx %s (HP %.0f)" % [current_wave, total_waves, _spawn_remaining, String(_current_wave_spec["name"]), float(_current_wave_spec["hp"])])
	_play_sfx("Select")
	_update_hud()


func _spawn_one_enemy() -> void:
	var paths: Array = map_cfg.get("enemy_paths", [])
	if paths.is_empty():
		_spawn_remaining = 0
		return

	var chosen_path: Array = paths[0]["waypoints"]
	var is_flying := bool(_current_wave_spec.get("flying", false))
	var matching: Array = []
	for p in paths:
		var pt := String(p.get("enemy_type", "Ground"))
		if (is_flying and pt == "Flying") or (not is_flying and pt != "Flying"):
			matching.append(p)
	if not matching.is_empty():
		var idx := _spawn_remaining % matching.size()
		chosen_path = matching[idx]["waypoints"]

	var enemy := EnemyEntity.new()
	enemy.setup(_current_wave_spec, chosen_path, barriers, commander)
	enemy.died.connect(_on_enemy_died)
	enemy.reached_end.connect(_on_enemy_reached_end)
	entities_layer.add_child(enemy)
	enemies.append(enemy)
	_spawn_remaining -= 1


func _on_enemy_died(enemy: EnemyEntity, killed_by_player: bool) -> void:
	enemies.erase(enemy)
	for p in projectiles:
		if is_instance_valid(p.get("target")) and p["target"] == enemy:
			p["target"] = null
	if killed_by_player:
		cash += enemy.reward
		score += enemy.reward * 10
		_play_sfx(enemy.death_sfx)
		_spawn_explosion_fx(enemy.position, 16.0, Color(0.55, 0.95, 0.45))
		_spawn_float_text(enemy.position + Vector2(0, -10), "+$%d" % enemy.reward, Color(1.0, 0.9, 0.3))


func _on_enemy_reached_end(enemy: EnemyEntity) -> void:
	enemies.erase(enemy)
	for p in projectiles:
		if is_instance_valid(p.get("target")) and p["target"] == enemy:
			p["target"] = null
	# Any enemy escaping past the Base damages the Base directly
	if barriers.size() > 0:
		var base_b := barriers[barriers.size() - 1]
		if is_instance_valid(base_b) and not base_b.destroyed:
			base_b.take_damage(maxf(50.0, enemy.melee_dmg * 25.0))


func _on_barrier_destroyed(b: BarrierEntity) -> void:
	_spawn_explosion_fx(b.position, 42.0, Color(1.0, 0.5, 0.25))
	_play_sfx("Impact_Explosion")
	if b.barrier_type == "Base":
		_trigger_game_over()
	else:
		_set_status("%s breached! Fall back to the Base defense line!" % b.barrier_name)


func _on_wave_cleared() -> void:
	wave_active = false
	# Exact Sentinel 3 interest formula: int((cash / 100.0) * 5.0)
	var interest := int(floor(float(cash) / 100.0 * 5.0))
	var wave_bonus := 10
	cash += interest + wave_bonus
	score += current_wave * 100 + interest * 5
	ship_energy = minf(max_ship_energy, ship_energy + 15.0)
	_wave_countdown = 3.0

	if current_wave >= total_waves:
		_trigger_victory()
		return

	map_renderer.set_path_preview(true)
	_play_sfx("Bleep")
	var msg := "Wave %d cleared! +$%d Bonus +$%d Interest (5%%)" % [current_wave, wave_bonus, interest]
	_set_status(msg)
	if commander != null:
		_spawn_float_text(commander.position + Vector2(0, -28), "+$%d Int" % interest, Color(0.4, 1.0, 0.65))
	_update_hud()


func _trigger_victory() -> void:
	victory = true
	var perfect := true
	for b in barriers:
		if is_instance_valid(b) and b.hp < b.max_hp:
			perfect = false
	_play_sfx("Perfect" if perfect else "Win")
	if _end_overlay:
		_end_title.text = "MISSION ACCOMPLISHED!"
		_end_title.add_theme_color_override("font_color", Color(0.35, 1.0, 0.65))
		_end_body.text = "%s\nFinal Score: %d\nWaves Survived: %d/%d%s" % [
			String(level_cfg.get("title", "")),
			score,
			current_wave,
			total_waves,
			"\nPERFECT DEFENSE!" if perfect else ""
		]
		_end_overlay.visible = true


func _trigger_game_over() -> void:
	if game_over:
		return
	game_over = true
	_play_sfx("GameOver")
	if _end_overlay:
		_end_title.text = "BASE DESTROYED"
		_end_title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		_end_body.text = "The alien swarm overwhelmed your Base on Wave %d/%d.\nFinal Score: %d" % [current_wave, total_waves, score]
		_end_overlay.visible = true


func _on_harvest_completed(cash_amt: int, energy_amt: float) -> void:
	cash += cash_amt
	ship_energy = minf(max_ship_energy, ship_energy + energy_amt)
	if harvest_drone != null:
		_spawn_float_text(harvest_drone.position + Vector2(0, -14), "+$%d +%dE" % [cash_amt, int(energy_amt)], Color(0.35, 0.95, 1.0))


# --- Tower Placement, Selection, Upgrade, Sell & Buffs ---

func try_build_tower_at_grid(tower_id: String, gx: int, gy: int) -> TowerEntity:
	if not GameData.TOWER_DEFS.has(tower_id):
		return null
	var tdef: Dictionary = GameData.TOWER_DEFS[tower_id]
	var cost := int(tdef["costs"][0])
	var fp := int(tdef["footprint"])
	if cash < cost:
		_set_status("Insufficient credits! Need $%d." % cost)
		return null
	if not map_renderer.can_place_footprint(gx, gy, fp):
		_set_status("Cannot build there — path or obstacle!")
		return null

	cash -= cost
	for dy in range(fp):
		for dx in range(fp):
			map_renderer.occupied_cells[Vector2i(gx + dx, gy + dy)] = true

	var t := TowerEntity.new()
	var center := map_renderer.grid_to_world_center(gx, gy, fp)
	t.setup(tower_id, Vector2i(gx, gy), center, enemies)
	t.sfx_requested.connect(_play_sfx)
	t.instant_beam_fx.connect(_spawn_beam_fx)
	t.projectile_requested.connect(_spawn_projectile)
	t.shockwave_fx.connect(_spawn_shockwave_fx)
	entities_layer.add_child(t)
	towers.append(t)

	_play_sfx("Select")
	recalculate_tower_buffs()
	select_tower(t)
	_set_status("Built %s ($%d)." % [String(tdef["name"]), cost])
	return t


func upgrade_tower(t: TowerEntity) -> bool:
	if not is_instance_valid(t) or not t.can_upgrade():
		return false
	var cost := t.get_upgrade_cost()
	if cash < cost:
		_set_status("Need $%d to upgrade %s." % [cost, String(t.def["name"])])
		return false
	cash -= cost
	t.upgrade()
	_play_sfx("Upgrade")
	_spawn_shockwave_fx(t.position, 28.0, Color(0.35, 1.0, 0.75))
	recalculate_tower_buffs()
	_refresh_inspector()
	return true


func sell_tower(t: TowerEntity) -> int:
	if not is_instance_valid(t):
		return 0
	var refund := t.get_sell_price()
	cash += refund
	for dy in range(t.footprint):
		for dx in range(t.footprint):
			map_renderer.occupied_cells.erase(Vector2i(t.grid_pos.x + dx, t.grid_pos.y + dy))
	towers.erase(t)
	if selected_tower == t:
		selected_tower = null
	t.queue_free()
	_play_sfx("Sell")
	_spawn_float_text(t.position, "+$%d" % refund, Color(1.0, 0.85, 0.3))
	recalculate_tower_buffs()
	_refresh_inspector()
	return refund


func recalculate_tower_buffs() -> void:
	for t in towers:
		t.booster_dmg_mult = 0.0
		t.booster_rate_mult = 0.0
		t.booster_range_mult = 0.0
		t.commander_buffed = false
		t.boosted_tower_positions.clear()

	# Booster towers (share pool among nearby offensive towers)
	for b in towers:
		if b.tower_id != "booster":
			continue
		var rng := b.get_effective_range()
		var targets: Array[TowerEntity] = []
		for other in towers:
			if other == b or other.tower_id == "booster":
				continue
			if b.position.distance_to(other.position) <= rng:
				targets.append(other)
		if targets.is_empty():
			continue
		var pool := b.get_booster_pool()
		var share := clampf(pool / float(targets.size()), 0.15 * float(b.level), 1.60)
		var rng_bonus := 0.08 + 0.04 * float(b.level)
		for tgt in targets:
			tgt.booster_dmg_mult += share
			tgt.booster_rate_mult += share * 0.35
			tgt.booster_range_mult = maxf(tgt.booster_range_mult, rng_bonus)
			b.boosted_tower_positions.append(tgt.position)
		b.queue_redraw()

	# Commander Morale Aura
	if is_instance_valid(commander) and commander.is_alive():
		for t in towers:
			if t.tower_id != "booster" and commander.position.distance_to(t.position) <= CommanderEntity.AURA_RANGE:
				t.commander_buffed = true
			t.queue_redraw()


func select_tower(t: TowerEntity) -> void:
	if is_instance_valid(selected_tower):
		selected_tower.selected = false
		selected_tower.queue_redraw()
	selected_tower = t
	if is_instance_valid(selected_tower):
		selected_tower.selected = true
		selected_tower.queue_redraw()
	_refresh_inspector()


# --- Orbital Ship Weapons ---

func cast_orbital(orbital_id: String, world_pos: Vector2) -> bool:
	if not GameData.ORBITAL_DEFS.has(orbital_id):
		return false
	var odef: Dictionary = GameData.ORBITAL_DEFS[orbital_id]
	var cost := float(odef["cost"])
	if float(orbital_cooldowns.get(orbital_id, 0.0)) > 0.0:
		_set_status("%s is recharging!" % String(odef["name"]))
		return false
	if ship_energy < cost:
		_set_status("Need %d Ship Energy!" % int(cost))
		return false

	ship_energy -= cost
	orbital_cooldowns[orbital_id] = float(odef["cooldown"])
	_play_sfx(String(odef["sfx"]))
	var rng := float(odef["radius"])
	var col: Color = odef["color"]

	match orbital_id:
		"orbital_laser":
			_spawn_beam_fx(Vector2(world_pos.x, 0.0), world_pos, col, 18.0, 0.55)
			_spawn_explosion_fx(world_pos, rng * 0.7, col)
			for e in enemies.duplicate():
				if is_instance_valid(e) and not e.is_dead and world_pos.distance_to(e.position) <= rng:
					e.take_damage(float(odef["damage"]), "laser")
		"ion_bomb":
			_spawn_shockwave_fx(world_pos, rng, col)
			_spawn_explosion_fx(world_pos, rng * 0.65, col)
			for e in enemies.duplicate():
				if is_instance_valid(e) and not e.is_dead and world_pos.distance_to(e.position) <= rng:
					e.take_damage(float(odef["damage"]), "explosive")
					e.apply_slow(0.35, 3.0)
		"turret_energizer":
			_spawn_shockwave_fx(world_pos, rng, col)
			for t in towers:
				if world_pos.distance_to(t.position) <= rng:
					t.apply_energizer(float(odef["duration"]))
		"repair_beam":
			_spawn_beam_fx(Vector2(world_pos.x, 0.0), world_pos, col, 10.0, 0.45)
			_spawn_shockwave_fx(world_pos, rng * 0.6, col)
			var best_b: BarrierEntity = null
			var best_d := rng * 1.5
			for b in barriers:
				if is_instance_valid(b):
					var d := world_pos.distance_to(b.position)
					if d <= best_d:
						best_d = d
						best_b = b
			if best_b != null:
				best_b.repair(float(odef["heal"]))
				_spawn_float_text(best_b.position + Vector2(0, -20), "+%d HP" % int(odef["heal"]), col)
			if is_instance_valid(commander) and commander.is_alive() and world_pos.distance_to(commander.position) <= rng:
				commander.hp = minf(commander.max_hp, commander.hp + float(odef["heal"]))

	_set_status("Activated %s!" % String(odef["name"]))
	return true


# --- Projectiles & Visual FX ---

func _spawn_projectile(from_pos: Vector2, target: EnemyEntity, target_pos: Vector2, spec: Dictionary) -> void:
	projectiles.append({
		"pos": from_pos,
		"target": target,
		"target_pos": target_pos,
		"spec": spec,
		"ttl": 4.0,
	})


func _update_projectiles(dt: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		var spec: Dictionary = p["spec"]
		var dest: Vector2 = p["target_pos"]
		var tgt_var: Variant = p.get("target")
		if is_instance_valid(tgt_var):
			var tgt: EnemyEntity = tgt_var as EnemyEntity
			if tgt != null and not tgt.is_dead:
				if bool(spec.get("homing", false)):
					dest = tgt.position
					p["target_pos"] = dest
			else:
				p["target"] = null
		else:
			p["target"] = null

		var ttl: float = float(p.get("ttl", 4.0)) - dt
		p["ttl"] = ttl
		var pos: Vector2 = p["pos"]
		var diff := dest - pos
		var dist := diff.length()
		var spd := float(spec["speed"])
		if spd * dt >= dist or ttl <= 0.0:
			_detonate_projectile(dest, spec)
			projectiles.remove_at(i)
		else:
			p["pos"] = pos + (diff / maxf(0.001, dist)) * spd * dt
	vfx_layer.queue_redraw()


func _detonate_projectile(impact: Vector2, spec: Dictionary) -> void:
	var splash := float(spec["splash"])
	var dmg := float(spec["damage"])
	var dmg_type := String(spec["dmg_type"])
	var dot_dps := float(spec.get("dot_dps", 0.0))
	var dot_dur := float(spec.get("dot_dur", 0.0))
	var col: Color = spec["color"]

	_spawn_explosion_fx(impact, maxf(16.0, splash * 0.55), col)
	if String(spec.get("tower_id", "")) == "artillery":
		_play_sfx("Impact_Explosion")

	for e in enemies.duplicate():
		if not is_instance_valid(e) or e.is_dead:
			continue
		var d := impact.distance_to(e.position)
		if d <= splash:
			var falloff := 1.0 - (d / maxf(1.0, splash)) * 0.45
			e.take_damage(dmg * falloff, dmg_type)
			if dot_dps > 0.0 and is_instance_valid(e) and not e.is_dead:
				e.apply_dot(dot_dps, dot_dur)

	# L4 Bomb Tower Cluster Bomb sub-munitions
	if bool(spec.get("cluster", false)):
		for k in range(4):
			var sub_pos := impact + Vector2.from_angle(float(k) * PI * 0.5 + 0.4) * 26.0
			_spawn_explosion_fx(sub_pos, 18.0, Color(1.0, 0.72, 0.25))
			for e in enemies.duplicate():
				if is_instance_valid(e) and not e.is_dead and sub_pos.distance_to(e.position) <= 28.0:
					e.take_damage(dmg * 0.35, dmg_type)


func _spawn_beam_fx(from_pos: Vector2, to_pos: Vector2, color: Color, width: float, duration: float) -> void:
	beam_fxs.append({"a": from_pos, "b": to_pos, "color": color, "width": width, "t": duration, "max_t": duration})


func _spawn_shockwave_fx(center: Vector2, radius: float, color: Color) -> void:
	shockwave_fxs.append({"pos": center, "radius": radius, "color": color, "t": 0.35, "max_t": 0.35})


func _spawn_explosion_fx(center: Vector2, radius: float, color: Color) -> void:
	explosion_fxs.append({"pos": center, "radius": radius, "color": color, "t": 0.28, "max_t": 0.28})


func _spawn_float_text(pos: Vector2, text: String, color: Color) -> void:
	float_texts.append({"pos": pos, "text": text, "color": color, "t": 1.0, "max_t": 1.0})


func _update_vfx(dt: float) -> void:
	for arr in [beam_fxs, shockwave_fxs, explosion_fxs, float_texts]:
		for i in range(arr.size() - 1, -1, -1):
			arr[i]["t"] = float(arr[i]["t"]) - dt
			if arr == float_texts:
				arr[i]["pos"] = Vector2(arr[i]["pos"]) + Vector2(0, -18.0 * dt)
			if float(arr[i]["t"]) <= 0.0:
				arr.remove_at(i)
	vfx_layer.queue_redraw()


func _draw_vfx() -> void:
	# Alien Eggs (if present on map, e.g., C2Map1)
	for egg in egg_nodes:
		var ep: Vector2 = egg["pos"]
		var tex := GameData.get_atlas_texture("EggMound", 0)
		if tex != null:
			vfx_layer.draw_texture_rect(tex, Rect2(ep - Vector2(18, 18), Vector2(36, 36)), false)
		else:
			vfx_layer.draw_circle(ep, 12.0, Color(0.55, 0.85, 0.35))

	# Projectiles
	for p in projectiles:
		var pos: Vector2 = p["pos"]
		var col: Color = p["spec"]["color"]
		vfx_layer.draw_circle(pos, 4.5, col)
		vfx_layer.draw_circle(pos, 2.2, Color.WHITE)

	# Beams
	for b in beam_fxs:
		var alpha := clampf(float(b["t"]) / float(b["max_t"]), 0.0, 1.0)
		var col: Color = b["color"]
		col.a = alpha
		vfx_layer.draw_line(b["a"], b["b"], col, float(b["width"]))
		vfx_layer.draw_line(b["a"], b["b"], Color(1, 1, 1, alpha * 0.85), maxf(1.0, float(b["width"]) * 0.4))

	# Shockwaves
	for s in shockwave_fxs:
		var prog := 1.0 - clampf(float(s["t"]) / float(s["max_t"]), 0.0, 1.0)
		var col: Color = s["color"]
		col.a = (1.0 - prog) * 0.85
		vfx_layer.draw_arc(s["pos"], float(s["radius"]) * prog, 0.0, TAU, 36, col, 2.5)

	# Explosions
	for ex in explosion_fxs:
		var prog := 1.0 - clampf(float(ex["t"]) / float(ex["max_t"]), 0.0, 1.0)
		var col: Color = ex["color"]
		col.a = (1.0 - prog) * 0.65
		vfx_layer.draw_circle(ex["pos"], float(ex["radius"]) * (0.3 + 0.7 * prog), col)

	# Floating combat/economy text
	var font := ThemeDB.fallback_font
	for ft in float_texts:
		var alpha := clampf(float(ft["t"]) / float(ft["max_t"]), 0.0, 1.0)
		var col: Color = ft["color"]
		col.a = alpha
		vfx_layer.draw_string(font, ft["pos"], String(ft["text"]), HORIZONTAL_ALIGNMENT_CENTER, -1, 11, col)


# --- Input Handling (Mouse + Touch seamlessly via Godot touch emulation) ---

func _input(event: InputEvent) -> void:
	if game_over or victory:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_clear_interaction_modes()
			select_tower(null)
			return

		if mb.button_index == MOUSE_BUTTON_LEFT:
			var world_pos := world_root.get_global_transform().affine_inverse() * mb.position
			var in_map := world_pos.x >= 0.0 and world_pos.y >= 0.0 and world_pos.x < GameData.MAP_WIDTH and world_pos.y < GameData.MAP_HEIGHT

			# Drag-and-drop release builds immediately on valid tile
			if not mb.pressed and dragging_tower and pending_tower_id != "":
				dragging_tower = false
				if in_map:
					var fp := int(GameData.TOWER_DEFS[pending_tower_id]["footprint"])
					var tile := map_renderer.world_to_grid(world_pos, fp)
					if try_build_tower_at_grid(pending_tower_id, tile.x, tile.y) != null:
						pending_tower_id = ""
						_refresh_inspector()
				return

			if mb.pressed and in_map:
				_handle_map_tap(world_pos)

	elif event is InputEventKey and event.pressed:
		var ke := event as InputEventKey
		if ke.keycode == KEY_ESCAPE:
			_clear_interaction_modes()
			select_tower(null)
		elif ke.keycode == KEY_SPACE:
			start_next_wave()


func _handle_map_tap(world_pos: Vector2) -> void:
	# 1. Orbital targeting mode
	if pending_orbital_id != "":
		if cast_orbital(pending_orbital_id, world_pos):
			pending_orbital_id = ""
			_refresh_inspector()
		return

	# 2. Commander move mode
	if commander_move_armed and is_instance_valid(commander):
		commander.order_move(world_pos)
		commander.selected = true
		commander_move_armed = false
		_set_status("Commander moving to target sector.")
		_refresh_inspector()
		return

	# 3. Tap-to-place turret mode
	if pending_tower_id != "":
		var fp := int(GameData.TOWER_DEFS[pending_tower_id]["footprint"])
		var tile := map_renderer.world_to_grid(world_pos, fp)
		if try_build_tower_at_grid(pending_tower_id, tile.x, tile.y) != null:
			pending_tower_id = ""
			_refresh_inspector()
		return

	# 4. Select Commander if tapped directly
	if is_instance_valid(commander) and commander.is_alive() and world_pos.distance_to(commander.position) <= 22.0:
		select_tower(null)
		commander.selected = true
		commander_move_armed = true
		commander.queue_redraw()
		_set_status("Commander selected — tap anywhere on the map to move!")
		_refresh_inspector()
		return

	# 5. Select existing Tower if tapped
	var tapped_tower: TowerEntity = null
	for t in towers:
		var half := float(t.footprint * GameData.TILE_SIZE) * 0.5
		if absf(world_pos.x - t.position.x) <= half and absf(world_pos.y - t.position.y) <= half:
			tapped_tower = t
			break

	if is_instance_valid(commander):
		commander.selected = false
		commander.queue_redraw()
	select_tower(tapped_tower)

	# 6. If tapping an alien Egg mound, allow player manual click damage / feedback
	if tapped_tower == null and egg_nodes.size() > 0:
		for i in range(egg_nodes.size() - 1, -1, -1):
			if world_pos.distance_to(egg_nodes[i]["pos"]) <= 22.0:
				egg_nodes[i]["hp"] = float(egg_nodes[i]["hp"]) - 35.0
				_spawn_explosion_fx(egg_nodes[i]["pos"], 16.0, Color(0.55, 0.95, 0.4))
				if float(egg_nodes[i]["hp"]) <= 0.0:
					map_renderer.occupied_cells.erase(egg_nodes[i]["tile"])
					cash += 25
					_spawn_float_text(egg_nodes[i]["pos"], "+$25 Egg Cleared!", Color(0.5, 1.0, 0.45))
					egg_nodes.remove_at(i)
					_play_sfx("Egg_RelDie")
				return


# --- HUD Action Callbacks ---

func _on_turret_button_down(tid: String) -> void:
	select_tower(null)
	pending_orbital_id = ""
	commander_move_armed = false
	pending_tower_id = tid
	dragging_tower = true
	_refresh_inspector()


func _on_turret_button_pressed(tid: String) -> void:
	dragging_tower = false
	pending_orbital_id = ""
	commander_move_armed = false
	pending_tower_id = tid
	var tdef: Dictionary = GameData.TOWER_DEFS[tid]
	_set_status("Placing %s ($%d) — tap any green tile." % [String(tdef["name"]), int(tdef["costs"][0])])
	_refresh_inspector()


func _arm_commander_move() -> void:
	select_tower(null)
	pending_tower_id = ""
	pending_orbital_id = ""
	commander_move_armed = true
	if is_instance_valid(commander):
		commander.selected = true
		commander.queue_redraw()
	_set_status("Tap anywhere on the battlefield to move Commander.")
	_refresh_inspector()


func _trigger_commander_stomp() -> void:
	if is_instance_valid(commander) and commander.trigger_stomp():
		_set_status("Commander unleashed Shockwave Stomp!")


func _on_drone_mode_toggled(repair_on: bool) -> void:
	if is_instance_valid(harvest_drone):
		harvest_drone.set_repair_mode(repair_on)
	_btn_drone_mode.text = "REPAIRING" if repair_on else "HARVEST"
	_set_status("Drone mode: %s" % ("Repairing damaged barriers" if repair_on else "Harvesting resources (+$5 / +6E)"))


func _arm_orbital(oid: String) -> void:
	var odef: Dictionary = GameData.ORBITAL_DEFS[oid]
	if float(orbital_cooldowns.get(oid, 0.0)) > 0.0:
		_set_status("%s recharging..." % String(odef["name"]))
		return
	if ship_energy < float(odef["cost"]):
		_set_status("Need %d Ship Energy for %s." % [int(odef["cost"]), String(odef["name"])])
		return
	select_tower(null)
	pending_tower_id = ""
	commander_move_armed = false
	pending_orbital_id = oid
	_set_status("Tap target location for %s!" % String(odef["name"]))
	_refresh_inspector()


func _on_upgrade_pressed() -> void:
	if selected_tower != null:
		upgrade_tower(selected_tower)


func _on_sell_pressed() -> void:
	if selected_tower != null:
		sell_tower(selected_tower)


func _clear_interaction_modes() -> void:
	pending_tower_id = ""
	pending_orbital_id = ""
	dragging_tower = false
	commander_move_armed = false
	if is_instance_valid(commander):
		commander.selected = false
		commander.queue_redraw()
	_refresh_inspector()


func _cycle_speed() -> void:
	if game_speed < 1.5:
		game_speed = 2.0
		_btn_speed.text = "2x"
	elif game_speed < 2.5:
		game_speed = 3.0
		_btn_speed.text = "3x"
	else:
		game_speed = 1.0
		_btn_speed.text = "1x"


func _toggle_mute() -> void:
	muted = not muted
	_btn_mute.text = "MUTE" if muted else "SFX"
	if muted:
		_music_player.stop()
	else:
		_play_music(_current_music if _current_music != "" else "InGameMusic_Low")


func _set_status(msg: String) -> void:
	if _lbl_status:
		_lbl_status.text = msg


func _update_hud() -> void:
	if _lbl_wave == null:
		return
	_lbl_wave.text = "WAVE %d/%d" % [current_wave, total_waves]
	_lbl_cash.text = "$%d" % cash
	_lbl_energy.text = "E: %d" % int(ship_energy)
	_lbl_score.text = "SCR %d" % score

	var base_pct := 0
	if barriers.size() > 0:
		var base_b := barriers[barriers.size() - 1]
		if is_instance_valid(base_b):
			base_pct = int(round((base_b.hp / base_b.max_hp) * 100.0))
	_lbl_base_hp.text = "BASE %d%%" % base_pct

	_btn_next_wave.disabled = wave_active or current_wave >= total_waves

	for tid in _tower_buttons.keys():
		var btn: Button = _tower_buttons[tid]
		var cost := int(GameData.TOWER_DEFS[tid]["costs"][0])
		btn.modulate = Color(1.0, 1.0, 1.0) if cash >= cost else Color(0.55, 0.55, 0.62)

	for oid in _orbital_buttons.keys():
		var obtn: Button = _orbital_buttons[oid]
		var odef: Dictionary = GameData.ORBITAL_DEFS[oid]
		var cd := float(orbital_cooldowns.get(oid, 0.0))
		if cd > 0.0:
			obtn.text = "%s (%.0fs)" % [String(odef["short"]), ceilf(cd)]
			obtn.modulate = Color(0.6, 0.6, 0.7)
		else:
			obtn.text = "%s (%dE)" % [String(odef["short"]), int(odef["cost"])]
			obtn.modulate = Color(1.0, 1.0, 1.0) if ship_energy >= float(odef["cost"]) else Color(0.55, 0.55, 0.62)

	if is_instance_valid(commander):
		var scd := commander.get_stomp_cooldown()
		_btn_cmd_stomp.text = "STOMP %.0fs" % ceilf(scd) if scd > 0.0 else "STOMP"
		_btn_cmd_stomp.disabled = scd > 0.0 or not commander.is_alive()


func _refresh_inspector() -> void:
	if _inspector_title == null:
		return
	_btn_upgrade.visible = false
	_btn_sell.visible = false
	_btn_cancel_mode.visible = false

	if is_instance_valid(selected_tower):
		var tdef: Dictionary = selected_tower.def
		_inspector_title.text = "%s (Tier %d/4)" % [String(tdef["name"]), selected_tower.level]
		var buff_pct := int(round((selected_tower.booster_dmg_mult + (0.25 if selected_tower.commander_buffed else 0.0)) * 100.0))
		if selected_tower.tower_id == "booster":
			_inspector_stats.text = "Buff Pool: +%.0f%%\nRange: %.0fpx\nBoosting: %d tower(s)" % [
				selected_tower.get_booster_pool() * 100.0,
				selected_tower.get_effective_range(),
				selected_tower.boosted_tower_positions.size()
			]
		else:
			_inspector_stats.text = "Damage: %.1f (+%d%% buff)\nReload: %.2fs | Range: %.0fpx\n%s" % [
				selected_tower.get_effective_damage(),
				buff_pct,
				selected_tower.get_effective_reload(),
				selected_tower.get_effective_range(),
				String(tdef["desc"])
			]
		if selected_tower.can_upgrade():
			var uc := selected_tower.get_upgrade_cost()
			_btn_upgrade.text = "UPGRADE ($%d)" % uc
			_btn_upgrade.disabled = cash < uc
			_btn_upgrade.visible = true
		_btn_sell.text = "SELL (+$%d)" % selected_tower.get_sell_price()
		_btn_sell.visible = true
	elif pending_tower_id != "":
		var tdef: Dictionary = GameData.TOWER_DEFS[pending_tower_id]
		_inspector_title.text = "Build: %s ($%d)" % [String(tdef["name"]), int(tdef["costs"][0])]
		_inspector_stats.text = "Footprint: %dx%d | Range: %.0fpx\n%s" % [
			int(tdef["footprint"]), int(tdef["footprint"]), float(tdef["range"]), String(tdef["desc"])
		]
		_btn_cancel_mode.visible = true
	elif pending_orbital_id != "":
		var odef: Dictionary = GameData.ORBITAL_DEFS[pending_orbital_id]
		_inspector_title.text = "Target: %s" % String(odef["name"])
		_inspector_stats.text = String(odef["desc"])
		_btn_cancel_mode.visible = true
	elif commander_move_armed:
		_inspector_title.text = "Commander Selected"
		_inspector_stats.text = "Tap the map to reposition Commander. Nearby towers within 96px gain +25% damage & +20% fire rate!"
		_btn_cancel_mode.visible = true
	elif GameData.campaign_levels.is_empty():
		_inspector_title.text = "Assets Required"
		_inspector_stats.text = "Place Sentinel-3-Homeworld-v1-4-2.apk in Downloads or the repo root, then run:\npython tools/extract_apk_assets.py"
	else:
		_inspector_title.text = String(level_cfg.get("title", "Mission Ready"))
		_inspector_stats.text = "End-of-wave gives +5%% Interest on unspent credits.\nTap a turret to place, or press NEXT WAVE!"
