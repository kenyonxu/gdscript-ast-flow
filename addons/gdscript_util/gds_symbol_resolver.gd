# addons/gdscript_util/gds_symbol_resolver.gd
# GDScript 4.7 符号解析器 — AST Visitor 模式遍历构建符号表+调用图+信号图+DefUse链
# 输入: GDScriptToken.ClassNode (Phase 1 产出)
# 输出: GDScriptAnalysisResult

class_name GDScriptSymbolResolver
extends RefCounted

var result: GDScriptAnalysisResult = null


# 入口 — Phase 1/2 阶段边界
# p_ast: GDScriptToken.ClassNode — Phase 1 产出的 AST 根
# p_file_path: String — 源文件路径（用于读取源码行和 const/var 区分）
func resolve(p_ast, p_file_path: String = "") -> GDScriptAnalysisResult:
	result = GDScriptAnalysisResult.new()
	result.ast = p_ast
	result.file_path = p_file_path
	result.call_graph = GDScriptCallGraph.new()
	result.signal_graph = GDScriptSignalGraph.new()
	result.def_use_chain = GDScriptDefUseChain.new()

	# 预加载源码行（用于 const/var 区分 — 方案 A）
	_load_source_lines(p_file_path)

	# 创建类作用域
	result.symbol_table = GDScriptSymbolTable.new()
	result.symbol_table.scope_name = "class:%s" % p_ast.classname_id if p_ast.classname_id != "" else "class:<anonymous>"

	# 填充基础信息
	result.classname_id = p_ast.classname_id
	result.extends_path = p_ast.extends_id

	# 预处理 const/var 标记
	_preprocess_const_vars(p_ast)

	# 开始 AST 遍历
	_resolve_class(p_ast, result.symbol_table)

	return result


# 加载源码行 — 用于 const/var 区分（方案 A）
func _load_source_lines(p_path: String):
	if p_path == "":
		return
	var file = FileAccess.open(p_path, FileAccess.READ)
	if file == null:
		return
	while not file.eof_reached():
		result._source_lines.append(file.get_line())


# 预处理: 区分 const 和 var 的 VariableNode
# Phase 1 的 _parse_const() 和 _parse_variable() 都返回 VariableNode
# 通过检查源码行首个非空白 token 是否为 "const" 来区分
# 结果存储在 result 内部的一个临时映射中
var _const_set: Dictionary = {}  # VariableNode → true (是 const)

func _preprocess_const_vars(p_ast):
	if result._source_lines.is_empty():
		return
	for member in p_ast.members:
		if member is GDScriptToken.VariableNode:
			var line_idx = member.line - 1
			if line_idx >= 0 and line_idx < result._source_lines.size():
				var line_text = result._source_lines[line_idx].strip_edges()
				if line_text.begins_with("const"):
					_const_set[member] = true


