class_name MeshyCharacterRig
extends Node3D
## Drop-in rig for Meshy-generated realistic characters (24-bone Meshy/Mixamo-style
## skeleton) plus a top-level weapon that AIMS down sights, FIRES (recoil + muzzle
## flash + tracer) and RELOADS (animated magazine). Game-agnostic — no UI, camera or
## input; you drive it from your own game code.
##
## USAGE
##   var rig := MeshyCharacterRig.new()
##   add_child(rig)
##   rig.setup(
##       load("res://chars/soldier.glb").instantiate(),   # character GLB (rigged)
##       load("res://weapons/rifle.glb").instantiate(),    # weapon GLB ("" / null = unarmed)
##       MeshyCharacterRig.RIFLE)                           # weapon config (see consts below)
##   rig.play("walk")     # idle walk run jump crouch walk_back dodge hit death victory
##   rig.aim()            # steady aim-down-sights
##   rig.fire()           # 6-round burst: recoil + muzzle flash + tracers
##   rig.reload()         # animated magazine reload
##
## REQUIREMENTS
##   • The character GLB carries ONE AnimationPlayer with the standard clip set
##     (idle/walk/run/jump/crouch/walk_back/dodge/aim/fire/reload/hit/death[/victory])
##     and a Skeleton3D with Meshy bone names: Hips, Spine*, Head, RightUpLeg/LeftUpLeg,
##     RightShoulder/RightArm/RightForeArm/RightHand (+ Left*).
##   • The weapon mounts UNDER this node (never under the sub-cm-scaled skeleton) and is
##     driven each frame from the hand bone's orthonormalized pose → it never inherits
##     bone scale, so it never stretches.
##
## WHY THE CONFIG MATTERS
##   Bare GLB + AnimationPlayer is NOT enough: Meshy's combat clips point the weapon
##   sideways/up, the rigid (finger-less) hands splay open, and some weapon meshes are
##   modelled barrel-along-(-X). This rig fixes all of that at runtime via the per-weapon
##   config: head-anchored ADS frame, two-bone arm IK onto the grip/handguard, hand
##   orientation, recoil, reload mag, body-forward derivation, and a `flip` for -X barrels.

const RELOAD_DUR := 1.9

## ── Per-weapon configs (flat dict; pass one to setup() or roll your own) ──────────────
## scale          on-hand world scale of the weapon mesh
## offset_pos/rot  hand-carry placement (movement clips); offset_pos.x is a barrel fraction
## muzzle          local muzzle position (flash/tracer origin); [-0.95,..] for flipped mesh
## tracer          [r,g,b] tracer/flash colour
## af/au/ar        ADS anchor offset from the Head bone (forward / up / right)
## pitch           barrel pitch (deg); negative = slight muzzle-down to read level
## gr/gl           right(grip)/left(handguard) hand position along the barrel
## dropr/dropl     right/left hand drop below the barrel line (firing hand → pistol grip)
## rhx             right-hand wrap pitch (deg) so the rigid hand grips the pistol grip
## mount           along-barrel offset that seats the weapon body over the hands
## flip            true if the mesh barrel runs along -X (turn it 180° to face forward)
const RIFLE := {"scale":0.38,"offset_pos":[0.8,0,0],"offset_rot":[0,0,0],"muzzle":[0.95,0,0],"tracer":[1.0,0.8,0.35],
    "af":0.24,"au":0.05,"ar":0.05,"pitch":-2,"gr":-0.06,"gl":0.40,"dropr":0.14,"dropl":0.04,"rhx":-55,"mount":0.20}
const PISTOL := {"scale":0.13,"offset_pos":[0.8,0,0],"offset_rot":[0,0,0],"muzzle":[0.95,0,0],"tracer":[1.0,0.85,0.4],
    "af":0.40,"au":-0.02,"ar":0.04,"pitch":0,"gr":-0.02,"gl":0.12,"dropr":0.06,"dropl":0.04,"rhx":-30,"mount":0.30}
const PLASMA := {"scale":0.38,"offset_pos":[0.8,0,0],"offset_rot":[0,0,0],"muzzle":[-0.95,0,0],"tracer":[0.3,1.0,0.95],
    "af":0.24,"au":0.05,"ar":0.05,"pitch":-2,"gr":-0.06,"gl":0.40,"dropr":0.14,"dropl":0.04,"rhx":-55,"mount":0.20,"flip":true}
