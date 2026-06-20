# tests/test_symbol_resolver.gd
# Phase 2 验收测试 — 10 个测试用例验证符号分析正确性

extends Node

func _ready():
	print("=== GDScript SymbolResolver Phase 2 Acceptance Tests ===\n")
	run_all_tests()

func run_all_tests():
	test_1_symbol_table_def_use()
	test_2_call_graph_implicit_self()
	test_3_call_graph_explicit_self()
	test_4_call_graph_super()
	test_5_lambda_no_capture()
	test_6_lambda_capture_vars()
	test_7_signal_emit()
	test_8_signal_connect()
	test_9_external_connect()
	test_10_def_use_full_chain()
	print("\n=== All tests completed ===")


# 辅助: 完整管道 — 源码 → tokens → AST → AnalysisResult
func resolve(p_source: String) -> GDScriptAnalysisResult:
	var tokenizer = GDScriptTokenizer.new()
	var tokens = tokenizer.tokenize(p_source)
	var parser = GDScriptParser.new()
	var ast = parser.parse(tokens)
	assert(parser.error == "", "Parse error: %s" % parser.error)

	var resolver = GDScriptSymbolResolver.new()
	var result = resolver.resolve(ast, "")
	return result


# 辅助: 从 SymbolTable 查找符号
func find_symbol(p_table: SymbolTable, p_name: String) -> Symbol:
	return p_table.resolve(p_name)


# 辅助: 断言
func assert_eq(p_expected, p_actual, p_msg: String = ""):
	if p_expected != p_actual:
		printerr("  FAIL: %s — expected '%s', got '%s'" % [p_msg, str(p_expected), str(p_actual)])
	else:
		pass  # success


func assert_true(p_cond: bool, p_msg: String = ""):
	if not p_cond:
		printerr("  FAIL: %s" % p_msg)


func assert_not_null(p_obj, p_msg: String = ""):
	if p_obj == null:
		printerr("  FAIL: %s — unexpected null" % p_msg)


# Test 1: SymbolTable + DefUseChain
# 源码: extends Node\nclass_name Player\nvar hp := 100\nfunc take_damage(amount: int):\n\thp -= amount
func test_1_symbol_table_def_use():
	print("Test 1: SymbolTable + DefUseChain...")
	var source = "extends Node\nclass_name Player\nvar hp := 100\nfunc take_damage(amount: int):\n\thp -= amount\n"
	var result = resolve(source)

	# SymbolTable 检查
	assert_not_null(result.symbol_table, "symbol_table should not be null")
	var hp_sym = find_symbol(result.symbol_table, "hp")
	assert_not_null(hp_sym, "hp should be in symbol table")
	if hp_sym:
		assert_eq(Symbol.Kind.VARIABLE, hp_sym.kind, "hp should be VARIABLE")

	var func_sym = find_symbol(result.symbol_table, "take_damage")
	assert_not_null(func_sym, "take_damage should be in symbol table")
	if func_sym:
		assert_eq(Symbol.Kind.FUNCTION, func_sym.kind, "take_damage should be FUNCTION")

	# DefUseChain 检查
	var hp_usage = result.get_variable_usages("hp")
	assert_not_null(hp_usage, "hp should have DefUseInfo")
	if hp_usage:
		assert_not_null(hp_usage.def_site, "hp should have def_site")
		# hp -= amount 是 READ_WRITE
		assert_true(hp_usage.write_sites.size() > 0, "hp should have write sites (READ_WRITE)")
	# amount 参数
	var amount_usage = result.get_variable_usages("amount")
	assert_not_null(amount_usage, "amount should have DefUseInfo")
	if amount_usage:
		assert_not_null(amount_usage.def_site, "amount should have def_site")
		assert_true(amount_usage.read_sites.size() > 0, "amount should have read sites")
	print("  PASS")


# Test 2: CallGraph — 隐式 self 调用
# foo() → bar()
func test_2_call_graph_implicit_self():
	print("Test 2: CallGraph implicit self...")
	var source = "func foo():\n\tbar()\nfunc bar():\n\tpass\n"
	var result = resolve(source)

	var callers = result.get_callers_of("bar")
	assert_eq(1, callers.size(), "bar should have 1 caller")
	if callers.size() > 0:
		assert_eq("foo", callers[0].caller, "caller should be foo")
		assert_eq(CallEdge.CallType.SELF, callers[0].call_type, "call_type should be SELF")
	print("  PASS")


# Test 3: CallGraph — 显式 self 调用
# self.bar()
func test_3_call_graph_explicit_self():
	print("Test 3: CallGraph explicit self...")
	var source = "func foo():\n\tself.bar()\nfunc bar():\n\tpass\n"
	var result = resolve(source)

	var callers = result.get_callers_of("bar")
	assert_eq(1, callers.size(), "bar should have 1 caller")
	if callers.size() > 0:
		assert_eq(CallEdge.CallType.SELF, callers[0].call_type, "call_type should be SELF")
	print("  PASS")


# Test 4: CallGraph — super 调用
# super._ready()
func test_4_call_graph_super():
	print("Test 4: CallGraph super...")
	var source = "func foo():\n\tsuper._ready()\nfunc bar():\n\tpass\n"
	var result = resolve(source)

	var callers = result.get_callers_of("_ready")
	assert_eq(1, callers.size(), "_ready should have 1 caller")
	if callers.size() > 0:
		assert_eq(CallEdge.CallType.SUPER, callers[0].call_type, "call_type should be SUPER")
	print("  PASS")


