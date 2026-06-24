# addons/gdscript_util/editor/panels/gds_analysis_summary.gd
# Dock 摘要面板 — 文件级分析摘要 + 错误列表

class_name GDSAnalysisSummary
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _l10n: GDSL10n = null
var _summary_label: RichTextLabel = null
var _error_list: Tree = null

func setup(p_bridge: GDSAnalysisBridge, p_l10n: GDSL10n = null) -> void:
	_bridge = p_bridge
	_l10n = p_l10n if p_l10n else GDSL10n.new()
	_bridge.analysis_completed.connect(_refresh)
	_build_ui()

func _build_ui() -> void:
	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = true
	_summary_label.custom_minimum_size = Vector2(200, 120)
	_summary_label.size_flags_horizontal = SIZE_EXPAND_FILL
	# 空状态占位 — 分析前不显示空白
	_summary_label.append_text("[i]Save a .gd file to analyze.[/i]")
	add_child(_summary_label)

	_error_list = Tree.new()
	_error_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_error_list.size_flags_vertical = SIZE_EXPAND_FILL
	_error_list.hide_root = true
	_error_list.columns = 1
	add_child(_error_list)

func _refresh(p_result: GDScriptAnalysisResult) -> void:
	_summary_label.clear()
	_summary_label.append_text("[b]File:[/b] %s\n" % p_result.file_path)
	_summary_label.append_text("[b]Class:[/b] %s\n" % p_result.classname_id)
	_summary_label.append_text("[b]Functions:[/b] %d\n" % p_result.get_all_functions().size())
	_summary_label.append_text("[b]Signals:[/b] %d\n" % p_result.get_all_signals().size())

	if p_result.call_graph:
		_summary_label.append_text("[b]Call Edges:[/b] %d\n" % p_result.call_graph.edges.size())
	if p_result.signal_graph:
		_summary_label.append_text("[b]Signal Flows:[/b] %d\n" % p_result.signal_graph.signals.size())

	# 错误列表
	_error_list.clear()
	var root = _error_list.create_item()
	for err in p_result.errors:
		var item = _error_list.create_item(root)
		item.set_text(0, err)
		item.set_custom_color(0, Color.YELLOW)
