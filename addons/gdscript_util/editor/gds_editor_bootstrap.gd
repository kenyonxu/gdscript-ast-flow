# addons/gdscript_util/editor/gds_editor_bootstrap.gd
# 模块化启动 — 将 plugin.gd 的 Phase 3 初始化拆分为独立类
# 参考: project-juicy-godot/addons/fuse/editor/bootstrap/fuse_editor_bootstrap.gd

class_name GDSEditorBootstrap
extends RefCounted

var _plugin: EditorPlugin = null
var _bridge: GDSAnalysisBridge = null
var _main_panel: GDSAnalysisMainPanel = null
var _analysis_queued: String = ""  # 待分析路径（非空表示有待执行）
var _is_analyzing: bool = false    # 重入保护

func setup(p_plugin: EditorPlugin) -> void:
	_plugin = p_plugin
	_bridge = GDSAnalysisBridge.new()

	# 底部面板 — 含 4 个子 tab（Summary / Call Graph / Signal Flow / Def-Use）
	_main_panel = GDSAnalysisMainPanel.new()
	_main_panel.setup(_bridge)
	_plugin.add_control_to_bottom_panel(_main_panel, "GDScript Analysis")

	_plugin.resource_saved.connect(_on_resource_saved)

	# Phase 3.2: 首次启动 deferred 全量项目分析
	call_deferred("_initial_project_scan")

func teardown() -> void:
	if _plugin.resource_saved.is_connected(_on_resource_saved):
		_plugin.resource_saved.disconnect(_on_resource_saved)

	if _main_panel and is_instance_valid(_main_panel):
		_plugin.remove_control_from_bottom_panel(_main_panel)
		_main_panel.queue_free()

func _on_resource_saved(resource: Resource) -> void:
	if resource is GDScript and resource.resource_path.ends_with(".gd"):
		# 不在 save 回调里同步跑重活（会阻塞编辑器）—— 延迟到下一帧
		# 连续保存只保留最后一次目标（去抖）
		_analysis_queued = resource.resource_path
		if not _is_analyzing:
			call_deferred("_run_queued_analysis")

func _run_queued_analysis() -> void:
	if _analysis_queued == "":
		return
	_is_analyzing = true
	var path = _analysis_queued
	_analysis_queued = ""
	_bridge.run_analysis(path)
	# Phase 3.2 增量: 若已有项目结果，重分析该文件 + 重解析跨文件边
	_bridge.refresh_file_in_project(path)
	_is_analyzing = false
	# 若期间又有新保存请求，继续处理
	if _analysis_queued != "":
		call_deferred("_run_queued_analysis")

func _initial_project_scan() -> void:
	_bridge.run_project_analysis("res://")
