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

const SECTION_KIND_MAP := {
	"gd_resource": SectionKind.GD_RESOURCE,
	"ext_resource": SectionKind.EXT_RESOURCE,
	"sub_resource": SectionKind.SUB_RESOURCE,
	"resource": SectionKind.RESOURCE,
}


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
			break

		var value: String = ""
		if p_text[i] == '"':
			i += 1
			while i < len:
				if p_text[i] == '\\' and i + 1 < len:
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
			i += 1
		else:
			var val_start: int = i
			while i < len and p_text[i] != ' ':
				i += 1
			value = p_text.substr(val_start, i - val_start)

		result[key] = value

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

	return result

func _parse_ext_resource(p_section: SectionData) -> GDSSceneResourceResult.ExtResourceInfo:
	var params = p_section.header_params
	var info = GDSSceneResourceResult.ExtResourceInfo.new()
	info.id = params.get("id", "")
	info.type = params.get("type", "")
	info.path = params.get("path", "")
	info.uid = params.get("uid", "")
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
	return data

func _parse_properties(p_section: SectionData) -> Dictionary:
	var props: Dictionary = {}
	for line in p_section.properties:
		var kv = _parse_property_line(line)
		if kv != null:
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
