# Phase 2: GDScript 符号解析器 设计规范

> 日期: 2026-06-20 | 状态: Phase 2 规划 | 依赖: Phase 1 (已完成 ✅)

## 一、目标与范围

### 1.1 目标

在 Phase 1 的 AST 管道之上，构建符号分析和逻辑流图能力。Phase 2 完成后可回答以下问题：

- "这个信号在哪里发射？谁连接了它？"
- "`take_damage()` 被哪些函数调用？"
- "变量 `hp` 在哪些位置被读写？"
- "这个 lambda 捕获了哪些外部变量？"

### 1.2 范围

**Phase 2 做：**

1. **SymbolTable** — 嵌套作用域符号表，支持 scope chain 查找
2. **CallGraph** — 方法调用图，覆盖 6 种调用模式
3. **SignalGraph** — 信号流程图：声明 → emit 发射点 → connect 连接点
4. **DefUseChain** — 变量定义-使用链：每个变量的 def/read/write 位置集合
5. **Lambda 闭包捕获** — 检测 lambda 捕获的外部变量，填入 `LambdaNode.captured_vars`
6. **GDScriptAnalysisResult** — 统一结果容器 + 查询 API
7. **EditorPlugin `resource_saved` 集成** — 脚本保存时自动重新分析
8. **验收测试** — 10 个具体测试用例验证符号分析正确性

**Phase 2 不做（Phase 3 扩展）：**

- 跨文件调用追踪（涉及 `extends` 链和 `preload` 的外部文件解析）
- 类型推断/类型检查（仅记录声明的类型标注，不做类型推导）
- `match` 模式中的变量绑定分析（`when` 分支引入的局部变量）
- 控制流分析（可达性、死代码检测）
- 可视化 UI 面板
- `namespace`、`trait` 等 Phase 3 语法的符号解析

### 1.3 与 Phase 1 的关系

```
Phase 1 输入: .gd 源码文本
Phase 1 输出: ClassNode (AST 根)
                   │
                   ▼ Phase 2 输入
Phase 2 输出: GDScriptAnalysisResult {
    ast, symbol_table, call_graph,
    signal_graph, def_use_chain, errors
}
```

Phase 2 不修改 Phase 1 的任何代码。它只读取 Phase 1 产出的 AST 节点类型（定义在 `gds_ast_nodes.gd` 中）。

## 二、组件设计：GDScriptSymbolResolver

### 2.1 入口与签名

```gdscript
class_name GDScriptSymbolResolver
extends RefCounted

func resolve(p_ast: GDScriptToken.ClassNode, p_file_path: String = "") -> GDScriptAnalysisResult:
    # 1. 创建 result 容器
    # 2. _resolve_class(p_ast) → 遍历 AST 构建符号表+图
    # 3. 返回 result
```

`resolve()` 是两个 Phase 的阶段边界——Phase 1 产出的 `ClassNode` 作为输入，Phase 3 的 EditorPlugin 消费 `GDScriptAnalysisResult`。

### 2.2 内部遍历架构

Resolver 以 **Visitor 模式** 递归遍历 AST。核心是一个 `_resolve_node(node, scope, current_function)` 方法，按节点类型分发：

```gdscript
func _resolve_node(p_node, p_scope: SymbolTable, p_current_function: String):
    match p_node.get_class():
        "ClassNode":      _resolve_class(p_node, p_scope)
        "FunctionNode":   _resolve_function(p_node, p_scope)
        "VariableNode":   _resolve_variable(p_node, p_scope, p_current_function)
        "SignalNode":     _resolve_signal(p_node, p_scope)
        "EnumNode":       _resolve_enum(p_node, p_scope)
        "SuiteNode":      _resolve_suite(p_node.body, p_scope, p_current_function)
        "IfNode":         _resolve_if(p_node, p_scope, p_current_function)
        "WhileNode":      _resolve_while(p_node, p_scope, p_current_function)
        "ForNode":        _resolve_for(p_node, p_scope, p_current_function)
        "MatchNode":      _resolve_match(p_node, p_scope, p_current_function)
        "ReturnNode":     _resolve_return(p_node, p_scope, p_current_function)
        "AssignmentNode": _resolve_assignment(p_node, p_scope, p_current_function)
        "CallNode":       _resolve_call(p_node, p_scope, p_current_function)
        "LambdaNode":     _resolve_lambda(p_node, p_scope, p_current_function)
        "IdentifierNode": _resolve_identifier_read(p_node, p_scope, p_current_function)
        # ... 其他语句/表达式节点递归处理子节点
```

其中 `p_current_function` 是当前所在函数的名称（如 `"take_damage"`），用于 CallGraph 和 DefUseChain 的上下文标注。顶层变量/常量使用 `"<class>"` 作为上下文。

### 2.3 文件规划

| 文件 | class_name | 预估行数 | 职责 |
|------|-----------|---------|------|
| `gds_symbol_resolver.gd` | GDScriptSymbolResolver | ~550 | AST 遍历 + 符号表/图构建 |
| `gds_analysis_result.gd` | GDScriptAnalysisResult + 数据类 | ~350 | 结果容器 + 所有图/表数据结构 + 查询 API |

两个文件均位于 `addons/gdscript_util/` 目录下。

## 三、核心数据结构

所有数据结构类均继承 `RefCounted`，定义在 `gds_analysis_result.gd` 中。

### 3.1 SymbolTable — 嵌套作用域符号表

