# samples/cross_file_demo/player.gd
class_name Player
extends Node

signal health_changed(old_v: int, new_v: int)

var hp: int = 100

func take_damage(amount: int) -> void:
	hp -= amount
	health_changed.emit(hp + amount, hp)
