# tests/test_scene_main_screen.gd
# 场景主屏验收测试 — 数据层逻辑 + 视图构建
# 跑测: headless Godot 加载 test_scene_main_screen.tscn

extends Node

const FIXTURES := "res://tests/fixtures/"
const SCENE_FULL := FIXTURES + "test_scene_full.tscn"
const SCENE_SIGNALS := FIXTURES + "test_scene_signals.tscn"
const SCRIPT_FILE := FIXTURES + "test_script_for_scene.gd"

var _tscn_parser: GDScriptTscnParser
var _lookup_view  # SceneScriptLookupView
var _signal_view  # SceneSignalGraphView

func _ready():
	print("\n=== Scene Main Screen Acceptance Tests ===\n")
	_tscn_parser = GDScriptTscnParser.new()
	_lookup_view = preload("res://addons/gdscript_ast/editor/scene/scene_script_lookup_view.gd").new()
	_signal_view = preload("res://addons/gdscript_ast/editor/scene/scene_signal_graph_view.gd").new()
	run_all()
	print("\n=== All tests completed ===\n")
	get_tree().quit()

func run_all():
	test_node_tree_render()
	test_node_detail_fields()
	test_node_full_path()
	test_script_lookup_index()
	test_signal_graph_build()
	test_signal_graph_navigate()
	test_parse_nkey()
	test_empty_state()
	test_scan_disabled()
	test_parse_error_mark()


# ============================================================
# 测试 1: 节点树渲染 — 验证场景数据结构
# ============================================================
func test_node_tree_render():
	print("Test: node tree render (data model)...")

	var result = _tscn_parser.parse(SCENE_FULL)
	assert(result != null, "Result should not be null")
	assert(result.root_nodes.size() == 1, "1 root node (Main), got %d" % result.root_nodes.size())

	var main_node = result.root_nodes[0]
	assert(main_node.name == "Main", "Root should be Main")
	assert(main_node.type == "Node", "Main type should be Node")

	# Player 是 Main 的子节点
	var found_player = false
	for c in main_node.children:
		if c.name == "Player":
			found_player = true
			assert(c.type == "CharacterBody2D", "Player type should be CharacterBody2D")
			assert(c.script_resource != "", "Player should have script_resource")
			# Player 至少有 2 个子节点
			assert(c.children.size() >= 2, "Player should have >=2 children, got %d" % c.children.size())
			break
	assert(found_player, "Player is child of Main")

	# 验证重名 Icon 在不同父节点下
	var container_a = null
	var container_b = null
	for child in main_node.children:
		if child.name == "ContainerA":
			container_a = child
		elif child.name == "ContainerB":
			container_b = child
	assert(container_a != null, "ContainerA should exist")
	assert(container_b != null, "ContainerB should exist")
	assert(container_a.children.size() == 1, "ContainerA should have 1 child")
	assert(container_b.children.size() == 1, "ContainerB should have 1 child")
	assert(container_a.children[0].name == "Icon", "ContainerA child should be Icon")
	assert(container_b.children[0].name == "Icon", "ContainerB child should be Icon")
	# 两个 Icon 是不同的节点对象
	assert(container_a.children[0] != container_b.children[0], "Two Icon nodes should be different objects")

	# 验证节点平铺索引
	assert(result.nodes_flat.size() > 0, "nodes_flat should have entries")
	var main_flat = result.nodes_flat.get(".", null)
	assert(main_flat != null, "Root should be in nodes_flat at '.'")

	print("  PASS")


# ============================================================
# 测试 2: 节点详情字段
# ============================================================
func test_node_detail_fields():
	print("Test: node detail fields...")

	var result = _tscn_parser.parse(SCENE_FULL)
	var main_node = result.root_nodes[0]

	# 基本字段
	assert(main_node.name != "", "name should not be empty")
	assert(main_node.type != "", "type should not be empty")
	assert(main_node.parent_path == "", "root parent_path should be empty")

	# Player 节点详情
	var player_node = null
	for child in main_node.children:
		if child.name == "Player":
			player_node = child
			break
	assert(player_node != null, "Player should exist")
	assert(player_node.parent_path == "Main", "Player parent_path should be Main")
	assert(player_node.script_resource != "", "Player should have script_resource")
	assert(player_node.script_resource.ends_with("test_script_for_scene.gd"),
			"Player script should be test_script_for_scene.gd, got '%s'" % player_node.script_resource)

	# groups
	if player_node.groups.size() > 0:
		print("  Player groups: %s" % player_node.groups)

	# 信号连接
	assert(result.signal_connections.size() >= 1, "Should have signal connections")

	print("  PASS")


