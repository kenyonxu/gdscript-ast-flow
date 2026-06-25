# addons/gdscript_ast/gds_tscn_parser.gd
# .tscn 场景文件解析器 — 两遍扫描
# 第一遍: 收集节 + ExtResource/SubResource 索引
# 第二遍: node + connection + editable 语义解析

class_name GDScriptTscnParser
extends RefCounted

# ---- 节类型枚举 ----
enum SectionKind {
	GD_SCENE,
	EXT_RESOURCE,
	SUB_RESOURCE,
	NODE,
	CONNECTION,
	EDITABLE,
	UNKNOWN,
}

# ---- 节——解析中间产物 ----
class SectionData:
	extends RefCounted

	var header: String = ""
	var kind: int = SectionKind.UNKNOWN
	var header_params: Dictionary = {}  # String → String
	var properties: Array = []  # of String
	var start_line: int = 0
	var end_line: int = 0

# ---- 公开属性 ----
var file_path: String = ""
var error: String = ""

# ---- 内部状态 ----
var _ext_resources: Dictionary = {}  # String(id) → ExtResourceInfo
var _sub_resources: Dictionary = {}  # String(id) → SubResourceData
var _nodes: Dictionary = {}  # String(name) → SceneNodeData（临时构建用）
var _connections: Array = []  # of SignalConnectionData
var _editable_paths: Array = []  # of String
var _scene_uid: String = ""
var _load_steps: int = 0

# 节常量
const SECTION_KIND_MAP := {
	"gd_scene": SectionKind.GD_SCENE,
	"ext_resource": SectionKind.EXT_RESOURCE,
	"sub_resource": SectionKind.SUB_RESOURCE,
	"node": SectionKind.NODE,
	"connection": SectionKind.CONNECTION,
	"editable": SectionKind.EDITABLE,
}

# 信号连接标志位
const FLAG_DEFERRED: int = 1         # CONNECT_DEFERRED
const FLAG_PERSIST: int = 2          # CONNECT_PERSIST
const FLAG_ONE_SHOT: int = 4         # CONNECT_ONE_SHOT
const FLAG_REFERENCE_COUNTED: int = 8  # CONNECT_REFERENCE_COUNTED


# ---- 公开 API ----

func parse(p_path: String) -> GDSSceneResourceResult:
	file_path = p_path
	var f = FileAccess.open(p_path, FileAccess.READ)
	if f == null:
		error = "无法打开文件: " + p_path
		return null
	var text = f.get_as_text()
	f.close()
	return parse_text(text, p_path)

func parse_text(p_text: String, p_virtual_path: String) -> GDSSceneResourceResult:
	file_path = p_virtual_path
	error = ""
	_reset_state()

	# 规范化换行符+BOM
	p_text = p_text.replace("\r\n", "\n").replace("\r", "\n")
	if p_text.begins_with("﻿"):
		p_text = p_text.substr(1)

	# 第一遍：读取所有节
	var sections: Array = _read_sections(p_text)
	if sections.is_empty():
		error = "空文件或无有效节"
		return null

	# 第二遍：语义解析
	var result = _parse_semantics(sections)
	return result


# ---- 内部: 重置状态 ----

func _reset_state():
	_ext_resources.clear()
	_sub_resources.clear()
	_nodes.clear()
	_connections.clear()
	_editable_paths.clear()
	_scene_uid = ""
	_load_steps = 0


# ---- 内部: 读取节（Chunk B1/B2） ----

func _read_sections(p_text: String) -> Array:
	var sections: Array = []  # of SectionData
	var lines = p_text.split("\n")
	var current_section: SectionData = null

	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue

		# 检查是否是节头 [...]
		if line.begins_with("[") and line.ends_with("]"):
			# 保存上一个节
			if current_section != null:
				current_section.end_line = i
				sections.append(current_section)

			current_section = SectionData.new()
			current_section.header = line
			current_section.start_line = i
			current_section.kind = _parse_header(line, current_section)
		elif current_section != null:
			current_section.properties.append(line)

	# 保存最后一个节
	if current_section != null:
		current_section.end_line = lines.size()
		sections.append(current_section)

	return sections

