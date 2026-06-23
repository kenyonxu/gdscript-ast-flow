# samples/parser_edge_cases.gd
# Parser 边界情况测试 — 用于发现 parser 尚不支持的 GDScript 4 语法
# 保存此文件 (Ctrl+S) 触发分析，看 Output 是否有 [ProjectAnalyzer] Parse error

extends Node

# 1. 三引号多行字符串
const DOCSTRING := """
This is a multi-line
string with "quotes" inside.
"""

# 2. 科学计数法数字（注: 1e6 as int 会卡 Godot 自身 parser，用 var 替代 const 测试）
const SCI_FLOAT: float = 1.5e-3

# 3. 二进制 / 八进制数字（Godot 4 原生 parser 不支持 0b/0o，仅测试我们的 tokenizer）
const BIN := 0b1010
const OCT := 0o777

# 4. match 表达式（基础 + when 分支）
func test_match(x: int) -> void:
	match x:
		1: print("one")
		2, 3: print("two or three")
		_: print("other")

# 5. 三目运算符
func test_ternary(cond: bool) -> int:
	return 1 if cond else 0
	var x = 1 if true else 2

# 6. Lambda 表达式
func test_lambda() -> void:
	var doubler := func(x: int) -> int: return x * 2
	var tripler = func(x): return x * 3

# 7. is / as 类型操作
func test_type_ops(obj) -> void:
	if obj is Node:
		var n = obj as Node2D

# 8. await 表达式
func test_await() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout

# 9. 数组 / 字典字面量
func test_containers() -> void:
	var arr: Array[int] = [1, 2, 3]
	var dict := { "key": "value", 1: 2 }
	var nested := { "a": { "b": [1, 2] } }
	print(arr, dict, nested)

# 10. 方法链调用
func test_chaining() -> void:
	var t := create_tween()
	t.set_loops().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# 11. $NodePath 语法
func test_nodepath() -> void:
	var x = $SomeNode/Child
	var y = $"%UniqueName"
	var z = $"Some Node With Spaces"

# 12. @export 带参数注解
@export_range(0, 100, 1, "or_greater") var health: int = 100
@export_flags("Fire", "Water", "Earth", "Air") var elements: int = 0
@export_enum("Warrior", "Mage", "Thief") var character_class: int = 0

# 13. 信号声明 + emit
signal health_changed(old: int, new: int)
signal died

# 14. 内联 setter/getter (简单形式)
var _hp: int = 100
var hp: int:
	get: return _hp
	set(value): _hp = clamp(value, 0, 100)

# 15. preload + 实例化
const FIREBALL := preload("res://demo/agents/fireball/fireball.gd")

# 16. enum
enum State { IDLE, RUNNING, JUMPING }

# 17. class 内部类
class InnerHelper:
	var value: int = 0
	func do_something() -> void:
		value += 1

# 18. namespace
namespace TestNS:
	var ns_var: int = 0
	func ns_func() -> void: pass

# 19. for 循环 + 变量作用域
func test_loop() -> void:
	for i in range(10):
		print(i)

# 20. while + break + continue
func test_while() -> void:
	var i := 0
	while i < 10:
		i += 1
		if i == 5: break
		if i % 2 == 0: continue

# 21. assert 带消息
func test_assert() -> void:
	assert(1 + 1 == 2, "Math is broken!")

# 22. breakpoint
func test_breakpoint() -> void:
	breakpoint
	print("after breakpoint")
