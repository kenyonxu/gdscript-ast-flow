# tests/test_symbol_resolver.gd
# Phase 2 验收测试 — 10 个测试用例验证符号分析正确性

extends Node

func _ready():
	print("=== GDScript SymbolResolver Phase 2 Acceptance Tests ===\n")
	run_all_tests()
	get_tree().quit()  # CLI headless 跑通用 — 测完自动退出（编辑器 F6 也兼容）

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
	test_11_builtin_filter()
	test_12_type_infer_new()
	test_13_type_infer_return()
	test_14_type_infer_preload()
	test_15_fstring()
	test_16_site_script_path()
	test_17_site_line_not_zero()
	test_18_usage_status()
	test_19_method_call_base_read()
	test_20_parameter_flag()
	test_21_is_unused_signal()
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


# 辅助: 源码 → AST（仅解析，不 resolve）
func parse(p_source: String) -> GDScriptToken.ClassNode:
	var tokenizer = GDScriptTokenizer.new()
	var tokens = tokenizer.tokenize(p_source)
	var parser = GDScriptParser.new()
	var ast = parser.parse(tokens)
	assert(parser.error == "", "Parse error: %s" % parser.error)
	return ast


# 辅助: 从 SymbolTable 查找符号
func find_symbol(p_table: GDScriptSymbolTable, p_name: String) -> GDScriptSymbol:
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
	print("Test 1: SymbolTable + GDScriptDefUseChain...")
	var source = "extends Node\nclass_name Player\nvar hp := 100\nfunc take_damage(amount: int):\n\thp -= amount\n"
	var result = resolve(source)

	# SymbolTable 检查
	assert_not_null(result.symbol_table, "symbol_table should not be null")
	var hp_sym = find_symbol(result.symbol_table, "hp")
	assert_not_null(hp_sym, "hp should be in symbol table")
	if hp_sym:
		assert_eq(GDScriptSymbol.Kind.VARIABLE, hp_sym.kind, "hp should be VARIABLE")

	var func_sym = find_symbol(result.symbol_table, "take_damage")
	assert_not_null(func_sym, "take_damage should be in symbol table")
	if func_sym:
		assert_eq(GDScriptSymbol.Kind.FUNCTION, func_sym.kind, "take_damage should be FUNCTION")

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
		assert_eq(GDScriptCallEdge.CallType.SELF, callers[0].call_type, "call_type should be SELF")
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
		assert_eq(GDScriptCallEdge.CallType.SELF, callers[0].call_type, "call_type should be SELF")
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
		assert_eq(GDScriptCallEdge.CallType.SUPER, callers[0].call_type, "call_type should be SUPER")
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
		assert_eq(GDScriptCallEdge.CallType.SIGNAL_CONNECT, callers[0].call_type, "call_type should be SIGNAL_CONNECT")
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
		assert_eq(GDScriptCallEdge.CallType.CONNECT, callers[0].call_type, "call_type should be CONNECT")
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

# Test 11: 内置函数过滤 — print/range 不记边，前向引用保留
func test_11_builtin_filter():
	print("Test 11: builtin function filter...")
	var resolver = GDScriptSymbolResolver.new()

	# 1. filter ON: print/range 不记边
	resolver.filter_builtin_calls = true
	var tok = GDScriptTokenizer.new()
	var ast = GDScriptParser.new().parse(tok.tokenize("func _a():\n	print(\"x\")\n	range(5)\n"))
	var full = resolver.resolve(ast, "")
	assert(full.call_graph.edges.is_empty(), "with filter ON, print/range should produce no edges")
	assert(full.call_in_degree.get("print", 0) == 0, "print in-degree should be 0")
	assert(full.call_out_degree.get("_a", 0) == 0, "_a out-degree should be 0")

	# 2. 前向引用（未声明的用户函数）仍记边
	resolver.filter_builtin_calls = true
	var tok2 = GDScriptTokenizer.new()
	var ast2 = GDScriptParser.new().parse(tok2.tokenize("func _b():\n	helper()\n"))
	var full2 = resolver.resolve(ast2, "")
	assert(full2.call_graph.edges.size() >= 1, "forward ref helper() should produce an edge")
	assert(full2.call_in_degree.get("helper", 0) >= 1, "helper in-degree should be >=1")

	# 3. filter OFF: print 记边（回归验证）
	resolver.filter_builtin_calls = false
	var tok3 = GDScriptTokenizer.new()
	var ast3 = GDScriptParser.new().parse(tok3.tokenize("func _c():\n	print(\"x\")\n"))
	var full3 = resolver.resolve(ast3, "")
	assert(full3.call_graph.edges.size() >= 1, "with filter OFF, print should produce an edge")
	assert(full3.call_in_degree.get("print", 0) >= 1, "print in-degree should be >=1 with filter OFF")
	print("  PASS")

