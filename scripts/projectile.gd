class_name PlasmaBolt
extends Area3D
## A slow, dodgeable energy bolt fired by ranged enemies (cyber enforcer + reaver boss).
## Hits the player or a wall, deals damage, and bursts.

var dir := Vector3.FORWARD
var speed := 22.0
var dmg := 12.0
var life := 3.0
var color := Color(1.0, 0.35, 0.85)

func _ready() -> void:
    add_to_group("bolt")
    collision_layer = 0
    collision_mask = 1 | 2     # world + player
    monitoring = true
    var cs := CollisionShape3D.new()
    var sp := SphereShape3D.new()
    sp.radius = 0.28
    cs.shape = sp
    add_child(cs)
    var mi := MeshInstance3D.new()
    var sm := SphereMesh.new()
    sm.radius = 0.22
    sm.height = 0.44
    mi.mesh = sm
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.albedo_color = color
    m.emission_enabled = true
    m.emission = color
    m.emission_energy_multiplier = 4.0
    mi.material_override = m
    add_child(mi)
    var glow := OmniLight3D.new()
    glow.light_color = color
    glow.light_energy = 1.6
    glow.omni_range = 4.0
    add_child(glow)
    body_entered.connect(_on_body)

func _physics_process(delta: float) -> void:
    global_position += dir * speed * delta
    life -= delta
    if life <= 0.0:
        queue_free()

func _on_body(body: Node) -> void:
    if body.is_in_group("player") and body.has_method("take_damage"):
        body.call("take_damage", dmg)
    _burst()
    queue_free()

func _burst() -> void:
    var p := CPUParticles3D.new()
    p.one_shot = true
    p.emitting = false
    p.amount = 16
    p.lifetime = 0.3
    p.explosiveness = 1.0
    p.spread = 80.0
    p.initial_velocity_min = 2.0
    p.initial_velocity_max = 6.0
    p.mesh = SphereMesh.new()
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.albedo_color = color
    m.emission_enabled = true
    m.emission = color
    m.emission_energy_multiplier = 3.0
    p.material_override = m
    var parent := get_parent()
    if parent == null:
        return
    parent.add_child(p)
    p.global_position = global_position
    p.emitting = true
    p.get_tree().create_timer(0.6).timeout.connect(func() -> void:
        if is_instance_valid(p): p.queue_free())
