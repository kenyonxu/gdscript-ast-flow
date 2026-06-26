# addons/gdscript_ast/gds_tres_parser.gd
# .tres 资源文件解析器
# 比 .tscn 简单得多：无节点树、无信号连接、无 editable 节
# 结构：[gd_resource] + [ext_resource]* + [sub_resource]* + [resource]

class_name GDScriptTresParser
extends RefCounted

# ---- 节类型枚举 ----
enum SectionKind {
	GD_RESOURCE,
	EXT_RESOURCE,
	SUB_RESOURCE,
	RESOURCE,
	UNKNOWN,
}

class SectionData:
	extends RefCounted

	var header: String = ""
	var kind: int = SectionKind.UNKNOWN
	var header_params: Dictionary = {}
	var properties: Array = []
	var start_line: int = 0
	var end_line: int = 0

# ---- 公开属性 ----
var file_path: String = ""
var error: String = ""

# ---- 内部状态 ----
var _ext_resources: Dictionary = {}  # String(id) → ExtResourceInfo
var _sub_resources: Dictionary = {}  # String(id) → SubResourceData

# Chunk A: uid 映射
var _uid_map: Dictionary = {}  # String(uid_str) → String(res_path)

const SECTION_KIND_MAP := {
	"gd_resource": SectionKind.GD_RESOURCE,
	"ext_resource": SectionKind.EXT_RESOURCE,
	"sub_resource": SectionKind.SUB_RESOURCE,
	"resource": SectionKind.RESOURCE,
}


# ---- 公开 API ----

func set_uid_map(p_map: Dictionary) -> void:
	_uid_map = p_map

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

	var sections: Array = _read_sections(p_text)
	if sections.is_empty():
		error = "空文件或无有效节"
		return null

	return _parse_semantics(sections)

# ---- 内部 ----

func _reset_state():
	_ext_resources.clear()
	_sub_resources.clear()

func _read_sections(p_text: String) -> Array:
	var sections: Array = []
	var lines = p_text.split("\n")
	var current_section: SectionData = null

	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue

		if line.begins_with("[") and line.ends_with("]"):
			if current_section != null:
				current_section.end_line = i
				sections.append(current_section)

			current_section = SectionData.new()
			current_section.header = line
			current_section.start_line = i
			current_section.kind = _parse_header(line, current_section)
		elif current_section != null:
			current_section.properties.append(line)

	if current_section != null:
		current_section.end_line = lines.size()
		sections.append(current_section)

	return sections

func _parse_header(p_header: String, p_section: SectionData) -> int:
	var inner = p_header.substr(1, p_header.length() - 2).strip_edges()
	if inner.is_empty():
		return SectionKind.UNKNOWN

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

	if rest != "":
		p_section.header_params = _parse_key_value_pairs(rest)

	return kind

func _parse_key_value_pairs(p_text: String) -> Dictionary:
	# 按空格分隔逐对解析 key=value
	# value 读到下一空格为止，然后去掉两端空格和引号
	var result: Dictionary = {}
	var i: int = 0
	var len: int = p_text.length()

	while i < len:
		while i < len and p_text[i] == ' ':
			i += 1
		if i >= len:
			break

		var key_start: int = i
		while i < len and p_text[i] != '=':
			i += 1
		var key: String = p_text.substr(key_start, i - key_start).strip_edges()

		if i < len:
			i += 1
		while i < len and p_text[i] == ' ':
			i += 1
		if i >= len:
			result[key] = ""
			break

		# 读 raw value（到下一个空格），再去掉两端引号
		var val_start: int = i
		while i < len and p_text[i] != ' ':
			i += 1
		var raw: String = p_text.substr(val_start, i - val_start)

		raw = raw.strip_edges()
		if raw.begins_with('"') and raw.ends_with('"') and raw.length() >= 2:
			raw = raw.substr(1, raw.length() - 2)

		result[key] = raw

	return result

