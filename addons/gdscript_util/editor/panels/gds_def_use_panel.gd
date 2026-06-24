# addons/gdscript_util/editor/panels/gds_def_use_panel.gd
# 变量读写子面板 — Tree 表格式 DEF/READ/WRITE 显示
# 参考: project-juicy-godot/addons/fuse/editor/debugging/variable_watcher.gd

class_name GDSDefUsePanel
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _l10n: GDSL10n = null
var _tree: Tree = null

const COLORS := {
	0: Color.GREEN,         # DEFINE
	1: Color.DODGER_BLUE,   # READ
	2: Color.ORANGE,        # WRITE
	3: Color.RED,           # READ_WRITE
}

func setup(p_bridge: GDSAnalysisBridge, p_l10n: GDSL10n = null) -> void:
	_bridge = p_bridge
	_l10n = p_l10n if p_l10n else GDSL10n.new()
	_bridge.analysis_completed.connect(_refresh)
	_bridge.variable_selected.connect(_on_variable_selected)
	_build_ui()

func _build_ui() -> void:
	_tree = Tree.new()
	_tree.size_flags_horizontal = SIZE_EXPAND_FILL
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 3
	_tree.set_column_title(0, "Variable")
	_tree.set_column_title(1, "Kind")
	_tree.set_column_title(2, "Sites")
	_tree.item_selected.connect(_on_item_selected)
	add_child(_tree)

func _refresh(p_result: GDScriptAnalysisResult) -> void:
	_tree.clear()
	if p_result.def_use_chain == null:
		return

	var root = _tree.create_item()
	for var_name in p_result.def_use_chain.variables:
		var info = p_result.def_use_chain.variables[var_name]
		var item = _tree.create_item(root)
		item.set_text(0, var_name)
		item.set_text(1, _kind_string(info))
		item.set_text(2, "%d DEF, %d READ, %d WRITE" % [
			1 if info.def_site != null else 0,
			info.read_sites.size(),
			info.write_sites.size()
		])
		item.set_metadata(0, {"kind": "variable", "name": var_name})

		# 子项 — 每个 site 一行
		_add_site_items(item, info.def_site, "DEF")
		for s in info.read_sites:
			_add_site_items(item, s, "READ")
		for s in info.write_sites:
			_add_site_items(item, s, "WRITE")

func _add_site_items(p_parent: TreeItem, p_site, p_label: String) -> void:
	if p_site == null:
		return
	var child = _tree.create_item(p_parent)
	child.set_text(0, "  %s" % p_label)
	child.set_text(1, p_site.enclosing_function + "()")
	child.set_text(2, "line %d" % p_site.line)
	child.set_metadata(0, {"kind": "site", "site": p_site})
	if COLORS.has(p_site.access_type):
		child.set_custom_color(0, COLORS[p_site.access_type])

func _kind_string(p_info) -> String:
	if p_info.def_site != null and p_info.def_site.access_type == 0:
		return "var/const"
	return "param"

func _on_item_selected() -> void:
	var item = _tree.get_selected()
	if item == null:
		return
	var meta = item.get_metadata(0)
	if meta == null:
		return
	if meta.get("kind", "") == "variable":
		_bridge.select_variable(meta["name"])
	elif meta.get("kind", "") == "site" and item.get_parent() != null:
		var parent_meta = item.get_parent().get_metadata(0)
		if parent_meta != null and parent_meta.get("kind", "") == "variable":
			_bridge.select_variable(parent_meta["name"])

func _on_variable_selected(p_name: String) -> void:
	# Phase 3.1: 联动预留
	pass
