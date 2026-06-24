# addons/gdscript_ast/editor/graphs/gds_graph_layout.gd
# 逻辑布局缓存 — 网格/双列排列，不依赖 GraphNode 实例

class_name GDSGraphLayout
extends RefCounted

static func assign_grid(p_nodes: Dictionary, p_cols := 5, p_cell: Vector2 = Vector2(200, 110)) -> void:
	var col := 0; var row := 0
	for name in p_nodes:
		p_nodes[name].pos = Vector2(col * p_cell.x, row * p_cell.y)
		col += 1
		if col >= p_cols:
			col = 0; row += 1

static func assign_two_column(p_left: Dictionary, p_center: Dictionary, p_right: Dictionary, p_cell: Vector2 = Vector2(200, 110)) -> void:
	var i := 0
	for name in p_left:
		p_left[name].pos = Vector2(150, i * p_cell.y); i += 1
	i = 0
	for name in p_center:
		p_center[name].pos = Vector2(500, i * p_cell.y); i += 1
	i = 0
	for name in p_right:
		p_right[name].pos = Vector2(850, i * p_cell.y); i += 1
