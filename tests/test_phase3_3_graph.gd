# tests/test_phase3_3_graph.gd
# Phase 3.3 图构建验收 — 度数 + view builder 产出节点/边数
extends Node

func _ready():
	print("=== Phase 3.3 Graph Tests ===\n")
	test_degree()
	test_call_graph_view()
	test_project_graph_view()
	print("\n=== Done ===")

# 用 analysis_demo.gd 单文件
func analyze_demo() -> GDScriptAnalysisResult:
	var f = FileAccess.open("res://samples/analysis_demo.gd", FileAccess.READ)
	var source = f.get_as_text()
	f.close()
	var tokenizer = GDScriptTokenizer.new()
	var parser = GDScriptParser.new()
	var ast = parser.parse(tokenizer.tokenize(source))
	assert(parser.error == "", "Parse error: %s" % parser.error)
	return GDScriptSymbolResolver.new().resolve(ast, "res://samples/analysis_demo.gd")

func test_degree():
	print("Test: call degree...")
	var r = analyze_demo()
	# analysis_demo.gd: _ready 调 take_damage + connect; take_damage emit 2 信号
	# _ready 应有出度 >= 2; take_damage 应有入度 >= 1
	assert(r.call_out_degree.get("_ready", 0) >= 2, "_ready out-degree >= 2 expected, got %d" % r.call_out_degree.get("_ready", 0))
	assert(r.call_in_degree.get("take_damage", 0) >= 1, "take_damage in-degree >= 1 expected, got %d" % r.call_in_degree.get("take_damage", 0))
	print("  PASS")

func test_call_graph_view():
	print("Test: call graph view build...")
	var r = analyze_demo()
	var view = GDSCallGraphView.new()
	var ge = GraphEdit.new()
	add_child(ge)
	view.build(ge, r)
	var node_count := 0
	for c in ge.get_children():
		if c is GraphNode:
			node_count += 1
	assert(node_count > 0, "Expected >0 graph nodes, got %d" % node_count)
	ge.queue_free()
	print("  PASS (%d nodes)" % node_count)

func test_project_graph_view():
	print("Test: project graph view build...")
	var pa = GDScriptProjectAnalyzer.new()
	# 测试用临时配置
	GDSScanConfig.save_config([{"path": "res://samples/cross_file_demo", "recursive": true}], [])
	GDSScanConfig.enable_scan()
	var proj = pa.analyze_full()
	var view = GDSProjectGraphView.new()
	var ge = GraphEdit.new()
	add_child(ge)
	view.build(ge, proj, 0)
	var node_count := 0
	for c in ge.get_children():
		if c is GraphNode:
			node_count += 1
	assert(node_count >= 2, "Expected >=2 file nodes, got %d" % node_count)
	ge.queue_free()
	print("  PASS (%d nodes)" % node_count)
