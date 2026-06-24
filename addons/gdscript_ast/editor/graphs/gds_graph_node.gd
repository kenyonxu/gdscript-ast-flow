# addons/gdscript_ast/editor/graphs/gds_graph_node.gd
# 通用 GraphNode — 表示函数/信号/文件节点，度数驱动视觉
# GraphNode 有左右 slot：左=入边，右=出边
# 签名/位置/入口标记/tooltip 增强

class_name GDSGraphNode
extends GraphNode

const ENTRY_METHODS := preload("res://addons/gdscript_ast/editor/gds_entry_methods.gd")

var _pending_title_color: Color = Color.TRANSPARENT  # _ready 时应用（add_child 前 override 不生效）

func _ready() -> void:
	# GraphNode 的 title 是内部 Label（theme type "GraphNodeTitleLabel"），不是 GraphNode
	# 自身的 theme color。直接改内部 Label 的 font_color 才能着色。
	if _pending_title_color != Color.TRANSPARENT:
		var hbox = get_titlebar_hbox()
		if hbox and hbox.get_child_count() > 0:
			var title_label = hbox.get_child(0) as Label
			if title_label:
				title_label.add_theme_color_override("font_color", _pending_title_color)

# p_kind: "function" / "signal" / "file"
# p_hub_threshold: 枢纽高亮阈值（函数默认 5，文件默认 1——文件耦合度数值本身小）
func configure(p_kind: String, p_name: String, p_subtitle: String, p_degree: int, p_signature: String = "", p_location: String = "", p_hub_threshold: int = 5) -> void:
	var display_name = p_name
	# 入口函数标记: 前缀 ▶ + 绿色 title（_ready 时应用 override）
	if p_kind == "function" and ENTRY_METHODS.is_entry(p_name):
		display_name = "▶ " + p_name
		_pending_title_color = Color.LIME_GREEN
	elif p_kind == "function" and p_degree >= p_hub_threshold:
		# 枢纽高亮: 前缀 ● + 橙红 title
		display_name = "● " + p_name
		_pending_title_color = Color.ORANGE_RED
	title = display_name
	# 签名副文本
	if p_signature != "":
		var sig_label = Label.new()
		sig_label.text = p_signature
		sig_label.add_theme_font_size_override("font_size", 11)
		sig_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		add_child(sig_label)
	# 位置副文本
	if p_location != "":
		var loc_label = Label.new()
		loc_label.text = p_location
		loc_label.add_theme_font_size_override("font_size", 10)
		loc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		add_child(loc_label)
	# 度数副文本 — 用 RichTextLabel 支持 BBcode 多色（文件节点 ref/func/signal 分别着色）
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF  # 不换行，否则 fit_content 撑高节点
	label.text = p_subtitle
	label.add_theme_font_size_override("normal_font_size", 11)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.size_flags_vertical = SIZE_FILL
	add_child(label)
	# tooltip — 完整信息
	tooltip_text = "%s\n%s\n%s\n%s" % [display_name, p_signature, p_location, p_subtitle]
	# slot: 左 enable（入边），右 enable（出边）；type 用于着色分组
	var in_type := 0
	var out_type := 1
	var in_color := Color.DODGER_BLUE
	var out_color := Color.DODGER_BLUE
	set_slot(0, true, in_type, in_color, true, out_type, out_color)
	# 默认尺寸
	custom_minimum_size = Vector2(220, 0)