```gdscript
class_name SymbolTable
extends RefCounted

var parent: SymbolTable           # 外层作用域 (null 表示根作用域)
var symbols: Dictionary = {}      # String → Symbol
var scope_name: String = ""       # 作用域描述: "class:Player", "func:take_damage", "lambda@12"

func define(p_name: String, p_kind: int, p_node, p_datatype: String = "") -> Symbol:
    var sym = Symbol.new()
    sym.name = p_name
    sym.kind = p_kind
    sym.declaration = p_node
    sym.datatype = p_datatype
    symbols[p_name] = sym
    return sym

func resolve(p_name: String) -> Symbol:
    # 先在当前作用域查找
    if symbols.has(p_name):
        return symbols[p_name]
    # 递归向 parent 查找
    if parent != null:
        return parent.resolve(p_name)
    return null

func resolve_local(p_name: String) -> Symbol:
    # 仅在当前作用域查找（不递归）
    return symbols.get(p_name, null)
```

**查找优先级链**（由嵌套 Scope 的自然 parent 链实现）：

```
局部作用域 (函数内 if/for/while 块)
  → 函数作用域 (函数参数 + 函数内 var)
    → Lambda 闭包作用域
      → 类成员作用域 (var/const/signal/enum/class)
        → [Phase 3] 内置函数作用域 (print, range, ...)
          → [Phase 3] 全局单例作用域
```

注意：GDScript 不支持块级作用域（`if`/`for`/`while` 中声明的变量提升到所在函数作用域）。与 Python 不同，GDScript 的缩进块不创建新的变量作用域。因此 SymbolResolver 的 `local_scope` 创建规则：

- **创建新作用域**：ClassNode（类成员）、FunctionNode（函数参数+局部变量）、LambdaNode（闭包作用域）、inner ClassNode（嵌套类）
- **不创建新作用域**：SuiteNode、IfNode、WhileNode、ForNode、MatchNode 的 body

```gdscript
class_name Symbol
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

### 3.2 CallGraph — 方法调用图

```gdscript
class_name CallGraph
extends RefCounted

var edges: Array[CallEdge] = []

func get_callers_of(p_func_name: String) -> Array[CallEdge]:
    # 返回所有 callee == p_func_name 的边
    var result: Array[CallEdge] = []
    for e in edges:
        if e.callee == p_func_name:
            result.append(e)
    return result

func get_callees_of(p_func_name: String) -> Array[CallEdge]:
    # 返回所有 caller == p_func_name 的边
    var result: Array[CallEdge] = []
    for e in edges:
        if e.caller == p_func_name:
            result.append(e)
    return result


class_name CallEdge
extends RefCounted

