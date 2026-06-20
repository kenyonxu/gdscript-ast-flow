# addons/gdscript_util/gds_def_use_chain.gd
# 变量定义-使用链 — 管理所有变量的读写追踪

class_name GDScriptDefUseChain
extends RefCounted

var variables: Dictionary = {}

func get_variable_usages(p_var_name: String) -> GDScriptDefUseInfo:
	return variables.get(p_var_name, null)

func _ensure_info(p_name: String) -> GDScriptDefUseInfo:
	if not variables.has(p_name):
		var info = GDScriptDefUseInfo.new()
		info.name = p_name
		variables[p_name] = info
	return variables[p_name]
