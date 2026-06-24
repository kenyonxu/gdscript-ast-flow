# addons/gdscript_util/editor/panels/gds_signal_flow_panel.gd
# 信号流子面板 — Tree 显示每个信号的 emit/connect 站点

class_name GDSSignalFlowPanel
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _l10n: GDSL10n = null
var _tree: Tree = null

func setup(p_bridge: GDSAnalysisBridge, p_l10n: GDSL10n = null) -> void:
	_bridge = p_bridge
	_l10n = p_l10n if p_l10n else GDSL10n.new()
	_bridge.analysis_completed.connect(_refresh)
	_build_ui()

func _build_ui() -> void:
	_tree = Tree.new()
	_tree.size_flags_horizontal = SIZE_EXPAND_FILL
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 1
	_tree.item_selected.connect(_on_item_selected)
	add_child(_tree)

func _refresh(p_result: GDScriptAnalysisResult) -> void:
	_tree.clear()
	if p_result.signal_graph == null:
		return

	var root = _tree.create_item()
	for sig_name in p_result.signal_graph.signals:
		var info = p_result.signal_graph.signals[sig_name]
		var sig_item = _tree.create_item(root)
		if info.declaration != null:
			sig_item.set_text(0, "signal %s (decl @%d)" % [sig_name, info.declaration.line])
		else:
			sig_item.set_text(0, "signal %s (external)" % sig_name)
		sig_item.set_metadata(0, {"kind": "signal", "name": sig_name})

		for site in info.emit_sites:
			var emit_item = _tree.create_item(sig_item)
			emit_item.set_text(0, "  EMIT: %s() @line %d" % [site.enclosing_function, site.line])
			emit_item.set_metadata(0, {"kind": "site", "site": site})
			emit_item.set_custom_color(0, Color.RED)

		for site in info.connect_sites:
			var conn_item = _tree.create_item(sig_item)
			conn_item.set_text(0, "  CONNECT: %s() @line %d" % [site.enclosing_function, site.line])
			conn_item.set_metadata(0, {"kind": "site", "site": site})
			conn_item.set_custom_color(0, Color.DODGER_BLUE)

func _on_item_selected() -> void:
	var item = _tree.get_selected()
	if item == null:
		return
	var meta = item.get_metadata(0)
	if meta == null:
		return
	if meta.get("kind", "") == "signal":
		_bridge.select_signal(meta["name"])
	elif meta.get("kind", "") == "site" and item.get_parent() != null:
		var parent_meta = item.get_parent().get_metadata(0)
		if parent_meta != null and parent_meta.get("kind", "") == "signal":
			_bridge.select_signal(parent_meta["name"])
