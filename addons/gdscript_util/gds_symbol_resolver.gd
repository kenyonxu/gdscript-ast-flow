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
	result.call_graph = CallGraph.new()
	result.signal_graph = SignalGraph.new()
	result.def_use_chain = DefUseChain.new()

	# 预加载源码行（用于 const/var 区分 — 方案 A）
	_load_source_lines(p_file_path)

	# 创建类作用域
	result.symbol_table = SymbolTable.new()
	result.symbol_table.scope_name = "class:%s" % p_ast.classname_id if p_ast.classname_id != "" else "class:<anonymous>"

	# 填充基础信息
	result.class_name = p_ast.classname_id
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
func _resolve_node(p_node, p_scope: SymbolTable, p_current_function: String, p_lambda_node = null):
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
func _resolve_expression(p_expr, p_scope: SymbolTable, p_current_function: String, p_lambda_node = null):
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
	elif p_expr in [GDScriptToken.LiteralNode, GDScriptToken.SelfNode, GDScriptToken.SuperNode]:
		pass  # 叶子节点
	elif p_expr is GDScriptToken.PreloadNode:
		if result.preloads.find(p_expr.path) == -1:
			result.preloads.append(p_expr.path)


# Suite 遍历 — 遍历语句列表（不创建新作用域）
func _resolve_suite(p_body, p_scope: SymbolTable, p_current_function: String, p_lambda_node = null):
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

	var site = DefUseSite.new()
	site.line = p_node.line if p_node.has_method("get") == false and "line" in p_node else 0
	site.node = p_node
	site.enclosing_function = p_current_function
	site.access_type = p_access_type

	match p_access_type:
		DefUseSite.AccessType.DEFINE:
			info.def_site = site
		DefUseSite.AccessType.READ:
			info.read_sites.append(site)
		DefUseSite.AccessType.WRITE, DefUseSite.AccessType.READ_WRITE:
			info.write_sites.append(site)


# 添加调用边
func _add_call_edge(p_caller: String, p_callee: String, p_line: int, p_call_type: int, p_target: String = "", p_arguments: Array = []):
	var edge = CallEdge.new()
	edge.caller = p_caller
	edge.callee = p_callee
	edge.site_line = p_line
	edge.call_type = p_call_type
	edge.target_object = p_target
	edge.arguments = p_arguments
	result.call_graph.add_edge(edge)


# 创建 Site 对象
func _make_site(p_node, p_enclosing_function: String, p_arguments: Array = []) -> Site:
	var site = Site.new()
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
func _resolve_class(p_node, p_parent_scope: SymbolTable):
	# 如果传入的不是 SymbolTable（首次调用从 resolve() 传入），直接使用
	var class_scope: SymbolTable = p_parent_scope

	# 填充 class_name 到 extends_path
	if p_node.classname_id != "":
		result.class_name = p_node.classname_id
	if p_node.extends_id != "":
		result.extends_path = p_node.extends_id

	# 遍历所有成员
	for member in p_node.members:
		_resolve_node(member, class_scope, "<class>")


# 解析函数 — 创建 func_scope（parent = class_scope），define 函数符号和参数
func _resolve_function(p_node, p_parent_scope: SymbolTable):
	# define 函数到父作用域（class_scope）
	var func_sym = p_parent_scope.define(p_node.name, Symbol.Kind.FUNCTION, p_node, _type_to_string(p_node.return_type))
	if p_node.is_static:
		func_sym.datatype = "static:" + func_sym.datatype

	# 创建函数作用域
	var func_scope = SymbolTable.new()
	func_scope.parent = p_parent_scope
	func_scope.scope_name = "func:%s" % p_node.name

	# define 参数
	for param in p_node.params:
		if param is GDScriptToken.ParameterNode:
			func_scope.define(param.name, Symbol.Kind.PARAMETER, param, _type_to_string(param.datatype))
			# 记录参数 def site
			_record_def_use(param.name, param, p_node.name, DefUseSite.AccessType.DEFINE)

	# 遍历函数体
	if p_node.body != null:
		_resolve_suite(p_node.body, func_scope, p_node.name)


# 解析变量声明 — 用方案 A 区分 const/var
func _resolve_variable(p_node, p_scope: SymbolTable, p_current_function: String):
	# 方案 A: 通过源码行确定是 const 还是 var
	var kind = Symbol.Kind.CONSTANT if _const_set.has(p_node) else Symbol.Kind.VARIABLE

	# define 到当前作用域
	var sym = p_scope.define(p_node.name, kind, p_node, _type_to_string(p_node.datatype))
	sym.is_exported = p_node.is_export

	# 记录 def site
	_record_def_use(p_node.name, p_node, p_current_function, DefUseSite.AccessType.DEFINE)

	# 解析初始化表达式中的标识符引用（这些是 READ）
	if p_node.initializer != null:
		_resolve_expression(p_node.initializer, p_scope, p_current_function)


# 解析信号声明
func _resolve_signal(p_node, p_scope: SymbolTable):
	# define 信号符号
	p_scope.define(p_node.name, Symbol.Kind.SIGNAL, p_node)

	# 注册 SignalInfo 到 SignalGraph
	var info = SignalInfo.new()
	info.name = p_node.name
	info.declaration = p_node
	for param in p_node.params:
		if param is GDScriptToken.ParameterNode:
			info.params.append(param.name)

	result.signal_graph.signals[p_node.name] = info


# 解析枚举声明
func _resolve_enum(p_node, p_scope: SymbolTable):
	# define 枚举到当前作用域
	var enum_name = p_node.name if p_node.name != "" else "<anonymous_enum>"
	p_scope.define(enum_name, Symbol.Kind.ENUM, p_node)

	# define 枚举值到当前作用域（GDScript 枚举值在 class scope 直接可用）
	for entry in p_node.values:
		var value_name = entry["name"]
		p_scope.define(value_name, Symbol.Kind.ENUM_VALUE, p_node)
