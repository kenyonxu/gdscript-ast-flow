# addons/gdscript_util/gds_symbol.gd
# 符号表条目 — 表示 SymbolTable 中的一个符号（函数/变量/信号/枚举等）

class_name GDScriptSymbol
extends RefCounted

enum Kind {
	CLASS = 0,        # class / inner class 定义
	FUNCTION = 1,     # func 定义
	VARIABLE = 2,     # var 定义
	SIGNAL = 3,       # signal 声明
	ENUM = 4,         # enum 定义
	PARAMETER = 5,    # 函数参数
	CONSTANT = 6,     # const 定义
	ENUM_VALUE = 7,   # enum 中的值
	FOR_VAR = 8       # for 循环变量
}

var name: String = ""
var kind: int = Kind.VARIABLE
var declaration = null
var datatype: String = ""
var is_exported: bool = false
