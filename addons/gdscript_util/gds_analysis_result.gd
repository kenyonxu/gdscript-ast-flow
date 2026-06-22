# addons/gdscript_util/gds_analysis_result.gd
# Phase 2 符号解析 — 统一结果容器
# 数据结构定义已提取为独立 class_name 文件:
#   gds_symbol.gd, gds_symbol_table.gd, gds_call_edge.gd, gds_call_graph.gd,
#   gds_site.gd, gds_signal_info.gd, gds_signal_graph.gd,
#   gds_def_use_site.gd, gds_def_use_info.gd, gds_def_use_chain.gd

class_name GDScriptAnalysisResult
extends RefCounted

var file_path: String = ""
var classname_id: String = ""
var extends_path: String = ""
var preloads: Array = []

# 核心数据
var ast = null
var symbol_table: GDScriptSymbolTable = null
var call_graph: GDScriptCallGraph = null
var signal_graph: GDScriptSignalGraph = null
var def_use_chain: GDScriptDefUseChain = null
var type_table: Dictionary = {}  # String(var/param name) → String(类型名) — 供跨文件解析用

# 错误/告警
var errors: Array = []

# 源码行缓存
var _source_lines: Array = []


# ---- 查询 API ----

func get_all_functions() -> Array:
	var funcs: Array = []
	if symbol_table == null:
		return funcs
	for sym_name in symbol_table.symbols:
		var sym = symbol_table.symbols[sym_name]
		if sym.kind == GDScriptSymbol.Kind.FUNCTION:
			funcs.append(sym.declaration)
	return funcs

func get_all_signals() -> Array:
	var signals: Array = []
	if symbol_table == null:
		return signals
	for sym_name in symbol_table.symbols:
		var sym = symbol_table.symbols[sym_name]
		if sym.kind == GDScriptSymbol.Kind.SIGNAL:
			signals.append(sym.declaration)
	return signals

func get_callers_of(p_func_name: String) -> Array:
	if call_graph == null:
		return []
	return call_graph.get_callers_of(p_func_name)

func get_callees_of(p_func_name: String) -> Array:
	if call_graph == null:
		return []
	return call_graph.get_callees_of(p_func_name)

func get_signal_flow(p_signal_name: String) -> GDScriptSignalInfo:
	if signal_graph == null:
		return null
	return signal_graph.get_signal_flow(p_signal_name)

func get_variable_usages(p_var_name: String) -> GDScriptDefUseInfo:
	if def_use_chain == null:
		return null
	return def_use_chain.get_variable_usages(p_var_name)

func get_dependency_tree() -> Dictionary:
	return {
		"extends": extends_path,
		"preloads": preloads,
		"class_name": classname_id,
	}

func add_error(p_msg: String):
	errors.append(p_msg)
