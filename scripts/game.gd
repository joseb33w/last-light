extends Node
## Outpost Vostok — global state, character roster, input-map setup and the Supabase
## leaderboard JS bridge. Autoloaded as `G`.

const HEROES := ["soldier", "vanguard", "specter"]

# Per-character definitions. `cfg` is the MeshyCharacterRig config constant name.
const ROSTER := {
    "soldier": {
        "display": "SOLDIER", "weapon": "rifle", "cfg": "RIFLE", "role": "Assault Rifleman",
        "damage": 24.0, "rof": 0.11, "auto": true, "mag": 30, "reserve": 150, "spread": 1.4,
        "tint": Color(0.62, 0.70, 0.55), "blurb": "Balanced full-auto rifle. The default tip of the spear.",
    },
    "vanguard": {
        "display": "VANGUARD", "weapon": "pistol", "cfg": "PISTOL", "role": "Sidearm Specialist",
        "damage": 40.0, "rof": 0.20, "auto": false, "mag": 15, "reserve": 105, "spread": 0.8,
        "tint": Color(0.45, 0.58, 0.72), "blurb": "Hard-hitting semi-auto. Tap fire, pinpoint accuracy.",
    },
    "specter": {
        "display": "SPECTER", "weapon": "plasma", "cfg": "PLASMA", "role": "Plasma Lancer",
        "damage": 64.0, "rof": 0.30, "auto": true, "mag": 12, "reserve": 72, "spread": 0.5,
        "tint": Color(0.35, 0.78, 0.74), "blurb": "Searing plasma bolts. Slow cadence, devastating hits.",
    },
}

# Persistent across runs in a session.
var selected_char := "soldier"
var player_name := "OPERATOR"
var last_score := 0
var last_wave := 1

var _client_id := ""
var _insets_cache := {"top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0}

func _ready() -> void:
    _ensure_input()
    _client_id = _make_client_id()

func cfg_dict(char_id: String) -> Dictionary:
    var cfg_name: String = String(ROSTER[char_id]["cfg"])
    match cfg_name:
        "RIFLE": return MeshyCharacterRig.RIFLE
        "PISTOL": return MeshyCharacterRig.PISTOL
        "PLASMA": return MeshyCharacterRig.PLASMA
        "ARMCANNON": return MeshyCharacterRig.ARMCANNON
        _: return MeshyCharacterRig.RIFLE

# ── input map (built in code so kb+mouse works regardless of project.godot) ──
func _ensure_input() -> void:
    _act("move_up", [KEY_W, KEY_UP], [])
    _act("move_down", [KEY_S, KEY_DOWN], [])
    _act("move_left", [KEY_A, KEY_LEFT], [])
    _act("move_right", [KEY_D, KEY_RIGHT], [])
    _act("fire", [KEY_SPACE], [MOUSE_BUTTON_LEFT])
    _act("aim", [KEY_Q], [MOUSE_BUTTON_RIGHT])
    _act("reload", [KEY_R], [])
    _act("sprint", [KEY_SHIFT], [])
    _act("interact", [KEY_E, KEY_F], [])

func _act(act_name: String, keys: Array, mouse: Array) -> void:
    if not InputMap.has_action(act_name):
        InputMap.add_action(act_name)
    for k in keys:
        var ev := InputEventKey.new()
        ev.physical_keycode = k
        InputMap.action_add_event(act_name, ev)
    for b in mouse:
        var mb := InputEventMouseButton.new()
        mb.button_index = b
        InputMap.action_add_event(act_name, mb)

# ── safe-area (notch) insets via a CSS env() probe ──
func safe_insets() -> Dictionary:
    if not OS.has_feature("web"):
        return _insets_cache
    var js := "(function(){var d=document.createElement('div');d.style.cssText='position:fixed;top:env(safe-area-inset-top);bottom:env(safe-area-inset-bottom);left:env(safe-area-inset-left);right:env(safe-area-inset-right)';document.body.appendChild(d);var r=getComputedStyle(d);var o={top:parseFloat(r.top)||0,bottom:parseFloat(r.bottom)||0,left:parseFloat(r.left)||0,right:parseFloat(r.right)||0};d.remove();return JSON.stringify(o);})()"
    var raw: String = str(JavaScriptBridge.eval(js, true))
    if raw == "":
        return _insets_cache
    var d: Variant = JSON.parse_string(raw)
    if d is Dictionary:
        _insets_cache = d
    return _insets_cache

# ── Supabase leaderboard bridge ──
func lb_submit(score_i: int, wave_i: int, char_id: String) -> void:
    if not OS.has_feature("web"):
        return
    var payload := {
        "name": player_name.substr(0, 24), "score": score_i, "wave": wave_i,
        "character": char_id, "user_id": _client_id,
    }
    var js := "window.__gogi_lb_payload=%s; if(window.gogiSubmitScore){window.gogiSubmitScore();}" % JSON.stringify(payload)
    JavaScriptBridge.eval(js, true)

func lb_fetch_top() -> void:
    if not OS.has_feature("web"):
        return
    JavaScriptBridge.eval("if(window.gogiFetchTop){window.gogiFetchTop();}", true)

# '' = not started, 'pending', 'error', or a JSON array string of {name,score,wave,character}
func lb_top_state() -> String:
    if not OS.has_feature("web"):
        return "nonweb"
    return str(JavaScriptBridge.eval("window.__gogi_lb_top || ''", true))

func lb_parse_top(s: String) -> Array:
    var v: Variant = JSON.parse_string(s)
    if v is Array:
        return v
    return []

func _make_client_id() -> String:
    if OS.has_feature("web"):
        var got: String = str(JavaScriptBridge.eval("(function(){try{var k='gogi_ov_id';var v=localStorage.getItem(k);if(!v){v=(crypto.randomUUID?crypto.randomUUID():('ov'+Date.now()+Math.random()));localStorage.setItem(k,v);}return v;}catch(e){return '';}})()", true))
        if got != "":
            return got
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    return "ov-%d-%d" % [Time.get_unix_time_from_system(), rng.randi()]
