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
var _file_label: Label = null
var _legend_button: Button = null
var _legend_box: HBoxContainer = null

func setup(p_bridge: GDSAnalysisBridge, p_l10n: GDSL10n = null) -> void:
	_bridge = p_bridge
	_l10n = p_l10n if p_l10n else GDSL10n.new()
	_bridge.analysis_completed.connect(_on_analysis_completed)
	_build_ui()

func _build_ui() -> void:
	# 底部面板默认可用高度（用户仍可拖拽调整）
	custom_minimum_size = Vector2(0, 240)
	# TabBar 行 — TabBar + 当前文件名 Label
	var tab_row = HBoxContainer.new()
	add_child(tab_row)
	_tab_bar = TabBar.new()
	_tab_bar.clip_tabs = false  # 关键：minimum 含全 tab 总宽（默认 clip_tabs=true 只算最宽单 tab+按钮）
	_tab_bar.size_flags_horizontal = SIZE_SHRINK_BEGIN  # 按 tab 总宽，不占满 → Label 紧跟
	_tab_bar.add_tab(_l10n.t("tab.summary"))       # tab 0
	_tab_bar.add_tab(_l10n.t("tab.call_graph"))    # tab 1
	_tab_bar.add_tab(_l10n.t("tab.signal_flow"))   # tab 2
	_tab_bar.add_tab(_l10n.t("tab.def_use"))       # tab 3
	_tab_bar.add_tab(_l10n.t("tab.project"))       # tab 4
	_tab_bar.tab_changed.connect(_on_tab_changed)
	tab_row.add_child(_tab_bar)
	_file_label = Label.new()
	_file_label.text = "未选择文件"
	_file_label.size_flags_horizontal = SIZE_SHRINK_BEGIN  # 紧跟 TabBar 右侧，不抢占空间
	tab_row.add_child(_file_label)
	_legend_button = Button.new()
	_legend_button.text = "?"
	_legend_button.tooltip_text = "颜色图例"
	_legend_button.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_legend_button.pressed.connect(_on_legend_toggle)
	tab_row.add_child(_legend_button)
	_legend_box = HBoxContainer.new()
	_legend_box.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_legend_box.visible = false
	tab_row.add_child(_legend_box)

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
	# 图例展开时，按新 tab 更新内容
	if _legend_box != null and _legend_box.visible and _get_legend_items(p_tab).size() > 0:
		_populate_legend(p_tab)


func _on_legend_toggle() -> void:
	_legend_box.visible = not _legend_box.visible
	if _legend_box.visible:
		_populate_legend(_tab_bar.current_tab)


func _populate_legend(p_tab: int) -> void:
	for child in _legend_box.get_children():
		child.queue_free()
	var items = _get_legend_items(p_tab)
	for item in items:
		var swatch = ColorRect.new()
		swatch.color = item["color"]
		swatch.custom_minimum_size = Vector2(14, 14)
		_legend_box.add_child(swatch)
		var lbl = Label.new()
		lbl.text = item["label"]
		_legend_box.add_child(lbl)


# 按 tab 返回颜色图例项 [{color, label}]
func _get_legend_items(p_tab: int) -> Array:
	match p_tab:
		1: return [  # Call Graph
			{color=Color.GREEN, label="SELF"},
			{color=Color.DODGER_BLUE, label="SUPER"},
			{color=Color.ORANGE, label="EXTERNAL"},
			{color=Color.MEDIUM_PURPLE, label="CONNECT"},
			{color=Color.PURPLE, label="SIGNAL_CONNECT"},
			{color=Color.CYAN, label="LAMBDA"},
			{color=Color.RED, label="EMIT"},
			{color=Color.GRAY, label="UNUSED"},
		]
		2: return [  # Signal Flow
			{color=Color.RED, label="EMIT"},
			{color=Color.DODGER_BLUE, label="CONNECT"},
			{color=Color.GRAY, label="UNUSED"},
		]
		3: return [  # DefUse
			{color=Color.GREEN, label="DEFINE"},
			{color=Color.DODGER_BLUE, label="READ"},
			{color=Color.ORANGE, label="WRITE"},
			{color=Color.RED, label="READ_WRITE"},
			{color=Color.GRAY, label="UNUSED"},
			{color=Color.MAGENTA, label="WRITE-ONLY"},
			{color=Color.CYAN, label="跨文件"},
		]
		4: return [  # Project
			{color=Color.DODGER_BLUE, label="出向引用"},
			{color=Color.SEA_GREEN, label="入向引用"},
			{color=Color.DIM_GRAY, label="分组标题"},
		]
		_: return []  # Summary 无图例


func _on_analysis_completed(p_result: GDScriptAnalysisResult) -> void:
	if p_result != null and p_result.file_path != "":
		_file_label.text = p_result.file_path.get_file()
	else:
		_file_label.text = "未选择文件"