# 核心分发 — 按 AST 节点类型匹配
func _resolve_node(p_node, p_scope: GDScriptSymbolTable, p_current_function: String, p_lambda_node = null):
	if p_node == null:
		return

	# Godot 4.x: 内部类需要用全限定名
	if p_node is GDScriptToken.ClassNode:
		_resolve_class(p_node, p_scope)
	elif p_node is GDScriptToken.FunctionNode:
		_resolve_function(p_node, p_scope)
	elif p_node is GDScriptToken.VariableNode:
		_resolve_variable(p_node, p_scope, p_current_function)
	elif p_node is GDScriptToken.SignalNode:
		_resolve_signal(p_node, p_scope)
	elif p_node is GDScriptToken.EnumNode:
		_resolve_enum(p_node, p_scope)
	elif p_node is GDScriptToken.SuiteNode:
		_resolve_suite(p_node.body, p_scope, p_current_function, p_lambda_node)
	elif p_node is GDScriptToken.IfNode:
		_resolve_if(p_node, p_scope, p_current_function, p_lambda_node)
	elif p_node is GDScriptToken.WhileNode:
		_resolve_while(p_node, p_scope, p_current_function, p_lambda_node)
	elif p_node is GDScriptToken.ForNode:
		_resolve_for(p_node, p_scope, p_current_function, p_lambda_node)
	elif p_node is GDScriptToken.MatchNode:
		_resolve_match(p_node, p_scope, p_current_function, p_lambda_node)
	elif p_node is GDScriptToken.ReturnNode:
		_resolve_return(p_node, p_scope, p_current_function, p_lambda_node)
	elif p_node is GDScriptToken.AssignmentNode:
		_resolve_assignment(p_node, p_scope, p_current_function)
	elif p_node is GDScriptToken.CallNode:
		_resolve_call(p_node, p_scope, p_current_function)
	elif p_node is GDScriptToken.LambdaNode:
		_resolve_lambda(p_node, p_scope, p_current_function)
	elif p_node is GDScriptToken.IdentifierNode:
		_resolve_identifier_read(p_node, p_scope, p_current_function, p_lambda_node)
	elif p_node is GDScriptToken.ExpressionStatementNode:
		_resolve_expression(p_node.expression, p_scope, p_current_function, p_lambda_node)
	elif p_node is GDScriptToken.AssertNode:
		_resolve_expression(p_node.condition, p_scope, p_current_function, p_lambda_node)
		if p_node.message != null:
			_resolve_expression(p_node.message, p_scope, p_current_function, p_lambda_node)
	elif p_node is GDScriptToken.AwaitNode:
		_resolve_expression(p_node.expression, p_scope, p_current_function, p_lambda_node)
	elif p_node in [GDScriptToken.BreakNode, GDScriptToken.ContinueNode, GDScriptToken.PassNode]:
		pass  # 无表达式子节点


# 表达式递归解析 — 处理所有表达式类型中的子节点
func _resolve_expression(p_expr, p_scope: GDScriptSymbolTable, p_current_function: String, p_lambda_node = null):
	if p_expr == null:
		return

	if p_expr is GDScriptToken.BinaryOpNode:
		_resolve_expression(p_expr.left, p_scope, p_current_function, p_lambda_node)
		_resolve_expression(p_expr.right, p_scope, p_current_function, p_lambda_node)
	elif p_expr is GDScriptToken.UnaryOpNode:
		_resolve_expression(p_expr.operand, p_scope, p_current_function, p_lambda_node)
	elif p_expr is GDScriptToken.TernaryOpNode:
		_resolve_expression(p_expr.condition, p_scope, p_current_function, p_lambda_node)
		_resolve_expression(p_expr.true_expr, p_scope, p_current_function, p_lambda_node)
		_resolve_expression(p_expr.false_expr, p_scope, p_current_function, p_lambda_node)
	elif p_expr is GDScriptToken.IdentifierNode:
		_resolve_identifier_read(p_expr, p_scope, p_current_function, p_lambda_node)
	elif p_expr is GDScriptToken.AttributeNode:
		_resolve_expression(p_expr.base, p_scope, p_current_function, p_lambda_node)
	elif p_expr is GDScriptToken.SubscriptNode:
		_resolve_expression(p_expr.base, p_scope, p_current_function, p_lambda_node)
		_resolve_expression(p_expr.index, p_scope, p_current_function, p_lambda_node)
	elif p_expr is GDScriptToken.CallNode:
		_resolve_call(p_expr, p_scope, p_current_function)
	elif p_expr is GDScriptToken.LambdaNode:
		_resolve_lambda(p_expr, p_scope, p_current_function)
	elif p_expr is GDScriptToken.ArrayNode:
		for elem in p_expr.elements:
			_resolve_expression(elem, p_scope, p_current_function, p_lambda_node)
	elif p_expr is GDScriptToken.DictionaryNode:
		for pair in p_expr.pairs:
			_resolve_expression(pair["key"], p_scope, p_current_function, p_lambda_node)
			_resolve_expression(pair["value"], p_scope, p_current_function, p_lambda_node)
	elif p_expr is GDScriptToken.CastNode:
		_resolve_expression(p_expr.expression, p_scope, p_current_function, p_lambda_node)
	elif p_expr is GDScriptToken.TypeTestNode:
		_resolve_expression(p_expr.expression, p_scope, p_current_function, p_lambda_node)
	elif p_expr in [GDScriptToken.LiteralNode, GDScriptSelfNode, GDScriptSuperNode]:
		pass  # 叶子节点
	elif p_expr is GDScriptToken.PreloadNode:
		if result.preloads.find(p_expr.path) == -1:
			result.preloads.append(p_expr.path)
	elif p_expr is GDScriptToken.AssignmentNode:
		_resolve_assignment(p_expr, p_scope, p_current_function)


