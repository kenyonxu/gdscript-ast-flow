# addons/gdscript_ast/editor/panels/gds_analysis_main_panel.gd
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
var _wrappers: Array = []  # PanelContainer wrappers（边框+底色）

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

	# 5 个子面板（包 PanelContainer 边框+底色，初始只显示 Summary）
	_summary_panel = GDSAnalysisSummary.new()
	_summary_panel.setup(_bridge, _l10n)
	_wrappers.append(_wrap_panel(_summary_panel))

	_call_graph_panel = GDSCallGraphPanel.new()
	_call_graph_panel.setup(_bridge, _l10n)
	_wrappers.append(_wrap_panel(_call_graph_panel))

	_signal_flow_panel = GDSSignalFlowPanel.new()
	_signal_flow_panel.setup(_bridge, _l10n)
	_wrappers.append(_wrap_panel(_signal_flow_panel))

	_def_use_panel = GDSDefUsePanel.new()
	_def_use_panel.setup(_bridge, _l10n)
	_wrappers.append(_wrap_panel(_def_use_panel))

	_project_panel = GDSProjectPanel.new()
	_project_panel.setup(_bridge, _l10n)
	_wrappers.append(_wrap_panel(_project_panel))

	for i in range(_wrappers.size()):
		_make_fill(_wrappers[i])
		_wrappers[i].visible = (i == 0)
		_content_stack.add_child(_wrappers[i])


# 让子面板填满父容器（水平+垂直都 EXPAND_FILL）
func _make_fill(p_control: Control) -> void:
	p_control.size_flags_horizontal = SIZE_EXPAND_FILL
	p_control.size_flags_vertical = SIZE_EXPAND_FILL


# 子面板包 PanelContainer（边框+底色，视觉分块）
func _wrap_panel(p_panel: Control) -> PanelContainer:
	var wrapper = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.12)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.30, 0.30, 0.35)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	wrapper.add_theme_stylebox_override("panel", style)
	wrapper.add_child(p_panel)
	return wrapper

func _on_tab_changed(p_tab: int) -> void:
	for i in range(_wrappers.size()):
		_wrappers[i].visible = (i == p_tab)
