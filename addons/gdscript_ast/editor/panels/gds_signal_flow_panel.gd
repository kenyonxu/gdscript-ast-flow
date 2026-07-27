# addons/gdscript_ast/editor/panels/gds_signal_flow_panel.gd
# 信号流子面板 — Tree 显示每个信号的 emit/connect 站点

class_name GDSSignalFlowPanel
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _l10n: GDSL10n = null
var _tree: Tree = null
var _search_edit: LineEdit = null
var _context_menu: PopupMenu = null

# 未连接信号高亮配色 — 与 EMIT(红)/CONNECT(蓝) 区分
const UNUSED_SIGNAL_COLOR := Color.GRAY

func setup(p_bridge: GDSAnalysisBridge, p_l10n: GDSL10n = null) -> void:
	_bridge = p_bridge
	_l10n = p_l10n if p_l10n else GDSL10n.new()
	_bridge.analysis_completed.connect(_refresh)
	_build_ui()

func _build_ui() -> void:
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "搜索信号..."
	_search_edit.text_changed.connect(_on_search_changed)
	add_child(_search_edit)

	_tree = Tree.new()
	_tree.size_flags_horizontal = SIZE_EXPAND_FILL
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 1
	_tree.allow_rmb_select = true
	_tree.item_selected.connect(_on_item_selected)
	_tree.item_activated.connect(_on_item_activated)
	_tree.item_mouse_selected.connect(_on_item_rmb)
	add_child(_tree)

	_context_menu = PopupMenu.new()
	_context_menu.add_item("跳转到定义", 0)
	_context_menu.add_item("复制 脚本:行", 1)
	_context_menu.add_item("选中信号", 2)
	_context_menu.id_pressed.connect(_on_context_action)
	add_child(_context_menu)

func _on_search_changed(p_text: String) -> void:
	GDSTreeSearch.highlight(_tree, p_text, 0)

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
	var result = _bridge.get_current_result()
	match p_id:
		0: _jump_to_site(site)
		1:
			if result != null:
				DisplayServer.clipboard_set("%s:%d" % [result.file_path, site.line])
		2:
			var parent = item.get_parent()
			if parent != null:
				var pm = parent.get_metadata(0)
				if pm != null and pm.get("kind", "") == "signal":
					_bridge.select_signal(pm["name"])

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
		_apply_unused_highlight(sig_item, sig_name, info)

		for site in info.emit_sites:
			var emit_item = _tree.create_item(sig_item)
			var args_str = GDSExprFormatter.format_args(site.arguments)
			emit_item.set_text(0, "  EMIT %s(%s) @L%d in %s()" % [sig_name, args_str, site.line, site.enclosing_function])
			emit_item.set_metadata(0, {"kind": "site", "site": site})
			emit_item.set_custom_color(0, Color.RED)

		for site in info.connect_sites:
			var conn_item = _tree.create_item(sig_item)
			var cb_str = "?"
			if site.arguments != null and site.arguments.size() > 0:
				cb_str = GDSExprFormatter.format(site.arguments[0])
			conn_item.set_text(0, "  CONNECT %s → %s @L%d in %s()" % [sig_name, cb_str, site.line, site.enclosing_function])
			conn_item.set_metadata(0, {"kind": "site", "site": site})
			conn_item.set_custom_color(0, Color.DODGER_BLUE)

	# 重建 items 后重应用搜索高亮（text 未变不触发 text_changed）
	if _search_edit != null and _search_edit.text != "":
		_on_search_changed(_search_edit.text)

# 未连接信号高亮 — `_` 开头信号排除（约定占位）
func _apply_unused_highlight(p_item: TreeItem, p_name: String, p_info) -> void:
	if p_name.begins_with("_"):
		return
	if not p_info.is_unused():
		return
	p_item.set_custom_color(0, UNUSED_SIGNAL_COLOR)
	p_item.set_tooltip_text(0, "信号 '%s' 已声明但从未 emit/connect（dead signal）" % p_name)

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
