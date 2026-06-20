# addons/gdscript_util/gds_analysis_result.gd
# Phase 2 符号解析器 — 全部数据结构定义 + 结果容器
# 纯数据定义，零业务逻辑（查询 API 除外）

# ---- Symbol — 符号表中的单个符号 ----

class_name GDScriptAnalysisResult
extends RefCounted
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


# ---- GDScriptAnalysisResult — 统一结果容器 ----

var file_path: String = ""
var classname_id: String = ""             # class_name 声明的类名
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
		"class_name": classname_id,
	}

# 添加错误
func add_error(p_msg: String):
	errors.append(p_msg)
