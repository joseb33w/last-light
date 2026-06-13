extends Node3D
## Outpost Vostok orchestrator: builds the station, runs the title/character-select, the
## wave-survival loop (with the wave-8 reaver boss), the third-person collision-clamped
## follow camera, kb+mouse and touch input routing, scoring, the quartermaster chat, and the
## game-over + Supabase top-10 leaderboard.

enum { TITLE, PLAYING, INTERMISSION, GAMEOVER }

const CAM_DIST := 5.2
const CAM_DIST_ADS := 3.4
const SPAWN_CAP := 9
const MOUSE_SENS := 0.0028
const TOUCH_SENS := 0.006

var _state := TITLE
var _world: Node3D
var _builder: WorldBuilder
var _player: Player
var _hud: HUD
var _npc: Quartermaster
var _camera: Camera3D

var _wave := 1
var _score := 0
var _alive: Array = []
var _spawn_queue: Array = []
var _spawn_timer := 0.0
var _boss_active := false

var _cam_yaw := 0.0
var _cam_pitch := -0.18
var _cam_dist := CAM_DIST
var _shake := 0.0
var _lb_polling := false
var _lb_deadline := 0.0
var auto_waves := true            # tests set false to drive controlled scenarios
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
    _rng.randomize()
    _force_expand()
    _world = Node3D.new()
    _world.name = "World"
    add_child(_world)
    _builder = WorldBuilder.new()
    _builder.build(_world)

    _npc = Quartermaster.new()
    _world.add_child(_npc)
    _npc.position = _builder.npc_point
    _npc.range_changed.connect(_on_npc_range)

    _camera = Camera3D.new()
    _camera.fov = 70.0
    _camera.current = true
    add_child(_camera)
    _camera.global_position = Vector3(0, 6, 18)

    var layer := CanvasLayer.new()
    layer.name = "HUDLayer"
    add_child(layer)
    _hud = HUD.new()
    _hud.set_persona(Quartermaster.PERSONA)
    layer.add_child(_hud)
    _hud.start_pressed.connect(_on_start)
    _hud.next_wave_pressed.connect(_on_next_wave)
    _hud.retry_pressed.connect(_on_retry)
    _hud.interact_pressed.connect(_toggle_chat)
    _hud.chat_close_pressed.connect(_close_chat)
    _hud.char_selected.connect(func(c: String) -> void: G.selected_char = c)

    _hud.show_title()
    _deep_link()

func _deep_link() -> void:
    # allow the verifier to jump straight into gameplay: #play or #play=specter
    if not OS.has_feature("web"):
        return
    var h: String = str(JavaScriptBridge.eval("location.hash || ''", true))
    if h.begins_with("#play"):
        var c := "soldier"
        var parts := h.split("=")
        if parts.size() > 1 and G.ROSTER.has(parts[1]):
            c = parts[1]
        call_deferred("begin_game", c)

# ════════════════════════════ STATE TRANSITIONS ════════════════════════════
func _on_start() -> void:
    begin_game(G.selected_char)

func begin_game(char_id: String) -> void:
    if _player != null and is_instance_valid(_player):
        _player.queue_free()
    G.selected_char = char_id
    _score = 0
    _wave = 1
    _boss_active = false
    _clear_enemies()
    _player = Player.new()
    _player.add_to_group("player")
    _player.setup(char_id)
    _world.add_child(_player)
    _player.global_position = _builder.player_start
    _player.health_changed.connect(func(hp: float, mx: float) -> void: _hud.set_health(hp, mx))
    _player.ammo_changed.connect(func(m: int, r: int) -> void: _hud.set_ammo(m, r))
    _player.fired.connect(func(_r: float) -> void: _shake = maxf(_shake, 0.18))
    _player.took_hit.connect(_on_player_hit)
    _player.died.connect(_on_player_died)
    _cam_yaw = PI
    _cam_pitch = -0.18
    _hud.set_char_name(char_id)
    _hud.set_score(0)
    _hud.show_playing()
    _state = PLAYING
    _capture_mouse(true)
    _start_wave(1)

func _start_wave(w: int) -> void:
    _wave = w
    _hud.set_wave(w)
    _spawn_queue = _compose(w)
    _spawn_timer = 0.6
    if w % 8 == 0:
        _boss_active = true
        _hud.banner("WAVE %d  -  THE REAVER" % w, Color(0.95, 0.3, 0.25))
    else:
        _hud.banner("WAVE %d" % w, Color(1.0, 0.62, 0.25))
    _state = PLAYING

