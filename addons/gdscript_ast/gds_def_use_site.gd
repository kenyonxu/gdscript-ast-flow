# addons/gdscript_ast/gds_def_use_site.gd
# 单个读写位置 — 记录变量的一次定义/读取/写入

class_name GDScriptDefUseSite
extends RefCounted

enum AccessType {
	DEFINE = 0,      # var x = ... / const x = ... 的定义
	READ = 1,        # 读取变量值
	WRITE = 2,       # 赋值写入
	READ_WRITE = 3   # 读+写 (复合赋值)
}

var line: int = 0
var node = null
var enclosing_function: String = ""
var access_type: int = AccessType.READ