# Suite 遍历 — 遍历语句列表（不创建新作用域）
func _resolve_suite(p_body, p_scope: GDScriptSymbolTable, p_current_function: String, p_lambda_node = null):
	if p_body == null:
		return
	# p_body 可能是 SuiteNode（多语句）或 ExpressionNode（单行 lambda body）
	if p_body is GDScriptToken.SuiteNode:
		for stmt in p_body.statements:
			_resolve_node(stmt, p_scope, p_current_function, p_lambda_node)
	else:
		_resolve_expression(p_body, p_scope, p_current_function, p_lambda_node)


# 记录 DefUse 站点
func _record_def_use(p_var_name: String, p_node, p_current_function: String, p_access_type: int):
	var info = result.def_use_chain._ensure_info(p_var_name)

	var site = GDScriptDefUseSite.new()
	site.line = p_node.line if p_node.has_method("get") == false and "line" in p_node else 0
	site.node = p_node
	site.enclosing_function = p_current_function
	site.access_type = p_access_type

	match p_access_type:
		GDScriptDefUseSite.AccessType.DEFINE:
			info.def_site = site
		GDScriptDefUseSite.AccessType.READ:
			info.read_sites.append(site)
		GDScriptDefUseSite.AccessType.WRITE, GDScriptDefUseSite.AccessType.READ_WRITE:
			info.write_sites.append(site)


# 添加调用边
func _add_call_edge(p_caller: String, p_callee: String, p_line: int, p_call_type: int, p_target: String = "", p_arguments: Array = []):
	var edge = GDScriptCallEdge.new()
	edge.caller = p_caller
	edge.callee = p_callee
	edge.site_line = p_line
	edge.call_type = p_call_type
	edge.target_object = p_target
	edge.arguments = p_arguments
	result.call_graph.add_edge(edge)


# 创建 Site 对象
func _make_site(p_node, p_enclosing_function: String, p_arguments: Array = []) -> GDScriptSite:
	var site = GDScriptSite.new()
	site.line = p_node.line if "line" in p_node else 0
	site.node = p_node
	site.enclosing_function = p_enclosing_function
	site.arguments = p_arguments
	return site


# 类型标注 → 字符串
func _type_to_string(p_type) -> String:
	if p_type == null:
		return ""
	return p_type.type_name if "type_name" in p_type else ""


# ---- Chunk 2: 符号表 + 作用域链 ----

# 解析类体 — 创建 class_scope，define 类级符号，遍历成员
func _resolve_class(p_node, p_parent_scope: GDScriptSymbolTable):
	# 如果传入的不是 SymbolTable（首次调用从 resolve() 传入），直接使用
	var class_scope: GDScriptSymbolTable = p_parent_scope

	# 填充 class_name 到 extends_path
	if p_node.classname_id != "":
		result.classname_id = p_node.classname_id
	if p_node.extends_id != "":
		result.extends_path = p_node.extends_id

	# 遍历所有成员
	for member in p_node.members:
		_resolve_node(member, class_scope, "<class>")


