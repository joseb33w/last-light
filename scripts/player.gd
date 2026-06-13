class_name Player
extends CharacterBody3D
## Spec-ops hero: camera-relative movement + sprint, ADS, hitscan firing (recoil + muzzle
## flash + tracer + impact + screen-shake), animated reload, and health — all driven through
## the MeshyCharacterRig. Works with kb+mouse and with HUD-fed touch input.

signal died
signal health_changed(hp: float, max_hp: float)
signal ammo_changed(mag: int, reserve: int)
signal fired(recoil: float)
signal took_hit

const MAX_HP := 120.0
const WALK_SPEED := 3.6
const RUN_SPEED := 6.6
const ADS_SPEED := 2.4
const ACCEL := 14.0
const HIT_RANGE := 90.0

var char_id := "soldier"
var hp := MAX_HP
var mag := 30
var reserve := 150
var damage := 24.0
var rof := 0.11
var auto_fire := true
var spread_deg := 1.4

# HUD-fed touch input
var touch_move := Vector2.ZERO
var touch_fire := false
var touch_aim := false
var input_locked := false        # true on menus/chat

var _rig: MeshyCharacterRig
var _cooldown := 0.0
var _reloading := false
var _reload_t := 0.0
var _dead := false
var _aiming := false
var _was_fire := false
var _rng := RandomNumberGenerator.new()

func setup(p_char: String) -> void:
    char_id = p_char
    var d: Dictionary = G.ROSTER[p_char]
    damage = float(d["damage"])
    rof = float(d["rof"])
    auto_fire = bool(d["auto"])
    mag = int(d["mag"])
    reserve = int(d["reserve"])
    spread_deg = float(d["spread"])
    hp = MAX_HP

func _ready() -> void:
    _rng.randomize()
    collision_layer = 2
    collision_mask = 1
    var cap := CapsuleShape3D.new()
    cap.radius = 0.4
    cap.height = 1.7
    var cs := CollisionShape3D.new()
    cs.shape = cap
    cs.position.y = 0.9
    add_child(cs)
    _build_rig()
    emit_signal("health_changed", hp, MAX_HP)
    emit_signal("ammo_changed", mag, reserve)

func _build_rig() -> void:
    var d: Dictionary = G.ROSTER[char_id]
    _rig = MeshyCharacterRig.new()
    add_child(_rig)
    var ch := (load("res://models/%s.glb" % char_id) as PackedScene).instantiate() as Node3D
    var wpath := "res://models/%s.glb" % String(d["weapon"])
    var wp := (load(wpath) as PackedScene).instantiate() as Node3D
    _rig.setup(ch, wp, G.cfg_dict(char_id))
    _rig.play("idle")

func _physics_process(delta: float) -> void:
    if _dead:
        velocity = Vector3.ZERO
        move_and_slide()
        return
    _cooldown = maxf(0.0, _cooldown - delta)
    if _reloading:
        _reload_t -= delta
        if _reload_t <= 0.0:
            _finish_reload()

    var cam := get_viewport().get_camera_3d()
    var fwd := Vector3(0, 0, -1)
    var right := Vector3(1, 0, 0)
    if cam != null:
        var cb := cam.global_transform.basis
        fwd = -cb.z
        fwd.y = 0.0
        if fwd.length() > 0.001:
            fwd = fwd.normalized()
        right = cb.x
        right.y = 0.0
        if right.length() > 0.001:
            right = right.normalized()

    var iv := Vector2.ZERO
    if not input_locked:
        iv = Input.get_vector("move_left", "move_right", "move_up", "move_down")
        iv += touch_move
    iv = iv.limit_length(1.0)
    var dir := (right * iv.x - fwd * iv.y)
    if dir.length() > 0.001:
        dir = dir.normalized()

    var want_aim := (not input_locked) and (Input.is_action_pressed("aim") or touch_aim or _firing_input())
    _aiming = want_aim
    var sprinting := Input.is_action_pressed("sprint") and not _aiming and iv.length() > 0.1
    var target_speed := ADS_SPEED if _aiming else (RUN_SPEED if sprinting else WALK_SPEED)

    var hv := velocity
    hv.y = 0.0
    hv = hv.move_toward(dir * target_speed, ACCEL * delta)
    velocity.x = hv.x
    velocity.z = hv.z
    velocity.y -= 18.0 * delta
    move_and_slide()
    _clamp_arena()

    _update_facing(fwd, dir)
    _update_anim(hv.length(), sprinting)
    _handle_fire(delta)
    if not input_locked and Input.is_action_just_pressed("reload"):
        start_reload()

