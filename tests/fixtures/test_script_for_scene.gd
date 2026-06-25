# tests/fixtures/test_script_for_scene.gd
# 被场景引用的伴生测试脚本
class_name TestSceneScript
extends Node

signal health_changed(new_hp: int)
signal died

@export var max_health: int = 100
@export var speed: float = 300.0

var current_health: int = max_health

func _ready():
	pass

func take_damage(amount: int) -> void:
	current_health -= amount
	health_changed.emit(current_health)
	if current_health <= 0:
		died.emit()

func heal(amount: int) -> void:
	current_health = mini(max_health, current_health + amount)
	health_changed.emit(current_health)

func _on_button_pressed() -> void:
	print("Button was pressed!")

func _on_health_updated(value: int) -> void:
	print("Health updated to: ", value)