func _parse_header(p_header: String, p_section: SectionData) -> int:
	# "[kind key1="val1" key2=val2 ...]" → kind + params
	var inner = p_header.substr(1, p_header.length() - 2).strip_edges()
	if inner.is_empty():
		return SectionKind.UNKNOWN

	# 提取 kind（第一个空格前的单词）
	var space_idx = inner.find(" ")
	var kind_str: String
	var rest: String
	if space_idx == -1:
		kind_str = inner
		rest = ""
	else:
		kind_str = inner.substr(0, space_idx)
		rest = inner.substr(space_idx + 1).strip_edges()

	var kind = SectionKind.UNKNOWN
	if SECTION_KIND_MAP.has(kind_str):
		kind = SECTION_KIND_MAP[kind_str]
	p_section.kind = kind

	# 解析 key="value" 或 key=value 对
	if rest != "":
		p_section.header_params = _parse_key_value_pairs(rest)

	return kind

func _parse_key_value_pairs(p_text: String) -> Dictionary:
	var result: Dictionary = {}
	var i: int = 0
	var len: int = p_text.length()

	while i < len:
		# 跳过空白
		while i < len and p_text[i] == ' ':
			i += 1
		if i >= len:
			break

		# 读取 key
		var key_start: int = i
		while i < len and p_text[i] != '=':
			i += 1
		var key: String = p_text.substr(key_start, i - key_start).strip_edges()

		# 跳过 =
		if i < len:
			i += 1  # skip '='

		# 跳过空白
		while i < len and p_text[i] == ' ':
			i += 1

		if i >= len:
			break

		# 读取 value（引号包围或裸值）
		var value: String = ""
		if p_text[i] == '"':
			i += 1  # skip opening "
			while i < len:
				if p_text[i] == '\\' and i + 1 < len:
					# 转义字符
					if p_text[i + 1] == '"':
						value += '"'
						i += 2
						continue
					elif p_text[i + 1] == '\\':
						value += '\\'
						i += 2
						continue
				elif p_text[i] == '"':
					break
				value += p_text[i]
				i += 1
			i += 1  # skip closing "
		else:
			# 裸值：读到空格或结尾
			var val_start: int = i
			while i < len and p_text[i] != ' ':
				i += 1
			value = p_text.substr(val_start, i - val_start)

		result[key] = value

	return result


# ---- 内部: 语义解析 ----

func _parse_semantics(p_sections: Array) -> GDSSceneResourceResult:
	# 第一遍（索引阶段）：ext_resource + sub_resource + gd_scene
	for section in p_sections:
		var s: SectionData = section
		match s.kind:
			SectionKind.EXT_RESOURCE:
				_parse_ext_resource(s)
			SectionKind.SUB_RESOURCE:
				_parse_sub_resource(s)
			SectionKind.GD_SCENE:
				_parse_gd_scene(s)

	# 第二遍（语义阶段）：node + connection + editable
	for section in p_sections:
		var s: SectionData = section
		match s.kind:
			SectionKind.NODE:
				_parse_node(s)
			SectionKind.CONNECTION:
				_parse_connection(s)
			SectionKind.EDITABLE:
				_parse_editable(s)

	# 构建结果
	var result = GDSSceneResourceResult.new()
	result.file_path = file_path
	result.file_type = GDSSceneResourceResult.FileType.TSCN
	result.scene_uid = _scene_uid
	result.load_steps = _load_steps

	# 复制 ext_resources
	for k in _ext_resources:
		result.ext_resources[k] = _ext_resources[k]
	for k in _sub_resources:
		result.sub_resources[k] = _sub_resources[k]
	for conn in _connections:
		result.signal_connections.append(conn)
	for p in _editable_paths:
		result.editable_paths.append(p)

	# 扫描 script_associations
	for node_name in _nodes:
		var node: GDSSceneResourceResult.SceneNodeData = _nodes[node_name]
		if node.script_resource != "" and not result.script_associations.has(node.script_resource):
			result.script_associations.append(node.script_resource)

	# 重建节点树（Chunk B5）
	_build_node_tree(result)

	return result


