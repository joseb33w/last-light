class_name Player
extends CharacterBody3D
## Third-person hero: a lone figure who keeps the fire alive. Joystick + keyboard movement,
## camera-relative facing, an axe melee swing with aim-assist + juice, and health.

signal health_changed(cur: float, total: float)
signal died
signal melee_swing
signal melee_landed(count: int)
signal scavenged

const MAX_HEALTH := 100.0
const WALK_SPEED := 3.6
const RUN_SPEED := 6.4
const ACCEL := 14.0
const GRAVITY := 22.0
const ATTACK_RANGE := 2.6
const ATTACK_ARC := 0.32          # dot threshold for the forward cone
const ATTACK_DAMAGE := 34.0
const HIT_DELAY := 0.26           # seconds into the swing when the blade connects
const ATTACK_LEN := 0.72

enum St { IDLE, MOVE, ATTACK, HURT, DEAD }

var health := MAX_HEALTH
var cam_yaw := PI                 # start looking north toward the road
var cam_pitch := 0.32
var _state: int = St.IDLE
var _atk_t := 0.0
var _did_hit := false
var _hurt_t := 0.0
var _shake := 0.0

var _model: Node3D
var _ap: AnimationPlayer
var _cam: Camera3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	add_to_group("player")

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.7
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	_model = load("res://models/chars/kk_Knight.glb").instantiate()
	add_child(_model)
	_ap = _model.find_child("AnimationPlayer", true, false)
	_loopify(["Idle_A", "Walking_C", "Running_A"])
	_attach_gear()

	_cam = Camera3D.new()
	_cam.fov = 66.0
	_cam.current = true
	add_child(_cam)
	_update_camera(0.0, true)

	if _ap != null:
		_ap.animation_finished.connect(_on_anim_finished)
		_ap.play("Idle_A")

func _attach_gear() -> void:
	var skel: Skeleton3D = _model.find_child("Skeleton3D", true, false)
	if skel == null:
		return
	var ra := BoneAttachment3D.new()
	ra.bone_name = "handslot_r"
	skel.add_child(ra)
	var axe_ps := load("res://models/props/axe_A.glb")
	if axe_ps != null:
		ra.add_child(axe_ps.instantiate())
	var la := BoneAttachment3D.new()
	la.bone_name = "handslot_l"
	skel.add_child(la)
	var sh_ps := load("res://models/props/shield_B.glb")
	if sh_ps != null:
		la.add_child(sh_ps.instantiate())

func _loopify(names: Array) -> void:
	if _ap == null:
		return
	for n: String in names:
		if _ap.has_animation(n):
			var a := _ap.get_animation(n)
			a.loop_mode = Animation.LOOP_LINEAR

func _enter_tree() -> void:
	if not G.attack_pressed.is_connected(_on_attack):
		G.attack_pressed.connect(_on_attack)

func _on_attack() -> void:
	_try_attack()

func _try_attack() -> void:
	if _state == St.DEAD or _state == St.ATTACK:
		return
	_state = St.ATTACK
	_atk_t = 0.0
	_did_hit = false
	_aim_assist()
	melee_swing.emit()
	if _ap != null and _ap.has_animation("Melee_1H_Attack_Slice_Diagonal"):
		_ap.play("Melee_1H_Attack_Slice_Diagonal", 0.08)

func _aim_assist() -> void:
	var nearest: Node3D = null
	var best := 4.0
	for e: Node in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D):
			continue
		var en := e as Node3D
		if en.has_method("is_dying") and en.call("is_dying"):
			continue
		var d := en.global_position.distance_to(global_position)
		if d < best:
			best = d
			nearest = en
	if nearest != null:
		var to := nearest.global_position - global_position
		to.y = 0.0
		if to.length() > 0.1:
			_model.rotation.y = atan2(to.x, to.z)

func _do_melee_hit() -> void:
	var fwd := Vector3(sin(_model.rotation.y), 0, cos(_model.rotation.y))
	var hits := 0
	for e: Node in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D):
			continue
		var en := e as Node3D
		if en.has_method("is_dying") and en.call("is_dying"):
			continue
		var to := en.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist > ATTACK_RANGE:
			continue
		if dist > 0.1 and fwd.dot(to.normalized()) < ATTACK_ARC:
			continue
		if en.has_method("take_hit"):
			en.call("take_hit", global_position, ATTACK_DAMAGE)
		hits += 1
	if hits > 0:
		add_shake(0.45)
		melee_landed.emit(hits)