const SHOTGUN := {"scale":0.26,"offset_pos":[0.8,0,0],"offset_rot":[0,0,0],"muzzle":[0.95,0,0],"tracer":[1.0,0.7,0.3],
    "af":0.24,"au":0.04,"ar":0.05,"pitch":-2,"gr":-0.05,"gl":0.30,"dropr":0.13,"dropl":0.04,"rhx":-50,"mount":0.22}
const ARMCANNON := {"scale":0.33,"offset_pos":[0.8,0,0],"offset_rot":[0,0,0],"muzzle":[-0.95,0,0],"tracer":[1.0,0.3,0.9],
    "af":0.42,"au":0.0,"ar":0.10,"pitch":0,"gr":0.0,"gl":0.14,"dropr":0.04,"dropl":0.0,"rhx":-20,"mount":0.25,"flip":true}

var facing_deg := 0.0                # yaw applied to the character (mesh front faces +Z)

var _holder: Node3D                  # weapon + character live here (top-level, unscaled)
var current_skel: Skeleton3D
var current_anim: AnimationPlayer
var current_weapon: Node3D
var muzzle: Node3D
var weapon_cfg: Dictionary = {}
var weapon_scale := 1.0
var weapon_offset_pos := Vector3.ZERO
var weapon_offset_rot := Vector3.ZERO
var tracer_color := Color(1, 0.85, 0.4)
var weapon_bone := -1
var weapon_forearm_bone := -1
var weapon_head_bone := -1
var weapon_recoil := 0.0             # 0..1, kicked to 1 per shot, decays each frame
var aiming := false                  # aim/fire/reload → freeze body + IK both hands on the weapon
var reload_t := -1.0                 # >=0 while a reload plays (seconds elapsed)
var reload_mag: Node3D = null
var current_clip := "idle"

func _ensure_holder() -> void:
    if _holder == null:
        _holder = Node3D.new()
        add_child(_holder)

## Mount an instantiated character GLB + optional weapon GLB + its config.
func setup(character: Node3D, weapon: Node3D = null, cfg: Dictionary = {}, p_facing_deg := 0.0) -> void:
    _ensure_holder()
    for c in _holder.get_children():
        c.queue_free()
    current_weapon = null; muzzle = null; reload_mag = null
    weapon_bone = -1; weapon_forearm_bone = -1; weapon_head_bone = -1
    weapon_recoil = 0.0; reload_t = -1.0; aiming = false
    facing_deg = p_facing_deg
    character.rotation_degrees.y = facing_deg
    _holder.add_child(character)
    current_anim = _find(character, "AnimationPlayer") as AnimationPlayer
    current_skel = _find(character, "Skeleton3D") as Skeleton3D
    weapon_cfg = cfg
    tracer_color = _color(cfg.get("tracer", [1, 0.85, 0.4]))
    if weapon != null and not cfg.is_empty() and current_skel != null:
        _attach_weapon(weapon, cfg)
    elif weapon != null:
        weapon.queue_free()
    play("idle")

# ── public clip API ─────────────────────────────────────────────────────────
func aim() -> void:
    play("aim")

func play(clip: String) -> void:
    current_clip = clip
    # aim/fire/reload use the braced both-hands-on-the-weapon pose: freeze the clip's
    # own body for legs/torso, then drive the arms + weapon by IK each frame.
    aiming = (clip == "aim" or clip == "fire" or clip == "reload") and current_weapon != null
    if not aiming and _holder != null:
        _holder.rotation.y = 0.0
    if clip != "reload" and reload_t >= 0.0:
        reload_t = -1.0
        if is_instance_valid(reload_mag): reload_mag.queue_free()
        reload_mag = null
    if current_anim == null:
        return
    var list := current_anim.get_animation_list()
    if list.has(clip):
        var a := current_anim.get_animation(clip)
        a.loop_mode = Animation.LOOP_LINEAR if clip in ["idle","walk","run","crouch","walk_back"] else Animation.LOOP_NONE
        current_anim.play(clip)
        if aiming:
            current_anim.seek(a.length * 0.5, true)
            current_anim.pause()

