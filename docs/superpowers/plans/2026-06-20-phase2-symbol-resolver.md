# Phase 2: GDScript 符号解析器 实现计划

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Phase 1 AST 管道之上构建符号分析和逻辑流图能力。完成后可回答：信号在哪里发射/连接？函数被谁调用？变量在哪些位置读写？Lambda 捕获了哪些外部变量？

**Architecture:** 两文件新增 + 一文件扩展 — `gds_analysis_result.gd`（数据结构） + `gds_symbol_resolver.gd`（AST Visitor） + `plugin.gd`（EditorPlugin 集成）。纯 GDScript 实现，不修改 Phase 1 代码（`gds_ast_nodes.gd` / `gds_tokenizer.gd` / `gds_parser.gd`）。

**Tech Stack:** Godot 4.7, GDScript, EditorPlugin API, RefCounted

**Spec reference:** `docs/superpowers/specs/2026-06-20-phase2-symbol-resolver-design.md`

**Phase 1 output reference:** `addons/gdscript_util/gds_ast_nodes.gd`（AST 节点类型定义）

---

## 文件结构

```
addons/gdscript_util/
├── gds_ast_nodes.gd          # [Phase 1] 不修改 — Token 枚举 + AST 节点类
├── gds_tokenizer.gd          # [Phase 1] 不修改 — 词法分析器
├── gds_parser.gd             # [Phase 1] 不修改 — 语法分析器
├── gds_analysis_result.gd    # [Phase 2 新增] 结果容器 + 全部数据结构 (~350行)
├── gds_symbol_resolver.gd    # [Phase 2 新增] AST Visitor 符号解析器 (~550行)
├── plugin.gd                 # [扩展] EditorPlugin 入口 — 添加 resource_saved 信号
└── plugin.cfg                # [Phase 1] 不修改

tests/
├── test_parser.gd            # [Phase 1] 已有 — 解析管道测试
└── test_symbol_resolver.gd   # [Phase 2 新增] 10 个验收测试
```

**职责边界：**
- `gds_analysis_result.gd` — 纯数据定义：SymbolTable、Symbol、CallGraph、CallEdge、SignalGraph、SignalInfo、Site、DefUseChain、DefUseInfo、DefUseSite、GDScriptAnalysisResult。所有数据类继承 RefCounted，含查询 API。
- `gds_symbol_resolver.gd` — 接收 `ClassNode`（AST 根）→ 遍历构建符号表+调用图+信号图+DefUse链 → 返回 `GDScriptAnalysisResult`。以 Visitor 模式递归遍历 AST。
- `plugin.gd` — 扩展：添加 `resource_saved` 信号连接，升级 `_on_parse_current()` 使用 Phase 2 管道，添加分析摘要输出。

**不修改的文件（核心原则）：**
- `gds_ast_nodes.gd` — 零改动。Phase 2 通过 `GDScriptToken.ClassName` 全限定名引用所有 AST 节点类型。
- `gds_tokenizer.gd` — 零改动。
- `gds_parser.gd` — 零改动。

---

## Chunk 1: 数据结构 + 框架

> **目标：** 建立 `gds_analysis_result.gd`（全部数据类）和 `gds_symbol_resolver.gd`（骨架 + resolve 入口 + AST 遍历分发框架）。本 Chunk 完成后，可以创建 Result 对象并遍历 AST（尚未构建符号表/图）。

### Task 1: 创建 gds_analysis_result.gd — 核心数据结构

**Files:** Create: `addons/gdscript_util/gds_analysis_result.gd`

- [ ] **Step 1: 创建 Symbol 和 SymbolTable**

```gdscript
# addons/gdscript_util/gds_analysis_result.gd
# Phase 2 符号解析器 — 全部数据结构定义 + 结果容器
# 纯数据定义，零业务逻辑（查询 API 除外）

# ---- Symbol — 符号表中的单个符号 ----
class Symbol:
	extends RefCounted

	enum Kind {
		CLASS = 0,        # class / inner class 定义
		FUNCTION = 1,     # func 定义
		VARIABLE = 2,     # var 定义
		SIGNAL = 3,       # signal 声明
		ENUM = 4,         # enum 定义
		PARAMETER = 5,    # 函数参数
		CONSTANT = 6,     # const 定义
		ENUM_VALUE = 7,   # enum 中的值 (如 enum { A, B } 中的 A)
		FOR_VAR = 8       # for 循环变量 (for i in ...)
	}

	var name: String = ""
	var kind: int = Kind.VARIABLE
	var declaration = null             # 指向 AST 中的声明节点 (VariableNode / FunctionNode / SignalNode / ...)
	var datatype: String = ""          # 类型标注字符串: "int", "Array", "Node" 等
	var is_exported: bool = false      # @export 标记
```

- [ ] **Step 2: 创建 SymbolTable**

```gdscript
# ---- SymbolTable — 嵌套作用域符号表 ----
class SymbolTable:
	extends RefCounted

	var parent: SymbolTable = null     # 外层作用域 (null 表示根作用域)
	var symbols: Dictionary = {}       # String → Symbol
	var scope_name: String = ""        # 作用域描述: "class:Player", "func:take_damage", "lambda@12"

	func define(p_name: String, p_kind: int, p_node, p_datatype: String = "") -> Symbol:
		var sym = Symbol.new()
		sym.name = p_name
		sym.kind = p_kind
		sym.declaration = p_node
		sym.datatype = p_datatype
		symbols[p_name] = sym
		return sym

	# 递归向上查找（scope chain）
	func resolve(p_name: String) -> Symbol:
		if symbols.has(p_name):
			return symbols[p_name]
		if parent != null:
			return parent.resolve(p_name)
		return null

	# 仅当前作用域查找（用于 lambda 捕获检测）
	func resolve_local(p_name: String) -> Symbol:
		return symbols.get(p_name, null)
```

- [ ] **Step 3: 创建 CallEdge 和 CallGraph**

