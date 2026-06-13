# Outpost Vostok

A realistic third-person **wave-survival sci-fi shooter** built in **Godot 4.6.3**, exported to the
web (Compatibility / WebGL2, single-threaded `nothreads`) and tuned to run in mobile and desktop
browsers. Hold a besieged dusk orbital station against escalating waves of the infected, aliens and
rogue cyber enforcers — and the **reaver boss** that breaks through at wave 8.

## Play
- **Desktop:** WASD move · mouse look · left-click fire · right-click ADS · `R` reload · `Shift` sprint · `E` talk.
- **Mobile:** left thumb-stick to move · drag the right side to look · on-screen **FIRE / ADS / RLD** buttons · **TALK** when near the Warden.
- Pick one of three operators at deploy, survive the waves, talk to the **Warden** quartermaster between
  waves to resupply, and post your run to the global **top-10 leaderboard**.

## Features
- **Realistic roster via the MeshyCharacterRig** — aim-down-sights, recoil firing (muzzle flash + tracer),
  and animated magazine reloads:
  - **Heroes (switchable):** Soldier (full-auto rifle), Vanguard (semi-auto pistol), Specter (plasma lance).
  - **Enemies:** infected & alien (melee), cyber enforcer (ranged arm-cannon), and the reaver boss.
  - **Warden** — the quartermaster (no gun), a talkable NPC.
- **Wave-survival loop** with escalating composition, per-wave speed scaling and a wave-8 boss.
- **Talkable quartermaster** powered by the shared NPC brain (live LLM dialogue, in-character).
- **Grim dusk industrial station** — metal floor/walls/cover, vostok set-dressing props, amber emergency
  lights, and an **HDRI sky** (with the Compatibility brightness fix, engine bug #83788).
- **Full HUD** — health, ammo, wave, score, crosshair, damage vignette, banners.
- **Persistent top-10 leaderboard** on Supabase.
- **Dual input** — keyboard + mouse AND touch, with responsive full-screen layout (portrait + landscape).

## Build
```bash
./fetch_assets.sh                 # download the CC0 art (not committed; see .gitignore)
# open in Godot 4.6.3 to auto-import, then:
godot --headless --path . --import
godot --headless --path . --export-release "Web" out/index.html
cp web/bridge.js out/bridge.js    # the leaderboard bridge sits next to the export
```
The Web preset is single-threaded (`thread_support=false`) and Compatibility-rendered so the build runs
in Safari / Chrome / Firefox on mobile and desktop with no special COOP/COEP headers.

## Backend (Supabase)
Leaderboard scores live in `public."<VITE_TABLE_PREFIX>_scores"` (RLS on; public read; bounded anonymous
insert; no anon update/delete). Configure `web/bridge.js` (or the build-time placeholder swap) with your
`VITE_SUPABASE_URL`, anon key, and `VITE_TABLE_PREFIX` — see `.env.example`.

## Tests
`test/Test.tscn` is a headless logic harness (run: `godot --headless --path . res://test/Test.tscn`) that
drives the real code paths and asserts movement facing (no moonwalk), fire→enemy-hp + impact FX, enemy
chase + damage, ranged fire, NPC chat panel, the HDRI shader sky, and full-screen HUD fill.
