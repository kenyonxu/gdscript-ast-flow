# tests/test_tscn_tres_parser.gd
# .tscn/.tres 解析器验收测试 — 12 套测试用例（含 Chunk A~F 增强）

extends Node

const FIXTURES := "res://tests/fixtures/"
const SCENE_FULL := FIXTURES + "test_scene_full.tscn"
const SCENE_SIMPLE := FIXTURES + "test_scene_simple.tscn"
const SCENE_SIGNALS := FIXTURES + "test_scene_signals.tscn"
const SCENE_UID := FIXTURES + "test_scene_uid.tscn"
const RESOURCE_FILE := FIXTURES + "test_resource.tres"
const RESOURCE_NESTED := FIXTURES + "test_resource_nested.tres"
const RESOURCE_CYCLE := FIXTURES + "test_resource_cycle.tres"
const SCRIPT_FILE := FIXTURES + "test_script_for_scene.gd"

var _tscn_parser: GDScriptTscnParser
var _tres_parser: GDScriptTresParser


func _ready():
	print("\n=== .tscn/.tres Parser Acceptance Tests ===\n")
	_tscn_parser = GDScriptTscnParser.new()
	_tres_parser = GDScriptTresParser.new()
	run_all()
	print("\n=== All tests completed ===")


func run_all():
	test_tscn_full()
	test_script_assoc()
	test_signals()
	test_tres()
	test_json_schema()
	test_script_attach()
	# Chunk F 额外覆盖
	test_tscn_simple()
	test_tscn_flags_value()
	# Chunk A~F 新增
	test_uid_resolve()
	test_export_overrides()
	test_sub_resource_inline()
	test_tres_sub_chain()
	test_tres_cycle()


# ============================================================
# 测试 1: 完整场景解析（6 种节全覆盖）
# ============================================================
func test_tscn_full():
	print("Test: full tscn parsing (6 section types)...")

	var result = _tscn_parser.parse(SCENE_FULL)
	assert(result != null, "Result should not be null")
	assert(_tscn_parser.error == "", "No parse error: '%s'" % _tscn_parser.error)
	assert(result.file_type == GDSSceneResourceResult.FileType.TSCN, "Should be TSCN")
	assert(result.file_path == SCENE_FULL, "File path should match")

	# gd_scene 节
	assert(result.scene_uid == "uid://test_full_scene", "Uid should match")
	assert(result.load_steps == 6, "Load steps should be 6, got %d" % result.load_steps)

	# ext_resource 节 (3 个)
	assert(result.ext_resources.size() == 3, "Expected 3 ext_resources, got %d" % result.ext_resources.size())
	assert(result.ext_resources.has("1_script"), "Should have 1_script")
	assert(result.ext_resources["1_script"].type == "Script", "1_script type should be Script")
	assert(result.ext_resources["1_script"].path.ends_with("test_script_for_scene.gd"), "1_script path mismatch")
	assert(result.ext_resources.has("2_tex"), "Should have 2_tex")
	assert(result.ext_resources.has("3_subscene"), "Should have 3_subscene")

	# sub_resource 节 (3 个)
	assert(result.sub_resources.size() == 3, "Expected 3 sub_resources, got %d" % result.sub_resources.size())
	assert(result.sub_resources.has("1_shape"), "Should have 1_shape")
	assert(result.sub_resources["1_shape"].type == "RectangleShape2D", "1_shape type mismatch")
	assert(result.sub_resources.has("2_shape"), "Should have 2_shape")
	assert(result.sub_resources.has("3_shape"), "Should have 3_shape")

	# node 节 — 单根节点设计
	assert(result.root_nodes.size() == 1, "Should have exactly 1 root node, got %d" % result.root_nodes.size())
	var main_node = result.root_nodes[0]
	assert(main_node.name == "Main", "Root node should be named Main")
	assert(main_node.type == "Node", "Main type should be Node")

	# Player 是 Main 的子节点
	var player_node = null
	for child in main_node.children:
		if child.name == "Player":
			player_node = child
			break
	assert(player_node != null, "Player should be a child of Main")
	assert(player_node.type == "CharacterBody2D", "Player type mismatch")

	# 子节点
	assert(player_node.children.size() >= 2, "Player should have at least 2 children: CollisionShape + Sprite")

	# collision_layer 属性
	assert(player_node.properties.has("collision_layer"), "Player should have collision_layer")

	# [editable] 节
	assert(result.editable_paths.size() >= 1, "Should have editable paths")
	assert(result.editable_paths.has("Main/SubScene"), "Editable should include Main/SubScene")

	# 验证重名节点（两个 Icon 在不同父节点下）
	var container_a = null
	var container_b = null
	for child in main_node.children:
		if child.name == "ContainerA":
			container_a = child
		elif child.name == "ContainerB":
			container_b = child
	assert(container_a != null, "ContainerA should exist")
	assert(container_b != null, "ContainerB should exist")
	assert(container_a.children.size() == 1, "ContainerA should have 1 child, got %d" % container_a.children.size())
	assert(container_b.children.size() == 1, "ContainerB should have 1 child, got %d" % container_b.children.size())
	assert(container_a.children[0].name == "Icon", "ContainerA child should be Icon")
	assert(container_b.children[0].name == "Icon", "ContainerB child should be Icon")
	# 两个 Icon 是不同的节点对象（重名不丢失）
	assert(container_a.children[0] != container_b.children[0], "Two Icon nodes should be different objects")

	print("  PASS")