func fire() -> void:
    play("fire")
    for i in 6:
        await get_tree().create_timer(0.1).timeout
        if muzzle == null or current_clip != "fire":
            return
        weapon_recoil = 1.0
        _muzzle_flash()
        _tracer()

func reload() -> void:
    play("reload")
    reload_t = 0.0
    _spawn_mag()

# ── per-frame drive ──────────────────────────────────────────────────────────
func _process(delta: float) -> void:
    if current_skel == null:
        return
    weapon_recoil = move_toward(weapon_recoil, 0.0, delta * 8.0)
    if reload_t >= 0.0:
        reload_t += delta
        if reload_t >= RELOAD_DUR:
            reload_t = -1.0
            if is_instance_valid(reload_mag): reload_mag.queue_free()
            reload_mag = null
    if aiming:
        _apply_aim_ik()           # body is paused (frozen) so this isn't overwritten
    _update_weapon_mount()
    if reload_t >= 0.0:
        _update_reload_mag()

# ── weapon attach ────────────────────────────────────────────────────────────
func _attach_weapon(winst: Node3D, cfg: Dictionary) -> void:
    for b in current_skel.get_bone_count():
        var bn := current_skel.get_bone_name(b)
        if bn.findn("RightHand") != -1 and bn.findn("Index") == -1 and bn.findn("Thumb") == -1 and bn.findn("Pinky") == -1 and bn.findn("Middle") == -1 and bn.findn("Ring") == -1:
            weapon_bone = b
        elif bn.findn("RightForeArm") != -1 or bn.findn("RightForearm") != -1 or bn.findn("RightLowerArm") != -1:
            weapon_forearm_bone = b
        elif bn == "Head" or bn == "head":
            weapon_head_bone = b
    if weapon_bone == -1:
        winst.queue_free()
        return
    weapon_offset_pos = _v3(cfg.get("offset_pos", [0, 0, 0]))
    weapon_offset_rot = _v3(cfg.get("offset_rot", [0, 0, 0]))
    weapon_scale = float(cfg.get("scale", 1.0))
    _holder.add_child(winst)
    current_weapon = winst
    muzzle = Node3D.new()
    muzzle.position = _v3(cfg.get("muzzle", [0.95, 0, 0]))
    # Flipped weapons (barrel along -X): rotate the muzzle node 180° so its +X — the
    # flash/tracer direction — still points down the real barrel (forward).
    if bool(cfg.get("flip", false)):
        muzzle.rotation.y = PI
    winst.add_child(muzzle)
    _update_weapon_mount()

# ── aim-down-sights: head-anchored frame + two-bone arm IK ───────────────────
func _bidx(want: String, excl: Array) -> int:
    for b in current_skel.get_bone_count():
        var bn := current_skel.get_bone_name(b)
        if bn.findn(want) != -1:
            var ok := true
            for e in excl:
                if bn.findn(e) != -1: ok = false
            if ok: return b
    return -1

# The character's TRUE forward, measured from the frozen pose's hip line. Meshy clips
# turn the body internally, so a hardcoded axis points the weapon the wrong way.
func _body_fwd() -> Vector3:
    var rul := _bidx("RightUpLeg", [])
    var lul := _bidx("LeftUpLeg", [])
    if rul < 0 or lul < 0:
        return Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(facing_deg))
    var sg := current_skel.global_transform
    var r := (sg * current_skel.get_bone_global_pose(rul)).origin - (sg * current_skel.get_bone_global_pose(lul)).origin
    r.y = 0
    if r.length() < 0.00001:
        return Vector3(0, 0, -1)
    return Vector3.UP.cross(r.normalized()).normalized()

