class_name WorldBuilder
extends RefCounted
## Builds the abandoned-bus-stop world: PBR ground + cracked road, realistic survival props,
## roadside dressing, the HDRI dusk->night sky, sun and fog. Returns the refs Main animates
## over the day/night cycle plus the spawn/pickup/player anchor points.

const SKY_SHADER := preload("res://shaders/sky_daynight.gdshader")

# Collision layers (bit values): 1 world, 2 player, 4 enemy, 8 pickup/trigger, 16 fire-zone.
const L_WORLD := 1

var world_env: WorldEnvironment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var spawn_points: Array[Vector3] = []
var pickup_points: Array[Vector3] = []
var player_start := Vector3(0, 0, 4.5)
var fire_point := Vector3(0, 0, 0)

func build(parent: Node3D) -> void:
	_build_environment(parent)
	_build_ground(parent)
	_build_road(parent)
	_build_props(parent)
	_build_dressing(parent)
	_build_treeline(parent)
	_compute_points()

# ---------------------------------------------------------------- environment
func _build_environment(parent: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("dusk_tex", load("res://skies/dusk.hdr"))
	sky_mat.set_shader_parameter("night_tex", load("res://skies/night.exr"))
	sky_mat.set_shader_parameter("blend", 0.0)
	sky_mat.set_shader_parameter("exposure", 1.0)
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.82
	env.tonemap_white = 8.0

	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.09
	env.adjustment_saturation = 0.9

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.42, 0.36, 0.32)
	env.fog_density = 0.015
	env.fog_sky_affect = 0.0
	env.fog_depth_begin = 12.0
	env.fog_depth_end = 80.0

	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	parent.add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(48.0), 0.0)
	sun.light_color = Color(1.0, 0.64, 0.34)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.04
	parent.add_child(sun)

