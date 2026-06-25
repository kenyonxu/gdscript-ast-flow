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
var _nodes: Dictionary = {}  # String(full_path) → SceneNodeData（临时构建用）
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
	# 按空格分隔逐对解析 key=value
	# value 读到下一空格为止，然后去掉两端空格和引号
	# 比逐字符转义解析更简洁，且 = 在 value 中不会截断（直接读到空格为止）
	var result: Dictionary = {}
	var i: int = 0
	var len: int = p_text.length()

	while i < len:
		# 跳过空白
		while i < len and p_text[i] == ' ':
			i += 1
		if i >= len:
			break

		# 读取 key（到第一个 =）
		var key_start: int = i
		while i < len and p_text[i] != '=':
			i += 1
		var key: String = p_text.substr(key_start, i - key_start).strip_edges()

		# 跳过 =
		if i < len:
			i += 1

		# 跳过空白
		while i < len and p_text[i] == ' ':
			i += 1

		if i >= len:
			result[key] = ""
			break

		# 读取 raw value（到下一个空白，保留引号包围）
		var val_start: int = i
		while i < len and p_text[i] != ' ':
			i += 1
		var raw: String = p_text.substr(val_start, i - val_start)

		# 去掉两端空白和引号
		raw = raw.strip_edges()
		if raw.begins_with('"') and raw.ends_with('"') and raw.length() >= 2:
			raw = raw.substr(1, raw.length() - 2)

		result[key] = raw

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

	# 用 parent_path + "/" + name 做键，避免重名节点丢失
	var node_key = node_name if node.parent_path in [".", ""] else node.parent_path + "/" + node_name
	_nodes[node_key] = node

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
	# _nodes 的 key 已经是 full_path（parent_path + "/" + name）
	# 直接填充 nodes_flat 和建立父子关系

	# 第一步：填充平铺索引
	for key in _nodes:
		p_result.nodes_flat[key] = _nodes[key]

	# 第二步：构建 root_nodes 和 children 树
	for key in _nodes:
		var node: GDSSceneResourceResult.SceneNodeData = _nodes[key]

		if node.parent_path in [".", ""]:
			# 根节点
			p_result.root_nodes.append(node)
		else:
			# parent_path 即是父节点的完整路径键
			var parent = _nodes.get(node.parent_path, null)
			if parent != null:
				parent.children.append(node)
			else:
				# 父节点未找到时作为根节点处理
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
		var inner = p_value.substr(13, p_value.length() - 15)  # 去掉 ExtResource(" 和 ")
		inner = inner.strip_edges()
		inner = inner.trim_prefix('"').trim_suffix('"')
		if _ext_resources.has(inner):
			return _ext_resources[inner]
	return null

func _resolve_sub_resource_ref(p_value: String) -> GDSSceneResourceResult.SubResourceData:
	# 匹配 SubResource("id") 格式
	if p_value.begins_with("SubResource(") and p_value.ends_with(")"):
		var inner = p_value.substr(13, p_value.length() - 15)  # 去掉 SubResource(" 和 ")
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
	# 解析 binds=Array[Type]([...]) 或 binds=[...] 格式
	# 括号深度感知提取，再用 str_to_var 解析

	# 1. 先尝试 str_to_var 整体解析（处理 Array[Type]([...]) 和 [...]）
	var parsed = str_to_var(p_value)
	if parsed is Array:
		return parsed

	# 2. 找 (...)，提取内层 [...]（括号深度感知）
	var paren = p_value.find("(")
	if paren != -1:
		var depth = 0
		var start = -1
		for i in range(paren + 1, p_value.length()):
			match p_value[i]:
				'[':
					if depth == 0:
						start = i
					depth += 1
				']':
					depth -= 1
					if depth == 0 and start != -1:
						var arr_str = p_value.substr(start, i - start + 1)
						parsed = str_to_var(arr_str)
						if parsed is Array:
							return parsed
						break

	# 3. 最简 fallback：找第一对 [...] 深度感知
	var fdepth = 0
	var fstart = -1
	for i in range(p_value.length()):
		if p_value[i] == '[':
			if fdepth == 0:
				fstart = i
			fdepth += 1
		elif p_value[i] == ']':
			fdepth -= 1
			if fdepth == 0 and fstart != -1:
				var arr_str = p_value.substr(fstart, i - fstart + 1)
				parsed = str_to_var(arr_str)
				if parsed is Array:
					return parsed
				break

	return []
