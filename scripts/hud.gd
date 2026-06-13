class_name HUD
extends Control
## Full HUD + UI: health/ammo/wave/score, crosshair, on-screen touch controls (joystick +
## fire/aim/reload/interact + drag-look), title/character-select, intermission, game-over +
## top-10 leaderboard, the quartermaster chat panel, and transient banners. Responsive: all
## layout is rebuilt from the live viewport size on every resize.

signal start_pressed
signal next_wave_pressed
signal retry_pressed
signal interact_pressed
signal char_selected(char_id: String)
signal chat_close_pressed

const AMBER := Color(1.0, 0.62, 0.25)
const CYAN := Color(0.45, 0.85, 1.0)
const RED := Color(0.95, 0.30, 0.25)
const PANEL_BG := Color(0.05, 0.06, 0.09, 0.92)

# live input state read by main each frame
var move_vector := Vector2.ZERO
var fire_held := false
var aim_held := false
var look_delta := Vector2.ZERO

var _persona := ""
var _touch := false

# ── nodes ──
var _crosshair: Control
var _hp_bar: ProgressBar
var _hp_label: Label
var _char_label: Label
var _wave_label: Label
var _score_label: Label
var _ammo_label: Label
var _talk_prompt: Label
var _banner: Label
var _vignette: ColorRect

var _joy_base: Control
var _joy_knob: Control
var _btn_fire: Button
var _btn_aim: Button
var _btn_reload: Button
var _btn_interact: Button

var _title: Control
var _name_edit: LineEdit
var _char_cards: Dictionary = {}
var _sel_char := "soldier"

var _inter: Control
var _inter_label: Label

var _over: Control
var _over_score: Label
var _over_list: VBoxContainer

var _chat: Control
var _chat_log: VBoxContainer
var _chat_scroll: ScrollContainer
var _chat_edit: LineEdit
var _chat_send: Button
var _chat_think: Label
var _chat_name: Label
var _http: HTTPRequest
var _chat_busy := false
var _msgs: Array = []
var _think_tw: Tween

var _joy_touch := -1
var _look_touch := -1
var _joy_center := Vector2.ZERO

func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _touch = _detect_touch()
    _build_play_hud()
    _build_touch_controls()
    _build_title()
    _build_inter()
    _build_over()
    _build_chat()
    _http = HTTPRequest.new()
    add_child(_http)
    _http.request_completed.connect(_on_chat_reply)
    get_viewport().size_changed.connect(_relayout)
    call_deferred("_relayout")

func set_persona(p: String) -> void:
    _persona = p

# ════════════════════════════ PLAY HUD ════════════════════════════
func _build_play_hud() -> void:
    _vignette = ColorRect.new()
    _vignette.color = Color(0.8, 0.05, 0.05, 0.0)
    _vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_vignette)

    var hp_panel := _panel()
    add_child(hp_panel)
    hp_panel.name = "HpPanel"
    _char_label = _mk_label("SOLDIER", 16, AMBER)
    hp_panel.add_child(_char_label)
    _char_label.position = Vector2(14, 8)
    _hp_bar = ProgressBar.new()
    _hp_bar.min_value = 0
    _hp_bar.max_value = 120
    _hp_bar.value = 120
    _hp_bar.show_percentage = false
    _hp_bar.custom_minimum_size = Vector2(210, 20)
    _hp_bar.position = Vector2(14, 34)
    _style_bar(_hp_bar, RED)
    hp_panel.add_child(_hp_bar)
    _hp_label = _mk_label("120 / 120", 13, Color.WHITE)
    hp_panel.add_child(_hp_label)
    _hp_label.position = Vector2(20, 35)

    var info_panel := _panel()
    add_child(info_panel)
    info_panel.name = "InfoPanel"
    _wave_label = _mk_label("WAVE 1", 18, CYAN)
    info_panel.add_child(_wave_label)
    _wave_label.position = Vector2(14, 8)
    _score_label = _mk_label("SCORE 0", 15, Color.WHITE)
    info_panel.add_child(_score_label)
    _score_label.position = Vector2(14, 36)

    var ammo_panel := _panel()
    add_child(ammo_panel)
    ammo_panel.name = "AmmoPanel"
    _ammo_label = _mk_label("30 / 150", 24, AMBER)
    ammo_panel.add_child(_ammo_label)
    _ammo_label.position = Vector2(16, 10)

    _crosshair = Control.new()
    _crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _crosshair.custom_minimum_size = Vector2(40, 40)
    add_child(_crosshair)
    _crosshair.draw.connect(_draw_crosshair)

    _talk_prompt = _mk_label("[E] / [TALK] - speak with WARDEN", 16, CYAN)
    _talk_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _talk_prompt.visible = false
    add_child(_talk_prompt)

    _banner = _mk_label("", 40, AMBER)
    _banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _banner.visible = false
    add_child(_banner)

