# addons/gdscript_ast/gds_signal_info.gd
# 单个信号的完整流程图

class_name GDScriptSignalInfo
extends RefCounted

var name: String = ""
var declaration = null
var params: Array = []
var emit_sites: Array = []
var connect_sites: Array = []


# 未连接信号判定 — UI 高亮依据
# declared 但 0 emit + 0 connect → dead signal
# 注: external 信号（未声明、通过 emit/connect 临时创建）天然有 site，不会 unused
func is_unused() -> bool:
	return emit_sites.is_empty() and connect_sites.is_empty()
