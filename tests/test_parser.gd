# tests/test_parser.gd
# Phase 1 验收测试 — 10 个测试用例验证解析管道正确性

extends Node

func _ready():
	print("=== GDScript Parser Phase 1 Acceptance Tests ===\n")
	run_all_tests()

func run_all_tests():
	test_1_empty_class()
	test_2_var_declaration()
	test_3_function_basic()
	test_4_signal_declaration()
	test_5_if_else()
	test_6_export_var()
	test_7_for_loop()
	test_8_match_basic()
	test_9_lambda()
	test_10_await()
	print("\n=== All tests completed ===")

func parse(p_source: String) -> GDScriptToken.ClassNode:
	var tokenizer = GDScriptTokenizer.new()
	var tokens = tokenizer.tokenize(p_source)
	var parser = GDScriptParser.new()
	var ast = parser.parse(tokens)
	assert(parser.error == "", "Parse error: %s" % parser.error)
	return ast

# Test 1: extends Node\nclass_name Player
func test_1_empty_class():
	print("Test 1: empty class with extends and class_name...")
	var source = "extends Node\nclass_name Player\n"
	var ast = parse(source)
	assert(ast.extends_id == "Node", "Expected extends 'Node', got '%s'" % ast.extends_id)
	assert(ast.classname_id == "Player", "Expected class_name 'Player', got '%s'" % ast.classname_id)
	print("  PASS")

# Test 2: var hp := 100
func test_2_var_declaration():
	print("Test 2: var declaration...")
	var source = "var hp := 100\n"
	var ast = parse(source)
	assert(ast.members.size() > 0, "Expected variable member")
	var v = ast.members[0]
	assert(v is GDScriptToken.VariableNode, "Expected VariableNode, got %s" % v.get_class())
	assert(v.name == "hp", "Expected name 'hp', got '%s'" % v.name)
	assert(v.initializer is GDScriptToken.LiteralNode, "Expected LiteralNode initializer")
	assert(v.initializer.value == 100, "Expected value 100, got %s" % v.initializer.value)
	print("  PASS")

# Test 3: func take_damage(amount: int) -> void:\n\tpass
func test_3_function_basic():
	print("Test 3: function with param and return type...")
	var source = "func take_damage(amount: int) -> void:\n\tpass\n"
	var ast = parse(source)
	assert(ast.members.size() > 0, "Expected function member")
	var f = ast.members[0]
	assert(f is GDScriptToken.FunctionNode, "Expected FunctionNode, got %s" % f.get_class())
	assert(f.name == "take_damage", "Expected 'take_damage', got '%s'" % f.name)
	assert(f.params.size() == 1, "Expected 1 param, got %d" % f.params.size())
	assert(f.params[0].name == "amount", "Expected param 'amount'")
	assert(f.params[0].datatype != null, "Expected type annotation on param")
	assert(f.params[0].datatype.type_name == "int", "Expected type 'int'")
	assert(f.return_type != null, "Expected return type annotation")
	print("  PASS")

# Test 4: signal health_changed(old, new)
func test_4_signal_declaration():
	print("Test 4: signal declaration...")
	var source = "signal health_changed(old, new)\n"
	var ast = parse(source)
	var s = ast.members[0]
	assert(s is GDScriptToken.SignalNode, "Expected SignalNode")
	assert(s.name == "health_changed", "Expected 'health_changed', got '%s'" % s.name)
	assert(s.params.size() == 2, "Expected 2 params, got %d" % s.params.size())
	print("  PASS")

# Test 5: if hp <= 0:\n\temit("died")\nelse:\n\tpass
func test_5_if_else():
	print("Test 5: if/else with comparison...")
	var source = "func check():\n\tif hp <= 0:\n\t\tpass\n\telse:\n\t\tpass\n"
	var ast = parse(source)
	var f = ast.members[0]
	assert(f.body.statements.size() > 0, "Expected statements in function body")
	var if_node = f.body.statements[0]
	assert(if_node is GDScriptToken.IfNode, "Expected IfNode, got %s" % if_node.get_class())
	assert(if_node.condition is GDScriptToken.BinaryOpNode, "Expected BinaryOpNode condition")
	assert(if_node.false_branch != null, "Expected else branch")
	print("  PASS")

# Test 6: @export var speed: float = 10.0
func test_6_export_var():
	print("Test 6: @export variable...")
	# @export 是成员注解, 在 _parse_class_member 中被消费
	# 文件级注解仅 @tool/@icon 由 parse() 消费
	var source = "@export var speed: float = 10.0\n"
	var ast = parse(source)
	assert(ast.members.size() > 0, "Expected member")
	var v = ast.members[0]
	assert(v is GDScriptToken.VariableNode, "Expected VariableNode")
	assert(v.is_export, "Expected is_export=true, got false")
	assert(v.name == "speed", "Expected name 'speed'")
	assert(v.datatype != null, "Expected type annotation")
	assert(v.datatype.type_name == "float", "Expected type 'float'")
	print("  PASS")

# Test 7: for i in range(10):\n\tprint(i)
func test_7_for_loop():
	print("Test 7: for loop...")
	var source = "func f():\n\tfor i in range(10):\n\t\tpass\n"
	var ast = parse(source)
	var f_node = ast.members[0]
	var for_node = f_node.body.statements[0]
	assert(for_node is GDScriptToken.ForNode, "Expected ForNode")
	assert(for_node.var_name == "i", "Expected var 'i'")
	assert(for_node.iterable is GDScriptToken.CallNode, "Expected CallNode as iterable")
	print("  PASS")

# Test 8: match x:\n\twhen 1, 2:\n\t\tpass
func test_8_match_basic():
	print("Test 8: match/when...")
	var source = "func f(x):\n\tmatch x:\n\t\twhen 1, 2:\n\t\t\tpass\n"
	var ast = parse(source)
	var f_node = ast.members[0]
	var match_node = f_node.body.statements[0]
	assert(match_node is GDScriptToken.MatchNode, "Expected MatchNode")
	assert(match_node.branches.size() == 1, "Expected 1 branch")
	assert(match_node.branches[0].patterns.size() == 2, "Expected 2 patterns")
	print("  PASS")

# Test 9: var callback = func(): return 42
func test_9_lambda():
	print("Test 9: lambda expression...")
	var source = "var callback = func(): return 42\n"
	var ast = parse(source)
	var v = ast.members[0]
	assert(v.initializer is GDScriptToken.LambdaNode, "Expected LambdaNode")
	var lam = v.initializer
	# spec: lambda 体直接存储返回值表达式 (单行 return 被解包)
	assert(lam.body is GDScriptToken.LiteralNode, "Expected LiteralNode as lambda body, got %s" % lam.body.get_class())
	assert(lam.body.value == 42, "Expected value 42, got %s" % lam.body.value)
	print("  PASS")

# Test 10: await get_tree().process_frame
func test_10_await():
	print("Test 10: await expression...")
	var source = "func f():\n\tawait get_tree().process_frame\n"
	var ast = parse(source)
	var f_node = ast.members[0]
	var await_node = f_node.body.statements[0]
	assert(await_node is GDScriptToken.AwaitNode, "Expected AwaitNode, got %s" % await_node.get_class())
	assert(await_node.expression is GDScriptToken.AttributeNode, "Expected AttributeNode as await target (get_tree().process_frame)")
	print("  PASS")