```gdscript
# ---- CallEdge — 调用图中的一条边 ----
class CallEdge:
	extends RefCounted

	enum CallType {
		SELF = 0,            # self.method() 或隐式 self 调用 (foo())
		SUPER = 1,           # super.method()
		EXTERNAL = 2,        # obj.method() —— 外部对象调用
		CONNECT = 3,         # .connect("sig", cb) 中的回调
		SIGNAL_CONNECT = 4,  # signal_name.connect(cb) 中的回调
		LAMBDA = 5,          # lambda 表达式作为回调 (connect 的参数)
		STATIC = 6,          # ClassName.static_method()
		EMIT = 7,            # emit("signal") / signal.emit() 信号发射
	}

	var caller: String = ""             # 调用方函数名（或 "<class>" 表示全局）
	var callee: String = ""             # 被调用方函数名
	var site_line: int = 0              # 调用所在行号
	var call_type: int = CallType.SELF
	var target_object: String = ""      # 调用目标对象名 (EXTERNAL 时填充，如 "obj")
	var arguments: Array = []           # of ExpressionNode — 调用参数的 AST 节点


# ---- CallGraph — 方法调用图 ----
class CallGraph:
	extends RefCounted

	var edges: Array = []               # of CallEdge

	func add_edge(p_edge: CallEdge):
		edges.append(p_edge)

	func get_callers_of(p_func_name: String) -> Array:
		var result: Array = []
		for e in edges:
			if e.callee == p_func_name:
				result.append(e)
		return result

	func get_callees_of(p_func_name: String) -> Array:
		var result: Array = []
		for e in edges:
			if e.caller == p_func_name:
				result.append(e)
		return result
```

- [ ] **Step 4: 创建 SignalGraph 相关（Site + SignalInfo + SignalGraph）**

```gdscript
# ---- Site — emit/connect 的位置信息 ----
class Site:
	extends RefCounted

	var line: int = 0
	var node = null                           # 对应的 AST 节点 (CallNode)
	var enclosing_function: String = ""       # 所在函数名
	var arguments: Array = []                 # of ExpressionNode


# ---- SignalInfo — 单个信号的完整流程图 ----
class SignalInfo:
	extends RefCounted

	var name: String = ""
	var declaration = null                    # GDScriptToken.SignalNode
	var params: Array = []                    # of String — 参数名列表
	var emit_sites: Array = []                # of Site — emit("name") / name.emit()
	var connect_sites: Array = []             # of Site — .connect("name", cb) / name.connect(cb)


# ---- SignalGraph — 信号流程图 ----
class SignalGraph:
	extends RefCounted

	var signals: Dictionary = {}              # String → SignalInfo

	func get_signal_flow(p_signal_name: String) -> SignalInfo:
		return signals.get(p_signal_name, null)
```

- [ ] **Step 5: 创建 DefUse 相关（DefUseSite + DefUseInfo + DefUseChain）**

```gdscript
# ---- DefUseSite — 单个读写位置 ----
class DefUseSite:
	extends RefCounted

	enum AccessType {
		DEFINE = 0,      # var x = ... / const x = ... 的定义
		READ = 1,        # 读取变量值 (作为表达式的一部分)
		WRITE = 2,       # 赋值写入 (x = value)
		READ_WRITE = 3   # 读+写 (x += 1, x -= 1 等复合赋值)
	}

	var line: int = 0
	var node = null                         # 对应的 AST 节点
	var enclosing_function: String = ""     # 所在函数名（"<class>" 表示顶层）
	var access_type: int = AccessType.READ


# ---- DefUseInfo — 单个变量的完整读写链 ----
class DefUseInfo:
	extends RefCounted

	var name: String = ""
	var def_site: DefUseSite = null         # 定义位置 (var / const / func param)
	var read_sites: Array = []              # of DefUseSite
	var write_sites: Array = []             # of DefUseSite

	func get_all_sites() -> Array:
		var all: Array = []
		if def_site != null:
			all.append(def_site)
		all.append_array(read_sites)
		all.append_array(write_sites)
		return all


# ---- DefUseChain — 变量定义-使用链 ----
class DefUseChain:
	extends RefCounted

	var variables: Dictionary = {}          # String → DefUseInfo

	func get_variable_usages(p_var_name: String) -> DefUseInfo:
		return variables.get(p_var_name, null)

	func _ensure_info(p_name: String) -> DefUseInfo:
		if not variables.has(p_name):
			var info = DefUseInfo.new()
			info.name = p_name
			variables[p_name] = info
		return variables[p_name]
```

- [ ] **Step 6: 创建 GDScriptAnalysisResult（结果容器 + 查询 API）**

```gdscript
# ---- GDScriptAnalysisResult — 统一结果容器 ----
class_name GDScriptAnalysisResult
extends RefCounted

var file_path: String = ""
var class_name: String = ""               # class_name 名称
var extends_path: String = ""             # extends 的父类路径
var preloads: Array = []                  # of String — preload 路径列表

# 核心数据
var ast = null                            # GDScriptToken.ClassNode
var symbol_table: SymbolTable = null      # 类作用域（根）
var call_graph: CallGraph = null
var signal_graph: SignalGraph = null
var def_use_chain: DefUseChain = null

# 错误/警告
var errors: Array = []                    # of String — "[SymbolResolver] 行:列: 描述" 格式

# 源码行缓存（用于 const/var 区分）
var _source_lines: Array = []             # of String


# ---- 查询 API ----

# 获取所有声明的函数
func get_all_functions() -> Array:
	var funcs: Array = []
	if symbol_table == null:
		return funcs
	for sym_name in symbol_table.symbols:
		var sym = symbol_table.symbols[sym_name]
		if sym.kind == Symbol.Kind.FUNCTION:
			funcs.append(sym.declaration)
	return funcs

# 获取所有声明的信号
func get_all_signals() -> Array:
	var signals: Array = []
	if symbol_table == null:
		return signals
	for sym_name in symbol_table.symbols:
		var sym = symbol_table.symbols[sym_name]
		if sym.kind == Symbol.Kind.SIGNAL:
			signals.append(sym.declaration)
	return signals

# 获取某函数的所有调用者
func get_callers_of(p_func_name: String) -> Array:
	if call_graph == null:
		return []
	return call_graph.get_callers_of(p_func_name)

# 获取某函数调用了谁
func get_callees_of(p_func_name: String) -> Array:
	if call_graph == null:
		return []
	return call_graph.get_callees_of(p_func_name)

# 获取信号的完整流程图
func get_signal_flow(p_signal_name: String) -> SignalInfo:
	if signal_graph == null:
		return null
	return signal_graph.get_signal_flow(p_signal_name)

# 获取变量的完整读写链
func get_variable_usages(p_var_name: String) -> DefUseInfo:
	if def_use_chain == null:
		return null
	return def_use_chain.get_variable_usages(p_var_name)

# 获取依赖树
func get_dependency_tree() -> Dictionary:
	return {
		"extends": extends_path,
		"preloads": preloads,
		"class_name": class_name,
	}

# 添加错误
func add_error(p_msg: String):
	errors.append(p_msg)
```

