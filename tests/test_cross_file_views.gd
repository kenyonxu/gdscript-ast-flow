extends Node

# preload 以注册 class_name（MCP 创建的文件不会自动扫描）
const GDSCrossFileKinds = preload("res://addons/gdscript_ast/editor/graphs/gds_cross_file_kinds.gd")
const GDSCallGraphView = preload("res://addons/gdscript_ast/editor/graphs/gds_call_graph_view.gd")
const GDScriptProjectResult = preload("res://addons/gdscript_ast/gds_project_result.gd")
const GDScriptTokenizer = preload("res://addons/gdscript_ast/gds_tokenizer.gd")
const GDScriptParser = preload("res://addons/gdscript_ast/gds_parser.gd")
const GDScriptSymbolResolver = preload("res://addons/gdscript_ast/gds_symbol_resolver.gd")
const GDSCrossFileEdge = preload("res://addons/gdscript_ast/gds_cross_file_edge.gd")
const GDSSignalGraphView = preload("res://addons/gdscript_ast/editor/graphs/gds_signal_graph_view.gd")
const GDSProjectGraphView = preload("res://addons/gdscript_ast/editor/graphs/gds_project_graph_view.gd")

func _ready():
	print("=== cross file views tests ===")
	test_kind_port_mapping()
	test_kind_colors()
	test_slot_config_multi_port()
	test_external_file_node_kind()
	test_call_view_cross_file_edges()
	test_signal_view_cross_file_edges()
	test_project_call_4_kinds()
	print("=== DONE ===")

func test_kind_port_mapping():
	print("Test: KIND_PORT mapping (CALL=0/INSTANCE=1/EXTENDS=2/VARIABLE_ACCESS=3)...")
	assert_eq(0, GDSCrossFileKinds.KIND_PORT[GDSCrossFileEdge.Kind.CALL], "CALL port")
	assert_eq(1, GDSCrossFileKinds.KIND_PORT[GDSCrossFileEdge.Kind.INSTANCE], "INSTANCE port")
	assert_eq(2, GDSCrossFileKinds.KIND_PORT[GDSCrossFileEdge.Kind.EXTENDS], "EXTENDS port")
	assert_eq(3, GDSCrossFileKinds.KIND_PORT[GDSCrossFileEdge.Kind.VARIABLE_ACCESS], "VARIABLE_ACCESS port")
	print("  PASS")

func test_kind_colors():
	print("Test: KIND_COLORS 4 entries...")
	assert_eq(4, GDSCrossFileKinds.KIND_COLORS.size(), "4 call-graph kinds")
	assert_eq(Color.DODGER_BLUE, GDSCrossFileKinds.KIND_COLORS[GDSCrossFileEdge.Kind.CALL], "CALL blue")
	assert_eq(Color.ORANGE, GDSCrossFileKinds.KIND_COLORS[GDSCrossFileEdge.Kind.INSTANCE], "INSTANCE orange")
	assert_eq(Color.MEDIUM_PURPLE, GDSCrossFileKinds.KIND_COLORS[GDSCrossFileEdge.Kind.EXTENDS], "EXTENDS purple")
	assert_eq(Color.CYAN, GDSCrossFileKinds.KIND_COLORS[GDSCrossFileEdge.Kind.VARIABLE_ACCESS], "VA cyan")
	print("  PASS")

func test_slot_config_multi_port():
	print("Test: GDSCrossFileKinds.make_slot_config multi-port...")
	var sc = GDSCrossFileKinds.make_slot_config([GDSCrossFileEdge.Kind.CALL, GDSCrossFileEdge.Kind.VARIABLE_ACCESS])
	assert_eq(2, sc.slots.size(), "2 slots for 2 kinds")
	assert_eq(true, sc.slots[0].li, "slot0 left enabled")
	assert_eq(Color.DODGER_BLUE, sc.slots[0].lc, "slot0 CALL blue")
	assert_eq(Color.CYAN, sc.slots[1].rc, "slot1 VA cyan right")
	print("  PASS")

func test_external_file_node_kind():
	print("Test: GDSGraphNode external_file kind...")
	var n = GDSGraphNode.new()
	n.configure("external_file", "enemy.gd", "external", 0)
	assert_eq("📁 enemy.gd", n.title, "external_file title = 📁 + filename")
	n.queue_free()
	print("  PASS")

func assert_eq(p_expected, p_actual, p_msg: String = ""):
	if p_expected != p_actual:
		printerr("  FAIL: %s — expected %s, got %s" % [p_msg, str(p_expected), str(p_actual)])

func assert_true(p_cond: bool, p_msg: String = ""):
	if not p_cond:
		printerr("  FAIL: %s" % p_msg)

func _resolve_project(p_sources: Dictionary) -> Dictionary:
	# p_sources: {path: source, "__cross_edges": [GDSCrossFileEdge...]} -> {project, files}
	var project = GDScriptProjectResult.new()
	var files: Dictionary = {}
	for path in p_sources:
		if path == "__cross_edges":
			continue
		var tz = GDScriptTokenizer.new()
		var parser = GDScriptParser.new()
		var ast = parser.parse(tz.tokenize(p_sources[path]))
		if parser.error != "":
			continue
		var r = GDScriptSymbolResolver.new()
		var result = r.resolve(ast, path)
		files[path] = result
		project.files[path] = result
	project.cross_edges = p_sources.get("__cross_edges", [])
	return {"project": project, "files": files}