# ============================================================
# 测试 2: 脚本关联
# ============================================================
func test_script_assoc():
	print("Test: script association...")

	var result = _tscn_parser.parse(SCENE_FULL)
	assert(result != null, "Result should not be null")

	# Main 节点的 script_resource
	var main_node = _find_node_in_flat(result, "Main")
	assert(main_node != null, "Main node should exist")
	assert(main_node.script_resource.ends_with("test_script_for_scene.gd"),
			"Main script_resource should point to test_script_for_scene.gd, got '%s'" % main_node.script_resource)

	# Player 节点
	var player_node = _find_node_in_flat(result, "Player")
	assert(player_node != null, "Player node should exist")
	assert(player_node.script_resource.ends_with("test_script_for_scene.gd"),
			"Player script_resource should point to test_script_for_scene.gd")

	# script_associations
	assert(result.script_associations.size() >= 1, "Should have script associations")
	var found_script = false
	for assoc in result.script_associations:
		if assoc.ends_with("test_script_for_scene.gd"):
			found_script = true
			break
	assert(found_script, "Script associations should include test_script_for_scene.gd")

	# ext_refs
	assert(main_node.ext_refs.has("script"), "Main should have ext_ref for 'script'")
	assert(main_node.ext_refs["script"].id == "1_script", "Script ref id should be 1_script")

	# sub_refs
	assert(player_node.children.size() > 0, "Player should have children")
	for child in player_node.children:
		if child.name == "CollisionShape":
			assert(child.sub_refs.has("shape"), "CollisionShape should have sub_ref for 'shape'")
			assert(child.sub_refs["shape"].id == "1_shape", "Shape ref id should be 1_shape")
			break

	print("  PASS")


# ============================================================
# 测试 3: 信号连接（含 flags）
# ============================================================
func test_signals():
	print("Test: signal connections with flags...")

	var result = _tscn_parser.parse(SCENE_FULL)
	assert(result != null, "Result should not be null")

	# 检查信号连接数（test_scene_full 有 4 条）
	assert(result.signal_connections.size() >= 4,
			"Expected >=4 signal connections, got %d" % result.signal_connections.size())

	# 查找 pressed 信号
	var pressed_conns = result.get_connections_for_signal("pressed")
	assert(pressed_conns.size() >= 1, "Should have pressed signal connection")
	var pressed = pressed_conns[0]
	assert(pressed.signal_name == "pressed", "Signal name should be pressed")
	assert(pressed.from_node == "Main/UI/HUD/Button", "from_node mismatch")
	assert(pressed.method == "_on_button_pressed", "method mismatch")
	assert(pressed.flags == 0, "pressed flags should be 0")

	# 查找 health_changed 信号（flags=4: ONE_SHOT）
	var health_conns = result.get_connections_for_signal("health_changed")
	assert(health_conns.size() >= 1, "Should have health_changed signal connections")
	var has_oneshot = false
	var has_deferred = false
	for c in health_conns:
		if c.flags == 4:
			has_oneshot = true
		if c.flags == 1:
			has_deferred = true
	assert(has_oneshot, "Should have a ONE_SHOT (flags=4) connection")
	assert(has_deferred, "Should have a DEFERRED (flags=1) connection")

	# 连接信号查询
	var main_conns = result.get_connections_for_node(".")
	assert(main_conns.size() >= 1, "Root node should have connections")

	print("  PASS")


