extends Node3D
## Last Light — orchestrator. Builds the world, runs the dusk->night->dawn cycle, spawns the
## dead as night deepens, handles feeding the fire, and resolves win (survive to dawn) / loss
## (fire goes out, or the keeper falls).

const SURVIVE_TIME := 150.0       # seconds from dusk to dawn
const MAX_ENEMIES := 12
const WOOD_PER_FEED := 1
const FUEL_PER_WOOD := 18.0
const FEED_RANGE := 6.0

var _world: Node3D
var _builder: WorldBuilder
var _fire: Campfire
var _player: Player
var _hud: HUD

var _running := false
var _ended := false
var _elapsed := 0.0
var _wood := 0
var _kills := 0
var _spawn_cd := 3.0
var _phase := "Dusk"
var _low_fire_warned := false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_force_expand()

	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)

	_builder = WorldBuilder.new()
	_builder.build(_world)

	_fire = Campfire.new()
	_fire.name = "Campfire"
	_world.add_child(_fire)
	_fire.global_position = _builder.fire_point
	_fire.went_out.connect(_on_fire_out)

	_player = Player.new()
	_player.name = "Player"
	_world.add_child(_player)
	_player.global_position = _builder.player_start
	_player.died.connect(_on_player_died)

	for p: Vector3 in _builder.pickup_points:
		var wp := WoodPickup.new()
		_world.add_child(wp)
		wp.global_position = p
		wp.collected.connect(_on_wood_collected)

	var layer := CanvasLayer.new()
	layer.name = "HUDLayer"
	add_child(layer)
	_hud = HUD.new()
	_hud.name = "HUD"
	layer.add_child(_hud)
	_hud.show_start()

	G.start_pressed.connect(_on_start)
	G.restart_pressed.connect(_on_restart)
	G.feed_pressed.connect(_on_feed)

	_player.set_physics_process(false)
	_apply_environment(0.0)
	_update_hud()

	if OS.has_feature("web"):
		var hash_str: String = str(JavaScriptBridge.eval("window.location.hash", true))
		if hash_str.contains("nightcheck"):
			_elapsed = SURVIVE_TIME * 0.62
			call_deferred("_on_start")
		elif hash_str.contains("play"):
			call_deferred("_on_start")

func _force_expand() -> void:
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

func _on_start() -> void:
	if _running or _ended:
		return
	_running = true
	_player.set_physics_process(true)
	_hud.show_playing()
	_hud.flash_message("Dusk falls. Keep the fire burning.")

func _on_restart() -> void:
	get_tree().reload_current_scene()

func _on_feed() -> void:
	if not _running or _ended or not _fire.is_lit:
		return
	if _player.global_position.distance_to(_fire.global_position) > FEED_RANGE:
		_hud.flash_message("Get closer to the fire to feed it.")
		return
	if _wood <= 0:
		_hud.flash_message("No wood! Grab the glowing piles.")
		return
	_wood -= WOOD_PER_FEED
	_fire.feed(FUEL_PER_WOOD)
	_player.play_scavenge()
	_hud.flash_message("You feed the fire.")
	_update_hud()

func _on_wood_collected(amount: int) -> void:
	_wood += amount
	_hud.flash_message("Scavenged wood  (+%d)" % amount)
	_update_hud()

func _on_fire_out() -> void:
	if _ended:
		return
	_end(false, "The fire went out. The dark closed in.")

func _on_player_died() -> void:
	if _ended:
		return
	_end(false, "You fell in the dark.")

func _on_enemy_died(_at: Vector3) -> void:
	_kills += 1

func _end(won: bool, reason: String) -> void:
	_ended = true
	_running = false
	var survived := "Survived %s  -  Slain %d" % [_fmt_time(_elapsed), _kills]
	if won:
		_hud.show_win("You held the light for the whole night.  Slain %d" % _kills)
	else:
		_hud.show_over(reason)
		_hud.set_stats(_player.health, Player.MAX_HEALTH, _fire.fuel, Campfire.MAX_FUEL, _wood, _phase, _dawn_ratio(), _kills)

func _physics_process(delta: float) -> void:
	if not _running or _ended:
		return
	_elapsed += delta
	var t := clampf(_elapsed / SURVIVE_TIME, 0.0, 1.0)
	_apply_environment(t)
	_fire.burn_rate = lerpf(1.2, 2.3, _darkness(t))
	_fire.tick(delta)
	_update_phase(t)
	_spawn_logic(delta, t)
	_warn_low_fire()
	_update_hud()
	if _elapsed >= SURVIVE_TIME:
		_end(true, "")

