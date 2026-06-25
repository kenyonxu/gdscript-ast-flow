# tests/test_gds_parser_syntax.gd
# 语法增强验收测试 — 表达式后缀、词法覆盖、错误恢复
# 对应 plan: 2026-06-25-gds-parser-syntax-enhancements.md

extends Node

var _test_count: int = 0
var _pass_count: int = 0

func _ready():
	print("\n=== GDScript Parser Syntax Enhancement Tests ===\n")
	run_all()
	print("\n=== %d / %d tests passed ===\n" % [_pass_count, _test_count])
	if _pass_count < _test_count:
		print("SOME TESTS FAILED!")
	else:
		print("ALL TESTS PASSED!")

func _assert(p_condition: bool, p_msg: String):
	_test_count += 1
	if p_condition:
		_pass_count += 1
		print("  PASS: %s" % p_msg)
	else:
		print("  FAIL: %s" % p_msg)

func parse(p_source: String) -> GDScriptToken.ClassNode:
	var tokenizer = GDScriptTokenizer.new()
	var tokens = tokenizer.tokenize(p_source)
	var parser = GDScriptParser.new()
	var ast = parser.parse(tokens)
	_assert(parser.error == "", "解析无错误")
	return ast

func parse_silent(p_source: String) -> Array:
	# 返回 [ast, parser]，用于预期有错误的场景
	var tokenizer = GDScriptTokenizer.new()
	var tokens = tokenizer.tokenize(p_source)
	var parser = GDScriptParser.new()
	var ast = parser.parse(tokens)
	return [ast, parser]

func run_all():
	# ---- Chunk A: 错误恢复 ----
	test_no_dead_loop()

	# ---- Chunk B: 表达式后缀 ----
	test_method_call_condition()
	test_member_chain()
	test_index()

	# ---- Chunk C: 词法/语法覆盖 ----
	test_scene_unique_node()
	test_semicolon()
	test_extends_string()

	# ---- 集成 ----
	test_combined_expression()

# =============================================
# A1: 错误恢复 — 死循环兜底
# =============================================
func test_no_dead_loop():
	print("\n--- Test: 错误恢复不死循环 (A1) ---")
	var fixture = _load_fixture("res://tests/fixtures/syntax/dead_loop.gd")
	var start_time = Time.get_ticks_msec()
	var result = parse_silent(fixture)
	var elapsed = Time.get_ticks_msec() - start_time
	# 核心断言: 在 5s 内返回（不死循环）
	_assert(elapsed < 5000, "解析在 5 秒内返回（耗时 %d ms）" % elapsed)
	# 即使有错误也应返回完整 AST
	_assert(result[0] != null, "返回了 AST（即使有错误）")
	print("  耗时: %d ms" % elapsed)

# =============================================
# B1: 方法调用条件
# =============================================
func test_method_call_condition():
	print("\n--- Test: if/elif 条件含方法调用 (B1) ---")
	var source = """
extends Node
func test(p_path: String):
	if p_path.ends_with(".gd"):
		pass
	elif p_path.ends_with(".tscn"):
		pass
"""
	var ast = parse(source)
	var f = ast.members[0]
	var if_node = f.body.statements[0]
	_assert(if_node is GDScriptToken.IfNode, "if 解析为 IfNode")
	_assert(if_node.condition != null, "if 条件非空")
	# 条件应该是 CallNode(callee=AttributeNode(base=IdentifierNode("p_path"), name="ends_with"))
	_assert(if_node.condition is GDScriptToken.CallNode, "条件为 CallNode（方法调用）")
	var call = if_node.condition
	_assert(call.callee is GDScriptToken.AttributeNode, "调用目标为 AttributeNode（成员访问）")
	_assert(call.callee.name == "ends_with", "成员名为 'ends_with'，got '%s'" % call.callee.name)
	_assert(call.callee.base is GDScriptToken.IdentifierNode, "基对象为 IdentifierNode")
	_assert(call.callee.base.name == "p_path", "基对象名为 'p_path'，got '%s'" % call.callee.base.name)
	_assert(call.arguments.size() == 1, "1 个参数，got %d" % call.arguments.size())
	_assert(call.arguments[0] is GDScriptToken.LiteralNode, "参数为字面量")
	_assert(call.arguments[0].value == ".gd", "参数值为 '.gd'，got '%s'" % str(call.arguments[0].value))
	# 验证 elif
	_assert(if_node.false_branch != null, "有 elif/else 分支")
	_assert(if_node.false_branch is GDScriptToken.IfNode, "elif 分支为 IfNode")
	var elif_node = if_node.false_branch
	_assert(elif_node.condition != null, "elif 条件非空")
	_assert(elif_node.condition is GDScriptToken.CallNode, "elif 条件为 CallNode")
	print("  PASS ALL")

