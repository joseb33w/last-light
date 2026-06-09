class_name WoodPickup
extends Area3D
## A glowing spot where firewood can be scavenged. Walk into it to grab wood; it depletes,
## then a fresh bundle fades back in after a short while.

signal collected(amount: int)

const RESPAWN := 9.0

var available := true
var _amount := 2
var _logs: Node3D
var _ring: MeshInstance3D
var _glow: OmniLight3D
var _t := 0.0

func _ready() -> void:
	collision_layer = 8
	collision_mask = 2          # detect the player (layer 2)
	monitoring = true
	add_to_group("pickups")

	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.5
	col.shape = sph
	col.position = Vector3(0, 0.6, 0)
	add_child(col)

	var logs_ps := load("res://models/dressing/campfire_logs.glb")
	if logs_ps != null:
		_logs = logs_ps.instantiate()
		add_child(_logs)
		_logs.scale = Vector3.ONE * 0.9
		_logs.position.y = 0.05

	# emissive glowing ring on the ground
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.7
	torus.outer_radius = 0.95
	_ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.emission_enabled = true
	rm.albedo_color = Color(1.0, 0.78, 0.34)
	rm.emission = Color(1.0, 0.7, 0.28)
	rm.emission_energy_multiplier = 3.0
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color.a = 0.85
	_ring.material_override = rm
	_ring.position = Vector3(0, 0.06, 0)
	add_child(_ring)

	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.74, 0.3)
	_glow.light_energy = 1.6
	_glow.omni_range = 4.5
	_glow.position = Vector3(0, 0.8, 0)
	add_child(_glow)

	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not available:
		return
	if body is Player:
		_collect(body)

func _collect(p: Player) -> void:
	available = false
	collected.emit(_amount)
	p.play_scavenge()
	Impact.burst(get_tree().current_scene, global_position + Vector3(0, 0.6, 0), Color(1.0, 0.75, 0.3), 12, 3.0, 0.5)
	_set_visible(false)
	var t := get_tree().create_timer(RESPAWN)
	t.timeout.connect(_respawn)

func _respawn() -> void:
	if not is_inside_tree():
		return
	available = true
	_amount = 2
	_set_visible(true)

func _set_visible(v: bool) -> void:
	if _logs != null:
		_logs.visible = v
	_ring.visible = v
	_glow.visible = v

func _process(delta: float) -> void:
	_t += delta
	if _ring.visible:
		_ring.rotation.y += delta * 1.2
		var pulse := 2.4 + 1.4 * sin(_t * 3.0)
		var rm := _ring.material_override as StandardMaterial3D
		if rm != null:
			rm.emission_energy_multiplier = pulse
		_glow.light_energy = 1.2 + 0.5 * sin(_t * 3.0)
	if _logs != null and _logs.visible:
		_logs.position.y = 0.05 + 0.05 * sin(_t * 2.0)
