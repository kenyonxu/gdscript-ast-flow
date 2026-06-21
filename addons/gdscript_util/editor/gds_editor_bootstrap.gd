# addons/gdscript_util/editor/gds_editor_bootstrap.gd
# 模块化启动 — 将 plugin.gd 的 Phase 3 初始化拆分为独立类
# 参考: project-juicy-godot/addons/fuse/editor/bootstrap/fuse_editor_bootstrap.gd

class_name GDSEditorBootstrap
extends RefCounted

var _plugin: EditorPlugin = null
var _bridge: GDSAnalysisBridge = null
var _main_panel: GDSAnalysisMainPanel = null
var _summary_panel: GDSAnalysisSummary = null

func setup(p_plugin: EditorPlugin) -> void:
	_plugin = p_plugin
	_bridge = GDSAnalysisBridge.new()

	_main_panel = GDSAnalysisMainPanel.new()
	_main_panel.setup(_bridge)
	_plugin.add_control_to_bottom_panel(_main_panel, "GDScript Analysis")

	_summary_panel = GDSAnalysisSummary.new()
	_summary_panel.setup(_bridge)
	_summary_panel.name = "Analysis Summary"  # dock tab 标题取自 .name
	_plugin.add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BR, _summary_panel)

	_plugin.resource_saved.connect(_on_resource_saved)

func teardown() -> void:
	if _plugin.resource_saved.is_connected(_on_resource_saved):
		_plugin.resource_saved.disconnect(_on_resource_saved)

	if _main_panel and is_instance_valid(_main_panel):
		_plugin.remove_control_from_bottom_panel(_main_panel)
		_main_panel.queue_free()
	if _summary_panel and is_instance_valid(_summary_panel):
		_plugin.remove_control_from_docks(_summary_panel)
		_summary_panel.queue_free()

func _on_resource_saved(resource: Resource) -> void:
	if resource is GDScript and resource.resource_path.ends_with(".gd"):
		_bridge.run_analysis(resource.resource_path)
