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
	# GraphEdit
	_graph_edit = GraphEdit.new()
	_graph_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_graph_edit.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_graph_edit)

func _on_data_changed(_arg = null) -> void:
	_rebuild()

func _rebuild() -> void:
	print("[D rebuild] scope=%d kind=%d visible=%s graph_edit=%s size=%s" % [_scope, _graph_kind, visible, is_instance_valid(_graph_edit), _graph_edit.size if is_instance_valid(_graph_edit) else "<null>"])
	# 清空
	for c in _graph_edit.get_children():
		if c is GraphNode:
			c.queue_free()
	_graph_edit.clear_connections()
	# 按 Scope × Kind 分发
	if _scope == 1:
		# 项目级（调用图语义=文件耦合；信号图=跨文件信号）
		print("[D rebuild] project_result=%s" % [_bridge.get_project_result()])
		_project_view.build(_graph_edit, _bridge.get_project_result(), _graph_kind)
	else:
		print("[D rebuild] current_result=%s" % [_bridge.get_current_result()])
		if _graph_kind == 0:
			_call_view.build(_graph_edit, _bridge.get_current_result())
		else:
			_signal_view.build(_graph_edit, _bridge.get_current_result())

func _on_relayout() -> void:
	_graph_edit.arrange_nodes()  # Godot 4 GraphEdit 内置自动布局
