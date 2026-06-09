class_name Impact
extends Node
## One-shot particle burst (blood / sparks / dust) that frees itself. Combat juice.

static var _soft: ImageTexture

static func _soft_tex() -> ImageTexture:
	if _soft == null:
		_soft = Campfire.make_soft_tex()
	return _soft

static func burst(parent: Node, pos: Vector3, color: Color, count: int, speed: float, life: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = count
	p.lifetime = life
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.18
	p.direction = Vector3(0, 1, 0)
	p.spread = 80.0
	p.gravity = Vector3(0, -7.0, 0)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.16
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_tex()
	mat.disable_receive_shadows = true
	qm.material = mat
	p.mesh = qm
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var timer := parent.get_tree().create_timer(life + 0.3)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())