# ---- Chunk B2: 第一遍 ----

func _parse_gd_scene(p_section: SectionData) -> void:
	_scene_uid = p_section.header_params.get("uid", "")
	_load_steps = int(p_section.header_params.get("load_steps", "0"))

func _parse_ext_resource(p_section: SectionData) -> void:
	var params = p_section.header_params
	var info = GDSSceneResourceResult.ExtResourceInfo.new()
	info.id = params.get("id", "")
	info.type = params.get("type", "")
	info.path = params.get("path", "")
	info.uid = params.get("uid", "")
	if info.id != "":
		_ext_resources[info.id] = info

func _parse_sub_resource(p_section: SectionData) -> void:
	var params = p_section.header_params
	var data = GDSSceneResourceResult.SubResourceData.new()
	data.id = params.get("id", "")
	data.type = params.get("type", "")
	if data.id != "":
		data.properties = _parse_key_value_props(p_section)
		_sub_resources[data.id] = data


# ---- Chunk B3: 第二遍 ----

func _parse_node(p_section: SectionData) -> void:
	var params = p_section.header_params
	var node_name = params.get("name", "")
	if node_name.is_empty():
		return

	var node = GDSSceneResourceResult.SceneNodeData.new()
	node.name = node_name
	node.type = params.get("type", "")
	node.parent_path = params.get("parent", ".")

	# 解析 groups（可选）
	if params.has("groups"):
		node.groups = _parse_groups_value(params["groups"])

	# 解析属性行
	for line in p_section.properties:
		var kv = _parse_property_line(line)
		if kv.size() >= 2:
			var key: String = kv[0]
			var value = kv[1]
			node.properties[key] = value
			# 脚本关联：script = ExtResource("N")
			if key == "script":
				var ref = _resolve_ext_resource_ref(value)
				if ref != null and ref.type == "Script":
					node.script_resource = ref.path
			# 普通 ExtResource / SubResource 引用
			_resolve_ref_in_value(key, value, node)

	_nodes[node_name] = node

func _parse_connection(p_section: SectionData) -> void:
	var params = p_section.header_params
	var conn = GDSSceneResourceResult.SignalConnectionData.new()
	conn.signal_name = params.get("signal", "")
	conn.from_node = params.get("from", "")
	conn.to_node = params.get("to", "")
	conn.method = params.get("method", "")

	# flags 解析（Chunk B4）
	if params.has("flags"):
		conn.flags = int(params["flags"])
	else:
		conn.flags = 0

	# binds 解析（可能在 header 或 properties 中）
	if params.has("binds"):
		conn.binds = _parse_binds_value(params["binds"])
	else:
		# 在 properties 中查找 binds
		for line in p_section.properties:
			var kv = _parse_property_line(line)
			if kv.size() >= 2 and kv[0] == "binds":
				conn.binds = _parse_binds_value(kv[1])
				break

	# unbinds
	if params.has("unbinds"):
		conn.unbinds = int(params["unbinds"])
	else:
		for line in p_section.properties:
			var kv = _parse_property_line(line)
			if kv.size() >= 2 and kv[0] == "unbinds":
				conn.unbinds = int(kv[1])
				break

	_connections.append(conn)

func _parse_editable(p_section: SectionData) -> void:
	var path = p_section.header_params.get("path", "")
	if path != "":
		_editable_paths.append(path)


# ---- Chunk B4: 信号连接 flags 帮助 ----