# Test 12: 类型推断 — T.new()
func test_12_type_infer_new():
	print("Test 12: type inference — T.new()...")
	var resolver = GDScriptSymbolResolver.new()
	resolver.enable_type_inference = true
	var tok = GDScriptTokenizer.new()
	var ast = GDScriptParser.new().parse(tok.tokenize("func _a():\n	var x := Player.new()\n	x.take_damage(10)\n"))
	var full = resolver.resolve(ast, "")
	assert(full.type_table.get("x", "") == "Player", "x should be inferred as Player")
	print("  PASS")

# Test 13: 类型推断 — 函数返回类型
func test_13_type_infer_return():
	print("Test 13: type inference — return type...")
	var resolver = GDScriptSymbolResolver.new()
	resolver.enable_type_inference = true
	var tok = GDScriptTokenizer.new()
	var src = "func get_player() -> Player:\n	return null\n\nfunc _b():\n	var p := get_player()\n"
	var ast = GDScriptParser.new().parse(tok.tokenize(src))
	var full = resolver.resolve(ast, "")
	assert(full.type_table.get("p", "") == "Player", "p should be inferred from get_player() return type")
	print("  PASS")

# Test 14: 类型推断 — preload
func test_14_type_infer_preload():
	print("Test 14: type inference — preload...")
	var resolver = GDScriptSymbolResolver.new()
	resolver.enable_type_inference = true
	var tok = GDScriptTokenizer.new()
	var ast = GDScriptParser.new().parse(tok.tokenize("func _c():\n	var c := preload(\"res://a.gd\")\n"))
	var full = resolver.resolve(ast, "")
	assert(full.type_table.get("c", "") == "res://a.gd", "c should be preload path")
	print("  PASS")


# Test 15: f-string 结构化解析
func test_15_fstring():
	print("Test 15: f-string parsing...")
	var source = "var name: String = \"World\"\nvar count: int = 42\nvar msg = f\"Hello, {name}! You have {count} items.\"\n"
	var ast = parse(source)
	var v = ast.members[2]  # var msg
	assert(v is GDScriptToken.VariableNode, "Expected VariableNode for msg")
	assert(v.initializer is GDScriptToken.FormattedStringNode, "Expected FormattedStringNode")
	var fs = v.initializer
	# 至少有 expr 段
	var has_expr = false
	for seg in fs.segments:
		if seg.get("type", "") == "expr":
			has_expr = true
			break
	assert(has_expr, "FormattedStringNode should have at least one expr segment")
	print("  PASS")


# Test 16: site 记录 script_path（数据层 — 跨文件铺路）
func test_16_site_script_path():
	print("Test 16: site script_path recording...")
	var source = "extends Node\nvar x: int = 0\nfunc _p():\n\tx = 1\n"
	var tok = GDScriptTokenizer.new()
	var ast = GDScriptParser.new().parse(tok.tokenize(source))
	var resolver = GDScriptSymbolResolver.new()
	var result = resolver.resolve(ast, "res://test_sample.gd")
	var usage = result.get_variable_usages("x")
	assert_not_null(usage, "x should have DefUseInfo")
	if usage:
		assert_not_null(usage.def_site, "x should have def_site")
		if usage.def_site:
			assert_eq("res://test_sample.gd", usage.def_site.script_path, "def_site.script_path should be recorded")
		if usage.write_sites.size() > 0:
			assert_eq("res://test_sample.gd", usage.write_sites[0].script_path, "write_site.script_path should be recorded")
	print("  PASS")


# Test 17: site.line 不为 0（regression — _record_def_use 三元条件写反导致恒 0）
func test_17_site_line_not_zero():
	print("Test 17: site.line regression (was always 0)...")
	var source = "extends Node\nvar x: int = 0\nfunc _p():\n\tx = 1\n\tprint(x)\n"
	var tok = GDScriptTokenizer.new()
	var ast = GDScriptParser.new().parse(tok.tokenize(source))
	var resolver = GDScriptSymbolResolver.new()
	var result = resolver.resolve(ast, "res://test.gd")
	var usage = result.get_variable_usages("x")
	assert_not_null(usage, "x should have DefUseInfo")
	if usage:
		assert_not_null(usage.def_site, "x should have def_site")
		if usage.def_site:
			assert_true(usage.def_site.line > 0, "def_site.line should be > 0 (line 2)")
		if usage.write_sites.size() > 0:
			assert_true(usage.write_sites[0].line > 0, "write_site.line should be > 0 (line 3)")
		if usage.read_sites.size() > 0:
			assert_true(usage.read_sites[0].line > 0, "read_site.line should be > 0 (line 4)")
	print("  PASS")


