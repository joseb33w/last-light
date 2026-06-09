extends Node
## Headless targeted logic checks, run as a normal scene so autoloads (G) resolve first.
## Reads REAL state deltas — no tautologies. Run:  godot --headless res://test/Test.tscn

var _pass := 0
var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("PASS  ", name, ("  (" + detail + ")") if detail != "" else "")
	else:
		_fail += 1
		print("FAIL  ", name, ("  (" + detail + ")") if detail != "" else "")

func _step(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame

func _ap_of(node: Node) -> AnimationPlayer:
	return node.find_child("AnimationPlayer", true, false)

func _ready() -> void:
	await _run()

func _run() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await _step(4)

	var player: Player = main._player
	var fire: Campfire = main._fire
	var g: Node = get_node("/root/G")
	var scene_root: Node = get_tree().current_scene

	var pap := _ap_of(player)
	var pclips := ["Idle_A", "Walking_C", "Running_A", "Melee_1H_Attack_Slice_Diagonal", "Hit_A", "Death_A", "PickUp"]
	var pall := pap != null
	for c: String in pclips:
		if pap == null or not pap.has_animation(c):
			pall = false
	_ok("player clips resolve", pall)

	player.set_physics_process(true)
	g.move_vec = Vector2(0, 1)
	var z0 := player.global_position.z
	await _step(30)
	var z1 := player.global_position.z
	var vyaw := player._model.rotation.y
	var fdir := Vector3(sin(vyaw), 0, cos(vyaw))
	var vel := Vector3(player.velocity.x, 0, player.velocity.z)
	var facing_dot := fdir.dot(vel.normalized()) if vel.length() > 0.05 else 0.0
	_ok("player moves on forward input", absf(z1 - z0) > 0.4, "dz=%.2f" % (z1 - z0))
	_ok("hero faces travel direction (no moonwalk)", facing_dot > 0.6, "dot=%.2f" % facing_dot)
	g.move_vec = Vector2.ZERO
	await _step(8)

	var e1 := _make_enemy(main, fire, player.global_position + Vector3(0, 0, 1.6))
	e1._state = Enemy.St.CHASE
	e1._model.position.y = 0.0
	await _step(2)
	var hp_before := e1.health
	var parts_before := _count_particles(scene_root)
	player._try_attack()
	await _step(34)
	var hp_after := e1.health
	var parts_after := _count_particles(scene_root)
	_ok("melee reduces enemy hp", hp_after < hp_before, "hp %.0f -> %.0f" % [hp_before, hp_after])
	_ok("melee spawns impact particles", parts_after > parts_before, "parts %d -> %d" % [parts_before, parts_after])
	if is_instance_valid(e1):
		e1.queue_free()
	await _step(2)

	var e2 := _make_enemy(main, fire, Vector3(0, 0, 20))
	e2._state = Enemy.St.CHASE
	e2._model.position.y = 0.0
	var d0 := e2.global_position.distance_to(fire.global_position)
	await _step(120)
	var d1 := e2.global_position.distance_to(fire.global_position)
	_ok("enemy lurches toward the camp", d1 < d0 - 1.0, "dist %.1f -> %.1f" % [d0, d1])
	if is_instance_valid(e2):
		e2.queue_free()
	await _step(2)

	var hp_p0 := player.health
	var e3 := _make_enemy(main, fire, player.global_position + Vector3(0.0, 0, 1.1))
	e3._state = Enemy.St.CHASE
	e3._model.position.y = 0.0
	await _step(80)
	_ok("enemy attack damages player", player.health < hp_p0, "hp %.0f -> %.0f" % [hp_p0, player.health])
	if is_instance_valid(e3):
		e3.queue_free()
	await _step(2)
	player.health = Player.MAX_HEALTH

	var wood0: int = main._wood
	var pt: Vector3 = main._builder.pickup_points[0]
	player.global_position = pt
	await _step(6)
	_ok("walking into a glowing pile scavenges wood", main._wood > wood0, "wood %d -> %d" % [wood0, main._wood])

	main._running = true
	main._wood = 3
	player.global_position = fire.global_position + Vector3(0, 0, 2.0)
	await _step(2)
	var fuel0 := fire.fuel
	main._on_feed()
	_ok("feeding the fire raises fuel + spends wood", fire.fuel > fuel0 and main._wood == 2, "fuel %.0f -> %.0f, wood=%d" % [fuel0, fire.fuel, main._wood])

	fire.fuel = 0.04
	fire.is_lit = true
	fire.tick(0.2)
	await _step(2)
	_ok("fire going out triggers game over", main._ended and main._hud.mode == HUD.Mode.OVER)

	_ok("prop colliders derived from mesh (not a fixed constant)", _check_collider(main))

	print("==== RESULT pass=%d fail=%d ====" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)

func _make_enemy(main: Node, fire: Campfire, pos: Vector3) -> Enemy:
	var e := Enemy.new()
	e.variant = "minion"
	e.max_health = 56.0
	e.fire_ref = fire
	main._world.add_child(e)
	e.global_position = pos
	return e

func _count_particles(n: Node) -> int:
	var c := 0
	for child in n.get_children():
		if child is CPUParticles3D:
			c += 1
		c += _count_particles(child)
	return c

func _check_collider(main: Node) -> bool:
	for body: StaticBody3D in main.find_children("*", "StaticBody3D", true, false):
		var parent := body.get_parent() as Node3D
		if parent == null or parent.name == "World":
			continue
		var cols := body.find_children("*", "CollisionShape3D", false, false)
		if cols.is_empty():
			continue
		var col := cols[0] as CollisionShape3D
		if col == null or not (col.shape is BoxShape3D):
			continue
		var box := col.shape as BoxShape3D
		var aabb := AABB()
		var first := true
		for m: MeshInstance3D in parent.find_children("*", "MeshInstance3D", true, false):
			if m.mesh == null:
				continue
			var a: AABB = m.transform * m.get_aabb()
			if first:
				aabb = a; first = false
			else:
				aabb = aabb.merge(a)
		if first:
			continue
		var msz: Vector3 = aabb.size * parent.scale
		if msz.x > 0.1 and absf(box.size.x - msz.x) / msz.x < 0.6:
			return true
	return false