func _compose(w: int) -> Array:
    var list: Array = []
    if w % 8 == 0:
        list.append("reaver")
        for i in (3 + int(w / 8.0)):
            list.append("infected")
        for i in 2:
            list.append("cyber")
    else:
        var base := 3 + w
        for i in base:
            var r := _rng.randf()
            if w >= 4 and r < 0.22:
                list.append("cyber")
            elif w >= 3 and r < 0.52:
                list.append("alien")
            else:
                list.append("infected")
    return list

func _on_next_wave() -> void:
    if _state != INTERMISSION:
        return
    _refill_player()
    _hud.show_playing()
    _capture_mouse(true)
    _start_wave(_wave + 1)

func _refill_player() -> void:
    if _player == null or not is_instance_valid(_player):
        return
    var d: Dictionary = G.ROSTER[_player.char_id]
    _player.mag = int(d["mag"])
    _player.reserve = int(d["reserve"])
    _player.emit_signal("ammo_changed", _player.mag, _player.reserve)

func _on_wave_cleared() -> void:
    if _boss_active:
        _boss_active = false
    _state = INTERMISSION
    _capture_mouse(false)
    _score += _wave * 60
    _hud.set_score(_score)
    _hud.show_intermission(_wave)

func _on_player_died() -> void:
    if _state == GAMEOVER:
        return
    _state = GAMEOVER
    G.last_score = _score
    G.last_wave = _wave
    _capture_mouse(false)
    _hud.show_gameover(_score, _wave)
    _hud.set_top10([])
    G.lb_submit(_score, _wave, _player.char_id if _player != null else "soldier")
    await get_tree().create_timer(0.8).timeout
    G.lb_fetch_top()
    _lb_polling = true
    _lb_deadline = 6.0

func _on_retry() -> void:
    _clear_enemies()
    if _player != null and is_instance_valid(_player):
        _player.queue_free()
        _player = null
    _state = TITLE
    _capture_mouse(false)
    _hud.show_title()

# ════════════════════════════ NPC CHAT ════════════════════════════
func _on_npc_range(in_range: bool) -> void:
    if _state in [PLAYING, INTERMISSION]:
        _hud.show_talk_prompt(in_range)

func _toggle_chat() -> void:
    if _hud.is_chat_open():
        _close_chat()
    elif _npc != null and _npc.in_range() and _state in [PLAYING, INTERMISSION]:
        _open_chat()

func _open_chat() -> void:
    _hud.open_chat()
    if _player != null and is_instance_valid(_player):
        _player.input_locked = true
    _capture_mouse(false)

func _close_chat() -> void:
    _hud.close_chat()
    if _player != null and is_instance_valid(_player):
        _player.input_locked = false
    if _state == PLAYING:
        _capture_mouse(true)

# ════════════════════════════ INPUT ════════════════════════════
func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and _state == PLAYING and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        var mm := event as InputEventMouseMotion
        _cam_yaw -= mm.relative.x * MOUSE_SENS
        _cam_pitch = clampf(_cam_pitch - mm.relative.y * MOUSE_SENS, -1.2, 0.55)
    elif event is InputEventKey:
        var k := event as InputEventKey
        if k.pressed and k.physical_keycode == KEY_ESCAPE:
            if _hud.is_chat_open():
                _close_chat()
            elif _state == PLAYING:
                _capture_mouse(false)
    if event.is_action_pressed("interact") and _state in [PLAYING, INTERMISSION]:
        _toggle_chat()

func _capture_mouse(on: bool) -> void:
    if DisplayServer.is_touchscreen_available():
        return
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

# ════════════════════════════ FRAME LOOP ════════════════════════════
func _process(delta: float) -> void:
    _update_camera(delta)
    _poll_leaderboard(delta)
    if _npc != null:
        _npc.idle_pose()
    if _state != PLAYING:
        if _player != null and is_instance_valid(_player) and _state == INTERMISSION:
            _feed_input()
        return
    _feed_input()
    _update_waves(delta)

func _feed_input() -> void:
    if _player == null or not is_instance_valid(_player):
        return
    _player.touch_move = _hud.move_vector
    _player.touch_fire = _hud.fire_held
    _player.touch_aim = _hud.aim_held
    var ld := _hud.consume_look()
    if ld != Vector2.ZERO:
        _cam_yaw -= ld.x * TOUCH_SENS
        _cam_pitch = clampf(_cam_pitch - ld.y * TOUCH_SENS, -1.2, 0.55)