func _draw_crosshair() -> void:
    var c := Vector2(20, 20)
    var col := Color(1, 1, 1, 0.85)
    var gap := 6.0
    var ln := 9.0
    var w := 2.0
    _crosshair.draw_line(c + Vector2(-gap - ln, 0), c + Vector2(-gap, 0), col, w)
    _crosshair.draw_line(c + Vector2(gap, 0), c + Vector2(gap + ln, 0), col, w)
    _crosshair.draw_line(c + Vector2(0, -gap - ln), c + Vector2(0, -gap), col, w)
    _crosshair.draw_line(c + Vector2(0, gap), c + Vector2(0, gap + ln), col, w)
    _crosshair.draw_circle(c, 1.5, AMBER)

# ════════════════════════════ TOUCH CONTROLS ════════════════════════════
func _build_touch_controls() -> void:
    _joy_base = _circle(120, Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.22))
    add_child(_joy_base)
    _joy_knob = _circle(54, Color(1, 1, 1, 0.22), AMBER)
    add_child(_joy_knob)

    _btn_fire = _mk_round_button("FIRE", RED)
    add_child(_btn_fire)
    _btn_fire.button_down.connect(func() -> void: fire_held = true)
    _btn_fire.button_up.connect(func() -> void: fire_held = false)

    _btn_aim = _mk_round_button("ADS", CYAN)
    add_child(_btn_aim)
    _btn_aim.button_down.connect(func() -> void: aim_held = true)
    _btn_aim.button_up.connect(func() -> void: aim_held = false)

    _btn_reload = _mk_round_button("RLD", AMBER)
    add_child(_btn_reload)
    _btn_reload.pressed.connect(func() -> void: Input.action_press("reload"); get_tree().create_timer(0.05).timeout.connect(func() -> void: Input.action_release("reload")))

    _btn_interact = _mk_round_button("TALK", CYAN)
    add_child(_btn_interact)
    _btn_interact.pressed.connect(func() -> void: emit_signal("interact_pressed"))
    _btn_interact.visible = false

    var show_touch := _touch
    for n in [_joy_base, _joy_knob, _btn_fire, _btn_aim, _btn_reload]:
        n.visible = false           # hidden until gameplay starts
        (n as CanvasItem).set_meta("touch_only", show_touch)