# 解析函数 — 创建 func_scope（parent = class_scope），define 函数符号和参数
func _resolve_function(p_node, p_parent_scope: GDScriptSymbolTable):
	# define 函数到父作用域（class_scope）
	var func_sym = p_parent_scope.define(p_node.name, GDScriptSymbol.Kind.FUNCTION, p_node, _type_to_string(p_node.return_type))
	if p_node.is_static:
		func_sym.datatype = "static:" + func_sym.datatype

	# 创建函数作用域
	var func_scope = GDScriptSymbolTable.new()
	func_scope.parent = p_parent_scope
	func_scope.scope_name = "func:%s" % p_node.name

	# define 参数
	for param in p_node.params:
		if param is GDScriptToken.ParameterNode:
			func_scope.define(param.name, GDScriptSymbol.Kind.PARAMETER, param, _type_to_string(param.datatype))
			# Phase 3.2: 参数声明类型
			var ptype = _type_to_string(param.datatype)
			if ptype != "":
				result.type_table[param.name] = ptype
			# 记录参数 def site
			_record_def_use(param.name, param, p_node.name, GDScriptDefUseSite.AccessType.DEFINE)

	# 遍历函数体
	if p_node.body != null:
		_resolve_suite(p_node.body, func_scope, p_node.name)


# 解析变量声明 — 用方案 A 区分 const/var
func _resolve_variable(p_node, p_scope: GDScriptSymbolTable, p_current_function: String):
	# 方案 A: 通过源码行确定是 const 还是 var
	var kind = GDScriptSymbol.Kind.CONSTANT if _const_set.has(p_node) else GDScriptSymbol.Kind.VARIABLE

	# define 到当前作用域
	var sym = p_scope.define(p_node.name, kind, p_node, _type_to_string(p_node.datatype))
	sym.is_exported = p_node.is_export

	# Phase 3.2: 记录变量声明类型到 type_table（供跨文件解析）
	var vtype = _type_to_string(p_node.datatype)
	if vtype != "":
		result.type_table[p_node.name] = vtype

	# 记录 def site
	_record_def_use(p_node.name, p_node, p_current_function, GDScriptDefUseSite.AccessType.DEFINE)

	# 解析初始化表达式中的标识符引用（这些是 READ）
	if p_node.initializer != null:
		_resolve_expression(p_node.initializer, p_scope, p_current_function)


# 解析信号声明
func _resolve_signal(p_node, p_scope: GDScriptSymbolTable):
	# define 信号符号
	p_scope.define(p_node.name, GDScriptSymbol.Kind.SIGNAL, p_node)

	# 注册 SignalInfo 到 SignalGraph
	var info = GDScriptSignalInfo.new()
	info.name = p_node.name
	info.declaration = p_node
	for param in p_node.params:
		if param is GDScriptToken.ParameterNode:
			info.params.append(param.name)

	result.signal_graph.signals[p_node.name] = info


# 解析枚举声明
func _resolve_enum(p_node, p_scope: GDScriptSymbolTable):
	# define 枚举到当前作用域
	var enum_name = p_node.name if p_node.name != "" else "<anonymous_enum>"
	p_scope.define(enum_name, GDScriptSymbol.Kind.ENUM, p_node)

	# define 枚举值到当前作用域（GDScript 枚举值在 class scope 直接可用）
	for entry in p_node.values:
		var value_name = entry["name"]
		p_scope.define(value_name, GDScriptSymbol.Kind.ENUM_VALUE, p_node)


# ---- Task 4: 语句节点遍历 + scope chain 查找 ----

# 解析 if 语句 — 不创建新作用域
func _resolve_if(p_node, p_scope: GDScriptSymbolTable, p_current_function: String, p_lambda_node = null):
	_resolve_expression(p_node.condition, p_scope, p_current_function, p_lambda_node)
	_resolve_suite(p_node.true_branch, p_scope, p_current_function, p_lambda_node)
	if p_node.false_branch != null:
		# false_branch 可能是 IfNode (elif) 或 SuiteNode (else)
		if p_node.false_branch is GDScriptToken.IfNode:
			_resolve_if(p_node.false_branch, p_scope, p_current_function, p_lambda_node)
		else:
			_resolve_suite(p_node.false_branch, p_scope, p_current_function, p_lambda_node)


