# addons/gdscript_util/gds_project_result.gd
# 项目级结果容器 — 汇总所有文件分析结果 + 跨文件边 + 查询 API

class_name GDScriptProjectResult
extends RefCounted

var root_path: String = ""
var files: Dictionary = {}            # String(path) → GDScriptAnalysisResult
var class_registry: Dictionary = {}   # String(class_name) → String(file_path)
var reverse_index: Dictionary = {}    # String(target_file) → Array[source_file]
var cross_edges: Array = []           # of GDSCrossFileEdge

# 查询: 谁跨文件调用了 p_class.p_method
func get_callers_across_files(p_class: String, p_method: String) -> Array:
	var result: Array = []
	for edge in cross_edges:
		if edge.kind == GDSCrossFileEdge.Kind.CALL \
				and edge.target_class == p_class \
				and edge.target_symbol == p_method:
			result.append(edge)
	return result

# 查询: 信号的跨文件 emit/connect
func get_signal_flow_across_files(p_signal: String) -> Array:
	var result: Array = []
	for edge in cross_edges:
		if edge.kind in [GDSCrossFileEdge.Kind.SIGNAL_EMIT, GDSCrossFileEdge.Kind.SIGNAL_CONNECT] \
				and edge.target_symbol == p_signal:
			result.append(edge)
	return result

# 查询: 哪些文件引用了 p_file
func get_files_referencing(p_file: String) -> Array:
	return reverse_index.get(p_file, [])

func add_edge(p_edge) -> void:
	cross_edges.append(p_edge)
	# 维护反向索引
	if not reverse_index.has(p_edge.target_file):
		reverse_index[p_edge.target_file] = []
	var sources = reverse_index[p_edge.target_file]
	if not sources.has(p_edge.source_file):
		sources.append(p_edge.source_file)