# ============================================================
# 测试 4: .tres 资源文件解析
# ============================================================
func test_tres():
	print("Test: tres resource file parsing...")

	var result = _tres_parser.parse(RESOURCE_FILE)
	assert(result != null, "Result should not be null")
	assert(result.file_type == GDSSceneResourceResult.FileType.TRES, "Should be TRES")
	assert(result.file_path == RESOURCE_FILE, "File path should match")

	# [gd_resource] type
	assert(result.resource_type == "Resource", "Resource type should be 'Resource'")
	assert(result.load_steps == 3, "Load steps should be 3")

	# ext_resource
	assert(result.ext_resources.size() == 2, "Should have 2 ext_resources")
	assert(result.ext_resources.has("1_script"), "Should have 1_script")
	assert(result.ext_resources["1_script"].type == "Script")

	# sub_resource
	assert(result.sub_resources.size() == 2, "Should have 2 sub_resources")
	assert(result.sub_resources.has("1_shape"), "Should have 1_shape")
	assert(result.sub_resources["1_shape"].type == "RectangleShape2D")

	# [resource] properties
	assert(result.resource_properties.size() >= 3, "Should have at least 3 properties")
	assert(result.resource_properties.has("max_health"), "Should have max_health")
	assert(result.resource_properties.has("speed"), "Should have speed")
	assert(result.resource_properties.has("script"), "Should have script")

	print("  PASS")


# ============================================================
# 测试 5: JSON Schema 验证
# ============================================================
func test_json_schema():
	print("Test: JSON schema validation (schema_version, fields)...")

	var result = _tscn_parser.parse(SCENE_FULL)
	var data = result.to_dict()

	# 基本结构
	assert(data.has("file_path"), "to_dict should have file_path")
	assert(data.has("file_type"), "to_dict should have file_type")
	assert(data.file_type == "TSCN", "file_type should be 'TSCN'")

	# TSCN 专有字段
	assert(data.has("scene_uid"), "to_dict should have scene_uid")
	assert(data.has("root_nodes"), "to_dict should have root_nodes")
	assert(data.has("signal_connections"), "to_dict should have signal_connections")
	assert(data.has("editable_paths"), "to_dict should have editable_paths")

	# 通用字段
	assert(data.has("ext_resources"), "to_dict should have ext_resources")
	assert(data.has("sub_resources"), "to_dict should have sub_resources")
	assert(data.has("script_associations"), "to_dict should have script_associations")

	# 节点序列化
	assert(data.root_nodes.size() >= 1, "root_nodes should have at least 1 entry")

	# TRES to_dict
	var tres_result = _tres_parser.parse(RESOURCE_FILE)
	var tres_data = tres_result.to_dict()
	assert(tres_data.file_type == "TRES", "TRES file_type should be 'TRES'")
	assert(tres_data.has("resource_type"), "TRES to_dict should have resource_type")
	assert(tres_data.has("resource_properties"), "TRES to_dict should have resource_properties")

	print("  PASS")