# 解析 while — 不创建新作用域
func _resolve_while(p_node, p_scope: GDScriptSymbolTable, p_current_function: String, p_lambda_node = null):
	_resolve_expression(p_node.condition, p_scope, p_current_function, p_lambda_node)
	_resolve_suite(p_node.body, p_scope, p_current_function, p_lambda_node)


# 解析 match — 不创建新作用域
func _resolve_match(p_node, p_scope: GDScriptSymbolTable, p_current_function: String, p_lambda_node = null):
	_resolve_expression(p_node.test, p_scope, p_current_function, p_lambda_node)
	for branch in p_node.branches:
		if branch is GDScriptToken.MatchBranchNode:
			for pattern in branch.patterns:
				_resolve_expression(pattern, p_scope, p_current_function, p_lambda_node)
			_resolve_suite(branch.body, p_scope, p_current_function, p_lambda_node)


# 解析 for 循环 — 不创建新作用域，循环变量 define 到当前作用域
func _resolve_for(p_node, p_scope: GDScriptSymbolTable, p_current_function: String, p_lambda_node = null):
	# for i in range(10): — i define 到当前作用域
	p_scope.define(p_node.var_name, GDScriptSymbol.Kind.FOR_VAR, p_node, "Variant")
	_record_def_use(p_node.var_name, p_node, p_current_function, GDScriptDefUseSite.AccessType.DEFINE)

	# iterable 中的标识符是 READ
	_resolve_expression(p_node.iterable, p_scope, p_current_function, p_lambda_node)

	# body 中可能有 for 循环变量的 READ 或 WRITE
	_resolve_suite(p_node.body, p_scope, p_current_function, p_lambda_node)


# 解析 return 语句
func _resolve_return(p_node, p_scope: GDScriptSymbolTable, p_current_function: String, p_lambda_node = null):
	if p_node.value != null:
		_resolve_expression(p_node.value, p_scope, p_current_function, p_lambda_node)


# 解析标识符读取
func _resolve_identifier_read(p_node, p_scope: GDScriptSymbolTable, p_current_function: String, p_lambda_node = null):
	# lambda 捕获检测优先
	if p_lambda_node != null:
		_resolve_identifier_in_lambda(p_node, p_scope, p_lambda_node, p_current_function)
		return

	var sym = p_scope.resolve(p_node.name)
	if sym == null:
		# 未解析 — 可能是内置函数/全局引用
		# 不记录错误，因为可能是内置函数（print, range 等）
		# [Phase 3] 引入内置函数列表做精确判断
		return

	# 记录 READ
	_record_def_use(sym.name, p_node, p_current_function, GDScriptDefUseSite.AccessType.READ)


# ---- Chunk 3: 调用图 + 信号图 ----

# 解析函数调用 — 6 种调用模式检测
func _resolve_call(p_node, p_scope: GDScriptSymbolTable, p_current_function: String):
	# 先解析参数中的标识符引用（都是 READ）
	for arg in p_node.arguments:
		_resolve_expression(arg, p_scope, p_current_function)

	var callee = p_node.callee

	# 模式 1: 裸标识符调用 — foo() / emit("sig")
	if callee is GDScriptToken.IdentifierNode:
		# 1a: emit("signal_name") → EMIT
		if callee.name == "emit":
			_resolve_emit_call(p_node, p_current_function)
			return
		# 1b: 隐式 self 调用 foo()
		var sym = p_scope.resolve(callee.name)
		if sym == null or sym.kind == GDScriptSymbol.Kind.FUNCTION:
			_add_call_edge(p_current_function, callee.name, callee.line, GDScriptCallEdge.CallType.SELF, "", p_node.arguments)
		# 否则可能是内置函数 (print, range 等) — 不记录 CallEdge

	# 模式 2: 属性调用 — self.foo() / obj.method() / super.foo() / sig.connect() / sig.emit()
	elif callee is GDScriptToken.AttributeNode:
		_resolve_attribute_call(p_node, callee, p_scope, p_current_function)