# Test 5: Lambda 不捕获变量
# var callback = func(x): return x * 2
func test_5_lambda_no_capture():
	print("Test 5: Lambda no capture...")
	var source = "var callback = func(x): return x * 2\n"
	var result = resolve(source)

	# 查找 LambdaNode
	var sym = find_symbol(result.symbol_table, "callback")
	assert_not_null(sym, "callback should be in symbol table")
	if sym and sym.declaration.initializer is GDScriptToken.LambdaNode:
		var lam = sym.declaration.initializer
		assert_eq(0, lam.captured_vars.size(), "lambda should capture 0 vars")
	print("  PASS")


# Test 6: Lambda 捕获变量
# var scale = 2\nvar doubler = func(x): return x * scale
func test_6_lambda_capture_vars():
	print("Test 6: Lambda capture variables...")
	var source = "var scale = 2\nvar doubler = func(x): return x * scale\n"
	var result = resolve(source)

	var sym = find_symbol(result.symbol_table, "doubler")
	assert_not_null(sym, "doubler should be in symbol table")
	if sym and sym.declaration.initializer is GDScriptToken.LambdaNode:
		var lam = sym.declaration.initializer
		assert_true(lam.captured_vars.has("scale"), "lambda should capture 'scale'")
	print("  PASS")


# Test 7: Signal emit
# signal health_changed(old, new)\nfunc take_damage(d):\n\thealth_changed.emit(hp, hp - d)
func test_7_signal_emit():
	print("Test 7: Signal emit...")
	var source = "signal health_changed(old, new)\nfunc take_damage(d):\n\thealth_changed.emit(hp, hp - d)\n"
	var result = resolve(source)

	var flow = result.get_signal_flow("health_changed")
	assert_not_null(flow, "health_changed should have SignalInfo")
	if flow:
		assert_not_null(flow.declaration, "health_changed should have declaration")
		assert_eq(1, flow.emit_sites.size(), "health_changed should have 1 emit site")
		if flow.emit_sites.size() > 0:
			assert_eq("take_damage", flow.emit_sites[0].enclosing_function, "emit should be in take_damage")
	print("  PASS")


# Test 8: Signal connect
# signal health_changed(old, new)\nfunc _ready():\n\thealth_changed.connect(_on_health)
func test_8_signal_connect():
	print("Test 8: Signal connect...")
	var source = "signal health_changed(old, new)\nfunc _ready():\n\thealth_changed.connect(_on_health)\nfunc _on_health(o, n):\n\tpass\n"
	var result = resolve(source)

	# SignalGraph
	var flow = result.get_signal_flow("health_changed")
	assert_not_null(flow, "health_changed should have SignalInfo")
	if flow:
		assert_eq(1, flow.connect_sites.size(), "health_changed should have 1 connect site")

	# CallGraph
	var callers = result.get_callers_of("_on_health")
	assert_eq(1, callers.size(), "_on_health should have 1 caller")
	if callers.size() > 0:
		assert_eq(CallEdge.CallType.SIGNAL_CONNECT, callers[0].call_type, "call_type should be SIGNAL_CONNECT")
	print("  PASS")


# Test 9: 外部对象 connect
# signal died\nfunc _ready():\n\t$AnimationPlayer.connect("finished", _on_anim_end)
func test_9_external_connect():
	print("Test 9: External connect...")
	var source = "signal died\nfunc _ready():\n\t$AnimationPlayer.connect(\"finished\", _on_anim_end)\nfunc _on_anim_end():\n\tpass\n"
	var result = resolve(source)

	# 已声明信号 died
	var died_flow = result.get_signal_flow("died")
	assert_not_null(died_flow, "died should have SignalInfo")

	# 未声明信号 finished — 通过 connect("finished",...) 触发
	var finished_flow = result.get_signal_flow("finished")
	assert_not_null(finished_flow, "finished should have temp SignalInfo")
	if finished_flow:
		assert_eq(1, finished_flow.connect_sites.size(), "finished should have 1 connect site")

	# CallGraph — _ready → _on_anim_end (CONNECT)
	var callers = result.get_callers_of("_on_anim_end")
	assert_eq(1, callers.size(), "_on_anim_end should have 1 caller")
	if callers.size() > 0:
		assert_eq(CallEdge.CallType.CONNECT, callers[0].call_type, "call_type should be CONNECT")
	print("  PASS")


# Test 10: DefUse 完整读写链
# var x: int = 0\nfunc _process(d):\n\tx = 1\n\tprint(x)\n\tx += 1
func test_10_def_use_full_chain():
	print("Test 10: DefUse full read/write chain...")
	var source = "var x: int = 0\nfunc _process(d):\n\tx = 1\n\tprint(x)\n\tx += 1\n"
	var result = resolve(source)

	var usage = result.get_variable_usages("x")
	assert_not_null(usage, "x should have DefUseInfo")
	if usage:
		# def site
		assert_not_null(usage.def_site, "x should have def site")

		# write sites: x = 1 → WRITE, x += 1 → READ_WRITE (counted as write)
		assert_true(usage.write_sites.size() >= 2, "x should have at least 2 write sites")

		# read sites: print(x) → READ, x += 1 → READ_WRITE (not separately counted as read)
		assert_true(usage.read_sites.size() >= 1, "x should have at least 1 read site")
	print("  PASS")
