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

func run_analysis(p_file_path: String) -> void:
	analysis_started.emit(p_file_path)
	# 调用 Phase 1+2 管道 — plugin.gd 中已有的 analyze_script()
	var result = GDScriptUtil.analyze_script(p_file_path)
	if result == null:
		analysis_failed.emit(p_file_path, "Parse error or file not found")
		return
	_current_result = result
	_cache[p_file_path] = result
	analysis_completed.emit(result)

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