# 属性调用分析 — AttributeNode(callee) 的 7 种子模式
func _resolve_attribute_call(p_call_node, p_attr, p_scope: GDScriptSymbolTable, p_current_function: String):
	var base = p_attr.base
	var method_name = p_attr.name

	# 2a: self.method() / super.method()
	if base is GDScriptSelfNode:
		_add_call_edge(p_current_function, method_name, p_attr.line, GDScriptCallEdge.CallType.SELF, "", p_call_node.arguments)
	elif base is GDScriptSuperNode:
		_add_call_edge(p_current_function, method_name, p_attr.line, GDScriptCallEdge.CallType.SUPER, "", p_call_node.arguments)

	# 2c: obj.connect("sig", cb) -> CONNECT
	elif method_name == "connect" and p_call_node.arguments.size() >= 1 and p_call_node.arguments[0] is GDScriptToken.LiteralNode and typeof(p_call_node.arguments[0].value) == TYPE_STRING:
		_resolve_object_connect(p_call_node, p_scope, p_current_function)

	# 2d: signal_name.connect(cb) -> SIGNAL_CONNECT / LAMBDA
	elif method_name == "connect" and base is GDScriptToken.IdentifierNode:
		_resolve_signal_connect(p_call_node, base.name, p_scope, p_current_function)

	# 2d2: obj.signal.connect(cb) -> 跨文件信号连接
	# base 是 AttributeNode(obj, signal_name)，如 player.health_changed.connect(cb)
	elif method_name == "connect" and base is GDScriptToken.AttributeNode:
		var sig_name = base.name
		var obj_base = base.base
		if obj_base is GDScriptToken.IdentifierNode:
			# 记录 connect_site 到信号图
			var info = result.signal_graph.get_signal_flow(sig_name)
			if info == null:
				info = GDScriptSignalInfo.new()
				info.name = sig_name
				result.signal_graph.signals[sig_name] = info
			info.connect_sites.append(_make_site(p_call_node, p_current_function, p_call_node.arguments))
			# 记录 SIGNAL_CONNECT 边: callee=信号名, target_object=对象名 (供跨文件解析)
			_add_call_edge(p_current_function, sig_name, p_attr.line, GDScriptCallEdge.CallType.SIGNAL_CONNECT, obj_base.name, p_call_node.arguments)
		else:
			_resolve_object_connect(p_call_node, p_scope, p_current_function)

	# 2e: other connect
	elif method_name == "connect":
		_resolve_object_connect(p_call_node, p_scope, p_current_function)

	# 2e: signal_name.emit() → EMIT
	elif method_name == "emit" and base is GDScriptToken.IdentifierNode:
		_resolve_signal_emit(p_call_node, base.name, p_current_function, "dot_emit")

	# 2f: obj.method() → EXTERNAL
	elif base is GDScriptToken.IdentifierNode:
		_add_call_edge(p_current_function, method_name, p_attr.line, GDScriptCallEdge.CallType.EXTERNAL, base.name, p_call_node.arguments)

	# 2g: 链式调用 a.b.method() 或 ClassName.method() — [Phase 3] STATIC 调用


# emit("signal_name") 形式 — 已在 _resolve_call 中通过 callee.name == "emit" 触发
func _resolve_emit_call(p_node, p_current_function: String):
	if p_node.arguments.size() > 0 and p_node.arguments[0] is GDScriptToken.LiteralNode:
		var sig_name = str(p_node.arguments[0].value)
		# 记录 emit_site
		var info = result.signal_graph.get_signal_flow(sig_name)
		if info == null:
			# 未声明的信号 — 创建临时 SignalInfo
			info = GDScriptSignalInfo.new()
			info.name = sig_name
			result.signal_graph.signals[sig_name] = info
			result.add_error("[SymbolResolver] %d: 信号 '%s' 未声明，通过 emit() 发射" % [p_node.line, sig_name])
		info.emit_sites.append(_make_site(p_node, p_current_function, p_node.arguments))
		# 同时记录为 EMIT 类型的 CallEdge
		_add_call_edge(p_current_function, sig_name, p_node.callee.line, GDScriptCallEdge.CallType.EMIT, "", p_node.arguments)


