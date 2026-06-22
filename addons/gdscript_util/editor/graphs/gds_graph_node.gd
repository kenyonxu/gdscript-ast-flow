# addons/gdscript_util/editor/graphs/gds_graph_node.gd
# 通用 GraphNode — 表示函数/信号/文件节点，度数驱动视觉
# GraphNode 有左右 slot：左=入边，右=出边

class_name GDSGraphNode
extends GraphNode

# kind: "function" / "signal" / "file"
func configure(p_kind: String, p_name: String, p_subtitle: String, p_degree: int) -> void:
	title = p_name
	# 副文本：@line / in:out / 文件路径
	var label = Label.new()
	label.text = p_subtitle
	label.add_theme_font_size_override("font_size", 11)
	add_child(label)
	# 枢纽高亮：度数 >= 5 用暖色（找"上帝函数"/高耦合文件）
	if p_degree >= 5:
		add_theme_color_override("title_color", Color.ORANGE_RED)
	# slot: 左 enable（入边），右 enable（出边）；type 用于着色分组
	var in_type := 0
	var out_type := 1
	var in_color := Color.DODGER_BLUE
	var out_color := Color.DODGER_BLUE
	set_slot(0, true, in_type, in_color, true, out_type, out_color)
	# 默认尺寸
	custom_minimum_size = Vector2(140, 0)
