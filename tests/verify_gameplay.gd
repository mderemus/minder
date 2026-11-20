extends Node
## Automated end-to-end verification suite for Sentinel 3: Homeworld clone.

const PREVIEW_PATH := "user://gameplay_preview.png"

var _failures: Array[String] = []


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append("ASSERT FAILED: " + msg)
		push_error("ASSERT FAILED: " + msg)
	else:
		print("[PASS] " + msg)


func _find_buildable_tile(mr: MapRenderer, footprint: int, near_pos: Vector2 = Vector2.ZERO) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_dist: float = 1e9
	for gy in range(GameData.MAP_ROWS - footprint + 1):
		for gx in range(GameData.MAP_COLS - footprint + 1):
			if mr.can_place_footprint(gx, gy, footprint):
				if near_pos == Vector2.ZERO:
					return Vector2i(gx, gy)
				var c: Vector2 = mr.grid_to_world_center(gx, gy, footprint)
				var d: float = c.distance_to(near_pos)
				if d < best_dist:
					best_dist = d
					best = Vector2i(gx, gy)
	return best


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await get_tree().process_frame
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var gm: GameManager = main_scene.instantiate() as GameManager
	get_tree().root.add_child(gm)
	await get_tree().process_frame

	# 1. Verify Level 1: Touchdown (Map1)
	_assert(gm.level_cfg.get("title", "") == "Touchdown", "Level 1 title is Touchdown")
	_assert(gm.cash == 80, "Starting cash is $80")
	_assert(int(gm.ship_energy) == 100, "Starting ship energy is 100")
	_assert(gm.total_waves == 10, "Total waves is 10")
	_assert(gm.barriers.size() == 2, "Map1 spawns 2 barriers (Normal + Base)")
	_assert(is_instance_valid(gm.commander), "Commander deployed")
	_assert(is_instance_valid(gm.harvest_drone), "Harvest drone deployed")

	# Verify path tile cannot be built on (Map1 wp0 is at x=0, y=81 -> tile (0,2))
	_assert(not gm.map_renderer.can_place_footprint(0, 2, 1), "Path tile (0,2) rejects tower placement")

	# 2. Verify Tower Placement, Upgrades, Buffs, and 80% Sell Refund
	gm.cash = 1000
	var laser_tile: Vector2i = _find_buildable_tile(gm.map_renderer, 1, Vector2(140, 120))
	_assert(laser_tile.x >= 0, "Found valid 1x1 buildable tile for Laser")
	var laser: TowerEntity = gm.try_build_tower_at_grid("laser", laser_tile.x, laser_tile.y)
	_assert(laser != null, "Built Laser tower ($20)")
	_assert(gm.cash == 980, "Cash deducted $20 -> $980")

	var upg_ok: bool = gm.upgrade_tower(laser)
	_assert(upg_ok and laser.level == 2, "Upgraded Laser to Level 2 ($20)")
	_assert(is_equal_approx(laser.get_effective_damage(), 2.0), "Laser L2 base damage is 2.0")

	# Build Booster adjacent to Laser
	var booster_tile: Vector2i = _find_buildable_tile(gm.map_renderer, 1, laser.position + Vector2(32, 0))
	var booster: TowerEntity = gm.try_build_tower_at_grid("booster", booster_tile.x, booster_tile.y)
	_assert(booster != null, "Built Booster tower adjacent to Laser")
	_assert(laser.booster_dmg_mult > 0.0, "Booster buffs adjacent Laser tower damage")

	# Move Commander within 96px of Laser to verify Morale Aura
	gm.commander.position = laser.position + Vector2(20, 0)
	gm.recalculate_tower_buffs()
	_assert(laser.commander_buffed, "Commander Morale Aura buffs nearby Laser tower")

	# Build 2x2 Artillery
	var arty_tile: Vector2i = _find_buildable_tile(gm.map_renderer, 2)
	_assert(arty_tile.x >= 0, "Found valid 2x2 buildable tile for Artillery")
	var arty: TowerEntity = gm.try_build_tower_at_grid("artillery", arty_tile.x, arty_tile.y)
	_assert(arty != null, "Built 2x2 Artillery tower ($100)")

	# Verify 80% sell refund on Laser ($20 + $20 = $40 invested -> $32 refund)
	var cash_before_sell: int = gm.cash
	var refund: int = gm.sell_tower(laser)
	_assert(refund == 32, "Sell refund for $40 invested is $32 (80%)")
	_assert(gm.cash == cash_before_sell + 32, "Cash updated accurately on sell")

	# 3. Reset to clean Level 1 and simulate Wave 1 combat & interest
	gm.load_mission(0, "medium")
	# Place 4 Laser towers ($80 total) near first turn around (160, 120)
	var built_count: int = 0
	for _i in range(4):
		var tpos: Vector2i = _find_buildable_tile(gm.map_renderer, 1, Vector2(160, 120))
		if tpos.x >= 0 and gm.try_build_tower_at_grid("laser", tpos.x, tpos.y) != null:
			built_count += 1
	_assert(built_count == 4, "Built 4 Laser towers with $80 starting cash")
	_assert(gm.cash == 0, "Cash is $0 after spending $80")

	gm.start_next_wave()
	_assert(gm.wave_active and gm.current_wave == 1, "Wave 1 started")

	var captured_preview: bool = false
	var saw_enemy: bool = false
	var cleared_wave: bool = false
	var sim_time: float = 0.0
	var dt: float = 0.05
	while sim_time < 45.0:
		gm.step_simulation(dt)
		for child in gm.entities_layer.get_children():
			if child.has_method("_process"):
				child._process(dt)
		if gm.enemies.size() > 0:
			saw_enemy = true
		if not captured_preview and DisplayServer.get_name() != "headless" and gm.enemies.size() >= 2 and sim_time >= 1.2:
			captured_preview = true
			gm.select_tower(gm.towers[0])
			gm.queue_redraw()
			gm.vfx_layer.queue_redraw()
			await get_tree().process_frame
			await get_tree().process_frame
			var out_path := ProjectSettings.globalize_path(PREVIEW_PATH)
			DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
			var img: Image = get_viewport().get_texture().get_image()
			if img != null:
				img.save_png(out_path)
				print("[INFO] Saved visual preview to ", out_path)
		if saw_enemy and not gm.wave_active:
			cleared_wave = true
			break
		sim_time += dt

	_assert(saw_enemy, "Enemies spawned and marched along EnemyPath")
	_assert(cleared_wave, "Defenses cleared Wave 1 within simulation window (t=%.1fs)" % sim_time)
	_assert(gm.score > 0, "Score increased from enemy kills (%d)" % gm.score)
	_assert(gm.cash > 0, "Earned enemy bounties + wave bonus/interest ($%d)" % gm.cash)

	# 4. Verify Orbital Weapon cast
	gm.ship_energy = 100.0
	var orb_ok: bool = gm.cast_orbital("orbital_laser", Vector2(200, 200))
	_assert(orb_ok and is_equal_approx(gm.ship_energy, 50.0), "Cast Orbital Laser deducted 50 Energy")

	# 5. Regression Test: Missile & Poison projectiles clear cleanly if target enemy dies mid-flight
	gm.load_mission(0, "medium")
	gm.cash = 500
	var p_tile: Vector2i = _find_buildable_tile(gm.map_renderer, 1, Vector2(144, 112))
	var poison_t: TowerEntity = gm.try_build_tower_at_grid("disease", p_tile.x, p_tile.y)
	var m_tile: Vector2i = _find_buildable_tile(gm.map_renderer, 1, Vector2(176, 112))
	var missile_t: TowerEntity = gm.try_build_tower_at_grid("missile", m_tile.x, m_tile.y)
	_assert(poison_t != null and missile_t != null, "Built Poison and Missile towers for mid-flight target death test")

	gm.start_next_wave()
	gm.paused = true
	var spawned_ok: bool = false
	for _tick in range(100):
		gm.step_simulation(0.05)
		for e in gm.enemies:
			if is_instance_valid(e):
				e.hp = 5000.0
				e.max_hp = 5000.0
		for child in gm.entities_layer.get_children():
			if child.has_method("_process"):
				child._process(0.05)
		var has_missile: bool = false
		var has_poison: bool = false
		for proj in gm.projectiles:
			var tid: String = String(proj["spec"].get("tower_id", ""))
			if tid == "missile":
				has_missile = true
			elif tid == "disease":
				has_poison = true
		if has_missile and has_poison and gm.projectiles.size() >= 2:
			spawned_ok = true
			break

	_assert(spawned_ok, "Missile and Poison projectiles launched toward live enemy")
	# Kill and free all active target enemies while projectiles are mid-flight
	for e in gm.enemies.duplicate():
		if is_instance_valid(e):
			e.take_damage(999999.0)
	gm._spawn_remaining = 0
	await get_tree().process_frame
	await get_tree().process_frame

	# Step simulation for 1.5s without newly spawned enemies; all projectiles must clear cleanly
	for _clear_tick in range(30):
		gm.step_simulation(0.05)
	_assert(gm.projectiles.is_empty(), "Missile & Poison projectiles cleared cleanly after target freed mid-flight")
	gm.paused = false

	# 6. Verify 2x2 Artillery & Poison 32-direction sprite mapping & aim-before-fire alignment
	_assert(TowerEntity.get_native_dir_idx(PI) == 0, "32-dir sprite index maps Left (PI) -> 0")
	_assert(TowerEntity.get_native_dir_idx(PI * 0.5) == 8, "32-dir sprite index maps Down (+PI/2) -> 8")
	_assert(TowerEntity.get_native_dir_idx(0.0) == 16, "32-dir sprite index maps Right (0) -> 16")
	_assert(TowerEntity.get_native_dir_idx(-PI * 0.5) == 24, "32-dir sprite index maps Up (-PI/2) -> 24")

	gm.load_mission(0, "medium")
	gm.cash = 1000
	var align_arty_tile: Vector2i = _find_buildable_tile(gm.map_renderer, 2, Vector2(140, 128))
	var align_arty: TowerEntity = gm.try_build_tower_at_grid("artillery", align_arty_tile.x, align_arty_tile.y)
	_assert(align_arty != null, "Built 2x2 Artillery for aim-alignment check")
	align_arty.turret_angle = 0.0 # Initially facing Right (dir 16)
	var align_enemy := EnemyEntity.new()
	var e_spec: Dictionary = GameData.get_wave_spawn_spec(0, 0, "medium", {"medium": 1.0})
	align_enemy.setup(e_spec, [
		{"x": align_arty.position.x - 120.0, "y": align_arty.position.y},
		{"x": align_arty.position.x - 120.0, "y": align_arty.position.y + 40.0}
	], [], null)
	gm.entities_layer.add_child(align_enemy)
	gm.enemies.append(align_enemy)
	align_enemy.position = Vector2(align_arty.position.x - 120.0, align_arty.position.y) # Directly Left (PI)

	# First tick at delta=0.02 should rotate toward PI without firing prematurely while 180 deg off
	align_arty._process(0.02)
	_assert(gm.projectiles.is_empty(), "Artillery rotates before firing when 180 deg misaligned")
	for _rot_tick in range(15):
		align_arty._process(0.05)
	_assert(absf(angle_difference(align_arty.turret_angle, PI)) <= 0.28 and gm.projectiles.size() >= 1,
		"Artillery aligns barrel Left (PI -> frame 0) before launching shell")

	# 7. Verify Campaign 2 Level 1 (C2Map1 - Dark Side)
	gm.load_mission(20, "hard")
	_assert(gm.level_cfg.get("title", "") == "Dark Side", "C2 Level 1 title is Dark Side")
	_assert(gm.total_waves == 30, "C2 Level 1 has 30 waves")
	_assert(gm.barriers.size() == 1, "C2Map1 has 1 Base barrier")
	_assert(gm.egg_nodes.size() == 1, "C2Map1 spawns 1 Alien Egg object")

	if is_instance_valid(gm):
		gm.queue_free()
		await get_tree().process_frame

	if _failures.is_empty():
		print("\nALL_TESTS_PASSED")
		get_tree().quit(0)
	else:
		print("\nTESTS_FAILED: ", _failures.size())
		get_tree().quit(1)