func _parse_semantics(p_sections: Array) -> GDSSceneResourceResult:
	var result = GDSSceneResourceResult.new()
	result.file_path = file_path
	result.file_type = GDSSceneResourceResult.FileType.TRES

	for section in p_sections:
		var s: SectionData = section
		match s.kind:
			SectionKind.GD_RESOURCE:
				result.resource_type = s.header_params.get("type", "")
				result.load_steps = int(s.header_params.get("load_steps", "0"))
			SectionKind.EXT_RESOURCE:
				var info = _parse_ext_resource(s)
				if info != null:
					result.ext_resources[info.id] = info
			SectionKind.SUB_RESOURCE:
				var data = _parse_sub_resource(s)
				if data != null:
					result.sub_resources[data.id] = data
			SectionKind.RESOURCE:
				result.resource_properties = _parse_properties(s)

	# Chunk D1: 展开 [resource] 中的 SubResource 引用链
	if result.resource_properties.size() > 0 and result.sub_resources.size() > 0:
		result.resource_properties = _expand_sub_resources(result.resource_properties, result.sub_resources)

	return result

func _parse_ext_resource(p_section: SectionData) -> GDSSceneResourceResult.ExtResourceInfo:
	var params = p_section.header_params
	var info = GDSSceneResourceResult.ExtResourceInfo.new()
	info.id = params.get("id", "")
	info.type = params.get("type", "")
	info.path = params.get("path", "")
	info.uid = params.get("uid", "")
	# Chunk A2: path 为空且 uid 非空时从 _uid_map 反查
	if info.path == "" and info.uid != "" and _uid_map.has(info.uid):
		info.path = _uid_map[info.uid]
	if info.id.is_empty():
		return null
	return info

func _parse_sub_resource(p_section: SectionData) -> GDSSceneResourceResult.SubResourceData:
	var params = p_section.header_params
	var data = GDSSceneResourceResult.SubResourceData.new()
	data.id = params.get("id", "")
	data.type = params.get("type", "")
	if data.id.is_empty():
		return null
	data.properties = _parse_properties(p_section)
	# Chunk C1: 常用类型结构化
	_inline_common_types(data)
	return data

func _parse_properties(p_section: SectionData) -> Dictionary:
	var props: Dictionary = {}
	for line in p_section.properties:
		var kv = _parse_property_line(line)
		if kv != null and kv.size() >= 2:
			props[kv[0]] = kv[1]
	return props

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


# ---- Chunk C1: 常用类型结构化（与 tscn 解析器共享逻辑） ----

func _inline_common_types(p_data: GDSSceneResourceResult.SubResourceData) -> void:
	for key in p_data.properties:
		var raw: String = p_data.properties[key]
		# 含资源引用（含 Array 包裹的 [SubResource(...)]）就跳过——str_to_var 会误触发 ResourceLoader.load
		if raw.find("SubResource(") != -1 or raw.find("ExtResource(") != -1:
			continue
		var parsed = str_to_var(raw)
		if parsed != null:
			p_data.properties[key] = parsed


# ---- Chunk D1: .tres SubResource 引用链展开 ----

func _expand_sub_resources(p_props: Dictionary, p_sub_resources: Dictionary) -> Dictionary:
	# 递归展开 SubResource("id") 引用，含环检测
	var result: Dictionary = {}
	for key in p_props:
		result[key] = _expand_value(p_props[key], p_sub_resources, {})
	return result

func _expand_value(p_value, p_sub_resources: Dictionary, p_visited: Dictionary):
	# 如果是 SubResource("id") 引用，递归展开
	if p_value is String and p_value.begins_with("SubResource(") and p_value.ends_with(")"):
		var inner = p_value.substr(13, p_value.length() - 15)
		inner = inner.strip_edges().trim_prefix('"').trim_suffix('"')

		# 环检测：如果 visited 中有此 id，标记环引用
		if p_visited.has(inner):
			return {"$circular_ref": inner}

		var sub = p_sub_resources.get(inner, null)
		if sub != null:
			p_visited[inner] = true
			var expanded: Dictionary = {}
			expanded["$type"] = sub.type
			for sk in sub.properties:
				expanded[sk] = _expand_value(sub.properties[sk], p_sub_resources, p_visited)
			p_visited.erase(inner)
			return expanded

	return p_value