- [ ] **Step 7: 提交**

```bash
git add addons/gdscript_util/gds_analysis_result.gd
git commit -m "feat: Phase 2 数据结构 — SymbolTable/CallGraph/SignalGraph/DefUseChain/GDScriptAnalysisResult"
```

---

### Task 2: 创建 gds_symbol_resolver.gd — 骨架 + AST 遍历框架

**Files:** Create: `addons/gdscript_util/gds_symbol_resolver.gd`

- [ ] **Step 1: 创建类骨架 + resolve() 入口**

```gdscript
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
```

- [ ] **Step 2: 添加源码行加载和 const/var 预处理（方案 A）**

```gdscript
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
```

- [ ] **Step 3: 添加核心 AST 遍历分发方法**

```gdscript
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
```

- [ ] **Step 4: 添加 DefUse 记录辅助方法**

```gdscript
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
```

- [ ] **Step 5: 提交**

```bash
git add addons/gdscript_util/gds_symbol_resolver.gd
git commit -m "feat: Phase 2 SymbolResolver 骨架 — resolve() 入口 + AST 遍历分发 + 辅助方法"
```

---

## Chunk 2: 符号表 + 作用域链

> **目标：** 实现完整的嵌套作用域符号表。ClassNode → FunctionNode → LambdaNode 创建新作用域；IfNode/WhileNode/ForNode/MatchNode 不创建（GDScript 无块级作用域）。实现 SymbolTable.define() 和 .resolve() 的 scope chain 查找。

### Task 3: 实现 _resolve_class / _resolve_function / _resolve_variable / _resolve_signal / _resolve_enum

**Files:** Modify: `addons/gdscript_util/gds_symbol_resolver.gd` (追加)

- [ ] **Step 1: 实现 _resolve_class — 根作用域 + 成员分发 + 内嵌类处理**

```gdscript
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
```

- [ ] **Step 2: 实现 _resolve_function — 创建 func_scope + define 参数**

```gdscript
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
```

- [ ] **Step 3: 实现 _resolve_variable — const/var 区分 + define + 初始化表达式解析**

```gdscript
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
```

- [ ] **Step 4: 实现 _resolve_signal — define + SignalGraph 注册**

```gdscript
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
```

- [ ] **Step 5: 实现 _resolve_enum — define 枚举 + 枚举值**

```gdscript
# 解析枚举声明
func _resolve_enum(p_node, p_scope: SymbolTable):
	# define 枚举到当前作用域
	var enum_name = p_node.name if p_node.name != "" else "<anonymous_enum>"
	p_scope.define(enum_name, Symbol.Kind.ENUM, p_node)

	# define 枚举值到当前作用域（GDScript 枚举值在 class scope 直接可用）
	for entry in p_node.values:
		var value_name = entry["name"]
		p_scope.define(value_name, Symbol.Kind.ENUM_VALUE, p_node)
```

- [ ] **Step 6: 提交**

```bash
git add addons/gdscript_util/gds_symbol_resolver.gd
git commit -m "feat: SymbolResolver — 类/函数/变量/信号/枚举解析 + const/var 区分(方案A)"
```

---

### Task 4: 作用域链验证 — 语句节点不创建作用域

**Files:** Modify: `addons/gdscript_util/gds_symbol_resolver.gd` (追加)

> 注意：GDScript 不支持块级作用域。IfNode / WhileNode / ForNode / MatchNode 不创建新的 SymbolTable。For 循环变量 define 到当前（函数）作用域。

- [ ] **Step 1: 实现 if/while/match 的语句遍历（不创建新作用域）**

```gdscript
# 解析 if 语句 — 不创建新作用域
func _resolve_if(p_node, p_scope: SymbolTable, p_current_function: String, p_lambda_node = null):
	_resolve_expression(p_node.condition, p_scope, p_current_function, p_lambda_node)
	_resolve_suite(p_node.true_branch, p_scope, p_current_function, p_lambda_node)
	if p_node.false_branch != null:
		# false_branch 可能是 IfNode (elif) 或 SuiteNode (else)
		if p_node.false_branch is GDScriptToken.IfNode:
			_resolve_if(p_node.false_branch, p_scope, p_current_function, p_lambda_node)
		else:
			_resolve_suite(p_node.false_branch, p_scope, p_current_function, p_lambda_node)


# 解析 while — 不创建新作用域
func _resolve_while(p_node, p_scope: SymbolTable, p_current_function: String, p_lambda_node = null):
	_resolve_expression(p_node.condition, p_scope, p_current_function, p_lambda_node)
	_resolve_suite(p_node.body, p_scope, p_current_function, p_lambda_node)


# 解析 match — 不创建新作用域
func _resolve_match(p_node, p_scope: SymbolTable, p_current_function: String, p_lambda_node = null):
	_resolve_expression(p_node.test, p_scope, p_current_function, p_lambda_node)
	for branch in p_node.branches:
		if branch is GDScriptToken.MatchBranchNode:
			for pattern in branch.patterns:
				_resolve_expression(pattern, p_scope, p_current_function, p_lambda_node)
			_resolve_suite(branch.body, p_scope, p_current_function, p_lambda_node)
```

- [ ] **Step 2: 实现 _resolve_for — for 变量 define 到当前作用域**

```gdscript
# 解析 for 循环 — 不创建新作用域，循环变量 define 到当前作用域
func _resolve_for(p_node, p_scope: SymbolTable, p_current_function: String, p_lambda_node = null):
	# for i in range(10): — i define 到当前作用域
	p_scope.define(p_node.var_name, Symbol.Kind.FOR_VAR, p_node, "Variant")
	_record_def_use(p_node.var_name, p_node, p_current_function, DefUseSite.AccessType.DEFINE)

	# iterable 中的标识符是 READ
	_resolve_expression(p_node.iterable, p_scope, p_current_function, p_lambda_node)

	# body 中可能有 for 循环变量的 READ 或 WRITE
	_resolve_suite(p_node.body, p_scope, p_current_function, p_lambda_node)
```

