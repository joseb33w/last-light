#!/usr/bin/env bash
# Outpost Vostok — fetch the CC0 art assets (realistic characters, weapons, vostok props,
# and the dusk HDRI sky) used by the game. The binaries are NOT committed to git; run this
# once after cloning, then open the project in Godot 4.6.3 (it auto-imports) and export the
# "Web" preset.
#
# All assets are CC0 (Meshy realistic roster, a realistic "vostok" survival prop set, and a
# Poly Haven industrial-sunset HDRI), mirrored on the asset CDN below.
set -euo pipefail
cd "$(dirname "$0")"

A="https://preview.myapping.com/godot-assets"

dl() { mkdir -p "$(dirname "$2")"; curl -sfL "$1" -o "$2" && echo "  ok $2" || { echo "  FAIL $1"; exit 1; }; }

echo "Playable heroes + quartermaster..."
for c in soldier vanguard specter warden; do
  dl "$A/realistic_characters/$c.glb" "models/$c.glb"
done

echo "Enemies (melee + ranged + boss)..."
for c in cyber alien infected reaver; do
  dl "$A/realistic_characters/$c.glb" "models/$c.glb"
done

echo "Weapons..."
for w in rifle pistol plasma armcannon; do
  dl "$A/realistic_weapons/$w.glb" "models/$w.glb"
done

echo "Station props (vostok_realistic)..."
for p in ms_control_box ms_cabinet_basic ms_cable_reel ms_barrier_road ms_brick_pile ms_board_message; do
  dl "$A/props/vostok_realistic/$p.glb" "models/$p.glb"
done

echo "Dusk industrial HDRI sky..."
dl "$A/skies/ph_industrial_sunset_puresky.hdr" "skies/dusk.hdr"

echo "Done. Open in Godot 4.6.3 to auto-import, then export the Web preset."