func _update_camera(delta: float) -> void:
    if _player == null or not is_instance_valid(_player):
        return
    var aiming := _hud.aim_held or _hud.fire_held or Input.is_action_pressed("aim") or Input.is_action_pressed("fire")
    var target_dist := CAM_DIST_ADS if aiming else CAM_DIST
    _cam_dist = lerpf(_cam_dist, target_dist, 8.0 * delta)
    _camera.fov = lerpf(_camera.fov, 55.0 if aiming else 70.0, 8.0 * delta)
    var look := Basis.from_euler(Vector3(_cam_pitch, _cam_yaw, 0))
    var forward := -look.z
    var pivot := _player.global_position + Vector3(0, 1.65, 0) + look.x * 0.5
    var desired := pivot - forward * _cam_dist
    # collision clamp against world
    var space := get_world_3d().direct_space_state
    var q := PhysicsRayQueryParameters3D.create(pivot, desired)
    q.collision_mask = 1
    var hit := space.intersect_ray(q)
    if not hit.is_empty():
        desired = (hit["position"] as Vector3) + forward * 0.3
    if _shake > 0.001:
        _shake = maxf(0.0, _shake - delta * 1.2)
        desired += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake * 0.25
    _camera.global_position = _camera.global_position.lerp(desired, clampf(18.0 * delta, 0.0, 1.0))
    _camera.look_at(pivot + forward * 3.0, Vector3.UP)

func _update_waves(delta: float) -> void:
    if not auto_waves:
        return
    var mul := minf(1.0 + 0.03 * _wave, 1.45)
    if not _spawn_queue.is_empty():
        _spawn_timer -= delta
        if _spawn_timer <= 0.0 and _alive.size() < SPAWN_CAP:
            var kind: String = _spawn_queue.pop_front()
            _spawn_enemy(kind, mul)
            _spawn_timer = 0.7 if kind != "reaver" else 0.0
    elif _alive.is_empty():
        _on_wave_cleared()

func _spawn_enemy(kind: String, mul: float) -> void:
    var e := Enemy.new()
    e.setup(kind)
    e.speed_mul = mul
    e.target = _player
    _world.add_child(e)
    var pts := _builder.spawn_points
    var p: Vector3 = pts[_rng.randi() % pts.size()] if pts.size() > 0 else Vector3(0, 0.1, -18)
    if kind == "reaver":
        p = Vector3(0, 0.1, -19)
    e.global_position = p
    e.died.connect(_on_enemy_died)
    _alive.append(e)

func _on_enemy_died(value: int, at: Vector3) -> void:
    _score += value
    _hud.set_score(_score)
    for i in range(_alive.size() - 1, -1, -1):
        if not is_instance_valid(_alive[i]) or (_alive[i] as Enemy).is_dead():
            _alive.remove_at(i)

func _clear_enemies() -> void:
    for e in _alive:
        if is_instance_valid(e):
            e.queue_free()
    _alive.clear()
    _spawn_queue.clear()

func _on_player_hit() -> void:
    _hud.flash_damage()
    _shake = maxf(_shake, 0.35)

func _poll_leaderboard(delta: float) -> void:
    if not _lb_polling:
        return
    _lb_deadline -= delta
    var st := G.lb_top_state()
    if st != "" and st != "pending" and st != "error" and st != "nonweb":
        _hud.set_top10(G.lb_parse_top(st))
        _lb_polling = false
    elif _lb_deadline <= 0.0:
        _lb_polling = false

func _force_expand() -> void:
    var w := get_window()
    w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
    w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

# ════════════════════════════ TEST HOOKS ════════════════════════════
func get_player() -> Player:
    return _player

func get_hud() -> HUD:
    return _hud

func get_world() -> Node3D:
    return _world

func get_npc() -> Quartermaster:
    return _npc

func get_camera() -> Camera3D:
    return _camera

func get_environment_sky_material() -> Material:
    for c in _world.get_children():
        if c is WorldEnvironment:
            var env := (c as WorldEnvironment).environment
            if env != null and env.sky != null:
                return env.sky.sky_material
    return null

func spawn_test_enemy(kind: String, pos: Vector3) -> Enemy:
    var e := Enemy.new()
    e.setup(kind)
    e.target = _player
    _world.add_child(e)
    e.global_position = pos
    e.died.connect(_on_enemy_died)
    _alive.append(e)
    return e

func alive_count() -> int:
    return _alive.size()
