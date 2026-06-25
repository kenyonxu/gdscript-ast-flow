# addons/gdscript_ast/gds_project_result.gd
# 项目级结果容器 — 汇总所有文件分析结果 + 跨文件边 + 查询 API

class_name GDScriptProjectResult
extends RefCounted

var root_path: String = ""
var files: Dictionary = {}            # String(path) → GDScriptAnalysisResult
var class_registry: Dictionary = {}   # String(class_name) → String(file_path)
var reverse_index: Dictionary = {}    # String(target_file) → Array[source_file]
var cross_edges: Array = []           # of GDSCrossFileEdge

# Chunk E: 场景/资源分析结果
var scenes: Dictionary = {}           # String(path) → GDSSceneResourceResult
var resources: Dictionary = {}        # String(path) → GDSSceneResourceResult
var script_associations: Array = []   # of Dictionary {scene, node, script, script_class}
var scene_signal_connections: Array = []  # of Dictionary {signal, from_scene, from_node, ...}

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


# ---- 序列化与导出 ----

func to_dict(p_project_name: String = "") -> Dictionary:
	var summary := _build_summary()
	var files_dict := {}
	for path in files:
		files_dict[path] = files[path].to_dict()
	var cross_arr: Array = []
	for edge in cross_edges:
		cross_arr.append(edge.to_dict())
	return {
		"schema_version": 2,
		"project": p_project_name,
		"source_path": root_path,
		"summary": summary,
		"files": files_dict,
		"cross_file": cross_arr,
		"hub_functions": _top_hubs(20),
		"coupled_files": _top_coupled(20),
		"scenes": _serialize_scenes(),
		"resources": _serialize_resources(),
		"script_associations": script_associations,
		"scene_signal_connections": scene_signal_connections,
	}

func export_json(p_path: String, p_project_name: String = "") -> Error:
	var data = to_dict(p_project_name)
	var json_str = JSON.stringify(data, "  ")
	var f = FileAccess.open(p_path, FileAccess.WRITE)
	if f == null:
		return ERR_CANT_OPEN
	f.store_string(json_str)
	f.close()
	return OK

func _build_summary() -> Dictionary:
	var func_count := 0
	var sig_count := 0
	var edge_count := 0
	for path in files:
		var fr = files[path]
		func_count += fr.get_all_functions().size()
		sig_count += fr.get_all_signals().size()
		if fr.call_graph:
			edge_count += fr.call_graph.edges.size()
	return {
		"files_analyzed": files.size(),
		"total_functions": func_count,
		"total_signals": sig_count,
		"total_call_edges": edge_count,
		"total_cross_file_edges": cross_edges.size(),
		"scenes_analyzed": scenes.size(),
		"resources_analyzed": resources.size(),
	}

func _serialize_scenes() -> Dictionary:
	var d: Dictionary = {}
	for path in scenes:
		d[path] = scenes[path].to_dict()
	return d

func _serialize_resources() -> Dictionary:
	var d: Dictionary = {}
	for path in resources:
		d[path] = resources[path].to_dict()
	return d

func _top_hubs(p_limit: int) -> Array:
	var hubs: Array = []
	for path in files:
		var fr = files[path]
		for name in fr.call_in_degree:
			var total = fr.call_in_degree[name] + fr.call_out_degree.get(name, 0)
			if total > 0:
				hubs.append({"name": name, "file": path, "total_degree": total})
	hubs.sort_custom(func(a, b): return a.total_degree > b.total_degree)
	return hubs.slice(0, mini(p_limit, hubs.size()))

func _top_coupled(p_limit: int) -> Array:
	var pair_counts: Dictionary = {}
	for edge in cross_edges:
		var key = [edge.source_file, edge.target_file]
		key.sort()
		var key_str = key[0] + "|" + key[1]
		pair_counts[key_str] = pair_counts.get(key_str, 0) + 1
	var pairs: Array = []
	for key_str in pair_counts:
		var parts = key_str.split("|")
		pairs.append({"file_a": parts[0], "file_b": parts[1], "edge_count": pair_counts[key_str]})
	pairs.sort_custom(func(a, b): return a.edge_count > b.edge_count)
	return pairs.slice(0, mini(p_limit, pairs.size()))
