# addons/gdscript_util/editor/gds_project_analyzer.gd
# 项目级分析器 — 扫描 .gd 文件 + 批量分析 + 跨文件解析
# 注意: 用 DirAccess + FileAccess 读源码，不用 load()（规避 resource_saved 死锁）

class_name GDScriptProjectAnalyzer
extends RefCounted

const SKIP_DIRS := [".", "..", ".godot", ".git", "addons"]  # addons 第三方噪音，可调

# 递归扫描 root 下所有 .gd 文件
func scan_project(p_root: String) -> Array:
	var list: Array = []
	_scan_dir(p_root, list)
	return list

func _scan_dir(p_dir: String, p_list: Array) -> void:
	var da = DirAccess.open(p_dir)
	if da == null:
		return
	da.list_dir_begin()
	var name = da.get_next()
	while name != "":
		if name in SKIP_DIRS:
			name = da.get_next()
			continue
		var full = p_dir.path_join(name)
		if da.current_is_dir():
			_scan_dir(full, p_list)
		elif name.ends_with(".gd"):
			p_list.append(full)
		name = da.get_next()
	da.list_dir_end()

# 单文件管道 — 直接读源码（不 load）
func _analyze_file(p_path: String) -> GDScriptAnalysisResult:
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


# 全量分析: 扫描 + 单文件管道，返回 GDScriptProjectResult（无跨文件边，待 B3）
func analyze_all(p_root: String) -> GDScriptProjectResult:
	var result = GDScriptProjectResult.new()
	result.root_path = p_root
	var paths = scan_project(p_root)
	for path in paths:
		var file_result = _analyze_file(path)
		if file_result != null:
			result.files[path] = file_result
	_build_class_registry(result)
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


func _try_resolve_cross_call(p_source_file: String, p_edge, p_obj_type: String, p_symbol: String, p_kind: int, p_project: GDScriptProjectResult) -> void:
	# obj 类型是否是用户类？
	var target_file = p_project.class_registry.get(p_obj_type, "")
	if target_file == "":
		return  # 内置类（Node/Object 等）— 跳过
	# 目标文件是否定义了这个方法/信号？
	var target_result = p_project.files.get(target_file, null)
	if target_result == null:
		return
	if not _file_defines_symbol(target_result, p_symbol):
		return
	# 产出跨文件边
	var xedge = GDSCrossFileEdge.new()
	xedge.kind = p_kind
	xedge.source_file = p_source_file
	xedge.source_symbol = p_edge.caller
	xedge.target_file = target_file
	xedge.target_class = p_obj_type
	xedge.target_symbol = p_symbol
	xedge.line = p_edge.site_line
	p_project.add_edge(xedge)


# 检查某文件的 symbol_table 是否定义了该方法/信号
func _file_defines_symbol(p_result: GDScriptAnalysisResult, p_name: String) -> bool:
	if p_result.symbol_table == null:
		return false
	for sym_name in p_result.symbol_table.symbols:
		var sym = p_result.symbol_table.symbols[sym_name]
		if sym.name == p_name and sym.kind in [GDScriptSymbol.Kind.FUNCTION, GDScriptSymbol.Kind.SIGNAL]:
			return true
	return false


# 完整入口
func analyze_full(p_root: String) -> GDScriptProjectResult:
	var result = analyze_all(p_root)
	resolve_cross_file(result)
	return result