# ---------------------------------------------------------------- day/night
func _darkness(t: float) -> float:
	var night := smoothstep(0.0, 0.5, t)
	var dawn := smoothstep(0.86, 1.0, t)
	return clampf(night - dawn, 0.0, 1.0)

func _apply_environment(t: float) -> void:
	var d := _darkness(t)
	var dawn := smoothstep(0.9, 1.0, t)
	if _builder.sky_mat != null:
		_builder.sky_mat.set_shader_parameter("blend", d)
		_builder.sky_mat.set_shader_parameter("exposure", lerpf(1.0, 0.42, d) + dawn * 0.25)
	if _builder.sun != null:
		_builder.sun.light_energy = lerpf(1.2, 0.1, d) + dawn * 1.0
		var dusk_col := Color(1.0, 0.6, 0.3)
		var moon_col := Color(0.46, 0.58, 0.9)
		_builder.sun.light_color = dusk_col.lerp(moon_col, d).lerp(Color(1.0, 0.7, 0.45), dawn)
		_builder.sun.rotation.x = deg_to_rad(lerpf(-20.0, -6.0, d))
		_builder.sun.rotation.y = deg_to_rad(lerpf(48.0, 120.0, t))
	var env := _builder.world_env.environment
	if env != null:
		env.ambient_light_energy = lerpf(0.85, 0.2, d) + dawn * 0.2
		env.fog_density = lerpf(0.015, 0.032, d)
		env.fog_light_color = Color(0.42, 0.36, 0.32).lerp(Color(0.13, 0.17, 0.27), d)

func _dawn_ratio() -> float:
	return clampf(_elapsed / SURVIVE_TIME, 0.0, 1.0)

func _update_phase(t: float) -> void:
	var p := "Dusk"
	if t >= 0.97:
		p = "Dawn"
	elif t >= 0.85:
		p = "Before Dawn"
	elif t >= 0.5:
		p = "Deep Night"
	elif t >= 0.16:
		p = "Nightfall"
	if p != _phase:
		_phase = p
		match p:
			"Nightfall": _hud.flash_message("Night falls. They are coming.")
			"Deep Night": _hud.flash_message("Deep night. Keep the flames high.")
			"Before Dawn": _hud.flash_message("Dawn is near. Hold the light!")
			"Dawn": _hud.flash_message("The sky is lightening...")

# ---------------------------------------------------------------- spawning
func _spawn_logic(delta: float, t: float) -> void:
	var d := _darkness(t)
	if d < 0.12:
		return
	_spawn_cd -= delta
	if _spawn_cd > 0.0:
		return
	_spawn_cd = lerpf(4.2, 1.1, d)
	var alive := get_tree().get_nodes_in_group("enemies").size()
	if alive >= MAX_ENEMIES:
		return
	_spawn_enemy(d)

func _spawn_enemy(d: float) -> void:
	if _builder.spawn_points.is_empty():
		return
	var origin := _player.global_position
	# prefer a spawn point away from the player so they emerge from the dark fringe
	var pts := _builder.spawn_points
	var best := pts[_rng.randi() % pts.size()]
	for i in range(3):
		var cand: Vector3 = pts[_rng.randi() % pts.size()]
		if cand.distance_to(origin) > best.distance_to(origin):
			best = cand
	var e := Enemy.new()
	if d > 0.55 and _rng.randf() < 0.35:
		e.variant = "warrior"
		e.max_health = 120.0
		e.damage = 16.0
		e.base_speed = 2.0
		e.tint = Color(0.86, 0.84, 0.8)
	else:
		e.variant = "minion"
		e.max_health = 56.0
		e.damage = 11.0
		e.base_speed = 2.5
		e.tint = Color(0.78, 0.82, 0.78).lerp(Color(0.6, 0.7, 0.6), _rng.randf())
	e.fire_ref = _fire
	_world.add_child(e)
	var jitter := Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
	e.global_position = best + jitter
	e.died.connect(_on_enemy_died)

# ---------------------------------------------------------------- hud / misc
func _warn_low_fire() -> void:
	if _fire.fuel_ratio() < 0.22 and _fire.is_lit:
		if not _low_fire_warned:
			_low_fire_warned = true
			_hud.flash_message("The fire is dying! Feed it!")
	else:
		_low_fire_warned = false

func _update_hud() -> void:
	_hud.set_stats(_player.health, Player.MAX_HEALTH, _fire.fuel, Campfire.MAX_FUEL,
		_wood, _phase, _dawn_ratio(), _kills)

func _fmt_time(secs: float) -> String:
	var s := int(secs)
	return "%d:%02d" % [s / 60, s % 60]
