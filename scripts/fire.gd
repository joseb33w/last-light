class_name Campfire
extends Node3D
## The last light. Burns fuel over time; the player feeds it scavenged wood. Throws warm,
## flickering light + embers, and weakens/repels the dead within its glow. Goes out at fuel 0.

signal went_out

const MAX_FUEL := 100.0
const WARMTH_RADIUS := 7.5      # enemies inside are slower + take more damage
const SCARE_RADIUS := 3.0       # enemies that get this close start to burn/flee

var fuel := 62.0
var burn_rate := 1.6            # fuel/sec, raised at night by Main
var is_lit := true

var _light: OmniLight3D
var _flame: CPUParticles3D
var _embers: CPUParticles3D
var _smoke: CPUParticles3D
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _glow_qm: QuadMesh
var _base_energy := 3.4
var _t := 0.0
var _soft: ImageTexture

static func make_soft_tex() -> ImageTexture:
	var n := 48
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := float(n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var d := Vector2(x - c, y - c).length() / c
			var v := clampf(1.0 - d, 0.0, 1.0)
			v = v * v
			img.set_pixel(x, y, Color(v, v, v, v))
	return ImageTexture.create_from_image(img)

func _ready() -> void:
	_soft = make_soft_tex()
	var model_ps := load("res://models/props/ms_campfire.glb")
	if model_ps != null:
		var model: Node3D = model_ps.instantiate()
		add_child(model)
		model.scale = Vector3.ONE

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.light_energy = _base_energy
	_light.omni_range = 18.0
	_light.omni_attenuation = 1.7
	_light.shadow_enabled = true
	_light.position = Vector3(0, 1.1, 0)
	add_child(_light)

	_flame = _make_particles(20, 0.6, 1.8, 0.32,
		Color(0.95, 0.62, 0.26, 1.0), Color(0.9, 0.26, 0.06, 0.0),
		Vector3(0, 3.0, 0), 0.5, 0.34)
	_flame.position = Vector3(0, 0.35, 0)
	add_child(_flame)

	_embers = _make_particles(16, 1.5, 2.4, 0.06,
		Color(1.0, 0.74, 0.28, 1.0), Color(1.0, 0.4, 0.1, 0.0),
		Vector3(0, 1.6, 0), 0.9, 0.1)
	_embers.position = Vector3(0, 0.5, 0)
	add_child(_embers)

	_smoke = _make_particles(10, 2.2, 1.2, 0.4,
		Color(0.16, 0.15, 0.14, 0.45), Color(0.1, 0.1, 0.1, 0.0),
		Vector3(0, 1.2, 0), 0.7, 0.5)
	_smoke.position = Vector3(0, 1.0, 0)
	_smoke.emitting = false
	add_child(_smoke)

	# Fake-bloom additive glow billboard behind the flame.
	_glow = MeshInstance3D.new()
	_glow_qm = QuadMesh.new()
	_glow_qm.size = Vector2(2.4, 2.4)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glow_mat.albedo_color = Color(1.0, 0.5, 0.18, 1.0)
	_glow_mat.albedo_texture = _soft
	_glow_mat.disable_receive_shadows = true
	_glow_qm.material = _glow_mat
	_glow.mesh = _glow_qm
	_glow.position = Vector3(0, 1.05, 0)
	add_child(_glow)

func _make_particles(amount: int, life: float, vel: float, radius: float,
		c0: Color, c1: Color, grav: Vector3, spread: float, sscale: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3(0, 1, 0)
	p.spread = spread * 40.0
	p.gravity = grav
	p.initial_velocity_min = vel * 0.6
	p.initial_velocity_max = vel
	p.scale_amount_min = sscale * 0.7
	p.scale_amount_max = sscale
	var ramp := Gradient.new()
	ramp.set_color(0, c0)
	ramp.set_color(1, c1)
	p.color_ramp = ramp
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.albedo_texture = _soft
	mat.disable_receive_shadows = true
	qm.material = mat
	p.mesh = qm
	return p

func feed(amount: float) -> void:
	if not is_lit:
		return
	fuel = minf(MAX_FUEL, fuel + amount)

func relight(amount: float) -> void:
	fuel = minf(MAX_FUEL, fuel + amount)
	if not is_lit and fuel > 0.0:
		is_lit = true
		_flame.emitting = true
		_embers.emitting = true
		_smoke.emitting = false

func fuel_ratio() -> float:
	return clampf(fuel / MAX_FUEL, 0.0, 1.0)

func tick(delta: float) -> void:
	if not is_lit:
		return
	fuel = maxf(0.0, fuel - burn_rate * delta)
	if fuel <= 0.0:
		is_lit = false
		_flame.emitting = false
		_embers.emitting = false
		_smoke.emitting = true
		went_out.emit()

func _process(delta: float) -> void:
	_t += delta
	var r := fuel_ratio()
	if is_lit:
		var flick := 0.78 + 0.22 * sin(_t * 17.0) + 0.12 * sin(_t * 41.0 + 1.3)
		var lvl := lerpf(0.35, 1.0, r)
		_light.light_energy = _base_energy * lvl * flick
		_light.position.x = sin(_t * 13.0) * 0.06
		_light.position.z = cos(_t * 11.0) * 0.06
		_flame.scale = Vector3.ONE * lerpf(0.55, 1.0, r)
		if _glow_mat != null:
			_glow_mat.albedo_color.a = (0.32 + 0.18 * flick) * lerpf(0.4, 1.0, r)
		if _glow_qm != null:
			var s := lerpf(1.6, 2.6, r) * (0.94 + 0.1 * flick)
			_glow_qm.size = Vector2(s, s)
	else:
		_light.light_energy = maxf(0.0, _light.light_energy - delta * 4.0)
