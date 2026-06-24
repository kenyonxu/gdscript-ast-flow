# addons/gdscript_util/editor/panels/gds_analysis_main_panel.gd
# 底部主面板 — TabBar 切换 4 个子面板（Summary / Call Graph / Signal Flow / Def-Use）

class_name GDSAnalysisMainPanel
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _l10n: GDSL10n = null
var _tab_bar: TabBar = null
var _content_stack: Control = null

var _summary_panel: GDSAnalysisSummary = null
var _call_graph_panel: GDSCallGraphPanel = null
var _signal_flow_panel: GDSSignalFlowPanel = null
var _def_use_panel: GDSDefUsePanel = null
var _project_panel: GDSProjectPanel = null

func setup(p_bridge: GDSAnalysisBridge, p_l10n: GDSL10n = null) -> void:
	_bridge = p_bridge
	_l10n = p_l10n if p_l10n else GDSL10n.new()
	_build_ui()

func _build_ui() -> void:
	# 底部面板默认可用高度（用户仍可拖拽调整）
	custom_minimum_size = Vector2(0, 240)
	# TabBar
	_tab_bar = TabBar.new()
	_tab_bar.add_tab(_l10n.t("tab.summary"))       # tab 0
	_tab_bar.add_tab(_l10n.t("tab.call_graph"))    # tab 1
	_tab_bar.add_tab(_l10n.t("tab.signal_flow"))   # tab 2
	_tab_bar.add_tab(_l10n.t("tab.def_use"))       # tab 3
	_tab_bar.add_tab(_l10n.t("tab.project"))       # tab 4
	_tab_bar.tab_changed.connect(_on_tab_changed)
	add_child(_tab_bar)

	# 内容区 — 必须是 Container，子面板的 size_flags 才会生效并填满底部 dock
	# (plain Control 不会把尺寸传给子节点，导致面板缩成最小尺寸)
	_content_stack = VBoxContainer.new()
	_content_stack.size_flags_horizontal = SIZE_EXPAND_FILL
	_content_stack.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_content_stack)

	# 4 个子面板（初始只显示第一个 Summary）
	# 每个 panel 都设 EXPAND_FILL，VBoxContainer 中可见的那个会占满剩余空间
	_summary_panel = GDSAnalysisSummary.new()
	_summary_panel.setup(_bridge, _l10n)
	_make_fill(_summary_panel)
	_content_stack.add_child(_summary_panel)

	_call_graph_panel = GDSCallGraphPanel.new()
	_call_graph_panel.setup(_bridge, _l10n)
	_make_fill(_call_graph_panel)
	_call_graph_panel.visible = false
	_content_stack.add_child(_call_graph_panel)

	_signal_flow_panel = GDSSignalFlowPanel.new()
	_signal_flow_panel.setup(_bridge, _l10n)
	_make_fill(_signal_flow_panel)
	_signal_flow_panel.visible = false
	_content_stack.add_child(_signal_flow_panel)

	_def_use_panel = GDSDefUsePanel.new()
	_def_use_panel.setup(_bridge, _l10n)
	_make_fill(_def_use_panel)
	_def_use_panel.visible = false
	_content_stack.add_child(_def_use_panel)

	_project_panel = GDSProjectPanel.new()
	_project_panel.setup(_bridge, _l10n)
	_make_fill(_project_panel)
	_project_panel.visible = false
	_content_stack.add_child(_project_panel)


# 让子面板填满父容器（水平+垂直都 EXPAND_FILL）
func _make_fill(p_control: Control) -> void:
	p_control.size_flags_horizontal = SIZE_EXPAND_FILL
	p_control.size_flags_vertical = SIZE_EXPAND_FILL

func _on_tab_changed(p_tab: int) -> void:
	_summary_panel.visible = (p_tab == 0)
	_call_graph_panel.visible = (p_tab == 1)
	_signal_flow_panel.visible = (p_tab == 2)
	_def_use_panel.visible = (p_tab == 3)
	_project_panel.visible = (p_tab == 4)
