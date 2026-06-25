# addons/gdscript_ast/editor/gds_project_analyzer.gd
# 项目级分析器 — 扫描 .gd/.tscn/.tres 文件 + 批量分析 + 跨文件解析
# 注意: 用 DirAccess + FileAccess 读源码，不用 load()（规避 resource_saved 死锁）

class_name GDScriptProjectAnalyzer
extends RefCounted

# Chunk A2: uid_map 缓存，由 analyze_all 初始化
var _uid_map: Dictionary = {}  # String(uid_str) → String(res_path)

# 按配置扫描 — 读 GDSScanConfig 的 include/exclude 目录
func scan_project() -> Array:
	var includes = GDSScanConfig.get_include_dirs()
	var excludes = GDSScanConfig.get_exclude_dirs()
	var list: Array = []
	for path in includes:
		if path != "":
			_scan_dir(path, list, excludes)
	return list


# 全部递归 — 支持 .gd/.tscn/.tres 后缀（Chunk D2）
func _scan_dir(p_dir: String, p_list: Array, p_excludes: Array) -> void:
	var da = DirAccess.open(p_dir)
	if da == null:
		return
	da.list_dir_begin()
	var name = da.get_next()
	while name != "":
		if name in [".", ".."]:
			name = da.get_next()
			continue
		var full = p_dir.path_join(name)
		if _is_excluded(full, p_excludes):
			name = da.get_next()
			continue
		if da.current_is_dir():
			_scan_dir(full, p_list, p_excludes)
		else:
			var is_scene = name.ends_with(".tscn")
			var is_resource = name.ends_with(".tres")
			if name.ends_with(".gd") or (is_scene and GDSScanConfig.is_scan_scenes_enabled()) or (is_resource and GDSScanConfig.is_scan_resources_enabled()):
				p_list.append(full)
		name = da.get_next()
	da.list_dir_end()


# 精简版排除检查 — 匹配任何 exclude 即排除
func _is_excluded(p_path: String, p_excludes: Array) -> bool:
	# Include 优先：找最具体的 include 和 exclude 前缀，更长（更深）的赢。
	# 支持 exclude 父目录同时 include 子目录（如 exclude res://addons + include res://addons/my_plugin）。
	var includes = GDSScanConfig.get_include_dirs()
	var best_inc = ""
	for inc in includes:
		if p_path == inc or p_path.begins_with(inc + "/"):
			if inc.length() > best_inc.length():
				best_inc = inc
	var best_exc = ""
	for excl in p_excludes:
		if p_path == excl or p_path.begins_with(excl + "/"):
			if excl.length() > best_exc.length():
				best_exc = excl
	# include 更具体（>=，同长 include 赢）则不排除；否则按 exclude
	if best_inc != "" and best_inc.length() >= best_exc.length():
		return false
	return best_exc != ""


# ---- Chunk A2: uid 映射收集 ----

func _collect_uid_map() -> Dictionary:
	# 扫描配置覆盖的目录下所有 .uid 文件，建 {uid_string → res_path} 映射
	var m: Dictionary = {}
	var includes = GDSScanConfig.get_include_dirs()
	var excludes = GDSScanConfig.get_exclude_dirs()
	for base in includes:
		if base == "":
			continue
		_scan_uid_in_dir(base, m, excludes)
	return m

func _scan_uid_in_dir(p_dir: String, p_map: Dictionary, p_excludes: Array) -> void:
	var da = DirAccess.open(p_dir)
	if da == null:
		return
	da.list_dir_begin()
	var name = da.get_next()
	while name != "":
		if name in [".", ".."]:
			name = da.get_next()
			continue
		var full = p_dir.path_join(name)
		if _is_excluded(full, p_excludes):
			name = da.get_next()
			continue
		if da.current_is_dir():
			_scan_uid_in_dir(full, p_map, p_excludes)
		elif name.ends_with(".uid"):
			# .uid 文件内容就是 uid 字符串（如 "uid://cxixtvlqumj56"）
			var uid_str = FileAccess.get_file_as_string(full).strip_edges()
			# 去掉 .uid 后缀即对应资源路径
			var res_path = full.trim_suffix(".uid")
			p_map[uid_str] = res_path
		name = da.get_next()
	da.list_dir_end()


# ---- 单文件管道 ----

# 分析 .gd 文件
func _analyze_gd_file(p_path: String) -> GDScriptAnalysisResult:
	var f = FileAccess.open(p_path, FileAccess.READ)
	if f == null:
		return null
	var source = f.get_as_text()
	f.close()
	if source == "":
		return null
	var tokenizer = GDScriptTokenizer.new()
	var tokens = tokenizer.tokenize(source)
	var parser = GDScriptParser.new()
	var ast = parser.parse(tokens)
	if parser.error != "":
		push_warning("[ProjectAnalyzer] Parse error in %s: %s" % [p_path, parser.error])
		return null
	var resolver = GDScriptSymbolResolver.new()
	return resolver.resolve(ast, p_path)


