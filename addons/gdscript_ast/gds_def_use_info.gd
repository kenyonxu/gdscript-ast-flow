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
