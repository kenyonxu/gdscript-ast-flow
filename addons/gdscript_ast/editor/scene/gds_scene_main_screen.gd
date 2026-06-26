# addons/gdscript_ast/editor/scene/gds_scene_main_screen.gd
# 场景可视化主屏容器 — 视角 toolbar + 3 视角 + navigate_to_node 联动
# Chunk A2: 容器骨架

class_name GDSSceneMainScreen
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _l10n: GDSL10n = null
var _node_tree_view = null  # SceneNodeTreeView
var _script_lookup_view = null  # SceneScriptLookupView
var _signal_graph_view = null  # SceneSignalGraphView
var _active_view: Control = null  # 当前活跃视角
var _toolbar_box: OptionButton = null
var _empty_label: Label = null  # 空状态/错误提示

func setup(p_bridge, p_l10n = null) -> void:
	_bridge = p_bridge
	_l10n = p_l10n if p_l10n else GDSL10n.new()
	_bridge.project_analysis_completed.connect(_on_data_changed)
	# 懒实例化 3 视角
	_node_tree_view = preload("scene_node_tree_view.gd").new()
	_script_lookup_view = preload("scene_script_lookup_view.gd").new()
	_signal_graph_view = preload("scene_signal_graph_view.gd").new()
	for v in [_node_tree_view, _script_lookup_view, _signal_graph_view]:
		v.setup(_bridge, _l10n, Callable(self, "_navigate_to_node"))
	_build_ui()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL

	# 视角 toolbar
	var toolbar = HBoxContainer.new()
	toolbar.size_flags_horizontal = SIZE_EXPAND_FILL
	toolbar.size_flags_vertical = 0
	add_child(toolbar)

	_toolbar_box = OptionButton.new()
	_toolbar_box.add_item(_l10n.t("view.node_tree"), 0)
	_toolbar_box.add_item(_l10n.t("view.script_lookup"), 1)
	_toolbar_box.add_item(_l10n.t("view.signal_graph"), 2)
	_toolbar_box.item_selected.connect(_on_view_changed)
	toolbar.add_child(_toolbar_box)

	# 空状态标签（默认隐藏）
	_empty_label = Label.new()
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_empty_label.size_flags_vertical = SIZE_EXPAND_FILL
	_empty_label.visible = false
	add_child(_empty_label)

	# 3 视角（默认隐藏）
	for v in [_node_tree_view, _script_lookup_view, _signal_graph_view]:
		v.size_flags_horizontal = SIZE_EXPAND_FILL
		v.size_flags_vertical = SIZE_EXPAND_FILL
		v.visible = false
		add_child(v)

	_active_view = _node_tree_view
	_node_tree_view.visible = true

func _on_view_changed(i: int) -> void:
	if _active_view:
		_active_view.visible = false
	var views = [_node_tree_view, _script_lookup_view, _signal_graph_view]
	_active_view = views[i]
	_active_view.visible = true
	_active_view.rebuild()

func rebuild_active() -> void:
	# 先检查项目扫描状态 / 空数据
	if _bridge == null:
		return

	if not GDSScanConfig.is_enabled():
		_show_empty(_l10n.t("msg.scan_disabled"))
		return

	var proj = _bridge.get_project_result()
	if proj == null or proj.scenes.is_empty():
		_show_empty(_l10n.t("msg.no_project_data"))
		return

	_hide_empty()
	if _active_view:
		_active_view.rebuild()

func _show_empty(p_text: String) -> void:
	_empty_label.text = p_text
	_empty_label.visible = true
	for v in [_node_tree_view, _script_lookup_view, _signal_graph_view]:
		v.visible = false
	if _toolbar_box:
		_toolbar_box.visible = false

func _hide_empty() -> void:
	_empty_label.visible = false
	if _toolbar_box:
		_toolbar_box.visible = true

# ——— 视角联动入口 ———
func _navigate_to_node(scene_path: String, node_path: String) -> void:
	if _active_view:
		_active_view.visible = false
	_active_view = _node_tree_view
	_node_tree_view.visible = true
	_node_tree_view.focus_node(scene_path, node_path)
	# 同步 toolbar 选中状态
	_toolbar_box.select(0)

func _on_data_changed(_arg = null) -> void:
	rebuild_active()
