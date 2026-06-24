# addons/gdscript_ast/gds_builtin_functions.gd
# GDScript 4.7 内置全局函数名表 — 供 resolver 过滤非用户调用噪声
# 来源: Godot 源码 modules/gdscript/gdscript_utility_functions.cpp + @GlobalScope 文档

class_name GDSBuiltinFunctions
extends RefCounted

const NAMES := {
	# 输出
	"print": true, "print_rich": true, "printerr": true, "printraw": true,
	"push_error": true, "push_warning": true,
	# 数学
	"abs": true, "absf": true, "absi": true,
	"acos": true, "asin": true, "atan": true, "atan2": true,
	"ceil": true, "ceilf": true, "ceili": true,
	"clamp": true, "clampf": true, "clampi": true,
	"cos": true, "cosh": true, "sin": true, "sinh": true, "tan": true, "tanh": true,
	"exp": true, "floor": true, "floorf": true, "floori": true,
	"fmod": true, "fposmod": true,
	"is_equal_approx": true, "is_finite": true, "is_inf": true, "is_nan": true,
	"is_zero_approx": true,
	"lerp": true, "lerpf": true,
	"log": true, "max": true, "min": true, "move_toward": true,
	"pow": true, "round": true, "roundf": true, "roundi": true,
	"sign": true, "signf": true, "signi": true,
	"snapped": true, "snappedf": true, "snappedi": true,
	"sqrt": true,
	"wrap": true, "wrapf": true, "wrapi": true,
	# 集合/转换
	"range": true, "len": true, "str": true,
	"var_to_str": true, "str_to_var": true,
	"bytes_to_var": true, "var_to_bytes": true,
	"type_string": true,
	# 反射
	"typeof": true, "type_exists": true, "is_instance_of": true,
	"get_stack": true, "instance_from_id": true,
}

static func is_builtin(p_name: String) -> bool:
	return NAMES.has(p_name)
