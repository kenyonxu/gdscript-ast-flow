# addons/gdscript_ast/gds_def_use_info.gd
# 单个变量的完整读写链

class_name GDScriptDefUseInfo
extends RefCounted

var name: String = ""
var def_site: GDScriptDefUseSite = null
var read_sites: Array = []
var write_sites: Array = []

func get_all_sites() -> Array:
	var all: Array = []
	if def_site != null:
		all.append(def_site)
	all.append_array(read_sites)
	all.append_array(write_sites)
	return all


# 使用状态判定 — UI 未使用高亮依据
# 返回 "unused"(完全死: 0 read + 0 write) / "write_only"(只写不读) / "normal"
# 注: `_` 开头占位变量的排除由 UI 层负责（约定，非数据语义）
func get_usage_status() -> String:
	if read_sites.is_empty() and write_sites.is_empty():
		return "unused"
	if read_sites.is_empty():
		return "write_only"
	return "normal"
