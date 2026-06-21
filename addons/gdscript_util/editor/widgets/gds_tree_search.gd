# addons/gdscript_util/editor/widgets/gds_tree_search.gd
# Tree 搜索高亮工具 — 搜索时高亮匹配项，保留上下文（不隐藏）
# 参考: limboai/editor/tree_search.cpp

class_name GDSTreeSearch
extends RefCounted

# 对一棵 Tree 的所有可见项执行搜索高亮
# p_query: 搜索词（空串则清除高亮）
# p_text_column: 文本所在列
static func highlight(p_tree: Tree, p_query: String, p_text_column: int = 0) -> void:
	var query_lower = p_query.to_lower()
	var root = p_tree.get_root()
	if root == null:
		return
	var item = root.get_first_child()
	while item != null:
		_highlight_item(item, query_lower, p_text_column)
		item = item.get_next_in_tree()

static func _highlight_item(p_item: TreeItem, p_query_lower: String, p_col: int) -> void:
	var text = p_item.get_text(p_col)
	if p_query_lower.is_empty():
		p_item.clear_custom_color(p_col)
	elif text.to_lower().find(p_query_lower) != -1:
		p_item.set_custom_color(p_col, Color.YELLOW)
	else:
		p_item.clear_custom_color(p_col)
