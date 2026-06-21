# addons/gdscript_util/editor/gds_editor_bootstrap.gd
# 模块化启动 — 将 plugin.gd 的 Phase 3 初始化拆分为独立类
# 参考: project-juicy-godot/addons/fuse/editor/bootstrap/fuse_editor_bootstrap.gd

class_name GDSEditorBootstrap
extends RefCounted

var _plugin: EditorPlugin = null
var _bridge: GDSAnalysisBridge = null
var _main_panel: GDSAnalysisMainPanel = null

func setup(p_plugin: EditorPlugin) -> void:
	_plugin = p_plugin
	_bridge = GDSAnalysisBridge.new()

	# 底部面板 — 含 4 个子 tab（Summary / Call Graph / Signal Flow / Def-Use）
	# Summary 作为第 1 个 tab，不再用右侧 Dock（避免侵入检查器区域）
	_main_panel = GDSAnalysisMainPanel.new()
	_main_panel.setup(_bridge)
	_plugin.add_control_to_bottom_panel(_main_panel, "GDScript Analysis")

	_plugin.resource_saved.connect(_on_resource_saved)

func teardown() -> void:
	if _plugin.resource_saved.is_connected(_on_resource_saved):
		_plugin.resource_saved.disconnect(_on_resource_saved)

	if _main_panel and is_instance_valid(_main_panel):
		_plugin.remove_control_from_bottom_panel(_main_panel)
		_main_panel.queue_free()

func _on_resource_saved(resource: Resource) -> void:
	if resource is GDScript and resource.resource_path.ends_with(".gd"):
		_bridge.run_analysis(resource.resource_path)
