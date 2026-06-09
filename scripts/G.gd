extends Node
## Global input/event bus. Decouples the touch HUD from the gameplay nodes.

signal start_pressed
signal restart_pressed
signal attack_pressed
signal feed_pressed

# Written by the HUD joystick each frame; read by the player.
var move_vec: Vector2 = Vector2.ZERO
# Accumulated drag-look delta (consumed by the player camera each frame).
var look_delta: Vector2 = Vector2.ZERO

func consume_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d