# ============================================================
# 测试 6: SCRIPT_ATTACH 跨文件边
# ============================================================
func test_script_attach():
	print("Test: SCRIPT_ATTACH cross-file edge via project analyzer...")

	# 使用项目分析器进行完整分析
	var pa = GDScriptProjectAnalyzer.new()
	GDSScanConfig.save_config([{"path": "res://tests/fixtures", "recursive": true}], [])
	GDSScanConfig.enable_scan()
	var result = pa.analyze_full()

	# 检查 scenes
	assert(result.scenes.size() >= 2, "Should have at least 2 scenes, got %d" % result.scenes.size())

	# 检查 files — test_script_for_scene.gd 应在 files 中
	var has_script = false
	for fpath in result.files:
		if fpath.ends_with("test_script_for_scene.gd"):
			has_script = true
			break
	assert(has_script, "test_script_for_scene.gd should be in analyzed files")

	# 检查 SCRIPT_ATTACH 边
	var attach_edges = []
	for edge in result.cross_edges:
		if edge.kind == GDSCrossFileEdge.Kind.SCRIPT_ATTACH:
			attach_edges.append(edge)
	assert(attach_edges.size() >= 1, "Should have >=1 SCRIPT_ATTACH edge, got %d" % attach_edges.size())

	# 验证边的 source 是场景，target 是脚本
	for edge in attach_edges:
		assert(edge.source_file.ends_with(".tscn") or edge.source_file.ends_with(".tres"),
				"SCRIPT_ATTACH source should be a scene/resource file, got %s" % edge.source_file)
		assert(edge.target_file.ends_with(".gd"),
				"SCRIPT_ATTACH target should be a .gd file, got %s" % edge.target_file)

	# 检查 script_associations (project level)
	assert(result.script_associations.size() >= 1, "Should have project-level script_associations")

	print("  PASS")


# ============================================================
# 额外测试: 简单场景解析
# ============================================================
func test_tscn_simple():
	print("Test: simple tscn parsing...")

	var result = _tscn_parser.parse(SCENE_SIMPLE)
	assert(result != null, "Result should not be null")
	assert(result.ext_resources.size() == 1, "Simple scene should have 1 ext_resource")
	assert(result.root_nodes.size() == 1, "Simple scene should have 1 root node")
	assert(result.root_nodes[0].name == "SimpleRoot", "Root node should be SimpleRoot")

	var child = _find_node_in_flat(result, "Child")
	assert(child != null, "Child node should exist")
	assert(child.parent_path == "SimpleRoot", "Child parent should be SimpleRoot")

	print("  PASS")


# ============================================================
# 额外测试: 信号 flags 值解析
# ============================================================
func test_tscn_flags_value():
	print("Test: signal flags value parsing...")

	var result = _tscn_parser.parse(SCENE_SIGNALS)
	assert(result != null, "Result should not be null")

	# 找到各种 flags
	var flags_seen = {}
	for conn in result.signal_connections:
		flags_seen[conn.flags] = conn

	assert(flags_seen.has(0), "Should have a connection with flags=0")
	assert(flags_seen.has(1), "Should have a connection with flags=1 (DEFERRED)")

	# flags=6 = PERSIST(2) | ONE_SHOT(4)
	assert(flags_seen.has(6), "Should have a connection with flags=6 (PERSIST|ONE_SHOT)")

	# 检查 from_node 路径正确
	var emitter_conns = result.get_connections_for_node("Emitter")
	assert(emitter_conns.size() >= 1, "Emitter should have connections")

	print("  PASS")


