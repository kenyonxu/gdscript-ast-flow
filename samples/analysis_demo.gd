# samples/analysis_demo.gd
# 分析验收样例 — 保存此文件 (Ctrl+S) 触发分析，验收 4 个子 tab
#
# 预期各 tab 内容:
#   Summary:    1 class, 3 functions, 2 signals, ~4 call edges, 2 signal flows
#   Call Graph: _ready → take_damage / connect; take_damage → emit(died/health_changed)
#   Signal Flow: health_changed (connect + emit), died (emit)
#   Def-Use:    hp (def/read-write/read), max_hp (def/write), amount/old_v/new_v (param/read)

extends Node

# ---- 变量 (Def-Use tab) ----
var hp: int = 100          # DEFINE @此行; READ_WRITE in take_damage; READ in _ready
var max_hp: int = 100      # DEFINE @此行; WRITE in _on_health_changed

# ---- 信号 (Signal Flow tab) ----
signal health_changed(old_value: int, new_value: int)  # connect + emit
signal died                                            # emit only


func _ready() -> void:
	# Call Graph: 隐式 self 调用 (绿色 SELF)
	take_damage(10)
	# Signal Flow: signal.connect(cb) (蓝 CONNECT)
	health_changed.connect(_on_health_changed)
	# Def-Use: hp READ
	print("starting hp: ", hp)


func take_damage(amount: int) -> void:
	# Def-Use: hp READ_WRITE (复合赋值 红色)
	hp -= amount
	# Def-Use: amount READ
	if hp <= 0:
		# Signal Flow: signal.emit() (红 EMIT)
		died.emit()
		return
	# Signal Flow: signal.emit(args) (红 EMIT)
	health_changed.emit(hp + amount, hp)


func _on_health_changed(old_v: int, new_v: int) -> void:
	# Def-Use: max_hp WRITE (橙色)
	max_hp = 100
	# Def-Use: old_v / new_v READ
	print("%d -> %d" % [old_v, new_v])
