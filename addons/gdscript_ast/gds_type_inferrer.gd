# addons/gdscript_ast/gds_type_inferrer.gd
# L1 类型推断器 — 三模式：T.new() / 函数返回类型 / preload

class_name GDSTypeInferrer
extends RefCounted

# p_expr: 变量 initializer 表达式 AST（CallNode / PreloadNode / null）
# p_return_table: {func_name: return_type_string} 预建返回类型表
# 返回类型名字符串，推不出返回 ""
static func infer(p_expr, p_return_table: Dictionary) -> String:
	if p_expr == null:
		return ""

	# 模式 1: T.new() → "T"
	if p_expr is GDScriptToken.CallNode:
		var callee = p_expr.callee
		if callee is GDScriptToken.AttributeNode and callee.name == "new":
			if callee.base is GDScriptToken.IdentifierNode:
				return callee.base.name

	# 模式 2: func() → 查返回类型表
	if p_expr is GDScriptToken.CallNode and p_expr.callee is GDScriptToken.IdentifierNode:
		var fn_name = p_expr.callee.name
		if p_return_table.has(fn_name):
			return p_return_table[fn_name]

	# 模式 3: preload("res://a.gd") → 脚本路径
	if p_expr is GDScriptToken.PreloadNode:
		return p_expr.path

	return ""
