# addons/gdscript_ast/editor/panels/gds_def_use_panel.gd
# 变量读写子面板 — Tree 表格式 DEF/READ/WRITE 显示
# 参考: project-juicy-godot/addons/fuse/editor/debugging/variable_watcher.gd

class_name GDSDefUsePanel
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _l10n: GDSL10n = null
var _tree: Tree = null
var _context_menu: PopupMenu = null

const COLORS := {
	0: Color.GREEN,         # DEFINE
	1: Color.DODGER_BLUE,   # READ
	2: Color.ORANGE,        # WRITE
	3: Color.RED,           # READ_WRITE
}

# 未使用高亮配色 — 辅助色系，与 COLORS 的读写动作语义隔离
const USAGE_COLORS := {
	"unused": Color.GRAY,          # 完全死变量
	"write_only": Color.MAGENTA,   # 只写不读 dead store
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
	_tree.allow_rmb_select = true  # 右键选中 + 触发 item_mouse_selected
	_tree.item_selected.connect(_on_item_selected)
	_tree.item_activated.connect(_on_item_activated)  # 双击
	_tree.item_mouse_selected.connect(_on_item_rmb)   # 右键
	add_child(_tree)

	# 右键上下文菜单（仅 site 行有效）
	_context_menu = PopupMenu.new()
	_context_menu.add_item("跳转到定义", 0)
	_context_menu.add_item("复制 脚本:行", 1)
	_context_menu.add_item("在主屏选中变量", 2)
	_context_menu.id_pressed.connect(_on_context_action)
	add_child(_context_menu)

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
		_apply_usage_highlight(item, var_name, info)

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
	# 列 1: 函数名() [脚本名.gd] — 脚本来源标注
	var script_name = p_site.script_path.get_file() if p_site.script_path != "" else "?"
	child.set_text(1, "%s() [%s]" % [p_site.enclosing_function, script_name])
	child.set_text(2, "line %d" % p_site.line)
	# tooltip: 完整路径 · 函数 · 行
	var path_for_tip = p_site.script_path if p_site.script_path != "" else "?"
	child.set_tooltip_text(1, "%s · %s() · line %d" % [
		path_for_tip, p_site.enclosing_function, p_site.line
	])
	child.set_metadata(0, {"kind": "site", "site": p_site})
	if COLORS.has(p_site.access_type):
		child.set_custom_color(0, COLORS[p_site.access_type])

func _kind_string(p_info) -> String:
	if p_info.def_site != null and p_info.def_site.access_type == 0:
		return "var/const"
	return "param"

# 未使用变量高亮 — `_` 开头占位变量排除
# 染变量名行 + Kind 列覆盖为 UNUSED/WRITE-ONLY（原类型移 tooltip）
func _apply_usage_highlight(p_item: TreeItem, p_name: String, p_info) -> void:
	if p_name.begins_with("_"):
		return
	var status = p_info.get_usage_status()
	if status == "normal":
		return
	if USAGE_COLORS.has(status):
		p_item.set_custom_color(0, USAGE_COLORS[status])
	var orig_kind = _kind_string(p_info)
	if status == "unused":
		p_item.set_text(1, "UNUSED")
	else:
		p_item.set_text(1, "WRITE-ONLY")
	p_item.set_tooltip_text(0, "%s · %s" % [p_name, orig_kind])

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

# 双击 site 行 → 跳转源码
func _on_item_activated() -> void:
	var item = _tree.get_selected()
	if item == null:
		return
	var meta = item.get_metadata(0)
	if meta == null or meta.get("kind", "") != "site":
		return
	_jump_to_site(meta["site"])

# 右键 → 仅 site 行弹菜单
func _on_item_rmb(_p_position: Vector2, p_mouse_button_index: int) -> void:
	if p_mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var item = _tree.get_selected()
	if item == null:
		return
	var meta = item.get_metadata(0)
	if meta != null and meta.get("kind", "") == "site":
		_context_menu.popup_on_parent(Rect2(get_global_mouse_position(), Vector2.ZERO))

# 菜单动作分发
func _on_context_action(p_id: int) -> void:
	var item = _tree.get_selected()
	if item == null:
		return
	var meta = item.get_metadata(0)
	if meta == null or meta.get("kind", "") != "site":
		return
	var site = meta["site"]
	match p_id:
		0: _jump_to_site(site)
		1: DisplayServer.clipboard_set("%s:%d" % [site.script_path, site.line])
		2:
			var parent = item.get_parent()
			if parent != null:
				var pm = parent.get_metadata(0)
				if pm != null and pm.get("kind", "") == "variable":
					_bridge.select_variable(pm["name"])

# 跳转到 site 对应源码行（尊重主屏锁定）
func _jump_to_site(p_site) -> void:
	if GDSGraphMainScreen.is_locked:
		return
	if p_site == null or p_site.line <= 0:
		return
	var result = _bridge.get_current_result()
	if result == null or result.file_path.is_empty():
		return
	EditorInterface.edit_script(load(result.file_path), p_site.line)
	EditorInterface.set_main_screen_editor("Script")

func _on_variable_selected(p_name: String) -> void:
	# Phase 3.1: 联动预留
	pass