func _unhandled_input(event: InputEvent) -> void:
    if not _touch or not _joy_base.visible:
        return
    var vp := get_viewport().get_visible_rect().size
    if event is InputEventScreenTouch:
        var t := event as InputEventScreenTouch
        if t.pressed:
            if t.position.x < vp.x * 0.5:
                if _joy_touch == -1:
                    _joy_touch = t.index
                    _joy_center = t.position
                    _joy_base.position = t.position - _joy_base.size * 0.5
                    _joy_base.visible = true
            else:
                if _look_touch == -1 and not _over_button_rect(t.position):
                    _look_touch = t.index
        else:
            if t.index == _joy_touch:
                _joy_touch = -1
                move_vector = Vector2.ZERO
                _joy_knob.position = _joy_center - _joy_knob.size * 0.5
            elif t.index == _look_touch:
                _look_touch = -1
    elif event is InputEventScreenDrag:
        var d := event as InputEventScreenDrag
        if d.index == _joy_touch:
            var off := d.position - _joy_center
            var r := 60.0
            if off.length() > r:
                off = off.normalized() * r
            _joy_knob.position = _joy_center + off - _joy_knob.size * 0.5
            move_vector = Vector2(off.x / r, off.y / r)
        elif d.index == _look_touch:
            look_delta += d.relative

func _over_button_rect(p: Vector2) -> bool:
    for b in [_btn_fire, _btn_aim, _btn_reload, _btn_interact]:
        if b.visible and Rect2(b.position, b.size).has_point(p):
            return true
    return false

func consume_look() -> Vector2:
    var d := look_delta
    look_delta = Vector2.ZERO
    return d

# ════════════════════════════ TITLE / CHARACTER SELECT ════════════════════════════
func _build_title() -> void:
    _title = _fullscreen_panel()
    add_child(_title)
    var title := _mk_label("OUTPOST VOSTOK", 44, AMBER)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.name = "TitleText"
    _title.add_child(title)
    var sub := _mk_label("Hold the station. Survive the waves. The dusk belongs to the dead.", 16, Color(0.8, 0.8, 0.85))
    sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    sub.name = "SubText"
    _title.add_child(sub)

    for c in G.HEROES:
        var card := _make_char_card(c)
        _title.add_child(card)
        _char_cards[c] = card

    var name_row := _mk_label("CALLSIGN", 14, CYAN)
    name_row.name = "NameLabel"
    _title.add_child(name_row)
    _name_edit = LineEdit.new()
    _name_edit.text = G.player_name
    _name_edit.max_length = 16
    _name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _name_edit.custom_minimum_size = Vector2(260, 40)
    _name_edit.name = "NameEdit"
    _title.add_child(_name_edit)

    var start := _mk_big_button("DEPLOY")
    start.name = "StartBtn"
    _title.add_child(start)
    start.pressed.connect(_on_start)

    var hint := _mk_label("", 13, Color(0.7, 0.7, 0.75))
    hint.name = "HintText"
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _title.add_child(hint)
    if _touch:
        hint.text = "Left stick to move - drag right to look - FIRE / ADS / RLD buttons"
    else:
        hint.text = "WASD move - mouse look - L-click fire - R-click ADS - R reload - Shift sprint - E talk"
    _select_char(_sel_char)

func _make_char_card(c: String) -> Button:
    var d: Dictionary = G.ROSTER[c]
    var b := Button.new()
    b.custom_minimum_size = Vector2(220, 150)
    b.toggle_mode = true
    b.focus_mode = Control.FOCUS_NONE
    var txt := "%s\n%s\n\nDMG %d   ROF %.2f\nMAG %d   RES %d\n\n%s" % [
        String(d["display"]), String(d["role"]), int(d["damage"]), float(d["rof"]),
        int(d["mag"]), int(d["reserve"]), String(d["blurb"])]
    b.text = txt
    b.add_theme_font_size_override("font_size", 14)
    b.pressed.connect(func() -> void: _select_char(c))
    return b

func _select_char(c: String) -> void:
    _sel_char = c
    for k in _char_cards.keys():
        var card := _char_cards[k] as Button
        card.button_pressed = (k == c)
        var col: Color = AMBER if k == c else Color(0.5, 0.5, 0.55)
        card.add_theme_color_override("font_color", col)
    emit_signal("char_selected", c)

func _on_start() -> void:
    G.player_name = _name_edit.text.strip_edges()
    if G.player_name == "":
        G.player_name = "OPERATOR"
    emit_signal("start_pressed")