func _firing_input() -> bool:
    if input_locked:
        return false
    return Input.is_action_pressed("fire") or touch_fire

func _update_facing(fwd: Vector3, dir: Vector3) -> void:
    if _rig == null:
        return
    var target_yaw := _rig.rotation.y
    if _aiming:
        if fwd.length() > 0.001:
            target_yaw = atan2(fwd.x, fwd.z)
    elif dir.length() > 0.1:
        target_yaw = atan2(dir.x, dir.z)
    _rig.rotation.y = lerp_angle(_rig.rotation.y, target_yaw, 0.35)

func _update_anim(speed: float, sprinting: bool) -> void:
    if _rig == null or _reloading:
        return
    if _aiming:
        if _rig.current_clip != "aim":
            _rig.aim()
        return
    var clip := "idle"
    if speed > 0.4:
        clip = "run" if sprinting or speed > WALK_SPEED + 0.6 else "walk"
    if _rig.current_clip != clip:
        _rig.play(clip)

func _handle_fire(_delta: float) -> void:
    var pressed := _firing_input()
    var do_fire := false
    if pressed and _cooldown <= 0.0 and not _reloading:
        if auto_fire:
            do_fire = true
        elif not _was_fire:
            do_fire = true
    _was_fire = pressed
    if not do_fire:
        return
    if mag <= 0:
        start_reload()
        return
    _shoot()

func _shoot() -> void:
    mag -= 1
    _cooldown = rof
    emit_signal("ammo_changed", mag, reserve)
    if _rig != null and _rig.current_clip != "aim":
        _rig.aim()
    if _rig != null:
        _rig.weapon_recoil = 1.0
    emit_signal("fired", 1.0)

    var cam := get_viewport().get_camera_3d()
    var origin := global_position + Vector3(0, 1.5, 0)
    var aim_dir := Vector3(0, 0, -1)
    if cam != null:
        origin = cam.global_position
        aim_dir = -cam.global_transform.basis.z
    # apply spread
    var sp := deg_to_rad(spread_deg)
    aim_dir = aim_dir.rotated(Vector3.UP, _rng.randf_range(-sp, sp))
    aim_dir = aim_dir.rotated(cam.global_transform.basis.x if cam != null else Vector3.RIGHT, _rng.randf_range(-sp, sp))
    aim_dir = aim_dir.normalized()

    var muzzle_pos := origin + aim_dir * 1.0
    if _rig != null and _rig.muzzle != null:
        muzzle_pos = _rig.muzzle.global_position
    _muzzle_flash(muzzle_pos)

    var hit_point := origin + aim_dir * HIT_RANGE
    var space := get_world_3d().direct_space_state
    var q := PhysicsRayQueryParameters3D.create(origin, origin + aim_dir * HIT_RANGE)
    q.collision_mask = 1 | 4    # world + enemies
    q.exclude = [get_rid()]
    q.collide_with_areas = false
    var res := space.intersect_ray(q)
    if not res.is_empty():
        hit_point = res["position"]
        var col: Object = res["collider"]
        if col != null and col.is_in_group("enemy") and col.has_method("take_damage"):
            col.call("take_damage", damage, hit_point)
            _impact(hit_point, true)
        else:
            _impact(hit_point, false)
    _tracer(muzzle_pos, hit_point)

func start_reload() -> void:
    if _reloading or _dead or mag >= int(G.ROSTER[char_id]["mag"]) or reserve <= 0:
        return
    _reloading = true
    _reload_t = MeshyCharacterRig.RELOAD_DUR
    if _rig != null:
        _rig.reload()