# =============================================
# B1: 成员链 a.b.c
# =============================================
func test_member_chain():
	print("\n--- Test: 成员链 a.b.c (B1) ---")
	var source = """
extends Node
func test():
	var x = a.b.c
"""
	var ast = parse(source)
	var f = ast.members[0]
	var v = f.body.statements[0]
	_assert(v is GDScriptToken.VariableNode, "变量声明")
	var init = v.initializer
	_assert(init != null, "有初始化值")
	_assert(init is GDScriptToken.AttributeNode, "初始值为 AttributeNode（a.b.c）")
	var attr_c = init
	_assert(attr_c.name == "c", "最外层成员名为 'c'，got '%s'" % attr_c.name)
	_assert(attr_c.base is GDScriptToken.AttributeNode, "c.base 为 AttributeNode（a.b）")
	var attr_b = attr_c.base
	_assert(attr_b.name == "b", "中间成员名为 'b'，got '%s'" % attr_b.name)
	_assert(attr_b.base is GDScriptToken.IdentifierNode, "b.base 为 IdentifierNode（a）")
	_assert(attr_b.base.name == "a", "基对象名为 'a'，got '%s'" % attr_b.base.name)
	print("  PASS ALL")

# =============================================
# B1: 索引 a[0], a[i]
# =============================================
func test_index():
	print("\n--- Test: 索引 a[0] / a[i] (B1) ---")
	var source = """
extends Node
func test():
	var x = items[0]
	var y = items[index]
"""
	var ast = parse(source)
	var f = ast.members[0]
	# 第一个变量: items[0]
	var v1 = f.body.statements[0]
	_assert(v1 is GDScriptToken.VariableNode, "第一个变量声明")
	_assert(v1.initializer is GDScriptToken.SubscriptNode, "初始值为 SubscriptNode（索引访问）")
	var sub1 = v1.initializer
	_assert(sub1.base is GDScriptToken.IdentifierNode, "基对象为 IdentifierNode")
	_assert(sub1.base.name == "items", "基对象名为 'items'，got '%s'" % sub1.base.name)
	_assert(sub1.index is GDScriptToken.LiteralNode, "索引为字面量")
	_assert(sub1.index.value == 0, "索引值为 0")
	# 第二个变量: items[index]
	var v2 = f.body.statements[1]
	_assert(v2 is GDScriptToken.VariableNode, "第二个变量声明")
	_assert(v2.initializer is GDScriptToken.SubscriptNode, "第二个初始值为 SubscriptNode")
	var sub2 = v2.initializer
	_assert(sub2.index is GDScriptToken.IdentifierNode, "第二个索引为 IdentifierNode")
	_assert(sub2.index.name == "index", "索引变量名为 'index'，got '%s'" % sub2.index.name)
	print("  PASS ALL")

# =============================================
# C1: %NodeName 场景唯一节点
# =============================================
func test_scene_unique_node():
	print("\n--- Test: %%NodeName 场景唯一节点 (C1) ---")
	var source = """
extends Node
func test():
	var hp = %HealthBar.value
"""
	var ast = parse(source)
	var f = ast.members[0]
	var v = f.body.statements[0]
	_assert(v is GDScriptToken.VariableNode, "变量声明")
	var init = v.initializer
	_assert(init != null, "有初始化值")
	# %HealthBar.value → AttributeNode(base=SceneUniqueNode("HealthBar"), name="value")
	_assert(init is GDScriptToken.AttributeNode, "初始值为 AttributeNode（成员访问）")
	var attr = init
	_assert(attr.name == "value", "成员名为 'value'，got '%s'" % attr.name)
	_assert(attr.base is GDScriptToken.SceneUniqueNode, "基对象为 SceneUniqueNode")
	_assert(attr.base.name == "HealthBar", "场景唯一节点名为 'HealthBar'，got '%s'" % attr.base.name)
	print("  PASS ALL")

