# tests/test_tscn_tres_parser.gd
# .tscn/.tres 解析器验收测试 — 6 套测试用例

extends Node

const FIXTURES := "res://tests/fixtures/"
const SCENE_FULL := FIXTURES + "test_scene_full.tscn"
const SCENE_SIMPLE := FIXTURES + "test_scene_simple.tscn"
const SCENE_SIGNALS := FIXTURES + "test_scene_signals.tscn"
const RESOURCE_FILE := FIXTURES + "test_resource.tres"
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

	# node 节 — 检查根节点
	assert(result.root_nodes.size() >= 1, "Should have at least 1 root node")
	var main_node = _find_root_by_name(result, "Main")
	assert(main_node != null, "Main node should exist")
	assert(main_node.type == "Node", "Main type should be Node")

	var player_node = _find_root_by_name(result, "Player")
	assert(player_node != null, "Player should be a root node (parent='.')")
	assert(player_node.type == "CharacterBody2D", "Player type mismatch")

	# 子节点
	assert(player_node.children.size() >= 2, "Player should have at least 2 children: CollisionShape + Sprite")

	# collision_layer 属性
	assert(player_node.properties.has("collision_layer"), "Player should have collision_layer")

	# [editable] 节
	assert(result.editable_paths.size() >= 1, "Should have editable paths")
	assert(result.editable_paths.has("SubScene"), "Editable should include SubScene")

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
	assert(pressed.from_node == "UI/HUD/Button", "from_node mismatch")
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