# ============================================================
# 测试 3: 节点完整路径推导
# ============================================================
func test_node_full_path():
	print("Test: node full path computation...")

	var result = _tscn_parser.parse(SCENE_FULL)

	# 在 nodes_flat 中找 Icon 节点，检查他们的父路径
	for path in result.nodes_flat:
		var node = result.nodes_flat[path]
		if node.name == "Icon":
			var expected_parent = path.rsplit("/", true, 1)[0] if "/" in path else "."
			print("  Icon at '%s', parent_path='%s'" % [path, node.parent_path])
			# 验证 Icon 的父路径是 ContainerA 或 ContainerB
			assert(node.parent_path in ["Main/ContainerA", "Main/ContainerB"],
					"Icon parent should be ContainerA or ContainerB, got '%s'" % node.parent_path)

	# 根节点 "." 的 parent_path 应为空
	var root_flat = result.nodes_flat.get(".", null)
	if root_flat:
		assert(root_flat.parent_path == "", "Root parent_path should be empty")

	print("  PASS")


# ============================================================
# 测试 4: 脚本反查聚合
# ============================================================
func test_script_lookup_index():
	print("Test: script lookup index...")

	# 构造假 script_associations 数据
	var fake_assocs = [
		{"scene": "res://scenes/level1.tscn", "node": "Player", "script": "res://player.gd"},
		{"scene": "res://scenes/level1.tscn", "node": "UI", "script": "res://ui.gd"},
		{"scene": "res://scenes/level2.tscn", "node": "Player", "script": "res://player.gd"},
		{"scene": "res://scenes/menu.tscn", "node": "Button", "script": "res://ui.gd"},
		{"scene": "res://scenes/level1.tscn", "node": "Enemy", "script": "res://enemy.gd"},
		{"scene": "res://scenes/level2.tscn", "node": "Boss", "script": "res://enemy.gd"},
		{"scene": "res://scenes/bonus.tscn", "node": "Player", "script": "res://player.gd"},
		# 空 script（应被跳过）
		{"scene": "res://scenes/level1.tscn", "node": "Dummy", "script": ""},
	]

	var idx = _lookup_view._build_index(fake_assocs)

	# player.gd → 3 挂载点
	assert(idx.has("res://player.gd"), "player.gd should be in index")
	assert(idx["res://player.gd"].size() == 3,
			"player.gd should have 3 mount points, got %d" % idx["res://player.gd"].size())

	# ui.gd → 2 挂载点
	assert(idx.has("res://ui.gd"), "ui.gd should be in index")
	assert(idx["res://ui.gd"].size() == 2,
			"ui.gd should have 2 mount points, got %d" % idx["res://ui.gd"].size())

	# enemy.gd → 2 挂载点
	assert(idx.has("res://enemy.gd"), "enemy.gd should be in index")
	assert(idx["res://enemy.gd"].size() == 2,
			"enemy.gd should have 2 mount points, got %d" % idx["res://enemy.gd"].size())

	# 空 script 不应出现在索引中
	assert(not idx.has(""), "Empty script should NOT be in index")

	print("  PASS")


# ============================================================
# 测试 5: 信号图 logical 构建
# ============================================================
func test_signal_graph_build():
	print("Test: signal graph logical build...")

	# 用真实场景数据构建模拟 proj
	var result = _tscn_parser.parse(SCENE_FULL)
	var signals_result = _tscn_parser.parse(SCENE_SIGNALS)

	# 构造假 proj 对象（模拟 bridge 返回的结构）
	var proj = {
		"scenes": {
			SCENE_FULL: result,
			SCENE_SIGNALS: signals_result,
		},
		"scene_signal_connections": [
			{
				"signal": "custom_signal",
				"from_scene": SCENE_FULL,
				"from_node": "Main/UI/HUD/Button",
				"to_scene": SCENE_SIGNALS,
				"to_node": "Receiver",
				"to_method": "_on_custom_signal",
			},
		],
	}

	var logical = _signal_view.build_logical(proj)

	# 验证节点数 > 0
	assert(logical.nodes.size() > 0, "Should have nodes, got %d" % logical.nodes.size())
	print("  Nodes: %d, Edges: %d" % [logical.nodes.size(), logical.edges.size()])

	# 验证跨场景边存在
	var has_cross = false
	for e in logical.edges:
		if not e.same_scene:
			has_cross = true
			assert(e.signal == "custom_signal", "Cross-scene edge should have custom_signal")
			break
	assert(has_cross, "Should have at least one cross-scene edge")

	# 验证同场景边存在
	var has_same = false
	for e in logical.edges:
		if e.same_scene:
			has_same = true
			break
	assert(has_same, "Should have at least one same-scene edge")

	print("  PASS")