- [ ] **Step 3: 实现 _resolve_return — 返回值表达式中的标识符是 READ**

```gdscript
# 解析 return 语句
func _resolve_return(p_node, p_scope: SymbolTable, p_current_function: String, p_lambda_node = null):
	if p_node.value != null:
		_resolve_expression(p_node.value, p_scope, p_current_function, p_lambda_node)
```

- [ ] **Step 4: 实现 _resolve_identifier_read — scope chain 查找 + DefUse 记录**

```gdscript
# 解析标识符读取
func _resolve_identifier_read(p_node, p_scope: SymbolTable, p_current_function: String, p_lambda_node = null):
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
	_record_def_use(sym.name, p_node, p_current_function, DefUseSite.AccessType.READ)
```

- [ ] **Step 5: 提交**

```bash
git add addons/gdscript_util/gds_symbol_resolver.gd
git commit -m "feat: SymbolResolver — 语句节点遍历 (if/while/for/match/return) + scope chain 查找"
```

---

## Chunk 3: 调用图 + 信号图

> **目标：** 实现完整的 CallGraph（6 种调用模式检测）和 SignalGraph（emit/connect 检测），包括 `self.hp = 10` 的 AttributeNode 特殊处理。

### Task 5: 实现 _resolve_call — 6 种调用模式检测

**Files:** Modify: `addons/gdscript_util/gds_symbol_resolver.gd` (追加)

- [ ] **Step 1: 实现 _resolve_call 主流程 — 参数解析 + 调用类型分发**

```gdscript
# 解析函数调用 — 6 种调用模式检测
func _resolve_call(p_node, p_scope: SymbolTable, p_current_function: String):
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
		if sym != null and sym.kind == Symbol.Kind.FUNCTION:
			_add_call_edge(p_current_function, callee.name, callee.line, CallEdge.CallType.SELF, "", p_node.arguments)
		# 否则可能是内置函数 (print, range 等) — 不记录 CallEdge

	# 模式 2: 属性调用 — self.foo() / obj.method() / super.foo() / sig.connect() / sig.emit()
	elif callee is GDScriptToken.AttributeNode:
		_resolve_attribute_call(p_node, callee, p_scope, p_current_function)


# 属性调用分析 — AttributeNode(callee) 的 7 种子模式
func _resolve_attribute_call(p_call_node, p_attr, p_scope: SymbolTable, p_current_function: String):
	var base = p_attr.base
	var method_name = p_attr.name

	# 2a: self.method() → SELF
	if base is GDScriptToken.SelfNode:
		_add_call_edge(p_current_function, method_name, p_attr.line, CallEdge.CallType.SELF, "", p_call_node.arguments)

	# 2b: super.method() → SUPER
	elif base is GDScriptToken.SuperNode:
		_add_call_edge(p_current_function, method_name, p_attr.line, CallEdge.CallType.SUPER, "", p_call_node.arguments)

	# 2c: signal_name.connect(cb) → SIGNAL_CONNECT 或 LAMBDA
	elif method_name == "connect" and base is GDScriptToken.IdentifierNode:
		_resolve_signal_connect(p_call_node, base.name, p_scope, p_current_function)

	# 2d: obj.connect("sig", cb) → CONNECT（base 不是 IdentifierNode 或 base 是但非信号名）
	elif method_name == "connect":
		_resolve_object_connect(p_call_node, p_scope, p_current_function)

	# 2e: signal_name.emit() → EMIT
	elif method_name == "emit" and base is GDScriptToken.IdentifierNode:
		_resolve_signal_emit(p_call_node, base.name, p_current_function, "dot_emit")

	# 2f: obj.method() → EXTERNAL
	elif base is GDScriptToken.IdentifierNode:
		_add_call_edge(p_current_function, method_name, p_attr.line, CallEdge.CallType.EXTERNAL, base.name, p_call_node.arguments)

	# 2g: 链式调用 a.b.method() 或 ClassName.method() — [Phase 3] STATIC 调用
```

- [ ] **Step 2: 实现 emit 检测逻辑**

```gdscript
# emit("signal_name") 形式 — 已在 _resolve_call 中通过 callee.name == "emit" 触发
func _resolve_emit_call(p_node, p_current_function: String):
	if p_node.arguments.size() > 0 and p_node.arguments[0] is GDScriptToken.LiteralNode:
		var sig_name = str(p_node.arguments[0].value)
		# 记录 emit_site
		var info = result.signal_graph.get_signal_flow(sig_name)
		if info == null:
			# 未声明的信号 — 创建临时 SignalInfo
			info = SignalInfo.new()
			info.name = sig_name
			result.signal_graph.signals[sig_name] = info
			result.add_error("[SymbolResolver] %d: 信号 '%s' 未声明，通过 emit() 发射" % [p_node.line, sig_name])
		info.emit_sites.append(_make_site(p_node, p_current_function, p_node.arguments))
		# 同时记录为 EMIT 类型的 CallEdge
		_add_call_edge(p_current_function, sig_name, p_node.callee.line, CallEdge.CallType.EMIT, "", p_node.arguments)


# signal_name.emit() 形式 — 从 _resolve_attribute_call 调用
func _resolve_signal_emit(p_call_node, p_signal_name: String, p_current_function: String, p_form: String):
	var info = result.signal_graph.get_signal_flow(p_signal_name)
	if info == null:
		info = SignalInfo.new()
		info.name = p_signal_name
		result.signal_graph.signals[p_signal_name] = info
		result.add_error("[SymbolResolver] %d: 信号 '%s' 未声明，通过 .emit() 发射" % [p_call_node.line, p_signal_name])
	info.emit_sites.append(_make_site(p_call_node, p_current_function, p_call_node.arguments))
	_add_call_edge(p_current_function, p_signal_name, p_call_node.callee.line, CallEdge.CallType.EMIT, "", p_call_node.arguments)
```

- [ ] **Step 3: 实现 connect 检测逻辑**