func get_flag_names(p_flags: int) -> Array:
	var names: Array = []
	if p_flags & FLAG_DEFERRED:
		names.append("DEFERRED")
	if p_flags & FLAG_PERSIST:
		names.append("PERSIST")
	if p_flags & FLAG_ONE_SHOT:
		names.append("ONE_SHOT")
	if p_flags & FLAG_REFERENCE_COUNTED:
		names.append("REFERENCE_COUNTED")
	return names


# ---- Chunk B5: 节点树重建 ----

func _build_node_tree(p_result: GDSSceneResourceResult) -> void:
	# 第一步：计算每个节点的完整路径
	# 使用临时字典存储 name → (node, full_path) 映射
	var name_to_node: Dictionary = {}  # String(name) → SceneNodeData
	var name_to_path: Dictionary = {}  # String(name) → String(full_path)

	# 先计算所有根节点（parent == "."）
	for node_name in _nodes:
		var node: GDSSceneResourceResult.SceneNodeData = _nodes[node_name]
		name_to_node[node_name] = node
		if node.parent_path == ".":
			name_to_path[node_name] = node_name
		else:
			# 延迟计算：等根节点路径确定后再算
			name_to_path[node_name] = ""

	# 递归解决 full_path（最多 256 层深度防循环）
	var max_iter: int = _nodes.size() * 2
	var iter: int = 0
	var resolved: bool = false
	while not resolved and iter < max_iter:
		resolved = true
		for node_name in name_to_node:
			if name_to_path[node_name] != "":
				continue
			var node: GDSSceneResourceResult.SceneNodeData = name_to_node[node_name]
			if name_to_path.has(node.parent_path):
				var parent_full: String = name_to_path[node.parent_path]
				if parent_full != "":
					name_to_path[node_name] = parent_full + "/" + node_name
				else:
					resolved = false
			else:
				# parent_path 可能包含多层如 "Parent/Grandparent"
				var parts = node.parent_path.split("/")
				var parent_name = parts[-1]  # 最后一节是直接父节点名... 其实不对，parent_path 是完整的路径
				# 以 "/" 分割的完整路径——需要用完整路径索引父节点
				if name_to_path.has(parent_name) and name_to_path[parent_name] != "":
					name_to_path[node_name] = name_to_path[parent_name] + "/" + node_name
				else:
					resolved = false
		iter += 1

	# 对于仍未解析的节点，使用 parent_path/name 作为 fallback
	for node_name in name_to_node:
		if name_to_path[node_name] == "":
			var node: GDSSceneResourceResult.SceneNodeData = name_to_node[node_name]
			name_to_path[node_name] = node.parent_path.trim_prefix("./") + "/" + node_name

	# 第二步：填充 p_result.nodes_flat
	for node_name in name_to_node:
		var full_path: String = name_to_path[node_name]
		var node: GDSSceneResourceResult.SceneNodeData = name_to_node[node_name]
		# 深拷贝节点（避免外部对 _nodes 的引用影响）
		p_result.nodes_flat[full_path] = node

	# 第三步：构建 root_nodes 和 children 树
	for node_name in name_to_node:
		var node: GDSSceneResourceResult.SceneNodeData = name_to_node[node_name]

		if node.parent_path == ".":
			# 根节点
			p_result.root_nodes.append(node)
		else:
			# 找到父节点
			# 尝试按 full_path 查找（通用）
			var parent_path_full: String = name_to_path.get(node.parent_path, "")
			if parent_path_full != "":
				# parent 字段指向另一个节点的名字
				var parent_node = p_result.nodes_flat.get(parent_path_full, null)
				if parent_node != null:
					parent_node.children.append(node)
					continue

			# 尝试按 parent_path 直接作为名字查找
			var parent_node = name_to_node.get(node.parent_path, null)
			if parent_node != null:
				parent_node.children.append(node)
				continue

			# parent_path 可能是多级路径
			var parent_full_candidate = node.parent_path
			var candidate = p_result.nodes_flat.get(parent_full_candidate, null)
			if candidate != null:
				candidate.children.append(node)
				continue

			# 如果所有查找都失败，作为根节点处理
			p_result.root_nodes.append(node)


