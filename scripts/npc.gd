class_name Quartermaster
extends Node3D
## Warden — the station quartermaster (melee character, no gun). Stands at the supply alcove;
## detects when the player is near so the HUD can offer "talk". The chat brain lives in the HUD.

signal range_changed(in_range: bool)

const NPC_NAME := "WARDEN"
const PERSONA := "You are Warden, the gruff battle-hardened quartermaster of Outpost Vostok, an orbital station overrun by infected, aliens and rogue cyber enforcers during a dusk siege. You issue the operator their loadout and bark terse, practical advice. The three loadouts: SOLDIER (balanced full-auto rifle), VANGUARD (hard-hitting semi-auto pistol), SPECTER (devastating plasma lance). A reaver boss breaks through around wave 8. Reply in 1-2 short, in-character sentences, under 40 words. Never break character, never mention being an AI, use only plain ASCII punctuation."

var _rig: MeshyCharacterRig
var _in_range := false

func _ready() -> void:
    _rig = MeshyCharacterRig.new()
    add_child(_rig)
    var ch := (load("res://models/warden.glb") as PackedScene).instantiate() as Node3D
    _rig.setup(ch)
    _rig.play("idle")
    var area := Area3D.new()
    area.collision_layer = 8     # layer 4 = triggers/NPC
    area.collision_mask = 2      # detect the player (layer 2)
    area.monitoring = true
    var cs := CollisionShape3D.new()
    var sp := SphereShape3D.new()
    sp.radius = 4.2
    cs.shape = sp
    cs.position.y = 1.0
    area.add_child(cs)
    add_child(area)
    area.body_entered.connect(_on_enter)
    area.body_exited.connect(_on_exit)
    # a small beacon so the player can find the quartermaster
    var beacon := OmniLight3D.new()
    beacon.light_color = Color(0.4, 0.9, 1.0)
    beacon.light_energy = 2.0
    beacon.omni_range = 6.0
    beacon.position = Vector3(0, 2.6, 0)
    add_child(beacon)

func _on_enter(body: Node) -> void:
    if body.is_in_group("player"):
        _in_range = true
        emit_signal("range_changed", true)

func _on_exit(body: Node) -> void:
    if body.is_in_group("player"):
        _in_range = false
        emit_signal("range_changed", false)

func in_range() -> bool:
    return _in_range

func idle_pose() -> void:
    if _rig != null and _rig.current_clip != "idle":
        _rig.play("idle")