# signal_name.emit() 形式 — 从 _resolve_attribute_call 调用
func _resolve_signal_emit(p_call_node, p_signal_name: String, p_current_function: String, p_form: String):
	var info = result.signal_graph.get_signal_flow(p_signal_name)
	if info == null:
		info = GDScriptSignalInfo.new()
		info.name = p_signal_name
		result.signal_graph.signals[p_signal_name] = info
		result.add_error("[SymbolResolver] %d: 信号 '%s' 未声明，通过 .emit() 发射" % [p_call_node.line, p_signal_name])
	info.emit_sites.append(_make_site(p_call_node, p_current_function, p_call_node.arguments))
	_add_call_edge(p_current_function, p_signal_name, p_call_node.callee.line, GDScriptCallEdge.CallType.EMIT, "", p_call_node.arguments)


# signal_name.connect(cb/lambda) 形式
func _resolve_signal_connect(p_call_node, p_signal_name: String, p_scope: GDScriptSymbolTable, p_current_function: String):
	var info = result.signal_graph.get_signal_flow(p_signal_name)
	if info == null:
		info = GDScriptSignalInfo.new()
		info.name = p_signal_name
		result.signal_graph.signals[p_signal_name] = info
		result.add_error("[SymbolResolver] %d: 信号 '%s' 未声明，通过 .connect() 连接" % [p_call_node.line, p_signal_name])

	# 记录 connect_site
	info.connect_sites.append(_make_site(p_call_node, p_current_function, p_call_node.arguments))

	# 判断回调类型并记录 CallEdge
	if p_call_node.arguments.size() > 0:
		var cb = p_call_node.arguments[0]
		if cb is GDScriptToken.IdentifierNode:
			# signal_name.connect(callback_func) → SIGNAL_CONNECT
			_add_call_edge(p_current_function, cb.name, p_call_node.callee.line, GDScriptCallEdge.CallType.SIGNAL_CONNECT, p_signal_name, p_call_node.arguments)
		elif cb is GDScriptToken.LambdaNode:
			# signal_name.connect(lambda) → LAMBDA
			_add_call_edge(p_current_function, "<lambda@%d>" % cb.line, p_call_node.callee.line, GDScriptCallEdge.CallType.LAMBDA, p_signal_name, p_call_node.arguments)
			# 同时解析 lambda（其 captured_vars 提供闭包上下文）
			_resolve_lambda(cb, p_scope, p_current_function)


# obj.connect("signal_name", cb) 形式
func _resolve_object_connect(p_call_node, p_scope: GDScriptSymbolTable, p_current_function: String):
	if p_call_node.arguments.size() >= 1 and p_call_node.arguments[0] is GDScriptToken.LiteralNode:
		var sig_name = str(p_call_node.arguments[0].value)

		# 记录 connect_site（可能是未声明的外部信号）
		var info = result.signal_graph.get_signal_flow(sig_name)
		if info == null:
			info = GDScriptSignalInfo.new()
			info.name = sig_name
			result.signal_graph.signals[sig_name] = info
		info.connect_sites.append(_make_site(p_call_node, p_current_function, p_call_node.arguments))

		# 判断回调
		if p_call_node.arguments.size() >= 2:
			var cb = p_call_node.arguments[1]
			if cb is GDScriptToken.IdentifierNode:
				_add_call_edge(p_current_function, cb.name, p_call_node.callee.line, GDScriptCallEdge.CallType.CONNECT, sig_name, p_call_node.arguments)
			elif cb is GDScriptToken.LambdaNode:
				_add_call_edge(p_current_function, "<lambda@%d>" % cb.line, p_call_node.callee.line, GDScriptCallEdge.CallType.LAMBDA, sig_name, p_call_node.arguments)
				_resolve_lambda(cb, p_scope, p_current_function)


# ---- Task 6: self.hp = 10 的 AttributeNode 特殊处理 ----