func test_call_view_cross_file_edges():
	print("Test: call_graph_view cross-file edges...")
	var sources = {
		"res://player.gd": "class_name Player\nextends Node\nfunc hit(e: Enemy):\n\te.take_damage()\n",
		"res://enemy.gd": "class_name Enemy\nextends Node\nfunc take_damage():\n\tpass\n",
	}
	var ce = GDSCrossFileEdge.new()
	ce.kind = GDSCrossFileEdge.Kind.CALL
	ce.source_file = "res://player.gd"
	ce.source_symbol = "hit"
	ce.target_file = "res://enemy.gd"
	ce.target_class = "Enemy"
	ce.target_symbol = "take_damage"
	sources["__cross_edges"] = [ce]
	var env = _resolve_project(sources)
	var view = GDSCallGraphView.new()
	var logical = view.build_logical(env.files["res://player.gd"], 0, env.project)
	var has_external = false
	var has_cross_edge = false
	for name in logical.nodes:
		if logical.nodes[name].get("kind") == "external_file" and logical.nodes[name].title == "enemy.gd":
			has_external = true
	for e in logical.edges:
		if e.size() >= 4 and e[2] == 0 and e[3] == 0:  # CALL port 0
			has_cross_edge = true
	assert_true(has_external, "should have external_file node enemy.gd")
	assert_true(has_cross_edge, "should have CALL cross edge port 0")
	print("  PASS")

func test_signal_view_cross_file_edges():
	print("Test: signal_graph_view cross-file emit/connect edges...")
	var sources = {
		"res://player.gd": "class_name Player\nextends Node\nsignal hit\nfunc _ready():\n\thit.emit()\n",
		"res://ui.gd": "class_name UI\nextends Node\nfunc _ready(p: Player):\n\tp.hit.connect(_on_hit)\nfunc _on_hit():\n\tpass\n",
	}
	# ui.gd connect player.hit —— 对 ui 是出边 connect 跨文件
	var ce_connect = GDSCrossFileEdge.new()
	ce_connect.kind = GDSCrossFileEdge.Kind.SIGNAL_CONNECT
	ce_connect.source_file = "res://ui.gd"
	ce_connect.source_symbol = "_ready"
	ce_connect.target_file = "res://player.gd"
	ce_connect.target_symbol = "hit"
	# player.gd emit hit —— 对 player 是出边 emit 跨文件
	var ce_emit = GDSCrossFileEdge.new()
	ce_emit.kind = GDSCrossFileEdge.Kind.SIGNAL_EMIT
	ce_emit.source_file = "res://player.gd"
	ce_emit.source_symbol = "_ready"
	ce_emit.target_file = "res://ui.gd"
	ce_emit.target_symbol = "hit"
	sources["__cross_edges"] = [ce_connect, ce_emit]
	var env = _resolve_project(sources)
	# 测试 ui.gd 视角：connect 出边到 player
	var view = GDSSignalGraphView.new()
	var logical_ui = view.build_logical(env.files["res://ui.gd"], 0, env.project)
	var has_external_ui = false
	for name in logical_ui.nodes:
		if logical_ui.nodes[name].get("kind") == "external_file":
			has_external_ui = true
	assert_true(has_external_ui, "signal view (ui.gd) should show external_file node for cross connect")
	# 测试 player.gd 视角：emit 出边到 ui
	var logical_pl = view.build_logical(env.files["res://player.gd"], 0, env.project)
	var has_external_pl = false
	for name in logical_pl.nodes:
		if logical_pl.nodes[name].get("kind") == "external_file":
			has_external_pl = true
	assert_true(has_external_pl, "signal view (player.gd) should show external_file node for cross emit")
	print("  PASS")

func test_project_call_4_kinds():
	print("Test: project_graph_view _build_call_logical 4 Kind edges...")
	var sources = {
		"res://player.gd": "class_name Player\nextends Node\nfunc hit(e: Enemy):\n\te.take_damage()\n",
		"res://enemy.gd": "class_name Enemy\nextends Node\nvar hp: int\nfunc take_damage():\n\thp -= 1\n",
	}
	# 4 种 cross edge: player ↔ enemy（每种 Kind 一条）
	var edges_arr = []
	for kind in [GDSCrossFileEdge.Kind.CALL, GDSCrossFileEdge.Kind.INSTANCE, GDSCrossFileEdge.Kind.EXTENDS, GDSCrossFileEdge.Kind.VARIABLE_ACCESS]:
		var ce = GDSCrossFileEdge.new()
		ce.kind = kind
		ce.source_file = "res://player.gd"
		ce.target_file = "res://enemy.gd"
		edges_arr.append(ce)
	sources["__cross_edges"] = edges_arr
	var env = _resolve_project(sources)
	var view = GDSProjectGraphView.new()
	var logical = view.build_logical(env.project, 0, 0)  # graph_kind=0 (call)
	assert_true(logical.edges.size() >= 4, "should have >=4 edges (4 kinds player->enemy)")
	# 验证 port 分配：每条边 4 元素 [from, to, from_port, to_port]
	var ports_found: Dictionary = {}
	for e in logical.edges:
		if e.size() >= 4:
			ports_found[e[2]] = true
	assert_true(ports_found.has(0), "should have port 0 (CALL)")
	assert_true(ports_found.has(1), "should have port 1 (INSTANCE)")
	assert_true(ports_found.has(2), "should have port 2 (EXTENDS)")
	assert_true(ports_found.has(3), "should have port 3 (VARIABLE_ACCESS)")
	print("  PASS")
