class_name WorldBuilder
extends RefCounted
## Builds the grim dusk industrial station: metal floor, perimeter walls, cover crates,
## vostok set-dressing props, amber emergency lights, the HDRI dusk sky + WorldEnvironment.
## Collision convention: layer 1 = world/props, 2 = player, 3 = enemies, 4 = triggers/NPC.

const ARENA := 46.0           # square half-extent-ish (full ~46 x 46 play area)
const WALL_H := 7.0

var player_start := Vector3(0, 0.1, 14)
var npc_point := Vector3(0, 0.0, -16)
var npc_facing := 0.0
var spawn_points: PackedVector3Array = []
var bound := 21.0             # player clamp radius from centre

var _rng := RandomNumberGenerator.new()

func build(root: Node3D) -> void:
    _rng.seed = 9123
    _environment(root)
    _lights(root)
    _floor(root)
    _walls(root)
    _cover(root)
    _props(root)
    _spawn_gates()

# ── environment + HDRI sky (with the #83788 brightness fix) ──
func _environment(root: Node3D) -> void:
    var we := WorldEnvironment.new()
    var env := Environment.new()
    var sky := Sky.new()
    var mat := ShaderMaterial.new()
    mat.shader = load("res://shaders/hdri_sky.gdshader")
    mat.set_shader_parameter("panorama", load("res://skies/dusk.hdr"))
    mat.set_shader_parameter("exposure", 0.95)
    sky.sky_material = mat
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_sky_contribution = 1.0
    env.ambient_light_energy = 0.65
    env.tonemap_mode = Environment.TONE_MAPPER_AGX
    env.tonemap_exposure = 1.0
    env.background_energy_multiplier = 1.0
    env.fog_enabled = true
    env.fog_light_color = Color(0.55, 0.38, 0.30)
    env.fog_density = 0.018
    env.fog_sky_affect = 0.3
    env.fog_aerial_perspective = 0.4
    we.environment = env
    root.add_child(we)

func _lights(root: Node3D) -> void:
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-18, 38, 0)   # low dusk sun
    sun.light_color = Color(1.0, 0.72, 0.48)
    sun.light_energy = 1.5
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 90.0
    root.add_child(sun)
    # amber emergency lamps around the rim
    var ring := [Vector3(-18, 4.5, -18), Vector3(18, 4.5, -18), Vector3(-18, 4.5, 18), Vector3(18, 4.5, 18), Vector3(0, 5.5, 0)]
    for p: Vector3 in ring:
        var o := OmniLight3D.new()
        o.light_color = Color(1.0, 0.55, 0.28)
        o.light_energy = 2.6
        o.omni_range = 22.0
        o.position = p
        root.add_child(o)

# ── floor ──
func _floor(root: Node3D) -> void:
    var mi := MeshInstance3D.new()
    var pm := PlaneMesh.new()
    pm.size = Vector2(ARENA * 2.4, ARENA * 2.4)
    mi.mesh = pm
    var m := StandardMaterial3D.new()
    m.albedo_color = Color(0.13, 0.14, 0.17)
    m.metallic = 0.65
    m.metallic_specular = 0.4
    m.roughness = 0.42
    m.uv1_scale = Vector3(26, 26, 1)
    mi.material_override = m
    root.add_child(mi)
    # emissive grid seams (an additive grid overlay quad just above the floor)
    var grid := MeshInstance3D.new()
    var gp := PlaneMesh.new()
    gp.size = Vector2(ARENA * 2.0, ARENA * 2.0)
    grid.mesh = gp
    grid.position.y = 0.02
    var gm := _grid_material()
    grid.material_override = gm
    root.add_child(grid)
    # physical floor collider
    var body := StaticBody3D.new()
    body.collision_layer = 1
    body.collision_mask = 0
    var col := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = Vector3(ARENA * 2.4, 0.4, ARENA * 2.4)
    col.shape = bs
    col.position.y = -0.2
    body.add_child(col)
    root.add_child(body)

func _grid_material() -> ShaderMaterial:
    var sm := ShaderMaterial.new()
    var sh := Shader.new()
    sh.code = """shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
uniform vec3 line_col : source_color = vec3(0.9, 0.45, 0.2);
uniform float cells = 46.0;
void fragment(){
    vec2 g = abs(fract(UV * cells - 0.5) - 0.5) / fwidth(UV * cells);
    float line = 1.0 - min(min(g.x, g.y), 1.0);
    ALBEDO = line_col * line * 0.5;
    ALPHA = line;
}"""
    sm.shader = sh
    return sm