enum CallType {
    SELF = 0,            # self.method() 或隐式 self 调用 (foo())
    SUPER = 1,           # super.method()
    EXTERNAL = 2,        # obj.method() —— 外部对象调用
    CONNECT = 3,         # .connect("sig", cb) 中的回调 — cb 是函数名
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
```

**6 种调用模式的 AST 检测规则：**

| # | 源码模式 | AST 结构 | call_type | 说明 |
|---|---------|---------|-----------|------|
| 1 | `self.foo()` | `CallNode(callee=AttributeNode(base=SelfNode, name="foo"))` | `SELF` | 显式 self 调用 |
| 2 | `foo()` | `CallNode(callee=IdentifierNode("foo"))` | `SELF` | 隐式 self — resolve 到当前类方法 |
| 3 | `super.method()` | `CallNode(callee=AttributeNode(base=SuperNode, name="method"))` | `SUPER` | 父类方法调用 |
| 4 | `obj.method()` | `CallNode(callee=AttributeNode(base=IdentifierNode("obj"), name="method"))` | `EXTERNAL` | 外部对象调用，target_object="obj" |
| 5 | `.connect("sig", cb)` | `CallNode(callee=AttributeNode(base=?, name="connect"))` | `CONNECT` / `SIGNAL_CONNECT` / `LAMBDA` | 见 §4.3 信号解析 |
| 6 | `ClassName.static_func()` | `CallNode(callee=AttributeNode(base=IdentifierNode("ClassName"), name="static_func"))` | `STATIC` | [Phase 3] 跨文件时识别为静态调用 |

**调用方上下文判断** — `caller` 字段填充规则：
- 若调用发生在函数体内 → `caller = "take_damage"`（当前函数名）
- 若调用发生在变量初始化器 / lambda 内 → `caller = "<class>"` 或所在函数名
- 若调用发生在顶层（不在任何函数内）→ `caller = "<class>"`

**内置函数处理：**
- Godot 内置函数（`print`, `range`, `push_error` 等）不在 SymbolTable 中定义，调用时不产生 CallEdge
- 识别方式：当 `resolve(name)` 返回 null 且 callee 是裸 `IdentifierNode` 时，判定为内置/外部引用，记录简化的 `callee = "<builtin>:name>"`
- [Phase 3] 引入内置函数列表做精确区分

### 3.3 SignalGraph — 信号流程图

```gdscript
class_name SignalGraph
extends RefCounted

var signals: Dictionary = {}       # String → SignalInfo

func get_signal_flow(p_signal_name: String) -> SignalInfo:
    return signals.get(p_signal_name, null)


class_name SignalInfo
extends RefCounted

var name: String = ""
var declaration: GDScriptToken.SignalNode = null
var params: Array[String] = []     # 参数名列表
var emit_sites: Array[Site] = []   # emit("name") / name.emit()
var connect_sites: Array[Site] = [] # .connect("name", cb) / name.connect(cb)


class_name Site
extends RefCounted

var line: int = 0
var node = null                           # 对应的 AST 节点 (CallNode)
var enclosing_function: String = ""       # 所在函数名
var arguments: Array = []                 # of ExpressionNode
```

**信号 emit 检测规则：**

```
emit 的两种 AST 形态:
1. emit("signal_name")    → CallNode(callee=IdentifierNode("emit"), arguments=[LiteralNode("signal_name")])
2. signal_name.emit()     → CallNode(callee=AttributeNode(base=IdentifierNode("<signal_name>"), name="emit"))
```

检测逻辑：
1. 遍历 CallNode
2. 若 `callee` 是 `IdentifierNode("emit")` 且第一个参数是 `LiteralNode`（字符串） → 提取信号名，记录 emit_site
3. 若 `callee` 是 `AttributeNode` 且 `name == "emit"` 且 `base` 是 `IdentifierNode` → 将 base 名称作为信号名

**信号 connect 检测规则：**

```
connect 的三种 AST 形态:
1. obj.connect("signal_name", callback)       → CallNode(callee=AttributeNode(base=..., name="connect"))
2. signal_name.connect(callback)              → CallNode(callee=AttributeNode(base=IdentifierNode("<signal_name>"), name="connect"))
3. obj.signal_name.connect(callback)          → CallNode(callee=AttributeNode(base=AttributeNode(...), name="connect"))
```

检测逻辑：
1. 遍历 CallNode
2. 若 `callee` 是 `AttributeNode` 且 `name == "connect"` 且参数 >= 1：
   - **模式 a**（字符串信号名）：若 base 不是 IdentifierNode（即 obj.connect(...) 形式）且第一个参数是 LiteralNode（字符串）→ 提取信号名，第二个参数若为 IdentifierNode → 其值为回调函数名
   - **模式 b**（Signal 类型调用）：若 base 是 IdentifierNode → base.name 为信号名，第一个参数若为 IdentifierNode → 其值为回调函数名
   - **模式 c**（Lambda 回调）：若参数之一是 LambdaNode → 记录 Connect 边，但不记录 callee 为函数名，而是标记 call_type=LAMBDA

**特殊处理：`signal.connect` 的 Godot 4.x 语义**
Godot 4.x 中 `Signal` 是一个内置类型，`signal_name` 返回 `Signal` 对象。`.connect(cb)` 是该对象的方法。SymbolResolver 通过 AST 结构（`CallNode` 不含括号内部细节）已经能够正确识别这两种模式，不需要额外的语义推断。

### 3.4 DefUseChain — 变量定义-使用链

```gdscript
class_name DefUseChain
extends RefCounted

var variables: Dictionary = {}      # String → DefUseInfo


class_name DefUseInfo
extends RefCounted

var name: String = ""
var def_site: DefUseSite = null      # 定义位置 (var / const / func param)
var read_sites: Array[DefUseSite] = []
var write_sites: Array[DefUseSite] = []


class_name DefUseSite
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
```

**追踪逻辑：**

1. **DEFINE**：遇到 VariableNode 声明、ParameterNode、`const`、`for i in ...` → 记录定义位置
2. **WRITE**：遇到 AssignmentNode 且 op == `=`（非复合赋值） → 对 target 中的标识符记录 WRITE
3. **READ_WRITE**：遇到 AssignmentNode 且 op 为复合赋值（`+=`, `-=` 等） → 对 target 中的标识符记录 READ_WRITE
4. **READ**：遇到 IdentifierNode 用于表达式（不在定义上下文、不在赋值左侧）→ 记录 READ

**上下文判断规则：**
- `IdentifierNode` 在 `AssignmentNode.target` 位置 → WRITE（或 READ_WRITE 若 op != `=`）
- `IdentifierNode` 在 `VariableNode.initializer` 位置 → 当前变量是 DEFINE，initializer 中的标识符是 READ
- `IdentifierNode` 在 `CallNode.arguments` 或 `BinaryOpNode` 等表达式位置 → READ
- `IdentifierNode` 在 `AttributeNode.base` 位置 → READ（访问对象的属性，读取了该变量）

## 四、解析策略

### 4.1 作用域链

#### 4.1.1 作用域创建时机

```
ClassNode        → 创建 class_scope（类成员 SymbolTable）
  ├─ FunctionNode  → 创建 func_scope（parent = class_scope）
  │   ├─ ParameterNode → define 参数到 func_scope
  │   └─ SuiteNode 语句遍历 → 在 func_scope 中解析
  │       └─ LambdaNode → 创建 lambda_scope（parent = 当前作用域）
  │           ├─ ParameterNode → define 参数到 lambda_scope
  │           └─ body 遍历 → 在 lambda_scope 中解析
  ├─ VariableNode   → define 变量到 class_scope
  ├─ SignalNode     → define 信号到 class_scope + 注册 SignalGraph
  ├─ EnumNode       → define 枚举到 class_scope，枚举值到枚举专用子 scope
  └─ inner ClassNode → 递归 _resolve_class → 创建新的 class_scope
```

#### 4.1.2 标识符解析流程

```
_resolve_identifier(node, scope, current_func):
    sym = scope.resolve(node.name)
    if sym == null:
        # 未解析 — 可能是内置函数/全局/外部引用
        if 当前在表达式上下文中:
            result.add_error("未解析的标识符: %s" % node.name, node.line)
        return null
    # 记录 DefUse: 读上下文 → READ
    _record_def_use(sym.name, node, current_func, DefUseSite.READ)
    return sym
```

#### 4.1.3 变量声明处理

```gdscript
func _resolve_variable(p_node: GDScriptToken.VariableNode, p_scope: SymbolTable, p_current_func: String):
    var kind = Symbol.Kind.CONSTANT if _is_const else Symbol.Kind.VARIABLE
    var sym = p_scope.define(p_node.name, kind, p_node, _type_to_string(p_node.datatype))
    sym.is_exported = p_node.is_export

    # 记录 def site
    _record_def_use(p_node.name, p_node, p_current_func, DefUseSite.DEFINE)