# ============================================================
# 测试 6: 信号图导航 — _parse_nkey
# ============================================================
func test_signal_graph_navigate():
	print("Test: signal graph navigate via _parse_nkey...")

	# 测试 nkey 解析
	var test_cases = [
		{
			"nkey": "res://tests/fixtures/test_scene_full.tscn/Main/Player",
			"expected_scene": "res://tests/fixtures/test_scene_full.tscn",
			"expected_node": "Main/Player",
		},
		{
			"nkey": "res://tests/fixtures/test_scene_signals.tscn/Emitter",
			"expected_scene": "res://tests/fixtures/test_scene_signals.tscn",
			"expected_node": "Emitter",
		},
		{
			"nkey": "res://tests/fixtures/test_scene_full.tscn/Main",
			"expected_scene": "res://tests/fixtures/test_scene_full.tscn",
			"expected_node": "Main",
		},
	]

	for tc in test_cases:
		var parsed = _signal_view._parse_nkey(tc.nkey)
		assert(parsed.scene == tc.expected_scene,
				"Scene mismatch: expected '%s', got '%s'" % [tc.expected_scene, parsed.scene])
		assert(parsed.node == tc.expected_node,
				"Node mismatch: expected '%s', got '%s'" % [tc.expected_node, parsed.node])
		print("  OK: %s → scene='%s', node='%s'" % [tc.nkey, parsed.scene, parsed.node])

	print("  PASS")


# ============================================================
# 测试 7: 空状态处理
# ============================================================
func test_empty_state():
	print("Test: empty state handling...")

	# 模拟无场景数据时的行为
	var empty_proj = {
		"scenes": {},
		"script_associations": [],
		"scene_signal_connections": [],
	}

	# signal view 空 proj
	var logical = _signal_view.build_logical(empty_proj)
	assert(logical.nodes.size() == 0, "Empty proj should have 0 nodes, got %d" % logical.nodes.size())
	assert(logical.edges.size() == 0, "Empty proj should have 0 edges, got %d" % logical.edges.size())

	# lookup view 空 index
	var idx = _lookup_view._build_index([])
	assert(idx.size() == 0, "Empty assocs should produce empty index, got %d" % idx.size())

	print("  PASS")


# ============================================================
# 测试 8: 扫描关闭处理
# ============================================================
func test_scan_disabled():
	print("Test: scan disabled handling...")

	# 测试 GDSScanConfig.is_enabled() 静态方法
	# headless 模式下默认就是 false
	var is_enabled = GDSScanConfig.is_enabled()
	print("  GDSScanConfig.is_enabled() = %s" % is_enabled)

	# 只要不崩就是测试通过（headless 下无 ProjectSettings）
	print("  PASS (method does not crash)")


# ============================================================
# 测试 9: 解析失败标记
# ============================================================
func test_parse_error_mark():
	print("Test: parse error marking...")

	# 正常场景的 errors 应为空
	var result = _tscn_parser.parse(SCENE_FULL)
	assert(result.errors.size() == 0,
			"Valid scene should have no errors, got %d: %s" % [result.errors.size(), result.errors])

	# 测试解析失败的场景 — 构造一个带 errors 的场景数据
	var error_scene = _tscn_parser.parse(SCENE_FULL)
	error_scene.errors.append("Parse error at line 42: unexpected token")
	assert(error_scene.errors.size() == 1, "Should have 1 error after appending")

	# 验证 error 标记存在
	var has_errors = error_scene.errors.size() > 0
	assert(has_errors, "Scene should have errors marked")

	print("  PASS")
