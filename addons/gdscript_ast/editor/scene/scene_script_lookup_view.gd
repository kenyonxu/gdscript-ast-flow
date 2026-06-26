# addons/gdscript_ast/editor/scene/scene_script_lookup_view.gd
# 脚本反查视角 — 脚本聚合列表 + 跨场景挂载点 + 联动
# Chunk C

class_name SceneScriptLookupView
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _l10n: GDSL10n = null
var _navigate: Callable = Callable()
var _script_list: ItemList = null
var _mount_list: ItemList = null
var _mount_label: Label = null
var _current_script_index: Dictionary = {}  # script_path → index in _script_list

func setup(p_bridge, p_l10n, p_navigate: Callable) -> void:
	_bridge = p_bridge
	_l10n = p_l10n
	_navigate = p_navigate
	_build_ui()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL

	var hsplit = HSplitContainer.new()
	hsplit.size_flags_horizontal = SIZE_EXPAND_FILL
	hsplit.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(hsplit)

	# 左侧: 脚本列表（底色 1）
	var left_box = VBoxContainer.new()
	var left_label = Label.new()
	left_label.text = _l10n.t("lookup.script")
	left_box.add_child(left_label)
	_script_list = ItemList.new()
	_script_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_script_list.size_flags_vertical = SIZE_EXPAND_FILL
	_script_list.item_selected.connect(_on_script_selected)
	left_box.add_child(_script_list)
	var left_panel = _make_bordered_panel(left_box, Color(0.13, 0.13, 0.16))
	left_panel.custom_minimum_size = Vector2(250, 0)
	hsplit.add_child(left_panel)

	# 右侧: 挂载点列表（底色 2，略蓝）
	var right_box = VBoxContainer.new()
	_mount_label = Label.new()
	right_box.add_child(_mount_label)
	_mount_list = ItemList.new()
	_mount_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_mount_list.size_flags_vertical = SIZE_EXPAND_FILL
	_mount_list.item_selected.connect(_on_mount_selected)
	right_box.add_child(_mount_list)
	var right_panel = _make_bordered_panel(right_box, Color(0.13, 0.14, 0.17))
	hsplit.add_child(right_panel)


# 带边框+底色的 PanelContainer（区域视觉分块）
func _make_bordered_panel(p_content: Control, p_bg: Color) -> PanelContainer:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = p_bg
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.30, 0.30, 0.35)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	panel.add_child(p_content)
	return panel

# 聚合: script_associations → {script → [{scene, node}]}
func _build_index(script_associations: Array) -> Dictionary:
	var idx: Dictionary = {}
	for entry in script_associations:
		var s = entry.get("script", "")
		if s == "":
			continue
		if not idx.has(s):
			idx[s] = []
		idx[s].append({
			"scene": entry.get("scene", ""),
			"node": entry.get("node", ""),
		})
	return idx

func rebuild() -> void:
	_script_list.clear()
	_mount_list.clear()
	_mount_label.text = ""
	_current_script_index.clear()

	var proj = _bridge.get_project_result()
	if proj == null:
		return

	var idx = _build_index(proj.script_associations)
	if idx.is_empty():
		return

	# 按挂载数降序排列
	var sorted_scripts = idx.keys()
	sorted_scripts.sort_custom(func(a, b): return idx[a].size() > idx[b].size())

	var item_idx = 0
	for s in sorted_scripts:
		var display = "%s (%d)" % [s, idx[s].size()]
		_script_list.add_item(display)
		_current_script_index[s] = item_idx
		item_idx += 1

func _on_script_selected(_idx: int) -> void:
	var selected = _script_list.get_selected_items()
	if selected.is_empty():
		return
	var idx = selected[0]
	var display = _script_list.get_item_text(idx)
	# 解析回 script_path（移除末尾 " (N)"）
	var paren_pos = display.rfind(" (")
	var script_path = display.substr(0, paren_pos) if paren_pos > 0 else display

	_mount_list.clear()
	var proj = _bridge.get_project_result()
	if proj == null:
		return

	var idx_dict = _build_index(proj.script_associations)
	var mounts = idx_dict.get(script_path, [])
	_mount_label.text = _l10n.t("lookup.mounts") + " (%d)" % mounts.size()
	for m in mounts:
		var mount_text = m.scene + "  →  " + m.node
		_mount_list.add_item(mount_text)

func _on_mount_selected(_idx: int) -> void:
	var selected = _mount_list.get_selected_items()
	if selected.is_empty():
		return
	var idx = selected[0]
	var mount_text = _mount_list.get_item_text(idx)
	# 格式: "scene_path  →  node_name"
	var parts = mount_text.split("  →  ")
	if parts.size() < 2:
		return
	var scene_path = parts[0].strip_edges()
	var node_name = parts[1].strip_edges()

	# 用 scene_path+node_name 调用联动
	if _navigate.is_valid():
		_navigate.call(scene_path, node_name)

func focus_node(_scene_path: String, _node_path: String) -> void:
	# 脚本反查视角不支持焦点定位（联动目标始终是节点树视角）
	pass
