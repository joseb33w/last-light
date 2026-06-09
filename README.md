# Last Light

A third-person **survival-horror** built in **Godot 4.6.3** and exported to **HTML5/WebGL2**, made to
be played in a phone browser (Safari / Chrome / Firefox, mobile + desktop). You are stranded at an
abandoned rural bus stop beside a cracked road. A real photographic sky slowly darkens from golden
dusk into night — and when the dark comes, the dead crawl out of it. **Keep the campfire alive and
survive until dawn.**

> This is a real Godot project (GDScript, `project.godot`, scenes, a web export preset) — not a
> web/JS/Canvas or three.js app.

## Play

▶ **Live preview:** open the preview link from the pull request (it deploys the web build).

- **Move** with the on-screen joystick (left) or **WASD / arrows**.
- **Look** by dragging the right side of the screen.
- **ATTACK** (right button / `J` / `Space`) — swing your axe. There's aim-assist so taps connect.
- **FEED** (button / `E` / `F`) — when you're near the fire and carrying wood, feed the flames.
- **Scavenge wood** by walking into the glowing piles around the camp (they respawn).

### Goal
The fire's **fuel** ticks down (faster as night deepens). If it goes out, the dark wins. As night
falls, skeletons rise from the ground and lurch toward your camp — cut them down. They are **slower
and easier to kill inside the firelight**, and burn if they get too close to the flames. Hold out
until the **DAWN** meter fills and you win.

## How it looks (committed art direction)
Atmospheric realistic survival-horror:
- **Real photographic HDRI sky** that crossfades golden dusk → starry night (custom sky shader with
  the HDR brightness-fix encoding).
- **PBR-textured** ground and a cracked asphalt road (albedo + normal + roughness).
- A **realistic survival prop set** — campfire, road barriers, message board, brick pile, rusted
  control box, cable reel, and a rural bus stop — plus a dark treeline and scattered rocks in fog.
- **Dynamic flickering firelight** (animated `OmniLight3D` + soft additive glow + flame/ember particles).
- Rigged, animated **Knight** hero (axe + shield) and **KayKit Skeleton** enemies that emerge from
  the ground on spawn. Juicy combat: hit-flash, blood/impact particles, knockback, screen shake.

## Build it yourself

Requires **Godot 4.6.3** (Compatibility/OpenGL renderer) with the **web export templates** installed.

```bash
./fetch_assets.sh          # download the CC0 models, skies, and PBR textures (not committed)
# then open the project in Godot 4.6.3 (it auto-imports), or headless:
godot --headless --path . --import
godot --headless --path . --export-release "Web" out/index.html
```

Serve `out/` over HTTP (the build is **single-threaded `nothreads`**, so it needs no COOP/COEP
headers and runs on any static host). Open `index.html`.

### Project layout
```
project.godot              # Compatibility renderer, nothreads web preset, input map, autoload
export_presets.cfg         # "Web" preset (thread_support=false, mobile head_include)
scenes/Main.tscn           # entry scene -> scripts/main.gd
scripts/
  main.gd                  # orchestrator: day/night cycle, wave spawning, win/lose
  world_builder.gd         # ground/road (PBR), props, dressing, sky, sun, fog
  player.gd                # CharacterBody3D hero: move, melee, AnimationTree, follow-cam
  enemy.gd                 # skeleton: rise-from-ground, chase, attack, hit-flash, death
  fire.gd                  # campfire fuel + flame/ember particles + flickering light
  wood_pickup.gd           # glowing respawning scavenge spots
  hud.gd                   # responsive custom touch HUD (joystick, buttons, meters, overlays)
  G.gd                     # autoload input/event bus
shaders/sky_daynight.gdshader   # dual-panorama dusk->night crossfade sky
test/Test.tscn             # headless logic checks (clips, facing, combat, triggers, fire-out)
fetch_assets.sh            # downloads the CC0 art
```

## Credits
All art is **CC0**: KayKit (Kay Lousberg), Kenney, Quaternius, ambientCG, Poly Haven, and a CC0
realistic survival prop set. No attribution required; credit given gladly.