    # 解析初始化表达式中的标识符 (这些是 READ)
    if p_node.initializer != null:
        _resolve_expression(p_node.initializer, p_scope, p_current_func)
```

> **关于 const 和 var 的区分**：Phase 1 的 `_parse_const()` 返回 `VariableNode`（无独立 ConstNode 类型）。SymbolResolver 无法从 AST 节点类型区分 const 和 var。Phase 2 通过以下方式处理：
> - 若成员解析时 Token 序列中该声明以 `TK_CONST` 开头 → `Symbol.Kind.CONSTANT`
> - 实现方式：在 `resolve()` 入口处预处理 ClassNode members，记录每个 VariableNode 的源 Token 类型（`var` vs `const`）
> - [Phase 3 备选] 在 `VariableNode` 上添加 `is_const: bool` 字段，由 Parser 在 Phase 1 中设置

### 4.2 调用图构建

#### 4.2.1 CallNode 检测

```gdscript
func _resolve_call(p_node: GDScriptToken.CallNode, p_scope: SymbolTable, p_current_func: String):
    # 先解析参数中的标识符引用
    for arg in p_node.arguments:
        _resolve_expression(arg, p_scope, p_current_func)

    # 检测调用类型
    var callee = p_node.callee

    # 模式 1: IdentifierNode — 隐式 self 调用 或 内置函数
    if callee is GDScriptToken.IdentifierNode:
        var sym = p_scope.resolve(callee.name)
        if sym != null and sym.kind == Symbol.Kind.FUNCTION:
            _add_call_edge(p_current_func, callee.name, callee.line, CallEdge.CallType.SELF, "", p_node.arguments)
        # 否则可能是内置函数 — 不记录边

    # 模式 2: AttributeNode — 需要检查 base 类型
    elif callee is GDScriptToken.AttributeNode:
        var base = callee.base
        var method_name = callee.name

        # 2a: self.method() → SELF
        if base is GDScriptToken.SelfNode:
            _add_call_edge(p_current_func, method_name, callee.line, CallEdge.CallType.SELF, "", p_node.arguments)

        # 2b: super.method() → SUPER
        elif base is GDScriptToken.SuperNode:
            _add_call_edge(p_current_func, method_name, callee.line, CallEdge.CallType.SUPER, "", p_node.arguments)

        # 2c: signal_name.connect() → SIGNAL_CONNECT
        elif method_name == "connect" and base is GDScriptToken.IdentifierNode:
            _resolve_signal_connect(p_node, base.name, p_scope, p_current_func)

        # 2d: obj.connect() → CONNECT
        elif method_name == "connect":
            _resolve_object_connect(p_node, p_scope, p_current_func)

        # 2e: signal_name.emit() → EMIT
        elif method_name == "emit" and base is GDScriptToken.IdentifierNode:
            _resolve_signal_emit(p_node, base.name, p_current_func, "dot_emit")

        # 2f: obj.method() → EXTERNAL
        elif base is GDScriptToken.IdentifierNode:
            _add_call_edge(p_current_func, method_name, callee.line, CallEdge.CallType.EXTERNAL, base.name, p_node.arguments)

        # 2g: 链式调用 a.b.method() — 不做追踪 (Phase 3)
```

#### 4.2.2 emit("sig") 检测

```gdscript
func _resolve_emit_call(p_node: GDScriptToken.CallNode, p_current_func: String):
    # emit("signal_name") 形式
    if p_node.callee is GDScriptToken.IdentifierNode and p_node.callee.name == "emit":
        if p_node.arguments.size() > 0 and p_node.arguments[0] is GDScriptToken.LiteralNode:
            var sig_name = str(p_node.arguments[0].value)
            var info = result.signal_graph.get_signal_flow(sig_name)
            if info == null:
                # 信号未声明 — 记录警告但创建临时 Info
                info = SignalInfo.new()
                info.name = sig_name
                result.signal_graph.signals[sig_name] = info
            info.emit_sites.append(_make_site(p_node, p_current_func, p_node.arguments))
            # 同时记录为 EMIT 类型的 CallEdge
            _add_call_edge(p_current_func, sig_name, p_node.callee.line, CallEdge.CallType.EMIT, "", p_node.arguments)
```

### 4.3 信号 emit/connect 链路

#### 4.3.1 信号声明

进入 `SignalNode` 时：
1. `define` 到 class_scope（`Symbol.Kind.SIGNAL`）
2. 创建 `SignalInfo` 并添加到 `SignalGraph.signals`
3. 记录参数名列表

#### 4.3.2 emit 发射点

两种语法形态都有相同的 emit_site 处理逻辑：
- `emit("signal_name")` → 在 `_resolve_call` 中检测 callee 是 `IdentifierNode("emit")`
- `signal_name.emit()` → 在 `_resolve_call` 中检测 callee 是 `AttributeNode(..., name="emit")`

每个 emit site 记录：行号、所在函数、参数 AST 节点。

#### 4.3.3 connect 连接点

两种语法形态都在 `_resolve_call` 中检测 callee 是 `AttributeNode(..., name="connect")`：

```
obj.connect("sig", callback):
  参数[0] = LiteralNode("sig")  → 信号名
  参数[1] = IdentifierNode("cb") → 回调函数名
  → 记录 connect_site + CallEdge(call_type=CONNECT)

signal_name.connect(callback):
  base = IdentifierNode("signal_name") → 信号名
  参数[0] = IdentifierNode("cb") 或 LambdaNode
  → 记录 connect_site + CallEdge(call_type=SIGNAL_CONNECT 或 LAMBDA)
```

#### 4.3.4 完整链路查询

```gdscript
func get_signal_flow(p_signal_name: String) -> SignalInfo:
    # 返回 SignalInfo，包含:
    #   - declaration: 信号声明位置
    #   - emit_sites: 所有 emit 调用点
    #   - connect_sites: 所有 connect 绑定点
```

### 4.4 Lambda 闭包捕获变量

#### 4.4.1 捕获变量检测

Lambda 引用了一个在 lambda 自身作用域中未定义的变量时，该变量即为"捕获变量"。

```gdscript
func _resolve_lambda(p_node: GDScriptToken.LambdaNode, p_parent_scope: SymbolTable, p_current_func: String):
    # 1. 创建 lambda_scope (parent = p_parent_scope)
    var lambda_scope = SymbolTable.new()
    lambda_scope.parent = p_parent_scope
    lambda_scope.scope_name = "lambda@%d" % p_node.line