```gdscript
# signal_name.connect(cb/lambda) 形式
func _resolve_signal_connect(p_call_node, p_signal_name: String, p_scope: SymbolTable, p_current_function: String):
	var info = result.signal_graph.get_signal_flow(p_signal_name)
	if info == null:
		info = SignalInfo.new()
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
			_add_call_edge(p_current_function, cb.name, p_call_node.callee.line, CallEdge.CallType.SIGNAL_CONNECT, p_signal_name, p_call_node.arguments)
		elif cb is GDScriptToken.LambdaNode:
			# signal_name.connect(lambda) → LAMBDA
			_add_call_edge(p_current_function, "<lambda@%d>" % cb.line, p_call_node.callee.line, CallEdge.CallType.LAMBDA, p_signal_name, p_call_node.arguments)
			# 同时解析 lambda（其 captured_vars 提供闭包上下文）
			_resolve_lambda(cb, p_scope, p_current_function)


# obj.connect("signal_name", cb) 形式
func _resolve_object_connect(p_call_node, p_scope: SymbolTable, p_current_function: String):
	if p_call_node.arguments.size() >= 1 and p_call_node.arguments[0] is GDScriptToken.LiteralNode:
		var sig_name = str(p_call_node.arguments[0].value)

		# 记录 connect_site（可能是未声明的外部信号）
		var info = result.signal_graph.get_signal_flow(sig_name)
		if info == null:
			info = SignalInfo.new()
			info.name = sig_name
			result.signal_graph.signals[sig_name] = info
		info.connect_sites.append(_make_site(p_call_node, p_current_function, p_call_node.arguments))

		# 判断回调
		if p_call_node.arguments.size() >= 2:
			var cb = p_call_node.arguments[1]
			if cb is GDScriptToken.IdentifierNode:
				_add_call_edge(p_current_function, cb.name, p_call_node.callee.line, CallEdge.CallType.CONNECT, sig_name, p_call_node.arguments)
			elif cb is GDScriptToken.LambdaNode:
				_add_call_edge(p_current_function, "<lambda@%d>" % cb.line, p_call_node.callee.line, CallEdge.CallType.LAMBDA, sig_name, p_call_node.arguments)
				_resolve_lambda(cb, p_scope, p_current_function)
```

- [ ] **Step 4: 提交**

```bash
git add addons/gdscript_util/gds_symbol_resolver.gd
git commit -m "feat: SymbolResolver — CallGraph 6 种调用模式 + SignalGraph emit/connect 检测"
```

---

### Task 6: self.hp = 10 的 AttributeNode 特殊处理

**Files:** Modify: `addons/gdscript_util/gds_symbol_resolver.gd` (追加)

> `self.hp = 10` 的 AST 结构是 `AssignmentNode(target=AttributeNode(base=SelfNode, name="hp"), value=LiteralNode(10))`。target 是 AttributeNode 时，需要区分：属性访问是 READ（读取对象引用）+ 属性名 WRITE（但不在当前文件变量追踪范围）。

- [ ] **Step 1: 实现 _resolve_assignment（含 AttributeNode 特殊处理）**

```gdscript
# 解析赋值语句 — 区分 target 形态
func _resolve_assignment(p_node, p_scope: SymbolTable, p_current_function: String):
	# 先解析 value 侧的表达式（所有标识符为 READ）
	_resolve_expression(p_node.value, p_scope, p_current_function)

	# 再解析 target 侧的标识符
	if p_node.target is GDScriptToken.IdentifierNode:
		# x = value → x 是 WRITE（或 READ_WRITE 若复合赋值）
		var access = DefUseSite.AccessType.WRITE if p_node.op == GDScriptToken.Type.EQUAL else DefUseSite.AccessType.READ_WRITE
		_record_def_use(p_node.target.name, p_node.target, p_current_function, access)

	elif p_node.target is GDScriptToken.AttributeNode:
		# a.b = value → a 是 READ（读取对象引用，未修改 a 本身）
		# 但 b 是对象属性写入，不在当前文件的变量追踪范围内
		var base = p_node.target.base

		# self.hp = 10 → self 是 SelfNode，不需要追踪
		# obj.hp = 10 → obj 是 IdentifierNode，记录 READ
		if base is GDScriptToken.IdentifierNode:
			_record_def_use(base.name, base, p_current_function, DefUseSite.AccessType.READ)
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
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_symbol_resolver.gd
git commit -m "feat: SymbolResolver — AssignmentNode 解析含 self.hp=10 的 AttributeNode 特殊处理"
```

---

## Chunk 4: DefUse + Lambda 捕获

> **目标：** 完善 DefUseChain 全量追踪 + Lambda 闭包捕获变量检测。

### Task 7: 完善 DefUseChain 追踪逻辑

**Files:** Modify: `addons/gdscript_util/gds_symbol_resolver.gd` (追加)

DefUse 追踪的核心已经在之前各 `_resolve_*` 方法中通过 `_record_def_use()` 实现。本 Task 完善以下边界场景：

- [ ] **Step 1: 确认所有 DEFINE 场景已被覆盖**

检查清单 — 以下场景均需记录 DEFINE：

| 场景 | 位置 | 已实现？ |
|------|------|---------|
| var/const 变量 | `_resolve_variable()` | ✅ Task 3 Step 3 |
| 函数参数 | `_resolve_function()` | ✅ Task 3 Step 2 |
| Lambda 参数 | `_resolve_lambda()` | → Task 8 |
| for 循环变量 | `_resolve_for()` | ✅ Task 4 Step 2 |

- [ ] **Step 2: 确认所有 READ 场景已被覆盖**

检查清单 — 以下场景均需记录 READ：

| 场景 | 位置 | 已实现？ |
|------|------|---------|
| 表达式中的 IdentifierNode | `_resolve_identifier_read()` → `_resolve_expression()` | ✅ Task 4 Step 4 |
| CallNode 参数中的标识符 | `_resolve_call()` → `_resolve_expression(arg)` | ✅ Task 5 Step 1 |
| 变量初始化器中的标识符 | `_resolve_variable()` → `_resolve_expression(init)` | ✅ Task 3 Step 3 |
| if/while/match 条件中的标识符 | `_resolve_if/while/match` → `_resolve_expression(cond)` | ✅ Task 4 |
| return 返回值中的标识符 | `_resolve_return()` → `_resolve_expression(val)` | ✅ Task 4 Step 3 |
| for iterable 中的标识符 | `_resolve_for()` → `_resolve_expression(iter)` | ✅ Task 4 Step 2 |
| assert 条件中的标识符 | `_resolve_node(AssertNode)` → `_resolve_expression` | ✅ Task 2 Step 3 |
| AttributeNode.base 中的标识符 | `_resolve_expression(AttributeNode)` → `_resolve_expression(base)` | ✅ Task 2 Step 3 |