# ════════════════════════════ INTERMISSION ════════════════════════════
func _build_inter() -> void:
    # transparent overlay so the world stays visible (the player walks to the Warden)
    _inter = Control.new()
    _inter.set_anchors_preset(Control.PRESET_FULL_RECT)
    _inter.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_inter)
    _inter_label = _mk_label("WAVE CLEARED", 34, AMBER)
    _inter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _inter.add_child(_inter_label)
    var note := _mk_label("Ammo resupplied. Speak with the WARDEN, then push on.", 16, Color(0.85, 0.85, 0.9))
    note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    note.name = "InterNote"
    _inter.add_child(note)
    var nxt := _mk_big_button("NEXT WAVE")
    nxt.name = "NextBtn"
    _inter.add_child(nxt)
    nxt.pressed.connect(func() -> void: emit_signal("next_wave_pressed"))
    _inter.visible = false

# ════════════════════════════ GAME OVER + LEADERBOARD ════════════════════════════
func _build_over() -> void:
    _over = _fullscreen_panel()
    add_child(_over)
    var t := _mk_label("STATION LOST", 40, RED)
    t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    t.name = "OverTitle"
    _over.add_child(t)
    _over_score = _mk_label("", 18, AMBER)
    _over_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _over.add_child(_over_score)
    var lb := _mk_label("- TOP OPERATORS -", 16, CYAN)
    lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lb.name = "LbTitle"
    _over.add_child(lb)
    _over_list = VBoxContainer.new()
    _over_list.name = "LbList"
    _over.add_child(_over_list)
    var retry := _mk_big_button("REDEPLOY")
    retry.name = "RetryBtn"
    _over.add_child(retry)
    retry.pressed.connect(func() -> void: emit_signal("retry_pressed"))
    _over.visible = false

func set_top10(rows: Array) -> void:
    for ch in _over_list.get_children():
        ch.queue_free()
    if rows.is_empty():
        var l := _mk_label("(no scores yet - be the first)", 14, Color(0.7, 0.7, 0.7))
        _over_list.add_child(l)
        return
    var rank := 1
    for r in rows:
        if not (r is Dictionary):
            continue
        var nm := String(r.get("name", "???")).substr(0, 16)
        var sc := int(r.get("score", 0))
        var wv := int(r.get("wave", 1))
        var line := "%2d. %-16s %8d  (W%d)" % [rank, nm, sc, wv]
        var col: Color = AMBER if rank <= 3 else Color.WHITE
        var l := _mk_label(line, 15, col)
        _over_list.add_child(l)
        rank += 1

# ════════════════════════════ CHAT ════════════════════════════
func _build_chat() -> void:
    _chat = _fullscreen_panel(Color(0.03, 0.04, 0.06, 0.85))
    add_child(_chat)
    var box := PanelContainer.new()
    box.name = "ChatBox"
    var sb := StyleBoxFlat.new()
    sb.bg_color = PANEL_BG
    sb.set_corner_radius_all(10)
    sb.set_border_width_all(2)
    sb.border_color = CYAN
    sb.set_content_margin_all(14)
    box.add_theme_stylebox_override("panel", sb)
    _chat.add_child(box)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 8)
    box.add_child(v)
    _chat_name = _mk_label("WARDEN - QUARTERMASTER", 18, AMBER)
    v.add_child(_chat_name)
    _chat_scroll = ScrollContainer.new()
    _chat_scroll.custom_minimum_size = Vector2(420, 240)
    _chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    v.add_child(_chat_scroll)
    _chat_log = VBoxContainer.new()
    _chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _chat_log.add_theme_constant_override("separation", 6)
    _chat_scroll.add_child(_chat_log)
    _chat_think = _mk_label("", 15, CYAN)
    v.add_child(_chat_think)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    v.add_child(row)
    _chat_edit = LineEdit.new()
    _chat_edit.placeholder_text = "Ask the Warden..."
    _chat_edit.max_length = 160
    _chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _chat_edit.custom_minimum_size = Vector2(300, 40)
    row.add_child(_chat_edit)
    _chat_edit.text_submitted.connect(func(_t: String) -> void: _do_send())
    _chat_send = Button.new()
    _chat_send.text = "SEND"
    _chat_send.custom_minimum_size = Vector2(90, 40)
    row.add_child(_chat_send)
    _chat_send.pressed.connect(_do_send)
    var close := Button.new()
    close.text = "CLOSE [X]"
    close.custom_minimum_size = Vector2(120, 36)
    v.add_child(close)
    close.pressed.connect(func() -> void: emit_signal("chat_close_pressed"))
    _chat.visible = false