    # 2. define lambda 参数到 lambda_scope
    for param in p_node.params:
        lambda_scope.define(param.name, Symbol.Kind.PARAMETER, param, _type_to_string(param.datatype))

    # 3. 遍历 lambda body，解析标识符
    _resolve_lambda_body(p_node.body, lambda_scope, p_current_func)

    # 4. 捕获变量: 在 lambda body 中被引用但 resolve_local 返回 null，
    #    且通过 parent scope resolve 能找到的变量 → 记录为 captured
    #    这由 _resolve_identifier_in_lambda 在处理过程中收集


func _resolve_identifier_in_lambda(p_node: GDScriptToken.IdentifierNode, p_lambda_scope: SymbolTable, 
                                    p_lambda_node: GDScriptToken.LambdaNode, p_current_func: String):
    var local = p_lambda_scope.resolve_local(p_node.name)
    if local != null:
        # lambda 局部变量（参数）— 正常处理
        _record_def_use(p_node.name, p_node, p_current_func, DefUseSite.READ)
        return local

    # 不在 lambda 局部 → 从父作用域查找
    var sym = p_lambda_scope.resolve(p_node.name)  # resolve 自动递归到 parent
    if sym != null:
        # 这是捕获变量！记录到 LambdaNode
        if not p_lambda_node.captured_vars.has(p_node.name):
            p_lambda_node.captured_vars.append(p_node.name)
        _record_def_use(p_node.name, p_node, p_current_func, DefUseSite.READ)
        return sym

    return null
```

#### 4.4.2 捕获变量与信号回调

当 Lambda 作为 `.connect()` 的参数时，其 `captured_vars` 提供了信号回调闭包的上下文信息：

```gdscript
# 源码:
# var hp = 100
# signal health_changed(old, new)
# health_changed.connect(func(old, new): print("HP: ", hp))
#
# 分析结果:
# LambdaNode.captured_vars = ["hp"]
# SignalInfo.connect_sites[0].arguments[0] → LambdaNode
```

### 4.5 变量 Def-Use 追踪

#### 4.5.1 递归遍历时的上下文

```gdscript
# 当遍历表达式时，对每个 IdentifierNode 的判断:
func _resolve_identifier_read(p_node, p_scope, p_current_func):
    var sym = p_scope.resolve(p_node.name)
    if sym == null:
        return  # 未解析 — 已记录错误
    # 默认记录为 READ
    _record_def_use(p_node.name, p_node, p_current_func, DefUseSite.READ)
```

#### 4.5.2 赋值语句中的特殊处理

```gdscript
func _resolve_assignment(p_node: GDScriptToken.AssignmentNode, p_scope: SymbolTable, p_current_func: String):
    # 先解析 value 侧的表达式 (所有标识符为 READ)
    _resolve_expression(p_node.value, p_scope, p_current_func)

    # 再解析 target 侧的标识符
    if p_node.target is GDScriptToken.IdentifierNode:
        var access = DefUseSite.WRITE if p_node.op == GDScriptToken.Type.EQUAL else DefUseSite.READ_WRITE
        _record_def_use(p_node.target.name, p_node.target, p_current_func, access)
    elif p_node.target is GDScriptToken.AttributeNode:
        # a.b = value → a 是 READ (读取对象引用，未修改 a 本身)
        # 但 b 是对象属性写入，不在当前文件的变量追踪范围内
        _resolve_expression(p_node.target.base, p_scope, p_current_func)  # base 中的标识符为 READ
    elif p_node.target is GDScriptToken.SubscriptNode:
        # a[b] = value → a 是 READ, b 中的标识符是 READ
        _resolve_expression(p_node.target.base, p_scope, p_current_func)
        _resolve_expression(p_node.target.index, p_scope, p_current_func)
```

#### 4.5.3 For 循环变量

```gdscript
func _resolve_for(p_node: GDScriptToken.ForNode, p_scope: SymbolTable, p_current_func: String):
    # for i in range(10): — i 是局部变量，define 到当前作用域
    p_scope.define(p_node.var_name, Symbol.Kind.FOR_VAR, p_node, "Variant")
    _record_def_use(p_node.var_name, p_node, p_current_func, DefUseSite.DEFINE)

    # iterable 中的标识符是 READ
    _resolve_expression(p_node.iterable, p_scope, p_current_func)

