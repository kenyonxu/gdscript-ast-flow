# addons/gdscript_ast/tests/test_graph_virtualization.gd
# 大图虚拟化冒烟测试 — 200 节点验证视口裁剪

extends Node

func _ready() -> void:
	test_virtualization_smoke()
	print("✓ 所有测试通过")

func test_virtualization_smoke():
	var ge = GDSVirtualGraphEdit.new()
	add_child(ge)
	
	var nodes: Dictionary = {}
	for i in 200:
		nodes["fn_n%d" % i] = {
			"pos": Vector2((i % 5) * 200, int(i / 5) * 110),
			"kind": "function", "title": "n%d" % i, "node_name": "fn_n%d" % i,
			"subtitle": "", "degree": 0, "signature": "", "location": "",
			"jump": {"file": "", "line": 0},
		}
	
	var edges: Array = []
	for i in 199:
		edges.append(["fn_n%d" % i, "fn_n%d" % (i + 1)])
	
	ge.set_graph(nodes, edges)
	
	# 验证：渲染节点数应远小于总节点数（视口裁剪生效）
	var rendered = ge._rendered.size()
	assert(rendered <= nodes.size(), "virtualization should not exceed total nodes")
	assert(rendered < 50, "virtualization should clip to viewport (<50 visible out of 200)")
	
	print("  总节点: %d, 渲染节点: %d (裁剪率: %.1f%%)" % [
		nodes.size(), rendered, (1.0 - float(rendered) / nodes.size()) * 100
	])
	
	ge.queue_free()
