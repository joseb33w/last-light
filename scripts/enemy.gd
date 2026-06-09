class_name Enemy
extends CharacterBody3D
## A skeleton that rises from the dark, lurches toward the camp, and attacks the keeper.
## Slower and easier to kill within the firelight. Juicy hit-flash + blood on every strike.

signal died(at: Vector3)

const GRAVITY := 22.0

# set by the spawner BEFORE add_child:
var variant := "minion"
var fire_ref: Campfire
var max_health := 60.0
var damage := 12.0
var base_speed := 2.3
var tint := Color(1, 1, 1)

enum St { SPAWNING, CHASE, ATTACK, HURT, DYING }

var health := 60.0
var _state: int = St.SPAWNING
var _model: Node3D
var _ap: AnimationPlayer
var _meshes: Array[MeshInstance3D] = []
var _spawn_t := 0.0
var _atk_cd := 0.0
var _atk_t := 0.0
var _did_strike := false
var _hurt_t := 0.0
var _burn_t := 0.0
var _knock := Vector3.ZERO
var _player: Player

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("enemies")

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.6
	col.shape = cap
	col.position = Vector3(0, 0.85, 0)
	add_child(col)

	health = max_health
	var path := "res://models/enemies/kk_Skeleton_Warrior.glb" if variant == "warrior" else "res://models/enemies/kk_Skeleton_Minion.glb"
	_model = load(path).instantiate()
	add_child(_model)
	_model.position.y = -1.05    # rise from the ground on spawn
	if tint != Color(1, 1, 1):
		_apply_tint(tint)
	_ap = _model.find_child("AnimationPlayer", true, false)
	for m: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(m)
	_loopify(["Skeletons_Walking", "Skeletons_Idle"])
	if _ap != null:
		_ap.animation_finished.connect(_on_anim_finished)
		if _ap.has_animation("Skeletons_Spawn_Ground"):
			_ap.play("Skeletons_Spawn_Ground")
		elif _ap.has_animation("Skeletons_Awaken_Standing"):
			_ap.play("Skeletons_Awaken_Standing")

	var ps := get_tree().get_first_node_in_group("player")
	if ps is Player:
		_player = ps

func _apply_tint(c: Color) -> void:
	for m: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		for s in range(maxi(1, m.mesh.get_surface_count())):
			var base := m.get_active_material(s)
			var mat := (base.duplicate() if base != null else StandardMaterial3D.new()) as StandardMaterial3D
			if mat == null:
				continue
			mat.albedo_color = c
			m.set_surface_override_material(s, mat)

func _loopify(names: Array) -> void:
	if _ap == null:
		return
	for n: String in names:
		if _ap.has_animation(n):
			_ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR

func is_dying() -> bool:
	return _state == St.DYING

func take_hit(from_pos: Vector3, dmg: float) -> void:
	if _state == St.DYING:
		return
	var near_fire := _near_fire()
	var mult := 1.6 if near_fire else 1.0
	health -= dmg * mult
	var hit_pos := global_position + Vector3(0, 1.1, 0)
	Impact.burst(get_tree().current_scene, hit_pos, Color(0.7, 0.05, 0.06), 16, 4.5, 0.5)
	Impact.burst(get_tree().current_scene, hit_pos, Color(1.0, 0.9, 0.7), 8, 5.5, 0.3)
	_flash()
	var dir := global_position - from_pos
	dir.y = 0.0
	if dir.length() > 0.05:
		_knock = dir.normalized() * 5.0
	if health <= 0.0:
		_die()
		return
	if _state != St.ATTACK:
		_state = St.HURT
		_hurt_t = 0.0
		if _ap != null and _ap.has_animation("Hit_A"):
			_ap.play("Hit_A", 0.05)

func _flash() -> void:
	for m: MeshInstance3D in _meshes:
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.albedo_color = Color(2.4, 2.0, 2.0)
		m.material_overlay = fm
	var tw := create_tween()
	tw.tween_interval(0.09)
	tw.tween_callback(_clear_flash)

func _clear_flash() -> void:
	for m: MeshInstance3D in _meshes:
		if is_instance_valid(m):
			m.material_overlay = null

