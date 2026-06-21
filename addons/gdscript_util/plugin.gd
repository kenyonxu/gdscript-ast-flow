@tool
extends EditorPlugin

var analysis_cache: Dictionary = {}  # String(path) → GDScriptAnalysisResult
var _phase3_bootstrap: GDSEditorBootstrap = null


func _enter_tree():
	add_tool_menu_item("GDScript Analysis – Parse Current", _on_parse_current)
	# Phase 2: 注册 resource_saved 信号实现自动分析
	resource_saved.connect(_on_resource_saved)
	# Phase 3: 编辑器面板
	_phase3_bootstrap = GDSEditorBootstrap.new()
	_phase3_bootstrap.setup(self)
	print("[GDScriptUtil v3.0] Plugin loaded — Phase 3: Editor Integration")


func _exit_tree():
	# Phase 3: 拆卸编辑器面板
	if _phase3_bootstrap:
		_phase3_bootstrap.teardown()
		_phase3_bootstrap = null
	remove_tool_menu_item("GDScript Analysis – Parse Current")
	resource_saved.disconnect(_on_resource_saved)
	analysis_cache.clear()
	print("[GDScriptUtil v3.0] Plugin unloaded")


# Phase 2 新增: 脚本保存时自动分析
func _on_resource_saved(p_resource: Resource):
	if p_resource is GDScript and p_resource.resource_path.ends_with(".gd"):
		_analyze_script(p_resource.resource_path)


func _on_parse_current():
	var editor = get_editor_interface()
	var script_editor = editor.get_script_editor()
	var current = script_editor.get_current_script()
	if current == null:
		print("[GDScriptUtil] No script open")
		return

	var source = current.source_code
	if source == "":
		print("[GDScriptUtil] Empty script")
		return

	# Phase 1 pipeline
	var tokenizer = GDScriptTokenizer.new()
	var tokens = tokenizer.tokenize(source)

	var parser = GDScriptParser.new()
	var ast = parser.parse(tokens)

	if parser.error != "":
		printerr("[GDScriptUtil] Parse error: %s" % parser.error)
		return

	# Phase 2 pipeline — 符号解析
	var resolver = GDScriptSymbolResolver.new()
	var result = resolver.resolve(ast, current.resource_path)
	analysis_cache[current.resource_path] = result

	# 输出分析摘要
	_print_analysis_summary(result)


# Phase 2 分析函数（resource_saved 调用）
func _analyze_script(p_path: String) -> GDScriptAnalysisResult:
	var script = load(p_path) as GDScript
	if script == null:
		return null

	var source = script.source_code
	if source == "":
		return null

	# Phase 1 管道
	var tokenizer = GDScriptTokenizer.new()
	var tokens = tokenizer.tokenize(source)
	var parser = GDScriptParser.new()
	var ast = parser.parse(tokens)

	if parser.error != "":
		push_warning("[GDScriptUtil] Parse error in %s: %s" % [p_path, parser.error])
		return null

	# Phase 2 符号解析
	var resolver = GDScriptSymbolResolver.new()
	var result = resolver.resolve(ast, p_path)

	# 缓存结果
	analysis_cache[p_path] = result

	# 静默分析（resource_saved 触发时不输出摘要，避免刷屏）
	# 仅在手动触发时输出摘要
	return result


# 分析摘要输出
func _print_analysis_summary(p_result: GDScriptAnalysisResult):
	var func_count = p_result.get_all_functions().size()
	var sig_count = p_result.get_all_signals().size()
	var var_count = p_result.def_use_chain.variables.size()

	print("[GDScriptUtil] %s — %d functions, %d signals, %d variables, %d calls, %d errors" % [
		p_result.file_path,
		func_count,
		sig_count,
		var_count,
		p_result.call_graph.edges.size(),
		p_result.errors.size()
	])

	# 输出错误
	for err in p_result.errors:
		push_warning(err)

	# 输出调用图摘要
	if p_result.call_graph.edges.size() > 0:
		print("  Call Graph:")
		for edge in p_result.call_graph.edges:
			var type_str = _call_type_to_string(edge.call_type)
			print("    %s() →%s %s() @line %d" % [edge.caller, type_str, edge.callee, edge.site_line])

	# 输出信号流摘要
	if p_result.signal_graph.signals.size() > 0:
		print("  Signal Flow:")
		for sig_name in p_result.signal_graph.signals:
			var info = p_result.signal_graph.signals[sig_name]
			var decl_line = info.declaration.line if info.declaration != null else "?"
			print("    signal %s (decl @%s): %d emits, %d connects" % [
				sig_name, decl_line, info.emit_sites.size(), info.connect_sites.size()
			])


func _call_type_to_string(p_type: int) -> String:
	match p_type:
		GDScriptCallEdge.CallType.SELF: return "[self]"
		GDScriptCallEdge.CallType.SUPER: return "[super]"
		GDScriptCallEdge.CallType.EXTERNAL: return "[ext]"
		GDScriptCallEdge.CallType.CONNECT: return "[connect]"
		GDScriptCallEdge.CallType.SIGNAL_CONNECT: return "[sig-conn]"
		GDScriptCallEdge.CallType.LAMBDA: return "[lambda]"
		GDScriptCallEdge.CallType.EMIT: return "[emit]"
		_: return "[?]"


# Phase 3: Bridge 使用的静态分析函数
static func analyze_script(p_path: String) -> GDScriptAnalysisResult:
	var script = load(p_path) as GDScript
	if script == null:
		return null

	var source = script.source_code
	if source == "":
		return null

	# Phase 1 管道
	var tokenizer = GDScriptTokenizer.new()
	var tokens = tokenizer.tokenize(source)
	var parser = GDScriptParser.new()
	var ast = parser.parse(tokens)

	if parser.error != "":
		push_warning("[GDScriptUtil] Parse error in %s: %s" % [p_path, parser.error])
		return null

	# Phase 2 符号解析
	var resolver = GDScriptSymbolResolver.new()
	var result = resolver.resolve(ast, p_path)
	return result
