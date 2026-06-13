# Outpost Vostok — build plan

## Goal
Ship "Outpost Vostok": a realistic 3rd-person wave-survival sci-fi shooter (Godot 4.6.3, mobile web,
gl_compatibility / nothreads). Spec-ops hero with ADS / recoil / reload, 3 switchable playable
characters, escalating enemy waves with a wave-8 boss, a talkable quartermaster NPC, a grim dusk
industrial station with an HDRI sky, a full HUD, an online top-10 Supabase leaderboard, and both
desktop (kb+mouse) and mobile (touch) controls.

## Files to touch
- `scripts/meshy_character_rig.gd` — the realistic MeshyCharacterRig (ADS/recoil/reload), from the asset lib.
- `shaders/hdri_sky.gdshader` — HDR-sky brightness fix (bug #83788) for the dusk industrial panorama.
- `scripts/game.gd` (autoload `G`) — roster defs, persistent state, input map setup, leaderboard JS-bridge polling.
- `scripts/world_builder.gd` — dusk industrial station: metal floor/walls/catwalks/crates + vostok props + lights + HDRI sky.
- `scripts/player.gd` — CharacterBody3D + rig: move/sprint, ADS, hitscan fire (recoil/muzzle/tracer/impact), reload, health.
- `scripts/enemy.gd` — melee (infected/alien), ranged (cyber enforcer), boss (reaver); chase AI + attacks + juice.
- `scripts/projectile.gd` — plasma bolt for ranged enemies.
- `scripts/npc.gd` — Warden quartermaster (no gun) talkable via the shared NPC brain.
- `scripts/hud.gd` — health/ammo/wave/score HUD, crosshair, touch controls, menus, chat panel, leaderboard.
- `scripts/main.gd` — orchestrator: states (title/play/dead), waves, camera, input routing, NPC, scoring.
- `web/bridge.js` — Supabase client for the leaderboard (anon key, injected at build).
- `scenes/Main.tscn` — code-driven root.
- `project.godot`, `export_presets.cfg` — name, autoload, SDK+bridge head_include.
- `.env` / `.env.example` — `VITE_TABLE_PREFIX`.
- `test/Test.gd` — headless logic gates (facing, combat delta, AI engage, chat contract, sky, layout).

## Backend (Supabase, shared project, per-app namespace)
- APP_PREFIX = `usr_nmexs7bytxq2_last_light`; table `public."usr_nmexs7bytxq2_last_light_scores"`.
- Public leaderboard: RLS on; SELECT `USING(true)` (public read); INSERT bounded `WITH CHECK` (no auth.uid
  requirement — anonymous arcade scores); no UPDATE/DELETE for anon (anti-tamper). Verified via REST.

## Verification approach
- Static pre-import scan (INFERENCE_ON_VARIANT, Node-member shadowing); clean `--import`.
- Headless logic test: rig clips resolve, W/S facing (no moonwalk), fire drops enemy hp + spawns impact,
  enemy chases + damages player, NPC chat contract + panel opens, sky is a shader/panorama sky, layout fills.
- Browser smoke verify (boot + canvas + clean console + frames) at portrait AND landscape.
- Backend REST verify (insert/read/negative) — done; preview deploy to R2.

## Out of scope
- Multiplayer (single-player wave survival). Authoritative anti-cheat leaderboard (anonymous arcade scores).
- Audio is generated/simple; real-device GPU/touch feel can't be exercised in-sandbox.