func _die() -> void:
	_state = St.DYING
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	if _ap != null and _ap.has_animation("Skeletons_Death"):
		_ap.play("Skeletons_Death", 0.1)
	died.emit(global_position)
	var tw := create_tween()
	tw.tween_interval(1.3)
	tw.tween_property(_model, "position:y", -1.4, 0.9)
	tw.tween_callback(queue_free)

func _on_anim_finished(anim: StringName) -> void:
	if anim == "Skeletons_Spawn_Ground" or anim == "Skeletons_Awaken_Standing":
		if _state == St.SPAWNING:
			_state = St.CHASE
	elif anim == "Hit_A" and _state == St.HURT:
		_state = St.CHASE
	elif anim == "Melee_1H_Attack_Chop" and _state == St.ATTACK:
		_state = St.CHASE

func _near_fire() -> bool:
	if fire_ref == null or not fire_ref.is_lit:
		return false
	return global_position.distance_to(fire_ref.global_position) < Campfire.WARMTH_RADIUS

func _target_pos() -> Vector3:
	if _player != null and not _player.is_dead():
		var dp := _player.global_position.distance_to(global_position)
		if dp < 9.0:
			return _player.global_position
	if fire_ref != null:
		return fire_ref.global_position
	return Vector3.ZERO

func _physics_process(delta: float) -> void:
	if _atk_cd > 0.0:
		_atk_cd -= delta

	# rise-from-ground on spawn
	if _state == St.SPAWNING:
		_spawn_t += delta
		_model.position.y = lerpf(-1.05, 0.0, clampf(_spawn_t / 1.2, 0.0, 1.0))
		if _spawn_t > 1.25:
			_state = St.CHASE
		_apply_gravity(delta)
		move_and_slide()
		return

	if _state == St.DYING:
		velocity = velocity.move_toward(Vector3(0, velocity.y, 0), 12.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		return

	# fire burns the dead that get too close to the flames
	if fire_ref != null and fire_ref.is_lit:
		var fd := global_position.distance_to(fire_ref.global_position)
		if fd < Campfire.SCARE_RADIUS:
			_burn_t += delta
			if _burn_t >= 0.5:
				_burn_t = 0.0
				take_hit(fire_ref.global_position, 10.0)
				return

	var tgt := _target_pos()
	var to := tgt - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector3.ZERO

	var speed := base_speed
	if _near_fire():
		speed *= 0.5
	if _state == St.HURT:
		_hurt_t += delta
		speed *= 0.2
		if _hurt_t > 0.35:
			_state = St.CHASE

	# attack the keeper when in reach
	if _state != St.ATTACK and _player != null and not _player.is_dead():
		var pd := _player.global_position.distance_to(global_position)
		if pd < 2.0 and _atk_cd <= 0.0:
			_begin_attack()

	if _state == St.ATTACK:
		_atk_t += delta
		speed = 0.0
		if not _did_strike and _atk_t >= 0.42:
			_did_strike = true
			_strike()
		if _atk_t >= 1.0:
			_state = St.CHASE

	var hv := dir * speed
	velocity.x = move_toward(velocity.x, hv.x, 10.0 * delta)
	velocity.z = move_toward(velocity.z, hv.z, 10.0 * delta)
	if _knock.length() > 0.05:
		velocity.x += _knock.x
		velocity.z += _knock.z
		_knock = _knock.move_toward(Vector3.ZERO, 18.0 * delta)
	_apply_gravity(delta)
	move_and_slide()

	if dir.length() > 0.05 and _state == St.CHASE:
		var yaw := atan2(dir.x, dir.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, yaw, 9.0 * delta)
		if _ap != null and _ap.has_animation("Skeletons_Walking") and _ap.current_animation != "Skeletons_Walking":
			_ap.play("Skeletons_Walking", 0.15)

func _begin_attack() -> void:
	_state = St.ATTACK
	_atk_t = 0.0
	_did_strike = false
	_atk_cd = 1.6
	if _player != null:
		var to := _player.global_position - global_position
		to.y = 0.0
		if to.length() > 0.1:
			_model.rotation.y = atan2(to.x, to.z)
	if _ap != null and _ap.has_animation("Melee_1H_Attack_Chop"):
		_ap.play("Melee_1H_Attack_Chop", 0.08)

func _strike() -> void:
	if _player == null or _player.is_dead():
		return
	if _player.global_position.distance_to(global_position) < 2.4:
		_player.take_damage(damage)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
