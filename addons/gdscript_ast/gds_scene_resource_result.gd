# addons/gdscript_ast/gds_scene_resource_result.gd
# 场景 (.tscn) / 资源 (.tres) 解析结果容器
# 包含所有数据模型类

class_name GDSSceneResourceResult
extends RefCounted

# ---- 文件类型枚举 ----
enum FileType {
	TSCN,
	TRES,
}

# ---- 外部资源引用 ----
class ExtResourceInfo:
	extends RefCounted

	var id: String = ""
	var type: String = ""
	var path: String = ""
	var uid: String = ""

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"type": type,
			"path": path,
			"uid": uid,
		}

# ---- 子资源数据 ----
class SubResourceData:
	extends RefCounted

	var id: String = ""
	var type: String = ""
	var properties: Dictionary = {}

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"type": type,
			"properties": properties,
		}

# ---- 场景节点数据 ----
class SceneNodeData:
	extends RefCounted

	var name: String = ""
	var type: String = ""
	var parent_path: String = ""
	var children: Array = []  # of SceneNodeData
	var groups: Array = []    # of String

	# 属性
	var properties: Dictionary = {}  # String(属性名) → Variant 值
	var script_resource: String = ""  # 关联脚本资源路径，解析后填充
	var export_overrides: Dictionary = {}  # String(变量名) → 填充值（P1）

	# ExtResource/SubResource 引用
	var ext_refs: Dictionary = {}  # String(属性名) → ExtResourceInfo
	var sub_refs: Dictionary = {}  # String(属性名) → SubResourceData

	func to_dict() -> Dictionary:
		var child_arr: Array = []
		for c in children:
			child_arr.append(c.to_dict())
		var ext_refs_dict: Dictionary = {}
		for k in ext_refs:
			ext_refs_dict[k] = ext_refs[k].to_dict()
		var sub_refs_dict: Dictionary = {}
		for k in sub_refs:
			sub_refs_dict[k] = sub_refs[k].to_dict()
		return {
			"name": name,
			"type": type,
			"parent": parent_path,
			"groups": groups,
			"properties": properties,
			"script": script_resource,
			"export_overrides": export_overrides,
			"ext_refs": ext_refs_dict,
			"sub_refs": sub_refs_dict,
			"children": child_arr,
		}

# ---- 信号连接数据 ----
class SignalConnectionData:
	extends RefCounted

	var signal_name: String = ""
	var from_node: String = ""
	var to_node: String = ""
	var method: String = ""
	var flags: int = 0
	var binds: Array = []
	var unbinds: int = 0

	func to_dict() -> Dictionary:
		return {
			"signal": signal_name,
			"from_node": from_node,
			"to_node": to_node,
			"method": method,
			"flags": flags,
			"binds": binds,
			"unbinds": unbinds,
		}

# ========== 主结果容器 ==========

var file_path: String = ""
var file_type: int = FileType.TSCN

# .tscn 专属
var scene_uid: String = ""
var load_steps: int = 0
var root_nodes: Array = []  # of SceneNodeData（顶层节点）
var nodes_flat: Dictionary = {}  # String(NodePath) → SceneNodeData（平铺索引）
var signal_connections: Array = []  # of SignalConnectionData
var editable_paths: Array = []  # of String

# .tres 专属
var resource_type: String = ""
var resource_properties: Dictionary = {}

# 通用
var ext_resources: Dictionary = {}  # String(id) → ExtResourceInfo
var sub_resources: Dictionary = {}  # String(id) → SubResourceData
var errors: Array = []  # of String

# 关联脚本路径列表（解析后填充）
var script_associations: Array = []  # of String（.gd 文件路径）


# ---- 查询 API ----

func get_nodes_by_type(p_type: String) -> Array:
	var result: Array = []
	for path in nodes_flat:
		var node: SceneNodeData = nodes_flat[path]
		if node.type == p_type:
			result.append(node)
	return result

func get_nodes_by_script(p_script_path: String) -> Array:
	var result: Array = []
	for path in nodes_flat:
		var node: SceneNodeData = nodes_flat[path]
		if node.script_resource == p_script_path:
			result.append(node)
	return result

func get_node_by_path(p_path: String) -> SceneNodeData:
	return nodes_flat.get(p_path, null)

func get_connections_for_node(p_node_path: String) -> Array:
	var result: Array = []
	for conn in signal_connections:
		var c: SignalConnectionData = conn
		if c.from_node == p_node_path or c.to_node == p_node_path:
			result.append(c)
	return result

func get_connections_for_signal(p_signal_name: String) -> Array:
	var result: Array = []
	for conn in signal_connections:
		var c: SignalConnectionData = conn
		if c.signal_name == p_signal_name:
			result.append(c)
	return result


# ---- 序列化 ----

func to_dict() -> Dictionary:
	var d: Dictionary = {
		"file_path": file_path,
		"file_type": "TSCN" if file_type == FileType.TSCN else "TRES",
		"errors": errors,
		"script_associations": script_associations,
	}

	if file_type == FileType.TSCN:
		d["scene_uid"] = scene_uid
		d["load_steps"] = load_steps
		var root_arr: Array = []
		for n in root_nodes:
			root_arr.append(n.to_dict())
		d["root_nodes"] = root_arr
		var sig_arr: Array = []
		for s in signal_connections:
			sig_arr.append(s.to_dict())
		d["signal_connections"] = sig_arr
		d["editable_paths"] = editable_paths

	if file_type == FileType.TRES:
		d["resource_type"] = resource_type
		d["resource_properties"] = resource_properties

	# 通用
	var ext_dict: Dictionary = {}
	for k in ext_resources:
		ext_dict[k] = ext_resources[k].to_dict()
	d["ext_resources"] = ext_dict

	var sub_dict: Dictionary = {}
	for k in sub_resources:
		sub_dict[k] = sub_resources[k].to_dict()
	d["sub_resources"] = sub_dict

	return d