func open_chat() -> void:
    _chat.visible = true
    if _msgs.is_empty():
        _append_chat("WARDEN", "State your business, operator. Need a loadout brief or intel on what's clawing at the door?", AMBER)
    _chat_edit.grab_focus()

func close_chat() -> void:
    _chat.visible = false

func is_chat_open() -> bool:
    return _chat != null and _chat.visible

func _do_send() -> void:
    if _chat_busy:
        return
    var t := _chat_edit.text.strip_edges()
    if t == "":
        return
    _chat_edit.text = ""
    _append_chat("YOU", t, CYAN)
    _msgs.append({"role": "user", "content": t})
    while _msgs.size() > 12:
        _msgs.pop_front()
    _chat_busy = true
    _chat_send.disabled = true
    _start_thinking()
    var headers := ["Content-Type: application/json"]
    var payload := {"persona": _persona, "messages": _msgs}
    var err := _http.request("https://npc.myapping.com/chat", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
    if err != OK:
        _on_chat_reply(0, 0, [], PackedByteArray())

func _on_chat_reply(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
    _stop_thinking()
    _chat_busy = false
    _chat_send.disabled = false
    var reply := ""
    if code == 200:
        var data: Variant = JSON.parse_string(body.get_string_from_utf8())
        if data is Dictionary and data.has("reply"):
            reply = String(data["reply"])
    if reply.strip_edges() == "":
        reply = "... (static crackles) Hold the line, operator - comms are down."
    _msgs.append({"role": "assistant", "content": reply})
    while _msgs.size() > 12:
        _msgs.pop_front()
    _append_chat("WARDEN", reply, AMBER)

func _append_chat(who: String, text: String, col: Color) -> void:
    var l := _mk_label("%s:  %s" % [who, text], 15, col)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.custom_minimum_size = Vector2(400, 0)
    _chat_log.add_child(l)
    await get_tree().process_frame
    _chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)

func _start_thinking() -> void:
    _stop_thinking()
    _chat_think.text = "WARDEN is thinking."
    _think_tw = _chat_think.create_tween().set_loops()
    var dots := [".", "..", "..."]
    for d in dots:
        _think_tw.tween_callback(func() -> void: _chat_think.text = "WARDEN is thinking" + d)
        _think_tw.tween_interval(0.35)

func _stop_thinking() -> void:
    if _think_tw != null and _think_tw.is_valid():
        _think_tw.kill()
    _think_tw = null
    _chat_think.text = ""

# ════════════════════════════ STATE SETTERS ════════════════════════════
func set_health(hp: float, max_hp: float) -> void:
    _hp_bar.max_value = max_hp
    _hp_bar.value = hp
    _hp_label.text = "%d / %d" % [int(round(hp)), int(round(max_hp))]

func set_ammo(mag: int, reserve: int) -> void:
    _ammo_label.text = "%d / %d" % [mag, reserve]

func set_wave(w: int) -> void:
    _wave_label.text = "WAVE %d" % w

func set_score(s: int) -> void:
    _score_label.text = "SCORE %d" % s

func set_char_name(c: String) -> void:
    _char_label.text = String(G.ROSTER[c]["display"])

func show_talk_prompt(on: bool) -> void:
    _talk_prompt.visible = on
    if _touch:
        _btn_interact.visible = on and not _chat.visible and not _title.visible and not _over.visible

func flash_damage() -> void:
    var tw := _vignette.create_tween()
    _vignette.color = Color(0.8, 0.05, 0.05, 0.45)
    tw.tween_property(_vignette, "color:a", 0.0, 0.4)

func banner(text: String, col := AMBER) -> void:
    _banner.text = text
    _banner.add_theme_color_override("font_color", col)
    _banner.visible = true
    _banner.modulate.a = 1.0
    var tw := _banner.create_tween()
    tw.tween_interval(1.6)
    tw.tween_property(_banner, "modulate:a", 0.0, 0.8)
    tw.tween_callback(func() -> void: _banner.visible = false)

func show_title() -> void:
    _hide_all_panels()
    _title.visible = true
    _set_play_visible(false)

func show_intermission(wave_cleared: int) -> void:
    _title.visible = false
    _over.visible = false
    _chat.visible = false
    _set_play_visible(true)
    _inter_label.text = "WAVE %d CLEARED" % wave_cleared
    _inter.visible = true

func show_gameover(score: int, wave: int) -> void:
    _hide_all_panels()
    _over_score.text = "SCORE %d     REACHED WAVE %d" % [score, wave]
    _over.visible = true
    _set_play_visible(false)

func show_playing() -> void:
    _hide_all_panels()
    _set_play_visible(true)

func _hide_all_panels() -> void:
    _title.visible = false
    _inter.visible = false
    _over.visible = false
    _chat.visible = false

func _set_play_visible(on: bool) -> void:
    for n in [_crosshair, _ammo_label.get_parent(), _hp_bar.get_parent(), _wave_label.get_parent()]:
        (n as CanvasItem).visible = on
    if _touch:
        for n in [_joy_base, _joy_knob, _btn_fire, _btn_aim, _btn_reload]:
            (n as CanvasItem).visible = on
    if not on:
        _talk_prompt.visible = false
        _btn_interact.visible = false
        move_vector = Vector2.ZERO
        fire_held = false
        aim_held = false

# ════════════════════════════ LAYOUT ════════════════════════════
func _relayout() -> void:
    var vp := get_viewport().get_visible_rect().size
    position = Vector2.ZERO
    size = vp
    var ins := G.safe_insets()
    var top: float = maxf(12.0, float(ins.get("top", 0.0)))
    var bot: float = maxf(14.0, float(ins.get("bottom", 0.0)))
    var left: float = maxf(12.0, float(ins.get("left", 0.0)))
    var right: float = maxf(12.0, float(ins.get("right", 0.0)))

    _get_panel("HpPanel").position = Vector2(left, top)
    _get_panel("HpPanel").size = Vector2(238, 62)
    var info := _get_panel("InfoPanel")
    info.size = Vector2(168, 64)
    info.position = Vector2(vp.x - 168 - right, top)
    var ammo := _get_panel("AmmoPanel")
    ammo.size = Vector2(150, 54)
    ammo.position = Vector2(vp.x - 150 - right, vp.y - 54 - bot - (140 if _touch else 0))

    _crosshair.position = vp * 0.5 - Vector2(20, 20)
    _talk_prompt.position = Vector2(vp.x * 0.5 - 200, vp.y * 0.32)
    _talk_prompt.size = Vector2(400, 30)
    _banner.position = Vector2(0, vp.y * 0.30)
    _banner.size = Vector2(vp.x, 70)

    # touch controls
    var jb := 96.0
    _joy_center = Vector2(left + 110, vp.y - bot - 120)
    _joy_base.position = _joy_center - _joy_base.size * 0.5
    _joy_knob.position = _joy_center - _joy_knob.size * 0.5
    var bx := vp.x - right - 90
    var by := vp.y - bot - 90
    _btn_fire.position = Vector2(bx, by)
    _btn_aim.position = Vector2(bx - 96, by + 20)
    _btn_reload.position = Vector2(bx - 30, by - 96)
    _btn_interact.position = Vector2(vp.x * 0.5 - 45, vp.y * 0.40)

    _relayout_panel(_title, vp)
    _relayout_title(vp)
    _relayout_panel(_inter, vp)
    _relayout_inter(vp)
    _relayout_panel(_over, vp)
    _relayout_over(vp)
    _relayout_panel(_chat, vp)
    _relayout_chat(vp)
    _crosshair.queue_redraw()

func _relayout_panel(p: Control, vp: Vector2) -> void:
    p.position = Vector2.ZERO
    p.size = vp

func _relayout_title(vp: Vector2) -> void:
    var cx := vp.x * 0.5
    _node(_title, "TitleText").position = Vector2(cx - 400, vp.y * 0.08)
    _node(_title, "TitleText").size = Vector2(800, 60)
    _node(_title, "SubText").position = Vector2(cx - 400, vp.y * 0.08 + 60)
    _node(_title, "SubText").size = Vector2(800, 30)
    var n := G.HEROES.size()
    var cw := 220.0
    var gap := 18.0
    var total := n * cw + (n - 1) * gap
    var start_x := cx - total * 0.5
    var cy := vp.y * 0.30
    var i := 0
    for c in G.HEROES:
        var card := _char_cards[c] as Button
        card.position = Vector2(start_x + i * (cw + gap), cy)
        card.size = Vector2(cw, 150)
        i += 1
    _node(_title, "NameLabel").position = Vector2(cx - 130, cy + 170)
    _node(_title, "NameEdit").position = Vector2(cx - 130, cy + 192)
    _node(_title, "StartBtn").position = Vector2(cx - 130, cy + 250)
    _node(_title, "StartBtn").size = Vector2(260, 52)
    _node(_title, "HintText").position = Vector2(cx - 400, cy + 318)
    _node(_title, "HintText").size = Vector2(800, 26)

func _relayout_inter(vp: Vector2) -> void:
    var cx := vp.x * 0.5
    _inter_label.position = Vector2(cx - 300, vp.y * 0.34)
    _inter_label.size = Vector2(600, 44)
    _node(_inter, "InterNote").position = Vector2(cx - 350, vp.y * 0.34 + 50)
    _node(_inter, "InterNote").size = Vector2(700, 30)
    _node(_inter, "NextBtn").position = Vector2(cx - 130, vp.y * 0.34 + 110)
    _node(_inter, "NextBtn").size = Vector2(260, 52)

func _relayout_over(vp: Vector2) -> void:
    var cx := vp.x * 0.5
    _node(_over, "OverTitle").position = Vector2(cx - 400, vp.y * 0.08)
    _node(_over, "OverTitle").size = Vector2(800, 50)
    _over_score.position = Vector2(cx - 400, vp.y * 0.08 + 56)
    _over_score.size = Vector2(800, 26)
    _node(_over, "LbTitle").position = Vector2(cx - 400, vp.y * 0.20)
    _node(_over, "LbTitle").size = Vector2(800, 24)
    _over_list.position = Vector2(cx - 220, vp.y * 0.20 + 32)
    _over_list.size = Vector2(440, 320)
    _node(_over, "RetryBtn").position = Vector2(cx - 130, vp.y * 0.86)
    _node(_over, "RetryBtn").size = Vector2(260, 52)

func _relayout_chat(vp: Vector2) -> void:
    var box := _node(_chat, "ChatBox")
    var w: float = minf(520.0, vp.x - 30.0)
    box.position = Vector2(vp.x * 0.5 - w * 0.5, vp.y * 0.10)
    box.size = Vector2(w, 0)
    _chat_scroll.custom_minimum_size = Vector2(w - 40, minf(260.0, vp.y * 0.45))

# ════════════════════════════ WIDGET HELPERS ════════════════════════════
func _detect_touch() -> bool:
    if DisplayServer.is_touchscreen_available():
        return true
    if OS.has_feature("web"):
        return str(JavaScriptBridge.eval("(('ontouchstart' in window)||(navigator.maxTouchPoints>0))", true)) == "true"
    return false

func _mk_label(text: String, sz: int, col: Color) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", sz)
    l.add_theme_color_override("font_color", col)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return l

func _panel() -> Control:
    var p := PanelContainer.new()
    var sb := StyleBoxFlat.new()
    sb.bg_color = PANEL_BG
    sb.set_corner_radius_all(8)
    sb.set_border_width_all(1)
    sb.border_color = Color(1, 1, 1, 0.15)
    p.add_theme_stylebox_override("panel", sb)
    p.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return p

func _fullscreen_panel(bg := Color(0.02, 0.03, 0.05, 0.96)) -> Control:
    var p := ColorRect.new()
    p.color = bg
    p.set_anchors_preset(Control.PRESET_FULL_RECT)
    p.mouse_filter = Control.MOUSE_FILTER_STOP
    return p

func _style_bar(bar: ProgressBar, fill: Color) -> void:
    var bg := StyleBoxFlat.new()
    bg.bg_color = Color(0.1, 0.1, 0.12, 0.9)
    bg.set_corner_radius_all(4)
    var fg := StyleBoxFlat.new()
    fg.bg_color = fill
    fg.set_corner_radius_all(4)
    bar.add_theme_stylebox_override("background", bg)
    bar.add_theme_stylebox_override("fill", fg)

func _circle(diam: float, fill: Color, border: Color) -> Control:
    var c := Control.new()
    c.custom_minimum_size = Vector2(diam, diam)
    c.size = Vector2(diam, diam)
    c.mouse_filter = Control.MOUSE_FILTER_IGNORE
    c.set_meta("fill", fill)
    c.set_meta("border", border)
    c.set_meta("diam", diam)
    c.draw.connect(func() -> void:
        var ctr := Vector2(diam, diam) * 0.5
        c.draw_circle(ctr, diam * 0.5, fill)
        for a in range(0, 360, 12):
            var p0 := ctr + Vector2.RIGHT.rotated(deg_to_rad(a)) * (diam * 0.5 - 2)
            var p1 := ctr + Vector2.RIGHT.rotated(deg_to_rad(a + 6)) * (diam * 0.5 - 2)
            c.draw_line(p0, p1, border, 2.0))
    return c

func _mk_round_button(text: String, col: Color) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size = Vector2(80, 80)
    b.size = Vector2(80, 80)
    b.focus_mode = Control.FOCUS_NONE
    b.add_theme_font_size_override("font_size", 16)
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(col.r, col.g, col.b, 0.22)
    sb.set_corner_radius_all(40)
    sb.set_border_width_all(2)
    sb.border_color = col
    b.add_theme_stylebox_override("normal", sb)
    var sb2 := sb.duplicate() as StyleBoxFlat
    sb2.bg_color = Color(col.r, col.g, col.b, 0.45)
    b.add_theme_stylebox_override("pressed", sb2)
    b.add_theme_stylebox_override("hover", sb)
    return b

func _mk_big_button(text: String) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size = Vector2(260, 52)
    b.add_theme_font_size_override("font_size", 22)
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.25)
    sb.set_corner_radius_all(8)
    sb.set_border_width_all(2)
    sb.border_color = AMBER
    b.add_theme_stylebox_override("normal", sb)
    var sbh := sb.duplicate() as StyleBoxFlat
    sbh.bg_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.45)
    b.add_theme_stylebox_override("hover", sbh)
    b.add_theme_stylebox_override("pressed", sbh)
    return b

func _get_panel(pname: String) -> Control:
    return get_node(pname) as Control

func _node(root: Control, n: String) -> Control:
    return root.get_node(n) as Control