# 分析 .tscn 场景文件（Chunk D3）
func _analyze_scene_file(p_path: String, p_script_results: Dictionary = {}) -> GDSSceneResourceResult:
	var parser = GDScriptTscnParser.new()
	parser.set_uid_map(_uid_map)
	parser.set_script_analysis_results(p_script_results)
	var result = parser.parse(p_path)
	if parser.error != "":
		push_warning("[ProjectAnalyzer] Tscn parse error in %s: %s" % [p_path, parser.error])
	return result


# 分析 .tres 资源文件（Chunk D3）
func _analyze_resource_file(p_path: String) -> GDSSceneResourceResult:
	var parser = GDScriptTresParser.new()
	parser.set_uid_map(_uid_map)
	var result = parser.parse(p_path)
	if parser.error != "":
		push_warning("[ProjectAnalyzer] Tres parse error in %s: %s" % [p_path, parser.error])
	return result


# 通用单文件分析调度（按后缀路由到对应分析器）
func _analyze_file(p_path: String):
	if p_path.ends_with(".gd"):
		return _analyze_gd_file(p_path)
	elif p_path.ends_with(".tscn"):
		return _analyze_scene_file(p_path)
	elif p_path.ends_with(".tres"):
		return _analyze_resource_file(p_path)
	return null


# ---- 全量分析 ----

func analyze_all() -> GDScriptProjectResult:
	var result = GDScriptProjectResult.new()
	result.root_path = "res://"

	# Chunk A2: 收集 uid 映射
	_uid_map = _collect_uid_map()
	result.uid_map = _uid_map

	var paths = scan_project()
	for path in paths:
		if path.ends_with(".gd"):
			var file_result = _analyze_gd_file(path)
			if file_result != null:
				result.files[path] = file_result
	_build_class_registry(result)

	# 第二遍：分析 .tscn（此时 files 已满，可查 script exports）
	for path in paths:
		if path.ends_with(".tscn"):
			var scene_result = _analyze_scene_file(path, result.files)
			if scene_result != null:
				result.scenes[path] = scene_result
		elif path.ends_with(".tres"):
			var res_result = _analyze_resource_file(path)
			if res_result != null:
				result.resources[path] = res_result
	return result


# 从各文件的 classname_id 建 {class_name: file_path}
func _build_class_registry(p_result: GDScriptProjectResult) -> void:
	for path in p_result.files:
		var file_result = p_result.files[path]
		if file_result.classname_id != "":
			p_result.class_registry[file_result.classname_id] = path


# 第二遍: 用 type_table + class_registry 解析跨文件调用/信号
func resolve_cross_file(p_result: GDScriptProjectResult) -> void:
	for path in p_result.files:
		var file_result = p_result.files[path]
		_resolve_file_cross_edges(path, file_result, p_result)


func _resolve_file_cross_edges(p_path: String, p_file: GDScriptAnalysisResult, p_project: GDScriptProjectResult) -> void:
	if p_file.call_graph == null:
		return
	for edge in p_file.call_graph.edges:
		# EXTERNAL 调用: obj.method() — 尝试解析 obj 的类型
		if edge.call_type == GDScriptCallEdge.CallType.EXTERNAL and edge.target_object != "":
			var obj_type = p_file.type_table.get(edge.target_object, "")
			if obj_type != "":
				_try_resolve_cross_call(p_path, edge, obj_type, edge.callee, GDSCrossFileEdge.Kind.CALL, p_project)
		# CONNECT / SIGNAL_CONNECT: obj.connect("sig", cb) — 跨文件信号连接
		if edge.call_type in [GDScriptCallEdge.CallType.CONNECT, GDScriptCallEdge.CallType.SIGNAL_CONNECT] \
				and edge.target_object != "":
			var obj_type = p_file.type_table.get(edge.target_object, "")
			if obj_type != "":
				_try_resolve_cross_call(p_path, edge, obj_type, edge.callee, GDSCrossFileEdge.Kind.SIGNAL_CONNECT, p_project)
		# EMIT: obj.signal.emit(args) — 跨文件信号发射
		if edge.call_type == GDScriptCallEdge.CallType.EMIT and edge.target_object != "":
			var obj_type = p_file.type_table.get(edge.target_object, "")
			if obj_type != "":
				_try_resolve_cross_call(p_path, edge, obj_type, edge.callee, GDSCrossFileEdge.Kind.SIGNAL_EMIT, p_project)


func _try_resolve_cross_call(p_source_file: String, p_edge, p_obj_type: String, p_symbol: String, p_kind: int, p_project: GDScriptProjectResult) -> void:
	var target_file = p_project.class_registry.get(p_obj_type, "")
	if target_file == "":
		return  # 内置类 — 跳过
	var target_result = p_project.files.get(target_file, null)
	if target_result == null:
		return
	if not _file_defines_symbol(target_result, p_symbol):
		return
	var xedge = GDSCrossFileEdge.new()
	xedge.kind = p_kind
	xedge.source_file = p_source_file
	xedge.source_symbol = p_edge.caller
	xedge.target_file = target_file
	xedge.target_class = p_obj_type
	xedge.target_symbol = p_symbol
	xedge.line = p_edge.site_line
	p_project.add_edge(xedge)