# ── perimeter walls ──
func _walls(root: Node3D) -> void:
    var half := ARENA
    var specs := [
        {"pos": Vector3(0, WALL_H * 0.5, -half), "size": Vector3(half * 2, WALL_H, 1.2)},
        {"pos": Vector3(0, WALL_H * 0.5, half), "size": Vector3(half * 2, WALL_H, 1.2)},
        {"pos": Vector3(-half, WALL_H * 0.5, 0), "size": Vector3(1.2, WALL_H, half * 2)},
        {"pos": Vector3(half, WALL_H * 0.5, 0), "size": Vector3(1.2, WALL_H, half * 2)},
    ]
    for s in specs:
        _metal_block(root, s["pos"], s["size"], Color(0.18, 0.19, 0.22), 0.55, 0.5)
    # inner barrier ring (the actual play boundary the player is clamped to) with panel pillars
    var n := 16
    for i in n:
        var a := TAU * float(i) / float(n)
        var p := Vector3(cos(a) * (bound + 1.5), 2.0, sin(a) * (bound + 1.5))
        _metal_block(root, p, Vector3(2.4, 4.0, 1.0), Color(0.2, 0.21, 0.24), 0.6, 0.45, a)

# ── cover crates & pillars ──
func _cover(root: Node3D) -> void:
    var spots := [
        Vector3(-8, 0, -4), Vector3(9, 0, 3), Vector3(-6, 0, 9), Vector3(7, 0, -9),
        Vector3(0, 0, -10), Vector3(-12, 0, 2), Vector3(12, 0, -2), Vector3(3, 0, 11),
    ]
    for s: Vector3 in spots:
        var h := _rng.randf_range(1.4, 2.4)
        var w := _rng.randf_range(1.6, 2.6)
        var col := Color(0.26, 0.24, 0.2).lerp(Color(0.2, 0.28, 0.3), _rng.randf())
        var pos := s + Vector3(0, h * 0.5, 0)
        _metal_block(root, pos, Vector3(w, h, w), col, 0.45, 0.6, _rng.randf_range(0, TAU))
    # a couple of tall structural pillars
    for px in [-15.0, 15.0]:
        for pz in [-15.0, 15.0]:
            _metal_block(root, Vector3(px, WALL_H * 0.5, pz), Vector3(2.2, WALL_H, 2.2), Color(0.16, 0.17, 0.2), 0.6, 0.4)

# ── vostok set-dressing props (realistic style) ──
func _props(root: Node3D) -> void:
    var entries := [
        ["res://models/ms_control_box.glb", Vector3(-3.5, 0, -15.2), 1.4],
        ["res://models/ms_cabinet_basic.glb", Vector3(3.4, 0, -15.4), 1.4],
        ["res://models/ms_cable_reel.glb", Vector3(-13, 0, -8), 1.3],
        ["res://models/ms_barrier_road.glb", Vector3(10, 0, 8), 1.6],
        ["res://models/ms_barrier_road.glb", Vector3(-9, 0, 7), 1.6],
        ["res://models/ms_brick_pile.glb", Vector3(13, 0, 11), 1.4],
        ["res://models/ms_board_message.glb", Vector3(0, 0, -18.5), 1.6],
    ]
    for e in entries:
        var path: String = e[0]
        var res := load(path)
        if res == null:
            continue
        var inst := (res as PackedScene).instantiate() as Node3D
        var sc: float = float(e[2])
        inst.scale = Vector3(sc, sc, sc)
        inst.position = e[1]
        inst.rotation.y = _rng.randf_range(-0.4, 0.4)
        root.add_child(inst)
        _collider_from_mesh(inst, sc)

# ── helpers ──
func _metal_block(root: Node3D, pos: Vector3, size: Vector3, col: Color, metal: float, rough: float, yaw := 0.0) -> void:
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = size
    mi.mesh = bm
    var m := StandardMaterial3D.new()
    m.albedo_color = col
    m.metallic = metal
    m.roughness = rough
    m.metallic_specular = 0.45
    mi.material_override = m
    mi.position = pos
    mi.rotation.y = yaw
    root.add_child(mi)
    var body := StaticBody3D.new()
    body.collision_layer = 1
    body.collision_mask = 0
    var cs := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = size
    cs.shape = bs
    body.add_child(cs)
    body.position = pos
    body.rotation.y = yaw
    root.add_child(body)

func _collider_from_mesh(inst: Node3D, sc: float) -> void:
    var aabb := AABB()
    var first := true
    for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
        if mi.mesh == null:
            continue
        var a := mi.get_aabb()
        if first:
            aabb = a
            first = false
        else:
            aabb = aabb.merge(a)
    if first:
        return
    var body := StaticBody3D.new()
    body.collision_layer = 1
    body.collision_mask = 0
    var cs := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = aabb.size * sc
    cs.shape = bs
    cs.position = aabb.get_center() * sc
    body.add_child(cs)
    inst.add_child(body)

func _spawn_gates() -> void:
    spawn_points = PackedVector3Array()
    var n := 10
    for i in n:
        var a := TAU * float(i) / float(n) + 0.3
        spawn_points.append(Vector3(cos(a) * (bound - 1.0), 0.1, sin(a) * (bound - 1.0)))
