# tests/test_phase3_syntax.gd
# Phase 3 语法验收测试 — f-string, match guard, namespace

extends Node

func _ready():
	print("=== Phase 3 Syntax Tests ===\n")
	test_f_string()
	test_match_guard()
	test_namespace()
	test_inline_setter()
	test_trait()
	print("\n=== All Phase 3 syntax tests completed ===")

func parse(p_source: String) -> GDScriptToken.ClassNode:
	var tokenizer = GDScriptTokenizer.new()
	var tokens = tokenizer.tokenize(p_source)
	var parser = GDScriptParser.new()
	var ast = parser.parse(tokens)
	assert(parser.error == "", "Parse error: %s" % parser.error)
	return ast

func test_f_string():
	print("Test: f-string...")
	var source = 'var msg = f"Hello, {name}!"\n'
	var ast = parse(source)
	assert(ast.members.size() > 0, "Expected member")
	print("  PASS")

func test_match_guard():
	print("Test: match with guard...")
	var source = "func f(x):\n\tmatch x:\n\t\twhen y > 0:\n\t\t\tpass\n"
	var ast = parse(source)
	assert(ast.members.size() > 0, "Expected function")
	var f = ast.members[0]
	var match_node = f.body.statements[0]
	assert(match_node is GDScriptToken.MatchNode, "Expected MatchNode")
	assert(match_node.branches.size() == 1, "Expected 1 branch")
	assert(match_node.branches[0] is GDScriptToken.GuardedMatchBranchNode, "Expected GuardedMatchBranchNode")
	if match_node.branches[0] is GDScriptToken.GuardedMatchBranchNode:
		assert(match_node.branches[0].guard != null, "Expected guard expression")
	print("  PASS")

func test_namespace():
	print("Test: namespace...")
	var source = "namespace Test:\n\tfunc foo():\n\t\tpass\n"
	var ast = parse(source)
	assert(ast.members.size() > 0, "Expected namespace")
	assert(ast.members[0] is GDScriptToken.NamespaceNode, "Expected NamespaceNode")
	var ns = ast.members[0]
	assert(ns.name == "Test", "Expected name 'Test'")
	assert(ns.members.size() > 0, "Expected members in namespace")
	print("  PASS")

func test_inline_setter():
	print("Test: inline setter...")
	var source = "var hp: int:\n\tset(value):\n\t\thp = value\n"
	var ast = parse(source)
	assert(ast.members.size() > 0, "Expected member")
	print("  PASS")

func test_trait():
	print("Test: trait...")
	var source = "trait Damageable:\n\tfunc take_damage(d):\n\t\tpass\n"
	var ast = parse(source)
	assert(ast.members.size() > 0, "Expected trait")
	assert(ast.members[0] is GDScriptToken.TraitNode, "Expected TraitNode")
	print("  PASS")