    # body 内可能有 WRITE 或 READ 对循环变量
    _resolve_suite(p_node.body, p_scope, p_current_func)
```

## 五、GDScriptAnalysisResult 查询 API

### 5.1 结果容器

```gdscript
class_name GDScriptAnalysisResult
extends RefCounted

var file_path: String = ""
var class_name: String = ""               # class_name 名称
var extends_path: String = ""             # extends 的父类路径
var preloads: Array[String] = []          # preload 路径列表

# 核心数据
var ast: GDScriptToken.ClassNode = null
var symbol_table: SymbolTable = null      # 类作用域（根）
var call_graph: CallGraph = null
var signal_graph: SignalGraph = null
var def_use_chain: DefUseChain = null

# 错误/警告
var errors: Array[String] = []           # "[阶段] 行:列: 描述" 格式
```

### 5.2 查询方法

```gdscript
# 获取所有声明的函数
func get_all_functions() -> Array[GDScriptToken.FunctionNode]:
    var funcs: Array[GDScriptToken.FunctionNode] = []
    for sym_name in symbol_table.symbols:
        var sym = symbol_table.symbols[sym_name]
        if sym.kind == Symbol.Kind.FUNCTION:
            funcs.append(sym.declaration)
    return funcs

# 获取所有声明的信号
func get_all_signals() -> Array[GDScriptToken.SignalNode]:
    var signals: Array[GDScriptToken.SignalNode] = []
    for sym_name in symbol_table.symbols:
        var sym = symbol_table.symbols[sym_name]
        if sym.kind == Symbol.Kind.SIGNAL:
            signals.append(sym.declaration)
    return signals

# 获取某函数的所有调用者
func get_callers_of(p_func_name: String) -> Array[CallEdge]:
    return call_graph.get_callers_of(p_func_name)

# 获取某函数调用了谁
func get_callees_of(p_func_name: String) -> Array[CallEdge]:
    return call_graph.get_callees_of(p_func_name)

# 获取信号的完整流程图
func get_signal_flow(p_signal_name: String) -> SignalInfo:
    return signal_graph.get_signal_flow(p_signal_name)

# 获取变量的完整读写链
func get_variable_usages(p_var_name: String) -> DefUseInfo:
    return def_use_chain.variables.get(p_var_name, null)

# 获取依赖树
func get_dependency_tree() -> Dictionary:
    return {
        "extends":  extends_path,
        "preloads": preloads,
        "class_name": class_name,
    }
```

### 5.3 使用示例

```gdscript
# Phase 2 完整管道
var source = FileAccess.get_file_as_string("res://player.gd")
var tokens = GDScriptTokenizer.new().tokenize(source)
var ast = GDScriptParser.new().parse(tokens)
var result = GDScriptSymbolResolver.new().resolve(ast, "res://player.gd")

# 检查错误
if not result.errors.is_empty():
    for err in result.errors:
        push_warning(err)

# 查询信号流
var flow = result.get_signal_flow("health_changed")
# → SignalInfo {
#     declaration @line 3,
#     emit_sites: [@line 8 (take_damage), @line 15 (heal)],
#     connect_sites: [@line 12 (hud.gd → _on_health_changed)]
#   }

# 查询调用者
var callers = result.get_callers_of("take_damage")
for edge in callers:
    print("%s() → take_damage() @line %d" % [edge.caller, edge.site_line])
# → _on_body_entered() → take_damage() @line 22
# → _process() → take_damage() @line 30

# 查询变量使用
var usage = result.get_variable_usages("hp")
# → DefUseInfo {
#     def @line 2 (var hp := 100),
#     reads: [@line 6 (if hp <= 0), @line 8 (hp)], 
#     writes: [@line 7 (hp -= damage)]
#   }

# 检查 lambda 捕获
for m in result.ast.members:
    if m is GDScriptToken.FunctionNode:
        # 递归遍历函数体中的 lambda
        pass
# LambdaNode.captured_vars → ["hp", "max_hp"]
```

## 六、EditorPlugin 集成

### 6.1 插件生命周期扩展

在现有 Phase 1 `plugin.gd` 基础上扩展：

```gdscript
@tool
extends EditorPlugin

var analysis_cache: Dictionary = {}  # String(path) → GDScriptAnalysisResult

func _enter_tree():
    add_tool_menu_item("GDScript Analysis – Parse Current", _on_parse_current)
    # Phase 2: 注册 resource_saved 信号
    resource_saved.connect(_on_resource_saved)
    print("[GDScriptUtil v2.0] Plugin loaded — Phase 2: Symbol Analysis")

func _exit_tree():
    remove_tool_menu_item("GDScript Analysis – Parse Current")
    resource_saved.disconnect(_on_resource_saved)
    analysis_cache.clear()
    print("[GDScriptUtil v2.0] Plugin unloaded")

# Phase 2 新增: 自动分析
func _on_resource_saved(p_resource: Resource):
    if p_resource is GDScript and p_resource.resource_path.ends_with(".gd"):
        _analyze_script(p_resource.resource_path)
```

### 6.2 分析函数升级

```gdscript
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

    # Phase 2 新增: 符号解析
    var resolver = GDScriptSymbolResolver.new()
    var result = resolver.resolve(ast, p_path)

    # 缓存结果
    analysis_cache[p_path] = result

    # 输出分析摘要
    _print_analysis_summary(result)

    return result

func _print_analysis_summary(p_result: GDScriptAnalysisResult):
    print("[GDScriptUtil] %s — %d functions, %d signals, %d variables, %d calls, %d errors" % [
        p_result.file_path,
        p_result.get_all_functions().size(),
        p_result.get_all_signals().size(),
        p_result.def_use_chain.variables.size(),
        p_result.call_graph.edges.size(),
        p_result.errors.size()
    ])

    # 输出调用图摘要
    for edge in p_result.call_graph.edges:
        var type_str = _call_type_to_string(edge.call_type)
        print("  %s() →%s %s() @line %d" % [edge.caller, type_str, edge.callee, edge.site_line])

