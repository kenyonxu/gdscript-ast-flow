# addons/gdscript_util/editor/graphs/../gds_graph_main_screen.gd
# 主屏 tab — Scope(单文件/项目) × Graph(调用/信号) 切换，重建 GraphEdit
# 必须 extends Container（VBoxContainer）——plain Control 不把尺寸传给子节点，
# GraphEdit 会塌缩为 0 高度导致节点不可见（同 Phase 3 底部面板布局教训）

class_name GDSGraphMainScreen
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _graph_edit: GraphEdit = null
var _scope: int = 0  # 0=当前文件, 1=项目
var _graph_kind: int = 0  # 0=调用, 1=信号
var _call_view: GDSCallGraphView = null
var _signal_view: GDSSignalGraphView = null
var _project_view: GDSProjectGraphView = null
var _min_degree: int = 0

func setup(p_bridge: GDSAnalysisBridge) -> void:
	_bridge = p_bridge
	_bridge.analysis_completed.connect(_on_data_changed)
	_bridge.project_analysis_completed.connect(_on_data_changed)
	_call_view = GDSCallGraphView.new()
	_signal_view = GDSSignalGraphView.new()
	_project_view = GDSProjectGraphView.new()
	_build_ui()
	_rebuild()

func _build_ui() -> void:
	# 主屏铺满编辑器主屏区域：
	# - PRESET_FULL_RECT (anchors) — 父级是 Control 时生效
	# - size_flags EXPAND_FILL — 父级是 Container 时生效（编辑器主屏实际是 Container）
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	# 顶部 toolbar
	var toolbar = HBoxContainer.new()
	toolbar.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(toolbar)
	# Scope 切换
	var scope_box = OptionButton.new()
	scope_box.add_item("Scope: Current File", 0)
	scope_box.add_item("Scope: Project", 1)
	scope_box.item_selected.connect(func(i): _scope = i; _rebuild())
	toolbar.add_child(scope_box)
	# Graph 类型切换
	var kind_box = OptionButton.new()
	kind_box.add_item("Graph: Call", 0)
	kind_box.add_item("Graph: Signal", 1)
	kind_box.item_selected.connect(func(i): _graph_kind = i; _rebuild())
	toolbar.add_child(kind_box)
	# Re-layout
	var relayout = Button.new()
	relayout.text = "Re-layout"
	relayout.pressed.connect(_on_relayout)
	toolbar.add_child(relayout)
	# Min-degree 筛选
	var thresh_label = Label.new()
	thresh_label.text = "Min degree:"
	toolbar.add_child(thresh_label)
	var thresh_box = SpinBox.new()
	thresh_box.min_value = 0
	thresh_box.max_value = 20
	thresh_box.value = 0
	thresh_box.value_changed.connect(func(v): _min_degree = v; _rebuild())
	toolbar.add_child(thresh_box)
	# 图例
	var legend = HBoxContainer.new()
	_add_legend_chip(legend, "■ emit", Color.RED)
	_add_legend_chip(legend, "■ connect", Color.DODGER_BLUE)
	_add_legend_chip(legend, "★ 入口", Color.LIME_GREEN)
	_add_legend_chip(legend, "▲ 枢纽", Color.ORANGE_RED)
	add_child(legend)
	# GraphEdit
	_graph_edit = GraphEdit.new()
	_graph_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_graph_edit.size_flags_vertical = SIZE_EXPAND_FILL
	_graph_edit.custom_minimum_size = Vector2(800, 500)  # 兜底：父容器未布局时也可见
	_graph_edit.node_selected.connect(_on_node_selected)
	add_child(_graph_edit)

func _add_legend_chip(p_parent: Control, p_text: String, p_color: Color) -> void:
	var chip = Label.new()
	chip.text = p_text
	chip.add_theme_color_override("font_color", p_color)
	chip.add_theme_font_size_override("font_size", 11)
	p_parent.add_child(chip)

func _on_data_changed(_arg = null) -> void:
	_rebuild()

func _rebuild() -> void:
	# 清空
	for c in _graph_edit.get_children():
		if c is GraphNode:
			c.queue_free()
	_graph_edit.clear_connections()
	# 按 Scope × Kind 分发
	if _scope == 1:
		# 项目级（调用图语义=文件耦合；信号图=跨文件信号）
		_project_view.build(_graph_edit, _bridge.get_project_result(), _graph_kind, _min_degree)
	else:
		if _graph_kind == 0:
			_call_view.build(_graph_edit, _bridge.get_current_result(), _min_degree)
		else:
			_signal_view.build(_graph_edit, _bridge.get_current_result(), _min_degree)


func _on_node_selected(p_node: Node) -> void:
	if not (p_node is GDSGraphNode):
		return
	# metadata 在 configure 时存（需 view 创建节点时 set_meta）
	var meta = p_node.get_meta("jump", {})
	if meta.has("file") and meta.has("line") and meta["file"] != "":
		var script = load(meta["file"])
		if script != null:
			EditorInterface.edit_script(script, int(meta["line"]))
	# 关联高亮：淡化非关联节点
	_highlight_related(p_node)

func _highlight_related(p_selected: GraphNode) -> void:
	# 简化：选中节点 + 与它同名前缀相关的保持正常，其余淡化
	for c in _graph_edit.get_children():
		if c is GraphNode and c != p_selected:
			c.modulate.a = 0.3  # 淡化
	# 再选别的或重建时恢复（_rebuild 重建会重置 modulate）

func _on_relayout() -> void:
	_graph_edit.arrange_nodes()  # Godot 4 GraphEdit 内置自动布局