func _aim_frame() -> Dictionary:
    var a := weapon_cfg
    var sg := current_skel.global_transform
    var fwd := _body_fwd()
    var rgt := fwd.cross(Vector3.UP).normalized()
    var hb := weapon_head_bone if weapon_head_bone >= 0 else _bidx("Head", ["end", "front"])
    var headw := (sg * current_skel.get_bone_global_pose(hb)).origin
    var pitch_deg := float(a.get("pitch", 0))
    var lower := 0.0
    var pull := 0.0
    if current_clip == "reload" and reload_t >= 0.0:
        var ws := _reload_ws()
        pitch_deg -= 10.0 * ws
        lower = 0.15 * ws
        pull = -0.12 * ws
    var bdir := fwd.rotated(rgt, deg_to_rad(pitch_deg)).normalized()
    var bup := rgt.cross(bdir).normalized()
    var pos := headw + bdir * float(a.get("af", 0.24)) + Vector3.UP * float(a.get("au", 0.05)) + rgt * float(a.get("ar", 0.05)) - bup * lower - bdir * pull
    var grip := pos + bdir * float(a.get("gr", -0.06)) - bup * float(a.get("dropr", 0.14))
    var fore := pos + bdir * float(a.get("gl", 0.40)) - bup * float(a.get("dropl", 0.04))
    var basis := Basis(bdir, bup, bdir.cross(bup).normalized())
    if weapon_recoil > 0.001:
        var pivot := pos - bdir * 0.32
        var rq := Basis(rgt, deg_to_rad(-weapon_recoil * 9.0))
        var back := -bdir * (weapon_recoil * 0.05) + bup * (weapon_recoil * 0.012)
        pos = pivot + rq * (pos - pivot) + back
        grip = pivot + rq * (grip - pivot) + back
        fore = pivot + rq * (fore - pivot) + back
        basis = rq * basis
        bdir = basis.x.normalized()
        bup = basis.y.normalized()
    return {"basis": basis, "pos": pos, "grip": grip, "fore": fore, "bdir": bdir, "bup": bup, "rgt": rgt}

func _reload_ws() -> float:
    if reload_t < 0.0:
        return 0.0
    var p := reload_t / RELOAD_DUR
    return smoothstep(0.0, 0.12, p) * (1.0 - smoothstep(0.86, 1.0, p))

func _reload_left(fr: Dictionary) -> Vector3:
    var p := reload_t / RELOAD_DUR
    var gr := float(weapon_cfg.get("gr", -0.06))
    var well: Vector3 = fr.pos + fr.bdir * (gr + 0.04) - fr.bup * 0.19
    var pouch: Vector3 = fr.pos - fr.bup * 0.46 - fr.rgt * 0.30 + fr.bdir * 0.18
    var raised: Vector3 = fr.pos - fr.bup * 0.10 - fr.rgt * 0.34 + fr.bdir * 0.24
    var hand: Vector3 = fr.fore
    if p < 0.26:
        return hand.lerp(pouch, smoothstep(0.0, 1.0, p / 0.26))
    elif p < 0.46:
        return pouch.lerp(raised, smoothstep(0.0, 1.0, (p - 0.26) / 0.20))
    elif p < 0.62:
        return raised.lerp(well, smoothstep(0.0, 1.0, (p - 0.46) / 0.16))
    elif p < 0.70:
        return well
    else:
        return well.lerp(hand, smoothstep(0.0, 1.0, (p - 0.70) / 0.30))

func _update_reload_mag() -> void:
    if not is_instance_valid(reload_mag) or reload_t < 0.0 or current_skel == null:
        return
    var p := reload_t / RELOAD_DUR
    if p < 0.20 or p > 0.62:
        reload_mag.visible = false
        return
    var lh := _bidx("LeftHand", [])
    if lh < 0:
        reload_mag.visible = false
        return
    var fr := _aim_frame()
    var lhw: Vector3 = (current_skel.global_transform * current_skel.get_bone_global_pose(lh)).origin
    reload_mag.visible = true
    reload_mag.global_transform = Transform3D(fr.basis, lhw - fr.bup * 0.09)

func _set_grot(bone: int, parent: int, gbasis: Basis) -> void:
    var pg := current_skel.get_bone_global_pose(parent)
    var lb := pg.basis.inverse() * gbasis
    current_skel.set_bone_pose_rotation(bone, lb.get_rotation_quaternion())

func _aim_bone(bone: int, parent: int, child_pos: Vector3, target: Vector3) -> void:
    var bg := current_skel.get_bone_global_pose(bone)
    var cur := (child_pos - bg.origin).normalized()
    var nw := (target - bg.origin).normalized()
    _set_grot(bone, parent, Basis(Quaternion(cur, nw)) * bg.basis)

