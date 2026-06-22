# samples/cross_file_demo/enemy.gd
extends Node

func attack(player: Player) -> void:
	# 跨文件调用: player.take_damage()
	player.take_damage(10)
	# 跨文件信号连接: player.health_changed.connect
	player.health_changed.connect(_on_player_hit)

func _on_player_hit(o: int, n: int) -> void:
	print(o, " -> ", n)
