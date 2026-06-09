class_name HUD
extends Control
## Fully custom-drawn, fully responsive touch HUD: floating joystick (left), attack + feed
## buttons (right), drag-look (right side), top meters (health / fire fuel / dawn), wood + phase
## readouts, tap-to-start, win + game-over overlays. Multitouch via finger-index tracking.

enum Mode { START, PLAYING, WIN, OVER }

var mode: int = Mode.START

var _font: Font
var _hp := 100.0
var _hpm := 100.0
var _fuel := 60.0
var _fuelm := 100.0
var _wood := 0
var _phase := "Dusk"
var _dawn := 0.0          # 0..1 progress toward dawn
var _kills := 0
var _msg := ""
var _msg_t := 0.0
var _over_reason := ""
var _survived := ""

# live layout (recomputed each frame/input from the real viewport)
var _ui := 1.0
var _joy_c := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _joy_r := 90.0
var _atk_c := Vector2.ZERO
var _atk_r := 78.0
var _feed_c := Vector2.ZERO
var _feed_r := 54.0
var _restart := Rect2()
var _insets := {"top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0}

var _roles: Dictionary = {}      # finger id -> role string
var _joy_id := -9999

func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_read_insets()
	set_process(true)

func _read_insets() -> void:
	if not OS.has_feature("web"):
		return
	var js := "(()=>{const d=document.createElement('div');d.style.cssText='position:fixed;top:env(safe-area-inset-top);bottom:env(safe-area-inset-bottom);left:env(safe-area-inset-left);right:env(safe-area-inset-right)';document.body.appendChild(d);const r=getComputedStyle(d);const o={top:parseFloat(r.top)||0,bottom:parseFloat(r.bottom)||0,left:parseFloat(r.left)||0,right:parseFloat(r.right)||0};d.remove();return JSON.stringify(o);})()"
	var raw: String = str(JavaScriptBridge.eval(js, true))
	if raw == "" or raw == "null":
		return
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		_insets = parsed

func _layout() -> void:
	var s := size
	_ui = clampf(minf(s.x, s.y) / 430.0, 0.78, 1.7)
	var il := maxf(18.0, float(_insets.get("left", 0.0)) + 12.0)
	var ir := maxf(18.0, float(_insets.get("right", 0.0)) + 12.0)
	var ib := maxf(20.0, float(_insets.get("bottom", 0.0)) + 16.0)
	_joy_r = 86.0 * _ui
	_atk_r = 76.0 * _ui
	_feed_r = 50.0 * _ui
	_atk_c = Vector2(s.x - ir - _atk_r, s.y - ib - _atk_r)
	_feed_c = Vector2(_atk_c.x - _atk_r - _feed_r + 4.0 * _ui, _atk_c.y - _atk_r - _feed_r * 0.4)
	if _joy_id == -9999:
		_joy_c = Vector2(il + _joy_r, s.y - ib - _joy_r)
		_joy_knob = _joy_c

func _process(delta: float) -> void:
	# Force the HUD to the LIVE viewport every frame (defeats the web first-frame size race
	# + any stale base-size layout). This is what keeps the controls on-screen on a phone.
	var vp := get_viewport().get_visible_rect().size
	if size != vp:
		size = vp
		position = Vector2.ZERO
	if _msg_t > 0.0:
		_msg_t -= delta
	queue_redraw()

# ----------------------------------------------------------------- public API
func set_stats(hp: float, hpm: float, fuel: float, fuelm: float, wood: int, phase: String, dawn: float, kills: int) -> void:
	_hp = hp; _hpm = hpm; _fuel = fuel; _fuelm = fuelm
	_wood = wood; _phase = phase; _dawn = dawn; _kills = kills

func flash_message(text: String) -> void:
	_msg = text
	_msg_t = 2.6

func show_start() -> void:
	mode = Mode.START

func show_playing() -> void:
	mode = Mode.PLAYING

func show_win(survived: String) -> void:
	mode = Mode.WIN
	_survived = survived

func show_over(reason: String) -> void:
	mode = Mode.OVER
	_over_reason = reason

# ----------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_press(t.index, t.position)
		else:
			_release(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag(d.index, d.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(-1, mb.position)
			else:
				_release(-1)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _roles.has(-1):
			_drag(-1, mm.position)

func _press(id: int, pos: Vector2) -> void:
	_layout()
	if mode == Mode.START:
		G.start_pressed.emit()
		return
	if mode == Mode.WIN or mode == Mode.OVER:
		if _restart.has_point(pos):
			G.restart_pressed.emit()
		return
	if pos.distance_to(_atk_c) <= _atk_r:
		G.attack_pressed.emit()
		_roles[id] = "atk"
		return
	if pos.distance_to(_feed_c) <= _feed_r:
		G.feed_pressed.emit()
		_roles[id] = "feed"
		return
	if pos.x < size.x * 0.5:
		_roles[id] = "joy"
		_joy_id = id
		_joy_c = pos
		_joy_knob = pos
		_update_move()
	else:
		_roles[id] = "look"

func _drag(id: int, pos: Vector2) -> void:
	var r: String = _roles.get(id, "")
	if r == "joy":
		_joy_knob = pos
		_update_move()
	elif r == "look":
		# accumulate delta from previous drag position
		var key := "lk_%d" % id
		var prev: Vector2 = _roles.get(key, pos)
		G.look_delta += (pos - prev)
		_roles[key] = pos

func _release(id: int) -> void:
	var r: String = _roles.get(id, "")
	if r == "joy":
		_joy_id = -9999
		G.move_vec = Vector2.ZERO
	_roles.erase(id)
	_roles.erase("lk_%d" % id)

func _update_move() -> void:
	var off := _joy_knob - _joy_c
	if off.length() > _joy_r:
		off = off.normalized() * _joy_r
		_joy_knob = _joy_c + off
	G.move_vec = Vector2(off.x / _joy_r, -off.y / _joy_r)

# ----------------------------------------------------------------- drawing
func _draw() -> void:
	_layout()
	if mode == Mode.PLAYING:
		_draw_meters()
		_draw_controls()
	if _msg_t > 0.0 and mode == Mode.PLAYING:
		_draw_center_text(_msg, 0.16, Color(1.0, 0.86, 0.6), 30)
	match mode:
		Mode.START:
			_draw_overlay(Color(0.02, 0.02, 0.04, 0.72))
			_draw_center_text("LAST LIGHT", 0.34, Color(1.0, 0.62, 0.26), 64)
			_draw_center_text("Keep the fire alive until dawn.", 0.45, Color(0.85, 0.82, 0.8), 24)
			_draw_center_text("Joystick to move  -  ATTACK to swing  -  FEED the fire", 0.53, Color(0.7, 0.7, 0.74), 20)
			_draw_center_text("Drag the right side to look around", 0.585, Color(0.6, 0.6, 0.66), 19)
			_draw_pulse_prompt("TAP TO BEGIN", 0.72)
		Mode.WIN:
			_draw_overlay(Color(0.04, 0.03, 0.02, 0.78))
			_draw_center_text("YOU SURVIVED", 0.34, Color(1.0, 0.78, 0.34), 56)
			_draw_center_text("Dawn breaks. The last light held.", 0.44, Color(0.88, 0.85, 0.8), 24)
			_draw_center_text(_survived, 0.51, Color(0.75, 0.75, 0.8), 21)
			_draw_button_centered("PLAY AGAIN", 0.66)
		Mode.OVER:
			_draw_overlay(Color(0.05, 0.01, 0.01, 0.8))
			_draw_center_text("DARKNESS WINS", 0.34, Color(0.85, 0.2, 0.16), 56)
			_draw_center_text(_over_reason, 0.44, Color(0.86, 0.82, 0.8), 24)
			_draw_center_text(_survived, 0.51, Color(0.75, 0.72, 0.74), 21)
			_draw_button_centered("TRY AGAIN", 0.66)

func _draw_meters() -> void:
	var pad := maxf(16.0, float(_insets.get("left", 0.0)) + 14.0)
	var top := maxf(14.0, float(_insets.get("top", 0.0)) + 12.0)
	var bw := minf(size.x * 0.5, 360.0 * _ui)
	var bh := 18.0 * _ui
	var gap := 9.0 * _ui
	var fs := int(15 * _ui)
	# dark backing panel so the readouts are legible over a bright dusk or dark night
	var panel := Rect2(pad - 10, top - 10, bw + 20, (bh + gap) * 3 + 14)
	draw_rect(panel, Color(0, 0, 0, 0.42))
	# health
	_bar(Vector2(pad, top), Vector2(bw, bh), _hp / maxf(1.0, _hpm), Color(0.16, 0.05, 0.05, 0.92), Color(0.85, 0.22, 0.2))
	_shadow_text(Vector2(pad + 8, top + bh * 0.5 + fs * 0.35), "HEALTH", fs, Color(1, 1, 1, 0.95))
	# fuel
	var y2 := top + bh + gap
	var fr := _fuel / maxf(1.0, _fuelm)
	var fc := Color(1.0, 0.6, 0.2)
	if fr < 0.25:
		fc = Color(1.0, 0.3, 0.12)
	_bar(Vector2(pad, y2), Vector2(bw, bh), fr, Color(0.12, 0.08, 0.03, 0.92), fc)
	_shadow_text(Vector2(pad + 8, y2 + bh * 0.5 + fs * 0.35), "FIRE FUEL", fs, Color(1, 1, 1, 0.95))
	# dawn progress
	var y3 := y2 + bh + gap
	_bar(Vector2(pad, y3), Vector2(bw, bh), _dawn, Color(0.04, 0.06, 0.12, 0.92), Color(0.45, 0.62, 0.95))
	_shadow_text(Vector2(pad + 8, y3 + bh * 0.5 + fs * 0.35), "%s  -  DAWN" % _phase.to_upper(), fs, Color(1, 1, 1, 0.95))
	# wood + kills, top-right
	var tr := size.x - maxf(16.0, float(_insets.get("right", 0.0)) + 14.0)
	_shadow_text_right(Vector2(tr, top + 20 * _ui), "WOOD  %d" % _wood, int(21 * _ui), Color(1.0, 0.82, 0.4))
	_shadow_text_right(Vector2(tr, top + 44 * _ui), "SLAIN  %d" % _kills, int(16 * _ui), Color(0.85, 0.85, 0.9))

func _bar(pos: Vector2, dim: Vector2, ratio: float, bg: Color, fg: Color) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	draw_rect(Rect2(pos - Vector2(2, 2), dim + Vector2(4, 4)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(pos, dim), bg)
	draw_rect(Rect2(pos, Vector2(dim.x * ratio, dim.y)), fg)
	draw_rect(Rect2(pos, dim), Color(1, 1, 1, 0.25), false, 1.5)

func _draw_controls() -> void:
	# joystick (high-contrast: dark halo + bright outline so it reads on any background)
	var active := _joy_id != -9999
	draw_circle(_joy_c, _joy_r + 4.0, Color(0, 0, 0, 0.30))
	draw_circle(_joy_c, _joy_r, Color(0.1, 0.1, 0.14, 0.34 if active else 0.24))
	draw_arc(_joy_c, _joy_r, 0, TAU, 48, Color(1, 1, 1, 0.85), 3.5 * _ui)
	draw_circle(_joy_knob, _joy_r * 0.44, Color(1.0, 0.78, 0.36, 0.85))
	draw_arc(_joy_knob, _joy_r * 0.44, 0, TAU, 32, Color(1, 1, 1, 0.95), 2.5 * _ui)
	# attack button
	draw_circle(_atk_c, _atk_r + 4.0, Color(0, 0, 0, 0.3))
	draw_circle(_atk_c, _atk_r, Color(0.66, 0.14, 0.1, 0.82))
	draw_arc(_atk_c, _atk_r, 0, TAU, 48, Color(1.0, 0.7, 0.55, 0.95), 4.0 * _ui)
	_shadow_text_centered(_atk_c, "ATTACK", int(20 * _ui), Color(1, 0.97, 0.92))
	# feed button
	draw_circle(_feed_c, _feed_r + 3.0, Color(0, 0, 0, 0.3))
	draw_circle(_feed_c, _feed_r, Color(0.82, 0.46, 0.1, 0.82))
	draw_arc(_feed_c, _feed_r, 0, TAU, 40, Color(1.0, 0.85, 0.5, 0.95), 3.5 * _ui)
	_shadow_text_centered(_feed_c, "FEED", int(17 * _ui), Color(1, 0.98, 0.92))

func _draw_overlay(c: Color) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), c)

func _draw_center_text(text: String, y_frac: float, c: Color, base_size: int) -> void:
	var fs := int(base_size * _ui)
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(size.x * 0.5 - w * 0.5, size.y * y_frac)
	draw_string(_font, p + Vector2(2, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7))
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)

func _draw_pulse_prompt(text: String, y_frac: float) -> void:
	var a := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 380.0)
	_draw_center_text(text, y_frac, Color(1.0, 0.86, 0.5, a), 30)

func _draw_button_centered(text: String, y_frac: float) -> void:
	var fs := int(26 * _ui)
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var bw := tw + 60 * _ui
	var bh := 64.0 * _ui
	_restart = Rect2(size.x * 0.5 - bw * 0.5, size.y * y_frac, bw, bh)
	draw_rect(_restart, Color(0.8, 0.4, 0.14, 0.9))
	draw_rect(_restart, Color(1, 1, 1, 0.8), false, 2.5)
	draw_string(_font, Vector2(_restart.position.x + 30 * _ui, _restart.position.y + bh * 0.62), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))

func _shadow_text(pos: Vector2, text: String, fs: int, c: Color) -> void:
	draw_string(_font, pos + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)

func _shadow_text_right(pos: Vector2, text: String, fs: int, c: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_shadow_text(Vector2(pos.x - w, pos.y), text, fs, c)

func _shadow_text_centered(c_pos: Vector2, text: String, fs: int, c: Color) -> void:
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	_shadow_text(Vector2(c_pos.x - sz.x * 0.5, c_pos.y + sz.y * 0.32), text, fs, c)
