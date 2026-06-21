# addons/gdscript_util/editor/panels/gds_analysis_main_panel.gd
# 底部主面板 — TabBar 切换 4 个子面板（Summary / Call Graph / Signal Flow / Def-Use）

class_name GDSAnalysisMainPanel
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _tab_bar: TabBar = null
var _content_stack: Control = null

var _summary_panel: GDSAnalysisSummary = null
var _call_graph_panel: GDSCallGraphPanel = null
var _signal_flow_panel: GDSSignalFlowPanel = null
var _def_use_panel: GDSDefUsePanel = null

func setup(p_bridge: GDSAnalysisBridge) -> void:
	_bridge = p_bridge
	_build_ui()

func _build_ui() -> void:
	# TabBar
	_tab_bar = TabBar.new()
	_tab_bar.add_tab("Summary")       # tab 0
	_tab_bar.add_tab("Call Graph")    # tab 1
	_tab_bar.add_tab("Signal Flow")   # tab 2
	_tab_bar.add_tab("Def-Use")       # tab 3
	_tab_bar.tab_changed.connect(_on_tab_changed)
	add_child(_tab_bar)

	# 内容区
	_content_stack = Control.new()
	_content_stack.size_flags_horizontal = SIZE_EXPAND_FILL
	_content_stack.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_content_stack)

	# 4 个子面板（初始只显示第一个 Summary）
	_summary_panel = GDSAnalysisSummary.new()
	_summary_panel.setup(_bridge)
	_content_stack.add_child(_summary_panel)

	_call_graph_panel = GDSCallGraphPanel.new()
	_call_graph_panel.setup(_bridge)
	_call_graph_panel.visible = false
	_content_stack.add_child(_call_graph_panel)

	_signal_flow_panel = GDSSignalFlowPanel.new()
	_signal_flow_panel.setup(_bridge)
	_signal_flow_panel.visible = false
	_content_stack.add_child(_signal_flow_panel)

	_def_use_panel = GDSDefUsePanel.new()
	_def_use_panel.setup(_bridge)
	_def_use_panel.visible = false
	_content_stack.add_child(_def_use_panel)

func _on_tab_changed(p_tab: int) -> void:
	_summary_panel.visible = (p_tab == 0)
	_call_graph_panel.visible = (p_tab == 1)
	_signal_flow_panel.visible = (p_tab == 2)
	_def_use_panel.visible = (p_tab == 3)