# 解析赋值语句 — 区分 target 形态
func _resolve_assignment(p_node, p_scope: GDScriptSymbolTable, p_current_function: String):
	# 先解析 value 侧的表达式（所有标识符为 READ）
	_resolve_expression(p_node.value, p_scope, p_current_function)

	# 再解析 target 侧的标识符
	if p_node.target is GDScriptToken.IdentifierNode:
		# x = value → x 是 WRITE（或 READ_WRITE 若复合赋值）
		var access = GDScriptDefUseSite.AccessType.WRITE if p_node.op == GDScriptToken.Type.EQUAL else GDScriptDefUseSite.AccessType.READ_WRITE
		_record_def_use(p_node.target.name, p_node.target, p_current_function, access)

	elif p_node.target is GDScriptToken.AttributeNode:
		# a.b = value → a 是 READ（读取对象引用，未修改 a 本身）
		# 但 b 是对象属性写入，不在当前文件的变量追踪范围内
		var base = p_node.target.base

		# self.hp = 10 → self 是 SelfNode，不需要追踪
		# obj.hp = 10 → obj 是 IdentifierNode，记录 READ
		if base is GDScriptToken.IdentifierNode:
			_record_def_use(base.name, base, p_current_function, GDScriptDefUseSite.AccessType.READ)
		# 递归处理更深层的属性链: a.b.c = value → a.b 是 READ
		elif base is GDScriptToken.AttributeNode:
			_resolve_expression(base, p_scope, p_current_function)
		# SelfNode / SuperNode / CallNode 等 → 递归解析 base 中的标识符
		elif base is GDScriptToken.CallNode:
			_resolve_call(base, p_scope, p_current_function)

	elif p_node.target is GDScriptToken.SubscriptNode:
		# a[b] = value → a 是 READ, b 中的标识符是 READ
		_resolve_expression(p_node.target.base, p_scope, p_current_function)
		_resolve_expression(p_node.target.index, p_scope, p_current_function)


# ---- Chunk 4: Lambda 闭包捕获 ----

# 解析 Lambda 表达式 — 创建 lambda_scope (parent = 当前作用域)
func _resolve_lambda(p_node, p_parent_scope: GDScriptSymbolTable, p_current_function: String):
	# 创建 lambda_scope
	var lambda_scope = GDScriptSymbolTable.new()
	lambda_scope.parent = p_parent_scope
	lambda_scope.scope_name = "lambda@%d" % p_node.line

	# define lambda 参数到 lambda_scope
	for param in p_node.params:
		if param is GDScriptToken.ParameterNode:
			lambda_scope.define(param.name, GDScriptSymbol.Kind.PARAMETER, param, _type_to_string(param.datatype))
			_record_def_use(param.name, param, p_current_function, GDScriptDefUseSite.AccessType.DEFINE)

	# 遍历 lambda body — 传入 p_node 自身用于捕获检测
	_resolve_suite(p_node.body, lambda_scope, p_current_function, p_node)


# Lambda 中的标识符解析 — 区分局部变量 vs 捕获变量
func _resolve_identifier_in_lambda(p_node, p_lambda_scope: GDScriptSymbolTable, p_lambda_node, p_current_function: String):
	# 先检查 lambda 自己的局部作用域（参数）
	var local = p_lambda_scope.resolve_local(p_node.name)
	if local != null:
		# lambda 局部变量（参数）— 正常记录 READ
		_record_def_use(p_node.name, p_node, p_current_function, GDScriptDefUseSite.AccessType.READ)
		return

	# 不在 lambda 局部 → 向父作用域查找（resolve 自动递归到 parent）
	var sym = p_lambda_scope.resolve(p_node.name)
	if sym != null:
		# 这是捕获变量！记录到 LambdaNode.captured_vars
		if p_lambda_node.captured_vars.find(p_node.name) == -1:
			p_lambda_node.captured_vars.append(p_node.name)
		_record_def_use(p_node.name, p_node, p_current_function, GDScriptDefUseSite.AccessType.READ)
		return

	# 完全未解析 — 可能是内置函数/全局引用
