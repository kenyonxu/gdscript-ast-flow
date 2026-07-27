# addons/gdscript_ast/gds_expr_formatter.gd
# AST 表达式 → 字符串序列化（DefUse/Signal/CallGraph 面板共用）
# 纯函数 + static 方法，可 TDD

class_name GDSExprFormatter
extends RefCounted

# 单个表达式节点 → 字符串
static func format(p_expr) -> String:
	if p_expr == null:
		return "<null>"

	# LiteralNode（数字/字符串/bool 字面量）
	if p_expr is GDScriptToken.LiteralNode:
		return str(p_expr.value)

	# IdentifierNode
	if p_expr is GDScriptToken.IdentifierNode:
		return p_expr.name

	# self / super（独立全局 class_name，见 gds_self_node.gd / gds_super_node.gd）
	if p_expr is GDScriptSelfNode:
		return "self"
	if p_expr is GDScriptSuperNode:
		return "super"

	# 二元运算
	if p_expr is GDScriptToken.BinaryOpNode:
		var op_str = _op_text(p_expr.op)
		return "%s %s %s" % [format(p_expr.left), op_str, format(p_expr.right)]

	# 一元运算
	if p_expr is GDScriptToken.UnaryOpNode:
		var op_str = _op_text(p_expr.op)
		return "%s%s" % [op_str, format(p_expr.operand)]

	# 三元运算
	if p_expr is GDScriptToken.TernaryOpNode:
		return "%s if %s else %s" % [format(p_expr.true_expr), format(p_expr.condition), format(p_expr.false_expr)]

	# 赋值
	if p_expr is GDScriptToken.AssignmentNode:
		var op_str = _op_text(p_expr.op)
		return "%s %s %s" % [format(p_expr.target), op_str, format(p_expr.value)]

	# 属性访问 (a.b)
	if p_expr is GDScriptToken.AttributeNode:
		return "%s.%s" % [format(p_expr.base), p_expr.name]

	# 调用 (foo(args))
	if p_expr is GDScriptToken.CallNode:
		return "%s(%s)" % [format(p_expr.callee), format_args(p_expr.arguments)]

	# 下标 (a[i])
	if p_expr is GDScriptToken.SubscriptNode:
		return "%s[%s]" % [format(p_expr.base), format(p_expr.index)]

	# 类型转换 (x as Type)
	if p_expr is GDScriptToken.CastNode:
		return "%s as %s" % [format(p_expr.expression), p_expr.type.type_name]

	# 类型测试 (x is Type)
	if p_expr is GDScriptToken.TypeTestNode:
		return "%s is %s" % [format(p_expr.expression), p_expr.type.type_name]

	# LambdaNode
	if p_expr is GDScriptToken.LambdaNode:
		return "<lambda>"

	# 数组字面量 [a, b]
	if p_expr is GDScriptToken.ArrayNode:
		return "[%s]" % format_args(p_expr.elements)

	# 字典字面量 {k: v}
	if p_expr is GDScriptToken.DictionaryNode:
		var pairs: Array = []
		for pair in p_expr.pairs:
			pairs.append("%s: %s" % [format(pair.get("key")), format(pair.get("value"))])
		return "{%s}" % ", ".join(pairs)

	# PreloadNode
	if p_expr is GDScriptToken.PreloadNode:
		return "preload(\"%s\")" % p_expr.path

	# FormattedStringNode (f-string)
	if p_expr is GDScriptToken.FormattedStringNode:
		return "<f-string>"

	# 场景唯一节点 %NodeName
	if p_expr is GDScriptToken.SceneUniqueNode:
		return "%%%s" % p_expr.name

	# 兜底
	return "<expr>"


# 参数数组 → "a, b, c"
static func format_args(p_args: Array) -> String:
	if p_args == null or p_args.is_empty():
		return ""
	var parts: Array = []
	for arg in p_args:
		parts.append(format(arg))
	return ", ".join(parts)


# Token.Type → 运算符文本
static func _op_text(p_type: int) -> String:
	# find_key 不依赖 enum 连续性（比 keys()[index] 稳健，防未来 enum 插入断值）
	var key = GDScriptToken.Type.find_key(p_type)
	if not key:
		return "?"
	return _op_map(key)


# 枚举名 → 运算符字符串
static func _op_map(p_key: String) -> String:
	match p_key:
		"PLUS": return "+"
		"MINUS": return "-"
		"STAR": return "*"
		"STAR_STAR": return "**"
		"SLASH": return "/"
		"PERCENT": return "%"
		"AMPERSAND": return "&"
		"PIPE": return "|"
		"CARET": return "^"
		"LESS_LESS": return "<<"
		"GREATER_GREATER": return ">>"
		"TILDE": return "~"
		"BANG_EQUAL": return "!="
		"EQUAL_EQUAL": return "=="
		"LESS": return "<"
		"LESS_EQUAL": return "<="
		"GREATER": return ">"
		"GREATER_EQUAL": return ">="
		"AND": return "and"
		"OR": return "or"
		"NOT": return "not"
		"EQUAL": return "="
		"PLUS_EQUAL": return "+="
		"MINUS_EQUAL": return "-="
		"STAR_EQUAL": return "*="
		"SLASH_EQUAL": return "/="
		"PERCENT_EQUAL": return "%="
		"STAR_STAR_EQUAL": return "**="
		"LESS_LESS_EQUAL": return "<<="
		"GREATER_GREATER_EQUAL": return ">>="
		"AMPERSAND_EQUAL": return "&="
		"PIPE_EQUAL": return "|="
		"CARET_EQUAL": return "^="
		_:
			return p_key.to_lower()