- [ ] **Step 3: 确认所有 WRITE 场景已被覆盖**

检查清单 — 以下场景均需记录 WRITE/READ_WRITE：

| 场景 | 位置 | 已实现？ |
|------|------|---------|
| AssignmentNode 的 IdentifierNode target | `_resolve_assignment()` | ✅ Task 6 Step 1 |
| AssignmentNode 的 AttributeNode target (base 的 READ) | `_resolve_assignment()` | ✅ Task 6 Step 1 |
| 复合赋值 (+=, -= 等) | `_resolve_assignment()` (READ_WRITE) | ✅ Task 6 Step 1 |

- [ ] **Step 4: 提交（如无新增代码则跳过）**

```bash
# 本 Task 为审查确认性质，不新增代码
# 若发现遗漏场景则补充后提交
```

---

### Task 8: Lambda 闭包捕获变量检测

**Files:** Modify: `addons/gdscript_util/gds_symbol_resolver.gd` (追加)

- [ ] **Step 1: 实现 _resolve_lambda — 创建 lambda_scope + define 参数 + 捕获检测**

```gdscript
# 解析 Lambda 表达式 — 创建 lambda_scope (parent = 当前作用域)
func _resolve_lambda(p_node, p_parent_scope: SymbolTable, p_current_function: String):
	# 创建 lambda_scope
	var lambda_scope = SymbolTable.new()
	lambda_scope.parent = p_parent_scope
	lambda_scope.scope_name = "lambda@%d" % p_node.line

	# define lambda 参数到 lambda_scope
	for param in p_node.params:
		if param is GDScriptToken.ParameterNode:
			lambda_scope.define(param.name, Symbol.Kind.PARAMETER, param, _type_to_string(param.datatype))
			_record_def_use(param.name, param, p_current_function, DefUseSite.AccessType.DEFINE)

	# 遍历 lambda body — 传入 p_node 自身用于捕获检测
	_resolve_suite(p_node.body, lambda_scope, p_current_function, p_node)


# Lambda 中的标识符解析 — 区分局部变量 vs 捕获变量
func _resolve_identifier_in_lambda(p_node, p_lambda_scope: SymbolTable, p_lambda_node, p_current_function: String):
	# 先检查 lambda 自己的局部作用域（参数）
	var local = p_lambda_scope.resolve_local(p_node.name)
	if local != null:
		# lambda 局部变量（参数）— 正常记录 READ
		_record_def_use(p_node.name, p_node, p_current_function, DefUseSite.AccessType.READ)
		return

	# 不在 lambda 局部 → 向父作用域查找（resolve 自动递归到 parent）
	var sym = p_lambda_scope.resolve(p_node.name)
	if sym != null:
		# 这是捕获变量！记录到 LambdaNode.captured_vars
		if p_lambda_node.captured_vars.find(p_node.name) == -1:
			p_lambda_node.captured_vars.append(p_node.name)
		_record_def_use(p_node.name, p_node, p_current_function, DefUseSite.AccessType.READ)
		return

	# 完全未解析 — 可能是内置函数/全局引用
```

- [ ] **Step 2: 处理单行 Lambda 的 return 解包**

```gdscript
# Lambda body 单行 return 已被 Phase 1 解包
# var f = func(x): return x * 2  → LambdaNode(body=BinaryOpNode(x * 2))
# _resolve_suite() 已处理 body 是 ExpressionNode 的情况（调用 _resolve_expression）
# 但需确保传递给 _resolve_expression 的 p_lambda_node 参数正确传递

# 在 _resolve_expression 中递归处理时，保持 lambda_node 传递:
# _resolve_expression(p_expr.left, p_scope, p_current_function, p_lambda_node)
# 这样 BinaryOpNode 中的 IdentifierNode 解析会触发 lambda 捕获检测
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/gds_symbol_resolver.gd
git commit -m "feat: SymbolResolver — Lambda 闭包捕获变量检测 + captured_vars 填充"
```

---

## Chunk 5: EditorPlugin 集成 + 验收测试

> **目标：** 扩展 `plugin.gd` 添加 `resource_saved` 自动分析 + Phase 2 管道调用 + 分析摘要输出。编写 10 个验收测试。

### Task 9: 扩展 plugin.gd — resource_saved 集成 + Phase 2 管道

**Files:** Modify: `addons/gdscript_util/plugin.gd`

- [ ] **Step 1: 添加 resource_saved 信号 + 分析缓存 + Phase 2 管道**

```gdscript
@tool
extends EditorPlugin

var analysis_cache: Dictionary = {}  # String(path) → GDScriptAnalysisResult


func _enter_tree():
	add_tool_menu_item("GDScript Analysis – Parse Current", _on_parse_current)
	# Phase 2: 注册 resource_saved 信号实现自动分析
	resource_saved.connect(_on_resource_saved)
	print("[GDScriptUtil v2.0] Plugin loaded — Phase 2: Symbol Analysis")


func _exit_tree():
	remove_tool_menu_item("GDScript Analysis – Parse Current")
	resource_saved.disconnect(_on_resource_saved)
	analysis_cache.clear()
	print("[GDScriptUtil v2.0] Plugin unloaded")


# Phase 2 新增: 脚本保存时自动分析
func _on_resource_saved(p_resource: Resource):
	if p_resource is GDScript and p_resource.resource_path.ends_with(".gd"):
		_analyze_script(p_resource.resource_path)
```

- [ ] **Step 2: 升级 _on_parse_current 使用 Phase 2 管道**

