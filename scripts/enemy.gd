class_name Enemy
extends CharacterBody3D
## Wave enemies: melee infected/alien, ranged cyber enforcer, and the reaver boss.
## Chases the player, attacks (melee lunge or plasma bolt), flashes on hit, dies for score.

signal died(score_value: int, at: Vector3)

const KINDS := {
    "infected": {"hp": 70.0, "speed": 4.0, "dmg": 9.0, "score": 100, "scale": 1.0,
        "tint": Color(0.50, 0.62, 0.40), "ranged": false, "range": 1.9, "cd": 1.2, "boss": false},
    "alien": {"hp": 55.0, "speed": 5.3, "dmg": 11.0, "score": 140, "scale": 1.0,
        "tint": Color(0.56, 0.44, 0.72), "ranged": false, "range": 1.9, "cd": 1.0, "boss": false},
    "cyber": {"hp": 115.0, "speed": 3.3, "dmg": 13.0, "score": 200, "scale": 1.05,
        "tint": Color(0.58, 0.66, 0.72), "ranged": true, "range": 13.0, "cd": 1.7, "boss": false},
    "reaver": {"hp": 1700.0, "speed": 3.6, "dmg": 30.0, "score": 3000, "scale": 1.9,
        "tint": Color(0.74, 0.30, 0.28), "ranged": true, "range": 3.4, "cd": 1.4, "boss": true},
}

var kind := "infected"
var target: Node3D = null
var speed_mul := 1.0

var hp := 70.0
var max_hp := 70.0
var dmg := 9.0
var score_value := 100
var move_speed := 4.0
var is_ranged := false
var is_boss := false
var atk_range := 1.9
var atk_cd := 1.2

var _rig: MeshyCharacterRig
var _mats: Array[StandardMaterial3D] = []
var _dead := false
var _atk_timer := 0.0
var _windup := -1.0
var _boss_special := 4.0
var _rng := RandomNumberGenerator.new()

func setup(p_kind: String) -> void:
    kind = p_kind
    var d: Dictionary = KINDS[p_kind]
    max_hp = float(d["hp"])
    hp = max_hp
    move_speed = float(d["speed"])
    dmg = float(d["dmg"])
    score_value = int(d["score"])
    is_ranged = bool(d["ranged"])
    is_boss = bool(d["boss"])
    atk_range = float(d["range"])
    atk_cd = float(d["cd"])

func _ready() -> void:
    _rng.randomize()
    add_to_group("enemy")
    collision_layer = 4         # layer 3 = enemies (player hitscan mask hits this)
    collision_mask = 1          # collide with world only
    var d: Dictionary = KINDS[kind]
    var sc: float = float(d["scale"])
    var cap := CapsuleShape3D.new()
    cap.radius = 0.45 * sc
    cap.height = 1.8 * sc
    var cs := CollisionShape3D.new()
    cs.shape = cap
    cs.position.y = 0.9 * sc
    add_child(cs)
    _build_rig(sc, d["tint"])

func _build_rig(sc: float, tint: Color) -> void:
    _rig = MeshyCharacterRig.new()
    _rig.scale = Vector3(sc, sc, sc)
    add_child(_rig)
    var ch := (load("res://models/%s.glb" % kind) as PackedScene).instantiate() as Node3D
    if kind == "cyber":
        var wp := (load("res://models/armcannon.glb") as PackedScene).instantiate() as Node3D
        _rig.setup(ch, wp, MeshyCharacterRig.ARMCANNON)
    else:
        _rig.setup(ch)
    _rig.play("idle")
    _cache_mats(tint)

func _cache_mats(tint: Color) -> void:
    for mi: MeshInstance3D in _rig.find_children("*", "MeshInstance3D", true, false):
        if mi.mesh == null:
            continue
        for s in range(maxi(1, mi.mesh.get_surface_count())):
            var base: Material = mi.get_active_material(s)
            var m := (base.duplicate() if base != null else StandardMaterial3D.new()) as StandardMaterial3D
            if m == null:
                continue
            m.albedo_color = m.albedo_color.lerp(tint, 0.45)
            mi.set_surface_override_material(s, m)
            _mats.append(m)