    # 输出信号流摘要
    for sig_name in p_result.signal_graph.signals:
        var info = p_result.signal_graph.signals[sig_name]
        print("  signal %s: %d emits, %d connects" % [
            sig_name, info.emit_sites.size(), info.connect_sites.size()
        ])
```

### 6.3 缓存策略

```
analysis_cache: Dictionary[String, GDScriptAnalysisResult]
  - key:  文件路径 (如 "res://player.gd")
  - value: 完整分析结果
  - 更新: 每次 _analyze_script() 调用时覆盖
  - 清理: _exit_tree() 时全部清除
  - [Phase 3] 可选: 检查文件修改时间戳避免重新分析未变化的文件
```

## 七、与 Phase 1 代码的接口约定

### 7.1 输入接口

| Phase 1 输出 | Phase 2 使用方式 |
|-------------|----------------|
| `ClassNode` | `resolve()` 入口参数，作为 AST 遍历根 |
| `FunctionNode` | 创建 func_scope，define 函数符号，作为 caller 上下文 |
| `VariableNode` | define 变量符号，记录 def site |
| `SignalNode` | define 信号符号，注册 SignalInfo |
| `EnumNode` | define 枚举符号，枚举值注册到子作用域 |
| `ParameterNode` | define 参数到函数/lambda 作用域 |
| `SuiteNode` | 递归遍历 statements |
| `IfNode` / `WhileNode` / `ForNode` | 遍历 body (不创建新作用域，但 for 变量 define 到当前作用域) |
| `CallNode` | 检测调用模式，构建 CallEdge 和 Signal connect/emit |
| `AssignmentNode` | 检测 target 标识符 → WRITE/READ_WRITE；value 标识符 → READ |
| `LambdaNode` | 创建 lambda_scope，检测捕获变量 |
| `IdentifierNode` | resolve → Symbol，记录 DefUse |
| `AttributeNode` | 检测 base 类型 → 判断 Self/Super/External 调用 |
| `SelfNode` / `SuperNode` | 在 AttributeNode.base 中检测 → 确定调用类型 |
| `LiteralNode` | 用于提取 emit/connect 的字符串参数 |
| `ReturnNode` / `AssertNode` / `AwaitNode` 等 | 递归遍历子表达式 |

### 7.2 输出接口

| Phase 2 输出 | Phase 3 消费方式 |
|-------------|----------------|
| `GDScriptAnalysisResult` | EditorPlugin 可视化面板的输入 |
| `SymbolTable` | 代码补全、跳转定义 [Phase 3] |
| `CallGraph.edges` | 调用图 UI 渲染 [Phase 3] |
| `SignalGraph.signals` | 信号流程图 UI [Phase 3] |
| `DefUseChain.variables` | 变量使用高亮 [Phase 3] |
| `LambdaNode.captured_vars` | 闭包检查、重构安全分析 [Phase 3] |

### 7.3 不修改 Phase 1 代码

Phase 2 的实现原则：
- **不修改** `gds_ast_nodes.gd` 中的任何节点类（除非必要扩展字段）
- **不修改** `gds_tokenizer.gd`
- **不修改** `gds_parser.gd`
- **扩展** `plugin.gd`：添加 `resource_saved` 信号连接和 Phase 2 管道调用
- **新增** `gds_symbol_resolver.gd` 和 `gds_analysis_result.gd`

### 7.4 错误处理约定

- Resolver 的 `resolve()` 始终返回一个 `GDScriptAnalysisResult`（不返回 null）
- 所有分析错误记录到 `result.errors: Array[String]`，格式：`"[SymbolResolver] 行:列: 描述"`
- 未解析的标识符不作为致命错误——记录警告并不影响继续分析
- 外部调用（`EXTERNAL` 类型）不在当前文件追踪 → 记录 CallEdge 但 `callee` 设为 `"<external>:obj.method"`
- 未声明的信号 emit → 创建临时 SignalInfo 并记录警告

## 八、验收标准

### 8.1 测试用例

| # | 输入源码 | 预期分析结果 | 验证维度 |
|---|---------|------------|---------|
| 1 | `extends Node\nclass_name Player\nvar hp := 100\nfunc take_damage(amount: int):\n\thp -= amount` | SymbolTable 有 `hp`(VARIABLE), `take_damage`(FUNCTION), `amount`(PARAMETER)；DefUseChain 有 `hp`: def@2, READ_WRITE@4；`amount`: def@3(参数), READ@4 | SymbolTable + DefUseChain |
| 2 | `func foo():\n\tbar()\nfunc bar():\n\tpass` | CallGraph: foo → bar (SELF @line 2)；get_callers_of("bar") 返回 1 条边 | CallGraph (隐式 self) |
| 3 | `func foo():\n\tself.bar()\nfunc bar():\n\tpass` | CallGraph: foo → bar (SELF @line 2) | CallGraph (显式 self) |
| 4 | `func foo():\n\tsuper._ready()\nfunc bar():\n\tpass` | CallGraph: foo → _ready (SUPER @line 2) | CallGraph (super) |
| 5 | `var callback = func(x): return x * 2` | LambdaNode.captured_vars 为空（无外部变量捕获） | Lambda 不捕获 |
| 6 | `var scale = 2\nvar doubler = func(x): return x * scale` | LambdaNode.captured_vars = ["scale"] | Lambda 捕获变量 |
| 7 | `signal health_changed(old, new)\nfunc take_damage(d):\n\thealth_changed.emit(hp, hp - d)` | SignalGraph: health_changed 有 1 个 emit_site @line 3 (take_damage)；get_signal_flow("health_changed").emit_sites.size() == 1 | Signal emit |
| 8 | `signal health_changed(old, new)\nfunc _ready():\n\thealth_changed.connect(_on_health)\nfunc _on_health(o, n):\n\tpass` | SignalGraph: health_changed 有 1 个 connect_site @line 3 (_ready)；CallGraph: _ready → _on_health (SIGNAL_CONNECT @line 3) | Signal connect + CallGraph |
| 9 | `signal died\nfunc _ready():\n\t$AnimationPlayer.connect("finished", _on_anim_end)` | SignalGraph: died(声明), "finished"(connect_site @line 3, 未声明信号)；CallGraph: _ready → _on_anim_end (CONNECT @line 3) | 外部 connect + 未声明信号 |
| 10 | `var x: int = 0\nfunc _process(d):\n\tx = 1\n\tprint(x)\n\tx += 1` | DefUseChain: x: def@1, WRITE@3, READ@4, READ_WRITE@5 | DefUse (完整读写链) |

### 8.2 验收通过条件

1. 10 个测试用例全部通过
2. `resolve()` 在输入任意有效 AST 时不崩溃
3. 所有错误记录到 `result.errors`，不通过 `push_error`/`printerr` 输出
4. 调用图、信号图、变量链的数据结构在查询 API 下返回正确结果
5. `plugin.gd` 的 `resource_saved` 信号成功触发自动分析

### 8.3 Phase 2 测试文件

```
tests/
├── test_parser.gd         # Phase 1 已有
└── test_symbol_resolver.gd # Phase 2 新增 — 10 个验收测试
```

## 九、实现顺序

### Chunk 1: 数据结构 + 框架

1. `gds_analysis_result.gd` — SymbolTable, Symbol, CallGraph, CallEdge, SignalGraph, SignalInfo, Site, DefUseChain, DefUseInfo, DefUseSite, GDScriptAnalysisResult
2. `gds_symbol_resolver.gd` — 类骨架 + `resolve()` 入口 + AST 遍历框架

### Chunk 2: 符号表 + 作用域链

3. 实现 `_resolve_class` / `_resolve_function` / `_resolve_variable` / `_resolve_signal` / `_resolve_enum`
4. 实现 scope chain：ClassScope → FuncScope → LambdaScope
5. 实现 `SymbolTable.define()` 和 `.resolve()`

### Chunk 3: 调用图 + 信号图

6. 实现 `_resolve_call` — 6 种调用模式检测
7. 实现 emit/connect 检测和 SignalGraph 构建

### Chunk 4: DefUse + Lambda 捕获

8. 实现 DefUseChain 追踪逻辑
9. 实现 Lambda 捕获变量检测

### Chunk 5: EditorPlugin + 测试

10. 扩展 `plugin.gd` — `resource_saved` 集成
11. `tests/test_symbol_resolver.gd` — 10 个验收测试

---

## 附录 A：CallEdge 6 种调用模式的 AST 检测速查表

```
源码                    AST 形态                                              call_type
────────────────────────────────────────────────────────────────────────────────────────
foo()                  CallNode(callee=IdentifierNode("foo"))                SELF
self.foo()             CallNode(callee=AttributeNode(                        SELF
                           base=SelfNode, name="foo"))
super.foo()            CallNode(callee=AttributeNode(                        SUPER
                           base=SuperNode, name="foo"))
obj.foo()              CallNode(callee=AttributeNode(                        EXTERNAL
                           base=IdentifierNode("obj"), name="foo"))
emit("sig")            CallNode(callee=IdentifierNode("emit"),               EMIT (+SignalGraph)
                           arguments=[LiteralNode("sig")])
sig.emit()             CallNode(callee=AttributeNode(                        EMIT (+SignalGraph)
                           base=IdentifierNode("sig"), name="emit"))
obj.connect("sig",cb)  CallNode(callee=AttributeNode(base=...,               CONNECT (+SignalGraph)
                           name="connect"), arguments=[Lit("sig"),Id("cb")])
sig.connect(cb)        CallNode(callee=AttributeNode(                        SIGNAL_CONNECT (+SigG)
                           base=IdentifierNode("sig"), name="connect"),
                           arguments=[IdentifierNode("cb")])
sig.connect(lambda)    CallNode(callee=AttributeNode(                        LAMBDA (+SignalGraph)
                           base=IdentifierNode("sig"), name="connect"),
                           arguments=[LambdaNode(...)])
```

## 附录 B：LambdaNode.body 的两种情况

Phase 1 的 `_parse_lambda()` 在两种情况下产生不同的 `body` 类型：

```gdscript
# 单行 lambda: body = ExpressionNode (LiteralNode / CallNode / ...)
var f = func(x): return x * 2
# → LambdaNode(params=[ParameterNode("x")], body=LiteralNode(2))  # return 被解包

# 多行 lambda: body = SuiteNode
var f = func(x):
    print(x)
    return x * 2
# → LambdaNode(params=[ParameterNode("x")], body=SuiteNode([ExpressionStatementNode(...), ReturnNode(...)]))
```

SymbolResolver 的 `_resolve_lambda_body` 需要同时处理这两种情况：

```gdscript
func _resolve_lambda_body(p_body, p_lambda_scope: SymbolTable, p_lambda_node, p_current_func: String):
    if p_body is GDScriptToken.SuiteNode:
        _resolve_suite(p_body, p_lambda_scope, p_current_func, p_lambda_node)
    else:
        # 单表达式 — 直接递归解析
        _resolve_expression(p_body, p_lambda_scope, p_current_func, p_lambda_node)
```

## 附录 C：Phase 2 常量标识符区分方案

由于 Phase 1 的 `_parse_const()` 和 `_parse_variable()` 都返回 `VariableNode`，SymbolResolver 无法从节点类型区分 `const` 和 `var`。采用以下方案：

**方案 A（推荐 — Phase 2 实施）：** 在 `resolve()` 入口处，传入原始 Token 流或源码片段，通过查找 `VariableNode` 对应行号的源 Token 来确定是 `var` 还是 `const`。

```gdscript
# 在 resolve() 中:
var source_lines = _load_source_lines(p_file_path)
for member in p_ast.members:
    if member is GDScriptToken.VariableNode:
        var line_text = source_lines[member.line - 1].strip_edges()
        var is_const = line_text.begins_with("const")
        var kind = Symbol.Kind.CONSTANT if is_const else Symbol.Kind.VARIABLE
```

**方案 B（Phase 3 备选 — 更干净）：** 在 `VariableNode` 上添加 `is_const: bool` 字段，由 Parser 在 Phase 1 中设置。这样 SymbolResolver 不需要访问源码文本。

Phase 2 实现时选择方案 A（最小改动原则）。