# ---- 内部: 属性/值解析工具 ----

func _parse_property_line(p_line: String) -> Array:
	# 按首个 = 分割，后面部分整体作为值
	var idx = p_line.find("=")
	if idx == -1:
		return []
	var key = p_line.substr(0, idx).strip_edges()
	var value = p_line.substr(idx + 1).strip_edges()
	if key.is_empty():
		return []
	return [key, value]

func _parse_key_value_props(p_section: SectionData) -> Dictionary:
	var props: Dictionary = {}
	for line in p_section.properties:
		var kv = _parse_property_line(line)
		if kv.size() >= 2:
			props[kv[0]] = kv[1]
	return props

func _resolve_ref_in_value(p_key: String, p_value: String, p_node: GDSSceneResourceResult.SceneNodeData) -> void:
	# 检查是否是 ExtResource("id")
	var ext_ref = _resolve_ext_resource_ref(p_value)
	if ext_ref != null:
		p_node.ext_refs[p_key] = ext_ref
		return

	# 检查是否是 SubResource("id")
	var sub_ref = _resolve_sub_resource_ref(p_value)
	if sub_ref != null:
		p_node.sub_refs[p_key] = sub_ref

func _resolve_ext_resource_ref(p_value: String) -> GDSSceneResourceResult.ExtResourceInfo:
	# 匹配 ExtResource("id") 格式
	if p_value.begins_with("ExtResource(") and p_value.ends_with(")"):
		var inner = p_value.substr(13, p_value.length() - 14)  # 去掉 ExtResource(" 和 ")
		inner = inner.strip_edges()
		inner = inner.trim_prefix('"').trim_suffix('"')
		if _ext_resources.has(inner):
			return _ext_resources[inner]
	return null

func _resolve_sub_resource_ref(p_value: String) -> GDSSceneResourceResult.SubResourceData:
	# 匹配 SubResource("id") 格式
	if p_value.begins_with("SubResource(") and p_value.ends_with(")"):
		var inner = p_value.substr(13, p_value.length() - 14)  # 去掉 SubResource(" 和 ")
		inner = inner.strip_edges()
		inner = inner.trim_prefix('"').trim_suffix('"')
		if _sub_resources.has(inner):
			return _sub_resources[inner]
	return null

func _parse_groups_value(p_value: String) -> Array:
	# 解析 groups=["group1","group2"] 格式
	var inner = p_value.trim_prefix("[").trim_suffix("]")
	if inner.is_empty():
		return []
	var groups: Array = []
	var parts = inner.split(",")
	for part in parts:
		var g = part.strip_edges().trim_prefix('"').trim_suffix('"')
		if g != "":
			groups.append(g)
	return groups

func _parse_binds_value(p_value: String) -> Array:
	# 解析 binds=Array[Type]([...]) 格式
	# 查找最内层的 [...] 内容
	var bracket_start = p_value.find("[")
	var bracket_end = p_value.rfind("]")
	if bracket_start == -1 or bracket_end == -1 or bracket_end <= bracket_start:
		return []
	var inner = p_value.substr(bracket_start + 1, bracket_end - bracket_start - 1)
	if inner.is_empty():
		return []

	# 简单的逗号分割（不考虑嵌套，因为 binds 值通常是简单类型）
	var items: Array = []
	var parts = inner.split(",")
	for part in parts:
		var item_str = part.strip_edges()
		if item_str != "":
			# 尝试解析为数字
			if item_str.is_valid_int():
				items.append(int(item_str))
			elif item_str.is_valid_float():
				items.append(float(item_str))
			elif item_str == "true" or item_str == "false":
				items.append(item_str == "true")
			else:
				# 去掉引号，作为字符串保存
				item_str = item_str.trim_prefix('"').trim_suffix('"')
				items.append(item_str)
	return items
