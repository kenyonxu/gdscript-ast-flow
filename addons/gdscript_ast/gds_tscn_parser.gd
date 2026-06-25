# addons/gdscript_util/gds_tscn_parser.gd
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
var _nodes: Dictionary = {}  # String(path) → SceneNodeData
var _connections: Array = []  # of SignalConnectionData

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

# ---- 内部: 读取节 ----

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
	# 第一遍：ext_resource + sub_resource 索引
	for section in p_sections:
		var s: SectionData = section
		match s.kind:
			SectionKind.EXT_RESOURCE:
				_parse_ext_resource(s)
			SectionKind.SUB_RESOURCE:
				_parse_sub_resource(s)

	# 第二遍：node + connection + editable
	for section in p_sections:
		var s: SectionData = section
		match s.kind:
			SectionKind.NODE:
				_parse_node(s)
			SectionKind.CONNECTION:
				_parse_connection(s)
			SectionKind.EDITABLE:
				_parse_editable(s)
			SectionKind.GD_SCENE:
				_parse_gd_scene(s)

	# 构建结果
	var result = GDSSceneResourceResult.new()
	result.file_path = file_path
	result.file_type = GDSSceneResourceResult.FileType.TSCN

	# 复制 ext_resources
	for k in _ext_resources:
		result.ext_resources[k] = _ext_resources[k]
	for k in _sub_resources:
		result.sub_resources[k] = _sub_resources[k]
	for conn in _connections:
		result.signal_connections.append(conn)

	# 重建节点树
	_build_node_tree(result)

	return result