func _ik_arm(upper: int, pu: int, lower: int, hand: int, target: Vector3, bend: Vector3) -> void:
    var S := current_skel.get_bone_global_pose(upper).origin
    var E := current_skel.get_bone_global_pose(lower).origin
    var H := current_skel.get_bone_global_pose(hand).origin
    var l1 := S.distance_to(E)
    var l2 := E.distance_to(H)
    var tv := target - S
    var dist := clampf(tv.length(), absf(l1 - l2) + 0.5, l1 + l2 - 0.5)
    var dir := tv.normalized()
    var cosA := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
    var ang := acos(cosA)
    var bp := bend - dir * bend.dot(dir)
    if bp.length() < 0.01:
        bp = Vector3(0, -1, 0) - dir * dir.dot(Vector3(0, -1, 0))
    bp = bp.normalized()
    var elbow := S + dir * (l1 * cosA) + bp * (l1 * sin(ang))
    _aim_bone(upper, pu, E, elbow)
    var h2 := current_skel.get_bone_global_pose(hand).origin
    _aim_bone(lower, upper, h2, target)

func _apply_aim_ik() -> void:
    if current_skel == null or current_weapon == null:
        return
    var ra := _bidx("RightArm", ["Fore", "Hand"])
    var la := _bidx("LeftArm", ["Fore", "Hand"])
    if ra < 0 or la < 0:
        return
    var fr := _aim_frame()
    var inv := current_skel.global_transform.affine_inverse()
    var bendR := (inv.basis * Vector3(0.3, -1, -0.2)).normalized()
    var bendL := (inv.basis * Vector3(-0.3, -1, 0.2)).normalized()
    var rh := _bidx("RightHand", [])
    var lh := _bidx("LeftHand", [])
    var left_target: Vector3 = fr.fore
    if current_clip == "reload" and reload_t >= 0.0:
        left_target = _reload_left(fr)
    _ik_arm(ra, _bidx("RightShoulder", []), _bidx("RightForeArm", []), rh, inv * fr.grip, bendR)
    _ik_arm(la, _bidx("LeftShoulder", []), _bidx("LeftForeArm", []), lh, inv * left_target, bendL)
    # Orient the rigid (finger-less) hand meshes so the palms wrap the weapon. The
    # firing hand pitches down to grip the pistol grip; the support hand lies along it.
    var rhx := deg_to_rad(float(weapon_cfg.get("rhx", -55.0)))
    _set_grot(rh, _bidx("RightForeArm", []), fr.basis * Basis.from_euler(Vector3(rhx, 0, 0)))
    _set_grot(lh, _bidx("LeftForeArm", []), fr.basis)

func _update_weapon_mount() -> void:
    if current_weapon == null or current_skel == null or weapon_bone < 0:
        return
    var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(facing_deg))
    # AIM / FIRE / RELOAD = braced ADS at the head-anchored barrel frame.
    if aiming:
        var fr := _aim_frame()
        var mount := float(weapon_cfg.get("mount", 0.20))
        var wb: Basis = fr.basis
        if bool(weapon_cfg.get("flip", false)):
            wb = wb * Basis.from_euler(Vector3(0.0, PI, 0.0))
            mount = -mount
        current_weapon.global_transform = Transform3D(wb, fr.pos) * Transform3D(
            Basis().scaled(Vector3(weapon_scale, weapon_scale, weapon_scale)),
            Vector3(mount, 0, 0) * weapon_scale)
        return
    # Movement clips: carry along the forearm→hand direction, never pointing backward.
    var lb := Basis.from_euler(Vector3(deg_to_rad(weapon_offset_rot.x), deg_to_rad(weapon_offset_rot.y), deg_to_rad(weapon_offset_rot.z)))
    lb = lb.scaled(Vector3(weapon_scale, weapon_scale, weapon_scale))
    var rec := Transform3D(
        Basis(Vector3(0, 0, 1), deg_to_rad(weapon_recoil * 9.0)),
        Vector3(-weapon_recoil * 0.06, 0.0, 0.0))
    var hand := current_skel.global_transform * current_skel.get_bone_global_pose(weapon_bone)
    var aim: Vector3 = hand.basis.orthonormalized().x
    if weapon_forearm_bone >= 0:
        var elbow := current_skel.global_transform * current_skel.get_bone_global_pose(weapon_forearm_bone)
        var d := hand.origin - elbow.origin
        if d.length() > 0.001:
            aim = d.normalized()
    var bf := _body_fwd()
    if aim.dot(bf) < 0.0:
        var v := aim.dot(Vector3.UP)
        aim = (bf * sqrt(max(0.0, 1.0 - v * v)) + Vector3.UP * v).normalized()
    var ref := Vector3.UP
    if absf(aim.dot(ref)) > 0.95:
        ref = Vector3(0, 0, 1)
    var zc := aim.cross(ref).normalized()
    var yc := zc.cross(aim).normalized()
    var mbasis := Basis(aim, yc, zc)
    var woff := weapon_offset_pos
    if bool(weapon_cfg.get("flip", false)):
        mbasis = mbasis * Basis.from_euler(Vector3(0.0, PI, 0.0))
        woff = Vector3(-woff.x, woff.y, woff.z)
    current_weapon.global_transform = Transform3D(mbasis, hand.origin) * rec * Transform3D(lb, woff * weapon_scale)