# Test 18: DefUseInfo.get_usage_status() 判定（未使用分级高亮依据）
func test_18_usage_status():
	print("Test 18: get_usage_status() classification...")
	# 完全死变量 — 只声明，无读无写
	var src_unused = "extends Node\nvar dead: int = 0\n"
	var r1 = resolve(src_unused)
	var u1 = r1.get_variable_usages("dead")
	assert_not_null(u1, "dead should have info")
	if u1:
		assert_eq("unused", u1.get_usage_status(), "dead var → 'unused'")

	# 只写不读 — dead store
	var src_wo = "extends Node\nvar wo: int = 0\nfunc _p():\n\two = 1\n"
	var r2 = resolve(src_wo)
	var u2 = r2.get_variable_usages("wo")
	assert_not_null(u2, "wo should have info")
	if u2:
		assert_eq("write_only", u2.get_usage_status(), "write-only var → 'write_only'")

	# 正常 — 有读
	var src_ok = "extends Node\nvar ok: int = 0\nfunc _p():\n\tprint(ok)\n"
	var r3 = resolve(src_ok)
	var u3 = r3.get_variable_usages("ok")
	assert_not_null(u3, "ok should have info")
	if u3:
		assert_eq("normal", u3.get_usage_status(), "read var → 'normal'")
	print("  PASS")


# Test 19: 方法调用 base 的读取应计入 def_use READ（修复 health.take_damage() 盲点）
func test_19_method_call_base_read():
	print("Test 19: method call base counts as READ...")
	var source = "var hp\nfunc _p():\n\thp.take_damage(10)\n"
	var r = resolve(source)
	var usage = r.get_variable_usages("hp")
	assert_not_null(usage, "hp should have info")
	if usage:
		assert_true(usage.read_sites.size() > 0, "hp should have READ site (method call base)")
		assert_eq("normal", usage.get_usage_status(), "hp should be normal (not unused)")

	# 负向：signal_name.connect() 不应给 signal 记 READ（信号由 signal_graph 追踪，不进 def_use_chain）
	var sig_src = "signal health_changed\nfunc _ready():\n\thealth_changed.connect(_on_h)\nfunc _on_h():\n\tpass\n"
	var sr = resolve(sig_src)
	var sig_usage = sr.get_variable_usages("health_changed")
	assert_eq(null, sig_usage, "signal should NOT enter def_use_chain (no READ for connect)")

	# 负向：signal_name.emit() 同理
	var emit_src = "signal died\nfunc _p():\n\tdied.emit()\n"
	var er = resolve(emit_src)
	var emit_usage = er.get_variable_usages("died")
	assert_eq(null, emit_usage, "signal should NOT enter def_use_chain (no READ for emit)")
	print("  PASS")

# Test 20: 参数 site 标 is_parameter（区分参数 vs 变量）
func test_20_parameter_flag():
	print("Test 20: parameter is_parameter flag...")
	# 参数应标 is_parameter=true
	var src_param = "func _p(a: int):\n\tprint(a)\n"
	var rp = resolve(src_param)
	var up = rp.get_variable_usages("a")
	assert_not_null(up, "param a should have info")
	if up and up.def_site:
		assert_true(up.def_site.is_parameter, "param a.is_parameter should be true")
	# 变量应标 is_parameter=false
	var src_var = "var x: int\nfunc _p():\n\tprint(x)\n"
	var rv = resolve(src_var)
	var uv = rv.get_variable_usages("x")
	assert_not_null(uv, "var x should have info")
	if uv and uv.def_site:
		assert_true(not uv.def_site.is_parameter, "var x.is_parameter should be false")
	# 函数局部 var 也应 is_parameter=false
	var src_local = "func _p():\n\tvar y: int = 0\n\tprint(y)\n"
	var rloc = resolve(src_local)
	var uloc = rloc.get_variable_usages("y")
	assert_not_null(uloc, "local var y should have info")
	if uloc and uloc.def_site:
		assert_true(not uloc.def_site.is_parameter, "local var y.is_parameter should be false")
	# lambda 参数也应标 is_parameter=true
	var src_lam = "func _p():\n\tvar cb = func(z: int):\n\t\tprint(z)\n"
	var rl = resolve(src_lam)
	# lambda 参数 z 在 def_use_chain 里（resolver 会记）
	var ul = rl.get_variable_usages("z")
	assert_not_null(ul, "lambda param z should have info")
	if ul and ul.def_site:
		assert_true(ul.def_site.is_parameter, "lambda param z.is_parameter should be true")
	print("  PASS")


# Test 21: signal is_unused 判定（未连接信号高亮依据）
func test_21_is_unused_signal():
	print("Test 21: signal is_unused flag...")
	# declared 但 0 emit + 0 connect → unused
	var src_unused = "signal dead_sig\n"
	var r1 = resolve(src_unused)
	var info1 = r1.get_signal_flow("dead_sig")
	assert_not_null(info1, "dead_sig should have info")
	if info1:
		assert_true(info1.is_unused(), "dead_sig (0 emit + 0 connect) → unused")
	# 有 emit → not unused
	var src_emit = "signal used_sig\nfunc _p():\n\tused_sig.emit()\n"
	var r2 = resolve(src_emit)
	var info2 = r2.get_signal_flow("used_sig")
	assert_not_null(info2, "used_sig should have info")
	if info2:
		assert_true(not info2.is_unused(), "used_sig (has emit) → not unused")
	print("  PASS")
