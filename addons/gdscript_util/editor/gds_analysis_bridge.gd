# addons/gdscript_util/editor/gds_analysis_bridge.gd
# 信号中继桥 — 解耦分析引擎和编辑器 UI 面板
# 参考: clef-dev/addons/clef/editor/clef_station_editor_bridge.gd

class_name GDSAnalysisBridge
extends RefCounted

# 分析生命周期
signal analysis_started(file_path: String)
signal analysis_completed(result: GDScriptAnalysisResult)
signal analysis_failed(file_path: String, error: String)

# Phase 3.2: 项目分析生命周期
signal project_analysis_started()
signal project_analysis_completed(result: GDScriptProjectResult)

# 面板间联动 — 用户在某面板选中一项，其他面板联动过滤
signal function_selected(func_name: String)
signal signal_selected(signal_name: String)
signal variable_selected(var_name: String)

var _current_result: GDScriptAnalysisResult = null
var _cache: Dictionary = {}  # String(path) → GDScriptAnalysisResult
var _timestamps: Dictionary = {}  # String(path) → int(mtime)

# Phase 3.2: 项目分析
var _project_result: GDScriptProjectResult = null
var _project_analyzer: GDScriptProjectAnalyzer = null


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
# 用 FileAccess 读源码（不用 load()）——避免 Godot 自身编译器卡死/返回 null
func _run_pipeline(p_file_path: String) -> GDScriptAnalysisResult:
	var f = FileAccess.open(p_file_path, FileAccess.READ)
	if f == null:
		return null
	var source = f.get_as_text()
	f.close()
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


# ---- Phase 3.2: 项目分析 ----

# 全量项目分析（deferred，不阻塞）
func run_project_analysis() -> void:
	project_analysis_started.emit()
	# deferred 跑重活
	call_deferred("_do_project_analysis")

func _do_project_analysis() -> void:
	if _project_analyzer == null:
		_project_analyzer = GDScriptProjectAnalyzer.new()
	_project_result = _project_analyzer.analyze_full()  # 不传 root，读配置
	project_analysis_completed.emit(_project_result)

func get_project_result() -> GDScriptProjectResult:
	return _project_result

# 增量: 重分析单文件 + 重建注册表 + 重解析跨文件边
func refresh_file_in_project(p_path: String) -> void:
	if _project_result == null or _project_analyzer == null:
		return  # 项目尚未全量分析过，跳过增量
	var new_result = _project_analyzer._analyze_file(p_path)
	if new_result == null:
		return
	# 检查 class_name 是否变化
	var old_cn = ""
	if _project_result.files.has(p_path):
		old_cn = _project_result.files[p_path].classname_id
	_project_result.files[p_path] = new_result
	if new_result.classname_id != old_cn:
		# class_name 变了 → 重建注册表
		_project_result.class_registry.clear()
		_project_analyzer._build_class_registry(_project_result)
	# 重解析跨文件边（简化: 全量重算 cross_edges，反向索引随之更新）
	_project_result.cross_edges.clear()
	_project_result.reverse_index.clear()
	_project_analyzer.resolve_cross_file(_project_result)
	project_analysis_completed.emit(_project_result)