func _physics_process(delta: float) -> void:
    if _dead or target == null:
        velocity = Vector3.ZERO
        move_and_slide()
        return
    _atk_timer = maxf(0.0, _atk_timer - delta)
    if is_boss:
        _boss_special = maxf(0.0, _boss_special - delta)
    var to: Vector3 = target.global_position - global_position
    to.y = 0.0
    var dist := to.length()
    var dir := to.normalized() if dist > 0.001 else Vector3.ZERO
    _face(dir)

    var want := Vector3.ZERO
    if is_ranged and not is_boss:
        if dist > atk_range + 2.0:
            want = dir
        elif dist < atk_range - 3.0:
            want = -dir
        else:
            want = dir.cross(Vector3.UP) * (1.0 if int(global_position.x) % 2 == 0 else -1.0) * 0.5
        if dist <= atk_range + 3.0 and _atk_timer <= 0.0:
            _fire_bolt(dir)
            _atk_timer = atk_cd
    else:
        if dist > atk_range * 0.85:
            want = dir
        elif _atk_timer <= 0.0 and _windup < 0.0:
            _windup = 0.0
        if is_boss and _boss_special <= 0.0 and dist < 22.0:
            _boss_slam(dir)
            _boss_special = 5.0

    # melee windup -> strike
    if _windup >= 0.0:
        _windup += delta
        want = Vector3.ZERO
        if _windup >= 0.32:
            _strike(dist, dir)
            _windup = -1.0
            _atk_timer = atk_cd

    var sp := move_speed * speed_mul
    var hv := velocity
    hv.y = 0.0
    hv = hv.move_toward(want * sp, 16.0 * delta)
    velocity.x = hv.x
    velocity.z = hv.z
    velocity.y -= 18.0 * delta
    move_and_slide()
    _anim(hv.length())

func _face(dir: Vector3) -> void:
    if _rig == null or dir.length() < 0.05:
        return
    var yaw := atan2(dir.x, dir.z)
    _rig.rotation.y = lerp_angle(_rig.rotation.y, yaw, 0.18)

func _anim(speed: float) -> void:
    if _rig == null:
        return
    if is_ranged and not is_boss and _atk_timer > atk_cd * 0.6:
        if _rig.current_clip != "aim":
            _rig.aim()
        return
    var clip := "idle"
    if speed > 0.5:
        clip = "run" if speed > 2.6 else "walk"
    if _rig.current_clip != clip:
        _rig.play(clip)

func _strike(dist: float, dir: Vector3) -> void:
    if _dead or target == null:
        return
    if _rig != null:
        var origin := global_position + Vector3(0, 1.1, 0) + dir * 1.0
        _claw(origin)
    if dist <= atk_range + 0.8 and target.has_method("take_damage"):
        target.call("take_damage", dmg)

func _fire_bolt(dir: Vector3) -> void:
    if _rig != null and _rig.current_clip != "aim":
        _rig.aim()
        _rig.weapon_recoil = 1.0
    var bolt := PlasmaBolt.new()
    bolt.dir = dir
    bolt.dmg = dmg
    bolt.speed = 24.0
    bolt.color = Color(1.0, 0.35, 0.85)
    var parent := get_parent()
    if parent == null:
        return
    parent.add_child(bolt)
    var mz := global_position + Vector3(0, 1.4, 0) + dir * 1.2
    if _rig != null and _rig.muzzle != null:
        mz = _rig.muzzle.global_position
    bolt.global_position = mz

func _boss_slam(dir: Vector3) -> void:
    var parent := get_parent()
    if parent == null:
        return
    for off in [-0.35, 0.0, 0.35]:
        var bolt := PlasmaBolt.new()
        bolt.dir = dir.rotated(Vector3.UP, off)
        bolt.dmg = dmg * 0.6
        bolt.speed = 18.0
        bolt.color = Color(1.0, 0.45, 0.25)
        parent.add_child(bolt)
        bolt.global_position = global_position + Vector3(0, 1.6, 0) + dir * 1.5

func take_damage(amount: float, _at := Vector3.ZERO) -> void:
    if _dead:
        return
    hp = maxf(0.0, hp - amount)
    _flash()
    if hp <= 0.0:
        _die()

func _flash() -> void:
    var tw := create_tween()
    tw.tween_method(_set_flash, 2.6, 0.0, 0.16)

func _set_flash(v: float) -> void:
    for m in _mats:
        if m == null:
            continue
        m.emission_enabled = true
        m.emission = Color(1.0, 0.95, 0.85)
        m.emission_energy_multiplier = v

func _die() -> void:
    _dead = true
    collision_layer = 0
    collision_mask = 0
    if _rig != null:
        _rig.play("death")
    emit_signal("died", score_value, global_position)
    var tw := create_tween()
    tw.tween_interval(1.1)
    tw.tween_property(self, "position:y", position.y - 2.2, 1.0)
    tw.tween_callback(func() -> void:
        if is_instance_valid(self): queue_free())

func is_dead() -> bool:
    return _dead

func _claw(pos: Vector3) -> void:
    var p := CPUParticles3D.new()
    p.one_shot = true
    p.emitting = false
    p.amount = 12
    p.lifetime = 0.25
    p.explosiveness = 1.0
    p.spread = 60.0
    p.initial_velocity_min = 2.5
    p.initial_velocity_max = 6.0
    p.mesh = SphereMesh.new()
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.albedo_color = Color(0.9, 0.3, 0.3)
    m.emission_enabled = true
    m.emission = Color(0.9, 0.2, 0.2)
    m.emission_energy_multiplier = 2.5
    p.material_override = m
    var parent := get_parent()
    if parent == null:
        return
    parent.add_child(p)
    p.global_position = pos
    p.emitting = true
    get_tree().create_timer(0.5).timeout.connect(func() -> void:
        if is_instance_valid(p): p.queue_free())
