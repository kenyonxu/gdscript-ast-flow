# addons/gdscript_util/editor/gds_analysis_bridge.gd
# 信号中继桥 — 解耦分析引擎和编辑器 UI 面板
# 参考: clef-dev/addons/clef/editor/clef_station_editor_bridge.gd

class_name GDSAnalysisBridge
extends RefCounted

# 分析生命周期
signal analysis_started(file_path: String)
signal analysis_completed(result: GDScriptAnalysisResult)
signal analysis_failed(file_path: String, error: String)

# 面板间联动 — 用户在某面板选中一项，其他面板联动过滤
signal function_selected(func_name: String)
signal signal_selected(signal_name: String)
signal variable_selected(var_name: String)

var _current_result: GDScriptAnalysisResult = null
var _cache: Dictionary = {}  # String(path) → GDScriptAnalysisResult
var _timestamps: Dictionary = {}  # String(path) → int(mtime)


func run_analysis(p_file_path: String) -> void:
	analysis_started.emit(p_file_path)

	# Phase 3: 时间戳缓存 — 未修改文件跳过分析
	if not should_reanalyze(p_file_path) and _cache.has(p_file_path):
		_current_result = _cache[p_file_path]
		analysis_completed.emit(_current_result)
		return

	# 直接运行 Phase 1+2 管道（不依赖 plugin.gd — 避免 class_name 依赖问题）
	var result = _run_pipeline(p_file_path)
	if result == null:
		analysis_failed.emit(p_file_path, "Parse error or file not found")
		return
	_current_result = result
	_cache[p_file_path] = result
	analysis_completed.emit(result)


# Phase 1+2 分析管道 — tokenizer → parser → symbol resolver
func _run_pipeline(p_file_path: String) -> GDScriptAnalysisResult:
	var script = load(p_file_path) as GDScript
	if script == null:
		return null

	var source = script.source_code
	if source == "":
		return null

	# Phase 1: tokenize + parse
	var tokenizer = GDScriptTokenizer.new()
	var tokens = tokenizer.tokenize(source)
	var parser = GDScriptParser.new()
	var ast = parser.parse(tokens)

	if parser.error != "":
		push_warning("[GDSAnalysisBridge] Parse error in %s: %s" % [p_file_path, parser.error])
		return null

	# Phase 2: symbol resolution
	var resolver = GDScriptSymbolResolver.new()
	return resolver.resolve(ast, p_file_path)


func get_current_result() -> GDScriptAnalysisResult:
	return _current_result

func get_cached(file_path: String) -> GDScriptAnalysisResult:
	return _cache.get(file_path, null)

func select_function(func_name: String) -> void:
	function_selected.emit(func_name)

func select_signal(signal_name: String) -> void:
	signal_selected.emit(signal_name)

func select_variable(var_name: String) -> void:
	variable_selected.emit(var_name)

# Phase 3: 时间戳缓存
func should_reanalyze(p_path: String) -> bool:
	if not FileAccess.file_exists(p_path):
		return false
	var mtime = FileAccess.get_modified_time(p_path)
	if _timestamps.has(p_path) and _timestamps[p_path] == mtime:
		return false
	_timestamps[p_path] = mtime
	return true