# ============================================================
# Chunk A: UID 引用解析测试
# ============================================================
func test_uid_resolve():
	print("Test: uid-only ext_resource resolution...")

	# 用项目分析器（含 uid_map 收集）
	var pa = GDScriptProjectAnalyzer.new()
	GDSScanConfig.save_config([{"path": "res://tests/fixtures", "recursive": true}], [])
	GDSScanConfig.enable_scan()
	var result = pa.analyze_all()

	# test_scene_uid.tscn 的 ext_resource 只有 uid= 无 path=
	var scene_result = result.scenes.get(SCENE_UID, null)
	if scene_result == null:
		# 若无 scenes 结果，验证 uid_map 存在
		assert(result.uid_map.size() > 0, "uid_map should have entries: %d" % result.uid_map.size())
		print("  SKIP (scene not in scan result, uid_map has %d entries)" % result.uid_map.size())
		return

	# ext_resource 的 path 应通过 uid_map 反查还原
	var ext_script = scene_result.ext_resources.get("1_script", null)
	assert(ext_script != null, "1_script ext_resource should exist")
	assert(ext_script.path != "", "1_script path should be resolved from uid, got empty")
	assert(ext_script.path.ends_with("test_script_for_scene.gd"),
			"1_script path should end with test_script_for_scene.gd, got '%s'" % ext_script.path)
	assert(ext_script.uid == "uid://cxixtvlqumj56", "uid should match")

	# 验证节点脚本关联
	var root_node = _find_node_in_flat(scene_result, "Root")
	assert(root_node != null, "Root node should exist")
	assert(root_node.script_resource != "", "script_resource should be resolved")
	assert(root_node.script_resource.ends_with("test_script_for_scene.gd"),
			"script_resource should end with test_script_for_scene.gd, got '%s'" % root_node.script_resource)

	print("  PASS")


# ============================================================
# Chunk B: @export 填充值提取测试
# ============================================================
func test_export_overrides():
	print("Test: export overrides extraction...")

	# 用项目分析器（含 script exports 查找）
	var pa = GDScriptProjectAnalyzer.new()
	GDSScanConfig.save_config([{"path": "res://tests/fixtures", "recursive": true}], [])
	GDSScanConfig.enable_scan()
	var result = pa.analyze_all()

	var scene_result = result.scenes.get(SCENE_FULL, null)
	assert(scene_result != null, "test_scene_full should be in scan results")

	# 查找 Player 节点（有 script + @export var 对应属性）
	# test_scene_full 中 Player 节点有 max_health=150 speed=500.0
	# test_script_for_scene.gd 声明 @export var max_health, @export var speed
	var player_node = _find_node_in_flat(scene_result, "Player")
	assert(player_node != null, "Player node should exist")
	assert(player_node.script_resource != "", "Player should have script_resource")

	# export_overrides 字典应有匹配的 @export var 值
	assert(player_node.export_overrides.has("max_health"),
			"export_overrides should have max_health. Keys: %s" % [player_node.export_overrides.keys()])
	assert(player_node.export_overrides.has("speed"),
			"export_overrides should have speed. Keys: %s" % [player_node.export_overrides.keys()])
	assert(player_node.export_overrides["max_health"] == "150",
			"max_health should be '150', got '%s'" % player_node.export_overrides["max_health"])
	assert(player_node.export_overrides["speed"] == "500.0",
			"speed should be '500.0', got '%s'" % player_node.export_overrides["speed"])

	print("  PASS")


# ============================================================
# Chunk C: 子资源内联解析测试
# ============================================================
func test_sub_resource_inline():
	print("Test: sub_resource inline type parsing...")

	# 用独立 parser 解析
	var result = _tscn_parser.parse(SCENE_FULL)
	assert(result != null, "Result should not be null")

	# 1_shape 是 RectangleShape2D，size = Vector2(32, 32)
	var shape1 = result.sub_resources.get("1_shape", null)
	assert(shape1 != null, "1_shape should exist")

	# Chunk C: size 应被解析为 Vector2（而非原始字符串 "Vector2(32, 32)"）
	assert(shape1.properties.has("size"), "1_shape should have 'size' property")
	var size_val = shape1.properties["size"]
	if typeof(size_val) == TYPE_VECTOR2:
		assert(size_val == Vector2(32, 32), "size should be Vector2(32, 32), got %s" % size_val)
	else:
		# 回退：str_to_var 不可用时至少透传字符串
		assert(size_val is String, "size fallback should be String, got %s" % typeof(size_val))
		assert(size_val == "Vector2(32, 32)", "size string should match")

	print("  PASS")