# ── fx ───────────────────────────────────────────────────────────────────────
func _spawn_mag() -> void:
    if is_instance_valid(reload_mag):
        reload_mag.queue_free()
    _ensure_holder()
    var m := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(0.045, 0.19, 0.066)
    m.mesh = box
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.30, 0.31, 0.34)  # neutral steel-gray — reads vs camo, gear and gun
    mat.metallic = 0.2
    mat.roughness = 0.55
    m.material_override = mat
    m.visible = false
    _holder.add_child(m)
    reload_mag = m

func _muzzle_flash() -> void:
    var p := CPUParticles3D.new()
    p.emitting = false
    p.one_shot = true
    p.amount = 16
    p.lifetime = 0.2
    p.explosiveness = 1.0
    p.direction = Vector3(1, 0, 0)
    p.spread = 45.0
    p.initial_velocity_min = 2.0
    p.initial_velocity_max = 5.0
    p.scale_amount_min = 0.08
    p.scale_amount_max = 0.22
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.albedo_color = tracer_color
    m.emission_enabled = true
    m.emission = tracer_color
    m.emission_energy_multiplier = 4.0
    p.mesh = SphereMesh.new()
    p.material_override = m
    muzzle.add_child(p)
    p.emitting = true
    get_tree().create_timer(0.5).timeout.connect(func(): if is_instance_valid(p): p.queue_free())

func _tracer() -> void:
    var t := MeshInstance3D.new()
    var cap := CapsuleMesh.new()
    cap.radius = 0.025
    cap.height = 0.9
    t.mesh = cap
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.albedo_color = tracer_color
    m.emission_enabled = true
    m.emission = tracer_color
    m.emission_energy_multiplier = 5.0
    t.material_override = m
    add_child(t)
    var origin := muzzle.global_transform.origin
    # fire from the weapon centre toward the muzzle node (works for +X and flipped -X)
    var dir := (origin - current_weapon.global_transform.origin).normalized()
    t.global_position = origin
    t.look_at(origin + dir, Vector3.UP)
    t.rotate_object_local(Vector3.RIGHT, PI / 2.0)
    var speed := 40.0
    var tw := create_tween()
    tw.tween_method(func(pp):
        if is_instance_valid(t):
            t.global_position = origin + dir * speed * pp
            var mm := t.material_override as StandardMaterial3D
            mm.emission_energy_multiplier = 5.0 * (1.0 - pp)
    , 0.0, 1.0, 0.5)
    tw.tween_callback(func(): if is_instance_valid(t): t.queue_free())

# ── helpers ──────────────────────────────────────────────────────────────────
func _find(node: Node, klass: String) -> Node:
    if node.is_class(klass):
        return node
    for c in node.get_children():
        var r := _find(c, klass)
        if r != null:
            return r
    return null

func _v3(a) -> Vector3:
    return Vector3(a[0], a[1], a[2])

func _color(arr) -> Color:
    return Color(arr[0], arr[1], arr[2])