func _file_defines_symbol(p_result: GDScriptAnalysisResult, p_name: String) -> bool:
	if p_result.symbol_table == null:
		return false
	for sym_name in p_result.symbol_table.symbols:
		var sym = p_result.symbol_table.symbols[sym_name]
		if sym.name == p_name and sym.kind in [GDScriptSymbol.Kind.FUNCTION, GDScriptSymbol.Kind.SIGNAL]:
			return true
	return false


# ---- Chunk D4: 场景/资源集成 ----

func _integrate_scene_resources(p_project: GDScriptProjectResult) -> void:
	# 遍历所有场景结果
	for scene_path in p_project.scenes:
		var scene_result: GDSSceneResourceResult = p_project.scenes[scene_path]

		# 1. 脚本关联
		for node_path in scene_result.nodes_flat:
			var node: GDSSceneResourceResult.SceneNodeData = scene_result.nodes_flat[node_path]
			if node.script_resource == "":
				continue

			# 尝试在 class_registry 或 files 中匹配
			var target_file = _resolve_script_path(node.script_resource, p_project)
			if target_file != "":
				# 生成 SCRIPT_ATTACH 跨文件边
				var xedge = GDSCrossFileEdge.new()
				xedge.kind = GDSCrossFileEdge.Kind.SCRIPT_ATTACH
				xedge.source_file = scene_path
				xedge.source_symbol = node_path
				xedge.target_file = target_file
				xedge.target_class = ""
				xedge.target_symbol = ""
				xedge.line = 0
				p_project.add_edge(xedge)

				# 向 project 级 script_associations 追加记录
				p_project.script_associations.append({
					"scene": scene_path,
					"node": node.name,
					"script": target_file,
					"script_class": p_project.files.get(target_file, {}).classname_id if p_project.files.has(target_file) else "",
				})

		# 2. 信号连接双出口
		for conn in scene_result.signal_connections:
			var c: GDSSceneResourceResult.SignalConnectionData = conn
			# 尝试匹配 from_node 的脚本
			var from_node: GDSSceneResourceResult.SceneNodeData = _find_node_in_scene(scene_result, c.from_node)
			var to_node: GDSSceneResourceResult.SceneNodeData = _find_node_in_scene(scene_result, c.to_node)

			var from_script: String = ""
			var to_script: String = ""
			if from_node != null:
				from_script = _resolve_script_path(from_node.script_resource, p_project)
			if to_node != null:
				to_script = _resolve_script_path(to_node.script_resource, p_project)

			if from_script != "" and to_script != "":
				# 两个端点都可解析 → CrossFileEdge(SIGNAL_CONNECT)
				var xedge = GDSCrossFileEdge.new()
				xedge.kind = GDSCrossFileEdge.Kind.SIGNAL_CONNECT
				xedge.source_file = from_script
				xedge.source_symbol = c.signal_name
				xedge.target_file = to_script
				xedge.target_class = ""
				xedge.target_symbol = c.method
				xedge.line = 0
				p_project.add_edge(xedge)
			else:
				# 无法完全匹配 → 记录到 scene_signal_connections
				p_project.scene_signal_connections.append({
					"signal": c.signal_name,
					"from_scene": scene_path,
					"from_node": c.from_node,
					"from_script": from_script,
					"to_scene": scene_path,
					"to_node": c.to_node,
					"to_method": c.method,
					"to_script": to_script,
				})


# 在场景结果中按节点路径查找 SceneNodeData
func _find_node_in_scene(p_scene: GDSSceneResourceResult, p_node_path: String) -> GDSSceneResourceResult.SceneNodeData:
	# 尝试全路径匹配
	if p_scene.nodes_flat.has(p_node_path):
		return p_scene.nodes_flat[p_node_path]

	# 尝试按名字匹配（遍历所有节点）
	for path in p_scene.nodes_flat:
		var node: GDSSceneResourceResult.SceneNodeData = p_scene.nodes_flat[path]
		if node.name == p_node_path:
			return node

	# 尝试 root_nodes
	for root in p_scene.root_nodes:
		if root.name == p_node_path:
			return root

	return null


# 解析脚本路径：class_name → 路径 → uid（SPEC 优先级）
func _resolve_script_path(p_script_path: String, p_project: GDScriptProjectResult) -> String:
	# 1. class_name 优先匹配
	var script_name = p_script_path.get_file().trim_suffix(".gd")
	if p_project.class_registry.has(script_name):
		return p_project.class_registry[script_name]

	# 2. 直接路径匹配
	if p_project.files.has(p_script_path):
		return p_script_path

	# 3. Chunk A3: uid 匹配 — 查 uid_map
	if p_script_path in p_project.uid_map:
		return p_project.uid_map[p_script_path]
	# 也尝试提取 uid 字符串前缀匹配
	if p_script_path.begins_with("uid://"):
		var resolved = p_project.uid_map.get(p_script_path, "")
		if resolved != "":
			return resolved

	return ""


# ---- 完整入口（Chunk D5） ----

func analyze_full() -> GDScriptProjectResult:
	var result = analyze_all()
	resolve_cross_file(result)
	_integrate_scene_resources(result)
	return result
