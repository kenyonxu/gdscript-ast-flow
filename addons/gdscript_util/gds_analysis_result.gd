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
# Phase 3.3: 调用度数（驱动图节点大小/枢纽高亮）
var call_in_degree: Dictionary = {}   # String(func) → int（被调次数）
var call_out_degree: Dictionary = {}  # String(func) → int（调用次数）

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


# ---- 序列化 ----

const ENTRY_METHODS := preload("res://addons/gdscript_util/editor/gds_entry_methods.gd")

func to_dict() -> Dictionary:
	var funcs: Array = []
	for fn in get_all_functions():
		funcs.append(_function_to_dict(fn))
	var sigs: Array = []
	for sig in get_all_signals():
		sigs.append(_signal_to_dict(sig))
	var call_edges: Array = []
	if call_graph:
		for edge in call_graph.edges:
			call_edges.append({
				"caller": edge.caller,
				"callee": edge.callee,
				"type": _call_type_str(edge.call_type),
				"line": edge.site_line,
			})
	return {
		"class_name": classname_id,
		"extends": extends_path,
		"functions": funcs,
		"signals": sigs,
		"call_edges": call_edges,
		"errors": errors,
	}

func _function_to_dict(p_fn) -> Dictionary:
	var params: Array = []
	for p in p_fn.params:
		params.append({"name": p.name, "type": _type_str(p.datatype)})
	return {
		"name": p_fn.name,
		"line": p_fn.line,
		"params": params,
		"return_type": _type_str(p_fn.return_type),
		"is_entry": ENTRY_METHODS.is_entry(p_fn.name),
		"is_static": p_fn.is_static,
		"in_degree": call_in_degree.get(p_fn.name, 0),
		"out_degree": call_out_degree.get(p_fn.name, 0),
	}

func _signal_to_dict(p_sig) -> Dictionary:
	var params: Array = []
	for p in p_sig.params:
		params.append(_type_str(p.datatype))
	var info = signal_graph.get_signal_flow(p_sig.name) if signal_graph else null
	return {
		"name": p_sig.name,
		"line": p_sig.line,
		"params": params,
		"emit_count": info.emit_sites.size() if info else 0,
		"connect_count": info.connect_sites.size() if info else 0,
	}

static func _type_str(p_type) -> String:
	if p_type == null:
		return ""
	return p_type.type_name if "type_name" in p_type else ""

static func _call_type_str(p_type: int) -> String:
	const NAMES := ["SELF", "SUPER", "EXTERNAL", "CONNECT", "SIGNAL_CONNECT", "LAMBDA", "STATIC", "EMIT"]
	return NAMES[p_type] if p_type >= 0 and p_type < NAMES.size() else "UNKNOWN"
