# addons/gdscript_ast/gds_call_edge.gd
# 调用图中的一条边 — 记录一次方法调用关系

class_name GDScriptCallEdge
extends RefCounted

enum CallType {
	SELF = 0,            # self.method() 或隐式 self 调用
	SUPER = 1,           # super.method()
	EXTERNAL = 2,        # obj.method() 外部对象调用
	CONNECT = 3,         # .connect("sig", cb) 中的回调
	SIGNAL_CONNECT = 4,  # signal_name.connect(cb) 中的回调
	LAMBDA = 5,          # lambda 作为回调
	STATIC = 6,          # ClassName.static_method()
	EMIT = 7,            # emit("signal") / signal.emit()
}

var caller: String = ""
var callee: String = ""
var site_line: int = 0
var call_type: int = CallType.SELF
var target_object: String = ""
var arguments: Array = []