func _on_anim_finished(anim: StringName) -> void:
	if anim == "Melee_1H_Attack_Slice_Diagonal" and _state == St.ATTACK:
		_state = St.IDLE
	elif anim == "Hit_A" and _state == St.HURT:
		_state = St.IDLE

func take_damage(amount: float) -> void:
	if _state == St.DEAD:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, MAX_HEALTH)
	add_shake(0.5)
	if health <= 0.0:
		_die()
		return
	if _state != St.ATTACK:
		_state = St.HURT
		_hurt_t = 0.0
		if _ap != null and _ap.has_animation("Hit_A"):
			_ap.play("Hit_A", 0.06)

func _die() -> void:
	_state = St.DEAD
	velocity = Vector3.ZERO
	if _ap != null and _ap.has_animation("Death_A"):
		_ap.play("Death_A", 0.1)
	died.emit()

func add_shake(amount: float) -> void:
	_shake = minf(1.2, _shake + amount)

func play_scavenge() -> void:
	if _state == St.DEAD:
		return
	scavenged.emit()
	if _ap != null and _ap.has_animation("PickUp") and _state != St.ATTACK:
		_ap.play("PickUp", 0.1)
		_state = St.IDLE

func _input_vector() -> Vector2:
	var kb := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_down", "move_up"))
	var v := kb + G.move_vec
	if v.length() > 1.0:
		v = v.normalized()
	return v

func _physics_process(delta: float) -> void:
	var look := G.consume_look()
	cam_yaw -= look.x * 0.005
	cam_pitch = clampf(cam_pitch - look.y * 0.004, -0.05, 0.75)

	if _state == St.DEAD:
		velocity.x = move_toward(velocity.x, 0, ACCEL * delta)
		velocity.z = move_toward(velocity.z, 0, ACCEL * delta)
		_apply_gravity(delta)
		move_and_slide()
		_update_camera(delta, false)
		return

	if _state == St.ATTACK:
		_atk_t += delta
		if not _did_hit and _atk_t >= HIT_DELAY:
			_did_hit = true
			_do_melee_hit()
		if _atk_t >= ATTACK_LEN:
			_state = St.IDLE
	if _state == St.HURT:
		_hurt_t += delta
		if _hurt_t >= 0.4:
			_state = St.IDLE

	var iv := _input_vector()
	var basis := Basis(Vector3.UP, cam_yaw)
	var wish := basis * Vector3(iv.x, 0, -iv.y)
	var moving := wish.length() > 0.05
	var running := iv.length() > 0.65
	var speed := (RUN_SPEED if running else WALK_SPEED)
	var slow := 1.0
	if _state == St.ATTACK:
		slow = 0.25
	elif _state == St.HURT:
		slow = 0.5
	var target_v := wish.normalized() * speed * slow if moving else Vector3.ZERO
	velocity.x = move_toward(velocity.x, target_v.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target_v.z, ACCEL * delta)
	_apply_gravity(delta)
	move_and_slide()

	if moving and _state != St.ATTACK:
		var yaw := atan2(wish.x, wish.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, yaw, 12.0 * delta)

	_drive_locomotion(delta, moving, running)
	_update_camera(delta, false)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5

func _drive_locomotion(delta: float, moving: bool, running: bool) -> void:
	if _ap == null or _state == St.ATTACK or _state == St.HURT or _state == St.DEAD:
		return
	var horiz := Vector2(velocity.x, velocity.z).length()
	if horiz < 0.4:
		if _ap.current_animation != "Idle_A":
			_ap.play("Idle_A", 0.15)
	elif horiz > WALK_SPEED + 0.6:
		if _ap.current_animation != "Running_A":
			_ap.play("Running_A", 0.15)
	else:
		if _ap.current_animation != "Walking_C":
			_ap.play("Walking_C", 0.15)

func _update_camera(delta: float, instant: bool) -> void:
	var target := global_position + Vector3(0, 1.5, 0)
	var rot := Basis(Vector3.UP, cam_yaw)
	var dist := 6.6
	var off := rot * Vector3(0, 2.4 + cam_pitch * 4.0, dist * (1.0 - cam_pitch * 0.4))
	var desired := target + off
	if instant:
		_cam.global_position = desired
	else:
		_cam.global_position = _cam.global_position.lerp(desired, clampf(10.0 * delta, 0.0, 1.0))
	var look_t := target
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.2)
		var s := _shake * 0.25
		look_t += Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))
	_cam.look_at(look_t, Vector3.UP)

func is_dead() -> bool:
	return _state == St.DEAD