# ---------------------------------------------------------------- ground
func _pbr_material(dir: String, tiling: float, rough_boost: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://textures/%s/albedo.png" % dir)
	mat.normal_enabled = true
	mat.normal_texture = load("res://textures/%s/normal_gl.png" % dir)
	mat.normal_scale = 1.0
	mat.roughness_texture = load("res://textures/%s/roughness.png" % dir)
	mat.roughness = rough_boost
	mat.metallic = 0.0
	mat.uv1_scale = Vector3(tiling, tiling, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

func _build_ground(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = L_WORLD
	body.collision_mask = 0
	parent.add_child(body)

	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(170, 170)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	mi.mesh = pm
	mi.material_override = _pbr_material("ground", 42.0, 1.0)
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := WorldBoundaryShape3D.new()
	shape.plane = Plane(Vector3.UP, 0.0)
	col.shape = shape
	body.add_child(col)

func _build_road(parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Road"
	var pm := PlaneMesh.new()
	pm.size = Vector2(170, 7.5)
	mi.mesh = pm
	var mat := _pbr_material("road", 1.0, 0.95)
	mat.uv1_scale = Vector3(24.0, 1.1, 1.0)
	mi.material_override = mat
	mi.position = Vector3(0, 0.02, 9.5)
	parent.add_child(mi)

	# soft gravel shoulder strip between road and camp
	var sh := MeshInstance3D.new()
	var spm := PlaneMesh.new()
	spm.size = Vector2(170, 3.0)
	sh.mesh = spm
	var smat := _pbr_material("ground", 8.0, 1.0)
	smat.albedo_color = Color(0.7, 0.66, 0.6)
	sh.material_override = smat
	sh.position = Vector3(0, 0.015, 5.4)
	parent.add_child(sh)

# ---------------------------------------------------------------- props
func _instance(parent: Node3D, path: String, pos: Vector3, yaw_deg: float, scl: float, collide: bool) -> Node3D:
	var ps := load(path)
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	parent.add_child(n)
	n.scale = Vector3(scl, scl, scl)
	n.rotation = Vector3(0, deg_to_rad(yaw_deg), 0)
	n.global_position = pos
	if collide:
		_add_box_collider(n, scl)
	return n

func _merged_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		var a := m.get_aabb()
		a = m.transform * a
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out

func _add_box_collider(model: Node3D, scl: float) -> void:
	var aabb := _merged_aabb(model)
	if aabb.size == Vector3.ZERO:
		return
	var body := StaticBody3D.new()
	body.collision_layer = L_WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var sz := aabb.size * scl
	# keep walls solid but not taller than they look; clamp tiny heights up a touch
	box.size = Vector3(maxf(sz.x, 0.3), maxf(sz.y, 0.4), maxf(sz.z, 0.3))
	col.shape = box
	col.position = aabb.get_center() * scl
	body.add_child(col)
	model.add_child(body)

func _build_props(parent: Node3D) -> void:
	var P := "res://models/props/"
	# Road barriers strung along the shoulder, between road and camp.
	_instance(parent, P + "ms_barrier_road.glb", Vector3(-7, 0, 4.2), 0, 1.0, true)
	_instance(parent, P + "ms_barrier_road.glb", Vector3(0.5, 0, 4.2), 0, 1.0, true)
	_instance(parent, P + "ms_barrier_road.glb", Vector3(8, 0, 4.2), 0, 1.0, true)
	# The abandoned rural bus stop, set just off the road.
	_instance(parent, P + "ms_bus_stop_rural.glb", Vector3(12.5, 0, 11.0), -90, 1.0, true)
	# Message board.
	_instance(parent, P + "ms_board_message.glb", Vector3(-10.0, 0, 7.5), 35, 1.0, true)
	# Rusted control box.
	_instance(parent, P + "ms_control_box.glb", Vector3(7.0, 0, 1.5), -120, 1.0, true)
	# Cable reel.
	_instance(parent, P + "ms_cable_reel.glb", Vector3(-6.0, 0, -4.5), 20, 1.0, true)
	# Brick pile.
	_instance(parent, P + "ms_brick_pile.glb", Vector3(5.0, 0, -5.5), -25, 1.0, true)
	# Cabinet + a sun chair near the fire for camp texture.
	_instance(parent, P + "ms_cabinet_basic.glb", Vector3(-8.0, 0, -7.5), 60, 1.0, true)
	_instance(parent, P + "ms_chair_sun.glb", Vector3(3.2, 0, 3.6), 150, 1.0, false)
	_instance(parent, P + "ms_candle.glb", Vector3(-7.4, 0, -6.7), 0, 1.0, false)

func _build_dressing(parent: Node3D) -> void:
	var D := "res://models/dressing/"
	var rocks := ["rock_largeA.glb", "rock_largeC.glb", "rock_largeE.glb"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	# scatter rocks + bushes in the mid-field, avoiding the camp core and the road
	var placed := 0
	var tries := 0
	while placed < 16 and tries < 200:
		tries += 1
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(9.0, 26.0)
		var p := Vector3(cos(ang) * rad, 0, sin(ang) * rad)
		if absf(p.z - 9.5) < 5.0:
			continue # keep the road clear
		var which := rng.randi() % 3
		var scl := rng.randf_range(0.7, 1.7)
		if which < 2:
			_instance(parent, D + rocks[rng.randi() % rocks.size()], p, rng.randf() * 360.0, scl, true)
		else:
			_instance(parent, D + "plant_bushLarge.glb", p, rng.randf() * 360.0, rng.randf_range(0.8, 1.6), false)
		placed += 1
	# a couple of stacked logs near camp as flavour (also wood theme)
	_instance(parent, D + "log_stack.glb", Vector3(-3.4, 0, 2.2), 40, 1.0, true)

func _build_treeline(parent: Node3D) -> void:
	var D := "res://models/dressing/"
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var count := 46
	for i in range(count):
		var ang := (float(i) / float(count)) * TAU + rng.randf_range(-0.05, 0.05)
		var rad := rng.randf_range(34.0, 44.0)
		var p := Vector3(cos(ang) * rad, 0, sin(ang) * rad)
		var scl := rng.randf_range(2.6, 4.4)
		_instance(parent, D + "tree_cone_dark.glb", p, rng.randf() * 360.0, scl, false)

# ---------------------------------------------------------------- anchor points
func _compute_points() -> void:
	# Wood scavenge spots: a loose ring around the camp, off the road.
	var spot_angles := [20.0, 80.0, 200.0, 250.0, 310.0]
	for a: float in spot_angles:
		var rad := 11.0
		var p := Vector3(cos(deg_to_rad(a)) * rad, 0, sin(deg_to_rad(a)) * rad)
		pickup_points.append(p)
	# Enemy spawn ring: further out, in the dark, spread all around.
	for i in range(12):
		var ang := (float(i) / 12.0) * TAU
		var rad := 24.0 + (float(i % 3) * 3.0)
		spawn_points.append(Vector3(cos(ang) * rad, 0, sin(ang) * rad))
