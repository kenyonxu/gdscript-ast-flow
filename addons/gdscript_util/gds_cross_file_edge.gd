# addons/gdscript_util/gds_cross_file_edge.gd
# 跨文件调用/信号边 — 记录跨文件的引用关系

class_name GDSCrossFileEdge
extends RefCounted

enum Kind {
	CALL,            # obj.method() 跨文件调用
	SIGNAL_EMIT,     # obj.emit("sig") 跨文件发射
	SIGNAL_CONNECT,  # obj.connect("sig", cb) 跨文件连接
	INSTANCE,        # T.new() 实例化
	EXTENDS,         # extends T 继承
}

var kind: int = Kind.CALL
var source_file: String = ""       # 调用方/连接方文件
var source_symbol: String = ""     # 所在函数名
var target_file: String = ""       # 目标类所在文件
var target_class: String = ""      # 目标类名
var target_symbol: String = ""     # 目标方法/信号名
var line: int = 0

const KIND_NAMES := ["CALL", "SIGNAL_EMIT", "SIGNAL_CONNECT", "INSTANCE", "EXTENDS"]

func to_dict() -> Dictionary:
	return {
		"source_file": source_file,
		"target_file": target_file,
		"target_class": target_class,
		"target_symbol": target_symbol,
		"kind": KIND_NAMES[kind] if kind >= 0 and kind < KIND_NAMES.size() else "UNKNOWN",
		"line": line,
	}
