# addons/gdscript_util/gds_call_graph.gd
# 方法调用图 — 记录所有方法间调用关系

class_name GDScriptCallGraph
extends RefCounted

var edges: Array = []

func add_edge(p_edge):
	edges.append(p_edge)

func get_callers_of(p_func_name: String) -> Array:
	var result: Array = []
	for e in edges:
		if e.callee == p_func_name:
			result.append(e)
	return result

func get_callees_of(p_func_name: String) -> Array:
	var result: Array = []
	for e in edges:
		if e.caller == p_func_name:
			result.append(e)
	return result