```gdscript
func _on_parse_current():
	var editor = get_editor_interface()
	var script_editor = editor.get_script_editor()
	var current = script_editor.get_current_script()
	if current == null:
		print("[GDScriptUtil] No script open")
		return

	var source = current.source_code
	if source == "":
		print("[GDScriptUtil] Empty script")
		return

	# Phase 1 pipeline
	var tokenizer = GDScriptTokenizer.new()
	var tokens = tokenizer.tokenize(source)

	var parser = GDScriptParser.new()
	var ast = parser.parse(tokens)

	if parser.error != "":
		printerr("[GDScriptUtil] Parse error: %s" % parser.error)
		return

	# Phase 2 pipeline — 符号解析
	var resolver = GDScriptSymbolResolver.new()
	var result = resolver.resolve(ast, current.resource_path)
	analysis_cache[current.resource_path] = result

	# 输出分析摘要
	_print_analysis_summary(result)
```

- [ ] **Step 3: 实现 _analyze_script 和 _print_analysis_summary**

```gdscript
# Phase 2 分析函数（resource_saved 调用）
func _analyze_script(p_path: String) -> GDScriptAnalysisResult:
	var script = load(p_path) as GDScript
	if script == null:
		return null

	var source = script.source_code
	if source == "":
		return null

	# Phase 1 管道
	var tokenizer = GDScriptTokenizer.new()
	var tokens = tokenizer.tokenize(source)
	var parser = GDScriptParser.new()
	var ast = parser.parse(tokens)

	if parser.error != "":
		push_warning("[GDScriptUtil] Parse error in %s: %s" % [p_path, parser.error])
		return null

	# Phase 2 符号解析
	var resolver = GDScriptSymbolResolver.new()
	var result = resolver.resolve(ast, p_path)

	# 缓存结果
	analysis_cache[p_path] = result

	# 静默分析（resource_saved 触发时不输出摘要，避免刷屏）
	# 仅在手动触发时输出摘要
	return result


# 分析摘要输出
func _print_analysis_summary(p_result: GDScriptAnalysisResult):
	var func_count = p_result.get_all_functions().size()
	var sig_count = p_result.get_all_signals().size()
	var var_count = p_result.def_use_chain.variables.size()

	print("[GDScriptUtil] %s — %d functions, %d signals, %d variables, %d calls, %d errors" % [
		p_result.file_path,
		func_count,
		sig_count,
		var_count,
		p_result.call_graph.edges.size(),
		p_result.errors.size()
	])

	# 输出错误
	for err in p_result.errors:
		push_warning(err)

	# 输出调用图摘要
	if p_result.call_graph.edges.size() > 0:
		print("  Call Graph:")
		for edge in p_result.call_graph.edges:
			var type_str = _call_type_to_string(edge.call_type)
			print("    %s() →%s %s() @line %d" % [edge.caller, type_str, edge.callee, edge.site_line])

	# 输出信号流摘要
	if p_result.signal_graph.signals.size() > 0:
		print("  Signal Flow:")
		for sig_name in p_result.signal_graph.signals:
			var info = p_result.signal_graph.signals[sig_name]
			var decl_line = info.declaration.line if info.declaration != null else "?"
			print("    signal %s (decl @%s): %d emits, %d connects" % [
				sig_name, decl_line, info.emit_sites.size(), info.connect_sites.size()
			])


func _call_type_to_string(p_type: int) -> String:
	match p_type:
		CallEdge.CallType.SELF: return "[self]"
		CallEdge.CallType.SUPER: return "[super]"
		CallEdge.CallType.EXTERNAL: return "[ext]"
		CallEdge.CallType.CONNECT: return "[connect]"
		CallEdge.CallType.SIGNAL_CONNECT: return "[sig-conn]"
		CallEdge.CallType.LAMBDA: return "[lambda]"
		CallEdge.CallType.EMIT: return "[emit]"
		_: return "[?]"
```

- [ ] **Step 4: 提交**

```bash
git add addons/gdscript_util/plugin.gd
git commit -m "feat: EditorPlugin Phase 2 集成 — resource_saved 自动分析 + 分析摘要输出"
```

---

### Task 10: 验收测试 — 10 个测试用例

**Files:** Create: `tests/test_symbol_resolver.gd`

- [ ] **Step 1: 创建测试框架 + 辅助函数**

```gdscript
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
```

- [ ] **Step 2: 实现 Test 1-5**

```gdscript
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
```

- [ ] **Step 3: 实现 Test 6-10**

```gdscript
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
```

- [ ] **Step 4: 提交**

```bash
git add tests/test_symbol_resolver.gd
git commit -m "test: Phase 2 验收测试 — 10 个测试用例验证符号分析"
```

---

## 完成检查清单

- [ ] `gds_analysis_result.gd` — 全部数据结构：SymbolTable, Symbol, CallGraph, CallEdge, SignalGraph, SignalInfo, Site, DefUseChain, DefUseInfo, DefUseSite, GDScriptAnalysisResult
- [ ] `gds_symbol_resolver.gd` — 完整 Visitor：resolve() 入口 + 全部 _resolve_* 方法 + 辅助方法
- [ ] `plugin.gd` — resource_saved 信号连接 + Phase 2 管道 + 分析摘要输出
- [ ] 符号表：嵌套作用域链正确（ClassScope → FuncScope → LambdaScope / 语句不创建作用域）
- [ ] const/var 区分：方案 A（源码行检测 `begins_with("const")`）已实现
- [ ] `self.hp = 10` AttributeNode 特殊处理已覆盖
- [ ] CallGraph：6 种调用模式检测全部正确
- [ ] SignalGraph：emit/connect 检测 + 未声明信号临时 SignalInfo
- [ ] DefUseChain：DEFINE/READ/WRITE/READ_WRITE 全量追踪
- [ ] Lambda 捕获：captured_vars 正确填充到 LambdaNode
- [ ] 10 个验收测试用例全部通过
- [ ] resolve() 在任意有效 AST 输入下不崩溃
- [ ] 所有错误记录到 result.errors，不通过 push_error/printerr 输出（仅 plugin.gd 汇总输出）
- [ ] 不修改 Phase 1 代码（gds_ast_nodes.gd / gds_tokenizer.gd / gds_parser.gd）

---

## 关键设计决策记录

### 决策 1: const/var 区分 — 采用方案 A

**背景:** Phase 1 的 `_parse_const()` 和 `_parse_variable()` 都返回 `VariableNode`，无独立 ConstNode 类型。

**方案 A（采用）:** 在 `resolve()` 入口预加载源码行，对每个 `VariableNode` 检查对应行是否以 `const` 开头。

