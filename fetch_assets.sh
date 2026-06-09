#!/usr/bin/env bash
# Last Light — fetch the CC0 art assets (models, skies, PBR textures) used by the game.
# The binaries are not committed to git; run this once after cloning, then open the project
# in Godot 4.6.3 (it auto-imports) and export the "Web" preset.
#
# All assets are CC0 (Kenney, KayKit / Kay Lousberg, Quaternius, ambientCG, Poly Haven,
# and a realistic survival prop set), mirrored on the asset CDN below.
set -euo pipefail
cd "$(dirname "$0")"

A="https://preview.myapping.com/godot-assets"
T="https://preview.myapping.com/godot-textures"

dl() { mkdir -p "$(dirname "$2")"; curl -sfL "$1" -o "$2" && echo "  ok $2" || { echo "  FAIL $1"; exit 1; }; }

echo "Hero + enemies..."
dl "$A/characters/kk_Knight.glb"            models/chars/kk_Knight.glb
dl "$A/characters/kk_Skeleton_Minion.glb"   models/enemies/kk_Skeleton_Minion.glb
dl "$A/characters/kk_Skeleton_Warrior.glb"  models/enemies/kk_Skeleton_Warrior.glb

echo "Weapon + shield..."
dl "$A/props/kk_weapons/axe_A.glb"          models/props/axe_A.glb
dl "$A/props/kk_weapons/shield_B.glb"       models/props/shield_B.glb

echo "Realistic survival props (vostok_realistic)..."
for p in ms_campfire ms_barrier_road ms_board_message ms_brick_pile ms_control_box \
         ms_cable_reel ms_bus_stop_rural ms_chair_sun ms_cabinet_basic ms_candle; do
  dl "$A/props/vostok_realistic/$p.glb" "models/props/$p.glb"
done

echo "Roadside dressing..."
for d in rock_largeA rock_largeC rock_largeE tree_cone_dark plant_bushLarge log_stack campfire_logs; do
  dl "$A/nature/$d.glb" "models/dressing/$d.glb"
done

echo "Skies (photographic HDRI: golden dusk + starry night)..."
dl "$A/skies/ph_evening_road_01_puresky.hdr" skies/dusk.hdr
dl "$A/skies/acg_nightskyhdri003.exr"         skies/night.exr

echo "PBR ground + cracked road (albedo + normal + roughness)..."
for m in albedo normal_gl roughness; do
  dl "$T/pbr/acg_ground103/$m.png" "textures/ground/$m.png"
  dl "$T/pbr/acg_road012a/$m.png"  "textures/road/$m.png"
done

echo "Done. Open the project in Godot 4.6.3 and export the 'Web' preset (nothreads)."
