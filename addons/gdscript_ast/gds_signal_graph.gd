# addons/gdscript_ast/gds_signal_graph.gd
# 信号流程图 — 管理所有信号的 emit/connect 关系

class_name GDScriptSignalGraph
extends RefCounted

var signals: Dictionary = {}

func get_signal_flow(p_signal_name: String) -> GDScriptSignalInfo:
	return signals.get(p_signal_name, null)