```gdscript
# 实现位置: gds_symbol_resolver.gd → _preprocess_const_vars()
# 核心逻辑:
var line_text = result._source_lines[member.line - 1].strip_edges()
if line_text.begins_with("const"):
    _const_set[member] = true
```

**方案 B（Phase 3 备选）:** 在 `VariableNode` 添加 `is_const: bool` 字段，由 Parser 设置。更干净但需修改 Phase 1 代码。

### 决策 2: self.hp = 10 的 AttributeNode 处理

**背景:** `self.hp = 10` 的 AST 是 `AssignmentNode(target=AttributeNode(base=SelfNode, name="hp"), ...)`。target 是 AttributeNode 时，base=SelfNode 不需要变量追踪，但 `obj.hp = 10` 中 `obj`（IdentifierNode）需要记录 READ。

**处理:** 在 `_resolve_assignment()` 中按 base 类型分发：
- `base` 是 `SelfNode` / `SuperNode` → 不追踪
- `base` 是 `IdentifierNode` → 记录 READ（读取了 obj 的引用）
- `base` 是 `AttributeNode` / `CallNode` → 递归解析

### 决策 3: 不修改 Phase 1 代码

Phase 2 严格遵循"读取但不修改"原则。所有 AST 节点通过 `GDScriptToken.ClassName` 全限定名引用。新增文件仅两个：`gds_analysis_result.gd` 和 `gds_symbol_resolver.gd`。仅扩展 `plugin.gd`。

### 决策 4: GDScript 无块级作用域

与 Python 不同，GDScript 不支持块级作用域（`if`/`for`/`while`/`match` 中声明的变量提升到所在函数作用域）。SymbolResolver 仅在以下节点创建新作用域：
- `ClassNode`（类成员作用域）
- `FunctionNode`（函数参数 + 局部变量作用域）
- `LambdaNode`（闭包作用域）
- 内嵌 `ClassNode`（嵌套类作用域）

### 决策 5: 未解析标识符不报错

由于 Phase 2 没有内置函数列表（Phase 3 引入），`resolve(name)` 返回 null 时不记录错误——可能是 `print`、`range` 等内置函数。仅在 `emit()` 使用未声明信号时记录 warning。

---

## 完成检查清单

- [x] `gds_analysis_result.gd` — 统一结果容器 + 查询 API
- [x] `gds_symbol_resolver.gd` — AST Visitor 符号解析器（~600行）
- [x] `plugin.gd` — Phase 2 集成（resource_saved 自动分析 + 摘要输出）
- [x] `tests/test_symbol_resolver.gd` — 10 个验收测试用例全部通过
- [x] `gds_symbol.gd` 等 10 个独立数据类文件
- [x] `gds_self_node.gd` / `gds_super_node.gd` — Self/Super AST 节点
- [x] LSP 零错误
- [x] 分支：`master`

---

## 与实际实现的差异

以下差异源于 Godot 4.7 GDScript 运行时限制，在 Phase 2 验收过程中发现并修复。

### 1. 数据类架构

| 项目 | 计划 | 实际 |
|------|------|------|
| 数据类定义 | 10 个内部类定义在 `gds_analysis_result.gd` 中 | 10 个独立 `class_name` 文件 |
| 原因 | — | 内部类 `is` 运算符运行时失效；内部类方法（`CallGraph.add_edge`）跨文件调用静默失败 |
| 修复提交 | — | `7487b3a` + `49b2d24` |

### 2. AST 节点类型

| 项目 | 计划 | 实际 |
|------|------|------|
| SelfNode/SuperNode | `GDScriptToken` 内部类，`extends ASTNode` | 独立 `class_name GDScriptSelfNode`/`GDScriptSuperNode`，`extends RefCounted` |
| 原因 | — | `is GDScriptToken.SelfNode` 运行时返回 false；内部类继承内部类链断裂 |
| 修复提交 | — | `7487b3a` |

### 3. 方法调用图 — 前向引用

| 项目 | 计划 | 实际 |
|------|------|------|
| 隐式 self 调用检测 | `if sym != null and sym.kind == FUNCTION:` | `if sym == null or sym.kind == FUNCTION:` |
| 原因 | — | 解析 `foo()` 时 `bar()` 定义在后面，`sym == null` 导致调用边跳过 |
| 影响 | — | Test 2 (`bar()` 隐式调用) FAIL |
| 修复提交 | — | `6353de2` |

### 4. connect 路由

| 项目 | 计划 | 实际 |
|------|------|------|
| connect 匹配顺序 | 先 `signal.connect(cb)` 后 `obj.connect("sig", cb)` | 先 `obj.connect("sig", cb)` 后 `signal.connect(cb)` |
| 原因 | — | `$AnimationPlayer.connect("finished", cb)` 的 base 是 `IdentifierNode("$AnimationPlayer")`，被误匹配为 `signal.connect` |
| 修复提交 | — | `4209f93` |

### 5. 表达式解析

| 项目 | 计划 | 实际 |
|------|------|------|
| `_resolve_expression` | 无 `AssignmentNode` 分支 | 新增 `AssignmentNode` → `_resolve_assignment` |
| 原因 | — | `hp -= amount` 被 `ExpressionStatementNode` 包裹后走 `_resolve_expression`，AssignmentNode 被忽略 |
| 修复提交 | — | `4209f93` |

### 6. 其他 Bug 修复

| Bug | 症状 | 修复 |
|-----|------|------|
| `class_name` 位置错误 | LSP: "Unexpected class_name in class body" | `class_name` 移到文件顶部 |
| `class_name` 作变量名 | LSP: "Unexpected class_name in class body" | `var class_name` → `var classname_id` |
| 内部类返回类型 | LSP: "Could not find type Site" | `-> Site:` → `-> GDScriptAnalysisResult.Site:` |
| 内部类参数类型 | LSP: "Could not find type SymbolTable" | `: SymbolTable` → `: GDScriptAnalysisResult.SymbolTable` |

### 7. 文件结构差异

| 计划 | 实际 |
|------|------|
| `gds_analysis_result.gd`（含 10 个内部类） | `gds_analysis_result.gd`（容器类）+ 10 个独立 `.gd` 文件 |
| 2 个新增文件 | 14 个新增文件 |
| — | `gds_self_node.gd` + `gds_super_node.gd`（Phase 1 残留问题） |
