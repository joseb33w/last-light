// Outpost Vostok - Supabase leaderboard bridge (loaded by the Godot web export head_include).
// GDScript (G.gd) sets window globals and calls these; results are written back to window
// globals that GDScript polls. Credentials are injected at build time (placeholder swap).
(function () {
  var SUPABASE_URL = "__SUPABASE_URL__";
  var SUPABASE_ANON_KEY = "__SUPABASE_ANON_KEY__";
  var TABLE = "__LB_TABLE__";
  var client = null;

  function ready() {
    if (client) return client;
    if (!window.supabase || !window.supabase.createClient) return null;
    client = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { persistSession: false }
    });
    return client;
  }

  window.gogiSubmitScore = function () {
    window.__gogi_lb_submit = "pending";
    var c = ready();
    var p = window.__gogi_lb_payload;
    if (!c || !p) { window.__gogi_lb_submit = "error"; return; }
    c.from(TABLE).insert({
      user_id: String(p.user_id || "anon").slice(0, 64),
      name: String(p.name || "OPERATOR").slice(0, 24),
      score: Math.max(0, Math.min(999999999, p.score | 0)),
      wave: Math.max(1, Math.min(999, p.wave | 0)),
      character: String(p.character || "soldier").slice(0, 16)
    }).then(function (res) {
      window.__gogi_lb_submit = res && res.error ? ("error:" + res.error.message) : "ok";
    }).catch(function (e) {
      window.__gogi_lb_submit = "error:" + e;
    });
  };

  window.gogiFetchTop = function () {
    window.__gogi_lb_top = "pending";
    var c = ready();
    if (!c) { window.__gogi_lb_top = "error"; return; }
    c.from(TABLE).select("name,score,wave,character").order("score", { ascending: false }).limit(10)
      .then(function (res) {
        if (res && res.error) { window.__gogi_lb_top = "error"; return; }
        window.__gogi_lb_top = JSON.stringify(res && res.data ? res.data : []);
      }).catch(function () {
        window.__gogi_lb_top = "error";
      });
  };
})();