func _finish_reload() -> void:
    _reloading = false
    var cap := int(G.ROSTER[char_id]["mag"])
    var need := cap - mag
    var take := mini(need, reserve)
    mag += take
    reserve -= take
    emit_signal("ammo_changed", mag, reserve)
    if _rig != null and not _aiming:
        _rig.play("idle")

func take_damage(amount: float) -> void:
    if _dead:
        return
    hp = maxf(0.0, hp - amount)
    emit_signal("health_changed", hp, MAX_HP)
    emit_signal("took_hit")
    if _rig != null and _rig.current_clip not in ["fire", "aim", "reload"]:
        _rig.play("hit")
    if hp <= 0.0:
        _die()

func _die() -> void:
    _dead = true
    if _rig != null:
        _rig.play("death")
    emit_signal("died")

func is_dead() -> bool:
    return _dead

func is_reloading() -> bool:
    return _reloading

func get_rig() -> MeshyCharacterRig:
    return _rig

func _clamp_arena() -> void:
    var r := 21.0
    var flat := Vector2(global_position.x, global_position.z)
    if flat.length() > r:
        flat = flat.normalized() * r
        global_position.x = flat.x
        global_position.z = flat.y
    if global_position.y < 0.0:
        global_position.y = 0.0

# ── fx ──
func _muzzle_flash(pos: Vector3) -> void:
    var p := CPUParticles3D.new()
    p.one_shot = true
    p.emitting = false
    p.amount = 12
    p.lifetime = 0.12
    p.explosiveness = 1.0
    p.spread = 40.0
    p.initial_velocity_min = 3.0
    p.initial_velocity_max = 7.0
    p.scale_amount_min = 0.07
    p.scale_amount_max = 0.18
    p.mesh = SphereMesh.new()
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.albedo_color = Color(1.0, 0.85, 0.45)
    m.emission_enabled = true
    m.emission = Color(1.0, 0.8, 0.4)
    m.emission_energy_multiplier = 4.0
    p.material_override = m
    get_parent().add_child(p)
    p.global_position = pos
    p.emitting = true
    get_tree().create_timer(0.4).timeout.connect(func() -> void:
        if is_instance_valid(p): p.queue_free())

func _tracer(from: Vector3, to: Vector3) -> void:
    var t := MeshInstance3D.new()
    var im := ImmediateMesh.new()
    t.mesh = im
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.emission_enabled = true
    var tc := Color(1.0, 0.82, 0.4)
    if char_id == "specter":
        tc = Color(0.4, 1.0, 0.95)
    m.albedo_color = tc
    m.emission = tc
    m.emission_energy_multiplier = 5.0
    im.surface_begin(Mesh.PRIMITIVE_LINES, m)
    im.surface_add_vertex(from)
    im.surface_add_vertex(to)
    im.surface_end()
    get_parent().add_child(t)
    var tw := t.create_tween()
    tw.tween_property(t, "transparency", 1.0, 0.12)
    tw.tween_callback(func() -> void:
        if is_instance_valid(t): t.queue_free())

func _impact(pos: Vector3, on_enemy: bool) -> void:
    var p := CPUParticles3D.new()
    p.one_shot = true
    p.emitting = false
    p.amount = 14
    p.lifetime = 0.35
    p.explosiveness = 0.9
    p.spread = 70.0
    p.initial_velocity_min = 2.0
    p.initial_velocity_max = 6.0
    p.gravity = Vector3(0, -6, 0)
    p.scale_amount_min = 0.05
    p.scale_amount_max = 0.14
    p.mesh = SphereMesh.new()
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.emission_enabled = true
    var c := Color(1.0, 0.4, 0.25) if on_enemy else Color(0.9, 0.85, 0.7)
    m.albedo_color = c
    m.emission = c
    m.emission_energy_multiplier = 3.0
    p.material_override = m
    get_parent().add_child(p)
    p.global_position = pos
    p.emitting = true
    get_tree().create_timer(0.7).timeout.connect(func() -> void:
        if is_instance_valid(p): p.queue_free())