# =============================================
# C2: ; 分号语句分隔
# =============================================
func test_semicolon():
	print("\n--- Test: ; 分号语句分隔 (C2) ---")
	var source = """
extends Node
func test():
	var a = 1; var b = 2
	var c = 3
"""
	var ast = parse(source)
	var f = ast.members[0]
	_assert(f.body.statements.size() >= 2, "函数体至少有 2 个语句，got %d" % f.body.statements.size())
	var v1 = f.body.statements[0]
	var v2 = f.body.statements[1]
	_assert(v1 is GDScriptToken.VariableNode, "第一个语句为变量声明")
	_assert(v1.name == "a", "第一个变量名为 'a'，got '%s'" % v1.name)
	_assert(v2 is GDScriptToken.VariableNode, "第二个语句为变量声明")
	_assert(v2.name == "b", "第二个变量名为 'b'，got '%s'" % v2.name)
	# 分号后空语句：;; → 不报错
	var source2 = """
extends Node
func test():
	;;
	var x = 1
"""
	var ast2 = parse(source2)
	_assert(ast2.members.size() > 0, "空分号也能解析")
	print("  PASS ALL")

# =============================================
# C3: extends "res://path" 字符串路径
# =============================================
func test_extends_string():
	print("\n--- Test: extends 字符串路径 (C3) ---")
	var source = 'extends "res://tests/fixtures/syntax/base_class.gd"\n'
	var ast = parse(source)
	_assert(ast.extends_path != "", "extends_path 非空")
	_assert(ast.extends_path == "res://tests/fixtures/syntax/base_class.gd",
		"extends_path 正确，got '%s'" % ast.extends_path)
	# extends_id 应为空（字符串路径时不填充 extends_id）
	_assert(ast.extends_id == "", "extends_id 为空")
	print("  PASS ALL")

# =============================================
# 集成测试：结合多种表达式
# =============================================
func test_combined_expression():
	print("\n--- Test: 综合表达式 (B1+C1) ---")
	var source = """
extends Node
func test():
	%Root.get_node("Child").visible = true
"""
	var ast = parse(source)
	var f = ast.members[0]
	var stmt = f.body.statements[0]
	_assert(stmt is GDScriptToken.ExpressionStatementNode, "表达式语句")
	# 整句是赋值: %Root.get_node("Child").visible = true
	var assign = stmt.expression
	_assert(assign is GDScriptToken.AssignmentNode, "赋值语句")
	# 赋值目标: %Root.get_node("Child").visible
	var target = assign.target
	_assert(target is GDScriptToken.AttributeNode, "赋值目标为 AttributeNode（.visible）")
	_assert(target.name == "visible", "成员名为 'visible'")
	# target.base: %Root.get_node("Child") — CallNode
	_assert(target.base is GDScriptToken.CallNode, "base 为 CallNode（get_node 调用）")
	var call = target.base
	_assert(call.callee is GDScriptToken.AttributeNode, "调用目标为 AttributeNode（.get_node）")
	_assert(call.callee.name == "get_node", "方法名为 'get_node'")
	_assert(call.callee.base is GDScriptToken.SceneUniqueNode, "基对象为 SceneUniqueNode（%%Root）")
	_assert(call.callee.base.name == "Root", "场景节点名为 'Root'")
	_assert(assign.value is GDScriptToken.LiteralNode, "赋值值为字面量")
	_assert(assign.value.value == true, "值为 true")
	print("  PASS ALL")

# ---- 工具 ----
func _load_fixture(p_path: String) -> String:
	var f = FileAccess.open(p_path, FileAccess.READ)
	if f == null:
		print("  WARN: 无法读取 fixture: %s" % p_path)
		return ""
	var content = f.get_as_text()
	f.close()
	return content