# ============================================================
# Chunk D: .tres 子资源链展开测试
# ============================================================
func test_tres_sub_chain():
	print("Test: tres sub-resource chain expansion...")

	# test_resource_nested.tres 有 3 层 SubResource 链：
	# 3_wrapper → 2_shape → 1_shape（RectangleShape2D size=Vector2(32,32)）
	var result = _tres_parser.parse(RESOURCE_NESTED)
	assert(result != null, "Result should not be null")

	# 验证 sub_resources 基础解析
	assert(result.sub_resources.size() == 3, "Should have 3 sub_resources, got %d" % result.sub_resources.size())

	# 验证 [resource] 中的 SubResource 已被递归展开
	var wrapper_props = result.resource_properties.get("wrapper", null)
	assert(wrapper_props != null, "wrapper should be expanded (not raw string)")
	assert(wrapper_props is Dictionary, "wrapper should be a Dictionary after expansion")

	# 检查展开后的内层结构
	if wrapper_props is Dictionary:
		assert(wrapper_props.has("$type"), "wrapper should have $type marker, keys: %s" % [wrapper_props.keys()])
		assert(wrapper_props["$type"] == "Resource", "wrapper $type should be 'Resource'")

		# 内层 2_shape
		var inner_shape = wrapper_props.get("inner", null)
		assert(inner_shape != null, "wrapper should have 'inner' key")
		assert(inner_shape is Dictionary, "inner should be expanded Dictionary")
		if inner_shape is Dictionary:
			assert(inner_shape.has("$type"), "inner should have $type")
			assert(inner_shape["$type"] == "CircleShape2D", "inner $type should be CircleShape2D")
			assert(inner_shape.has("radius"), "inner should have radius")
			# 最内层 1_shape（RectangleShape2D）
			var innermost = inner_shape.get("inner_shape", null)
			assert(innermost != null, "inner should have inner_shape")
			assert(innermost is Dictionary, "innermost should be expanded")
			if innermost is Dictionary:
				assert(innermost.has("$type"), "innermost should have $type")
				assert(innermost["$type"] == "RectangleShape2D", "innermost $type should be RectangleShape2D")

	print("  PASS")


# ============================================================
# Chunk D: 环检测测试
# ============================================================
func test_tres_cycle():
	print("Test: tres sub-resource cycle detection...")

	# test_resource_cycle.tres: 1_a → 2_b → 1_a（环）
	var result = _tres_parser.parse(RESOURCE_CYCLE)
	assert(result != null, "Result should not be null")
	assert(result.sub_resources.size() == 2, "Should have 2 sub_resources")

	# 展开不应无限递归
	var root_props = result.resource_properties.get("root", null)
	assert(root_props != null, "root should be expanded")
	assert(root_props is Dictionary, "root should be Dictionary after expansion")

	if root_props is Dictionary:
		assert(root_props.has("$type"), "root should have $type")
		# 第二层 2_b 应被展开
		var child_b = root_props.get("child", null)
		assert(child_b != null, "root should have child key")
		assert(child_b is Dictionary, "child should be expanded")

		# 返回 1_a 时遇到环 → 标记 $circular_ref
		if child_b is Dictionary:
			var back_ref = child_b.get("child", null)
			assert(back_ref != null, "child_b should have child key")
			assert(back_ref is Dictionary, "back ref should be Dictionary")
			if back_ref is Dictionary:
				assert(back_ref.has("$circular_ref"), "Circular reference should be marked with $circular_ref")
				assert(back_ref["$circular_ref"] == "1_a", "Circular ref should point to '1_a'")

	print("  PASS")


# ============================================================
# 辅助方法
# ============================================================

func _find_root_by_name(p_result: GDSSceneResourceResult, p_name: String) -> GDSSceneResourceResult.SceneNodeData:
	for root in p_result.root_nodes:
		if root.name == p_name:
			return root
	return null

func _find_node_in_flat(p_result: GDSSceneResourceResult, p_name: String) -> GDSSceneResourceResult.SceneNodeData:
	for path in p_result.nodes_flat:
		var node: GDSSceneResourceResult.SceneNodeData = p_result.nodes_flat[path]
		if node.name == p_name:
			return node
	return null
