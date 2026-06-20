# GDScript 解析器 Godot 4.7 重写规范

> 日期: 2026-06-20 | 状态: 设计中 | 阶段: 规范制定

## 一、项目背景与目标

### 1.1 背景

当前工程 `godot-byte-code-parser` 是为 Godot Engine 3.4.4 设计的 GDScript 字节码/AST 解析器。Godot 4.x 完全重构了 GDScript 编译器，`.gdc` 文件从"编译后的虚拟机字节码"变为"分词后的源码缓存"，令牌体系、AST 结构、解析流程均不兼容。

### 1.2 目标

为 Godot 4.7 完全重写 GDScript 解析工具，支持：
- 解析 `.gd` 源文件，构建抽象语法树（AST）
- 符号解析：作用域链、变量/函数/信号声明与引用
- 逻辑流分析：方法调用图、信号连接/发射链路、变量定义-使用追踪
- 作为 Godot 编辑器插件（EditorPlugin）集成，辅助工具开发

### 1.3 约束

- 纯 GDScript 实现（不依赖 GDExtension 或 C++ 模块）
- 解析 `.gd` 源文件文本（非 `.gdc` 二进制）
- 语法覆盖：Phase 1 核心子集（见 1.4 节精确定义），架构预留扩展到完整 4.7 语法

### 1.4 Phase 1 核心子集 — 语法覆盖精确定义

以下为 Phase 1 必须支持的 GDScript 语法结构，Phase 3 扩展为完整语法。

**Phase 1 支持：**
- 类定义：`extends`, `class_name`, `@tool`/`@icon` 文件级注解
- 变量声明：`var x = 1`, `var x: int = 1`, `var x := 1`, `const`, `@export`, `@onready`
- 函数定义：`func name(params) -> Type:`, 默认参数值, 静态函数, `return` 类型标注
- 函数参数：`param: Type = default`
- 控制流：`if/elif/else`, `while`, `for x in range`, `match` 含 `when` 分支（不含 guard 表达式）
- 信号：`signal name(params)`, `emit("name")`, `name.emit()`, `signal.connect(cb)`, `obj.connect("sig", cb)`
- 枚举：`enum { A, B, C }`, `enum Name { A = 1, B }`
- 表达式：二元/一元运算符（完整 4.7 优先级表），三目 `a if cond else b`
- 字面量：数字、字符串（单/双引号）、数组 `[1, 2]`、字典 `{"k": v}`、`self`
- 属性访问：`a.b`, `a[b]`
- 函数调用：`foo()`, `obj.method()`, `super.method()`
- Lambda：`func(params): return x`（含独立缩进栈）
- await：`await expr`
- 类型操作：`x as Type`, `x is Type`, 类型标注 `: Type`, 泛型容器 `Array[int]`, `Dictionary[String, int]`
- 其他：`preload("path")`, `assert`, `breakpoint`, `pass`, `return`, `$NodePath`, `break`, `continue`, `yield`
- 字符串格式化：`"text %s" % var`（`%` 运算符），`"text {var}".format()`（方法调用，通过 CallNode 自然支持）

**Phase 1 不支持（Phase 3 扩展）：**
- `namespace`, `trait` 关键字
- `match` 的 `when` guard 表达式（`when x > 0:`）
- `f"..."` 格式化字符串语法
- 内联 setter/getter（`var hp: set(v): hp = clamp(v, 0, 100)`）— 仅支持声明式 `setget`
- 完整 `Callable` 语法（`Callable(obj, "method")`）

**Phase 1 验收标准（测试用例）：**
1. `extends Node\nclass_name Player\n` → ClassNode(extends="Node", classname="Player")
2. `var hp := 100` → VariableNode(name="hp", initializer=LiteralNode(100))
3. `func take_damage(amount: int) -> void:\n\tpass` → FunctionNode 含一个 ParameterNode + SuiteNode
4. `signal health_changed(old, new)` → SignalNode 含 2 个 ParameterNode
5. `if hp <= 0:\n\temit("died")\nelse:\n\tpass` → IfNode 含 BinaryOpNode 条件 + 两个 SuiteNode
6. `@export var speed: float = 10.0` → AnnotationNode(@export) + VariableNode(speed, float, 10.0)
7. `for i in range(10):\n\tprint(i)` → ForNode(var_name="i", iterable=CallNode)
8. `match x:\n\twhen 1, 2:\n\t\tpass` → MatchNode 含 MatchBranchNode
9. `var callback = func(): return 42` → LambdaNode 无参数, body=LiteralNode(42)
10. `await get_tree().process_frame` → AwaitNode(CallNode(AttributeNode(...)))

## 二、架构总览

### 2.1 管道架构

```
.gd 源码文本
    │
    ▼
┌─────────────────────────┐
│ GDScriptTokenizer       │  词法分析
│ Input:  String          │  逐字符扫描 → Token 流
│ Output: Array[GDScriptToken]  │
└───────────┬─────────────┘
            │ token_list
            ▼
┌─────────────────────────┐
│ GDScriptParser          │  语法分析
│ Input:  Array[Token]    │  递归下降 → AST
│ Output: ClassNode       │
└───────────┬─────────────┘
            │ ast_root
            ▼
┌─────────────────────────┐
│ GDScriptSymbolResolver  │  符号解析
│ Input:  ClassNode       │  遍历 AST → 符号表+图
│ Output: GDScriptAnalysisResult │
└─────────────────────────┘
```

### 2.2 文件规划

| 文件 | class_name | 预估行数 | 职责 |
|------|-----------|---------|------|
| `gds_tokenizer.gd` | GDScriptTokenizer | ~400 | 词法分析：逐字符扫描状态机 |
| `gds_ast_nodes.gd` | (多个节点类 + Token 枚举) | ~300 | AST 节点定义 + Token.Type 枚举 |
| `gds_parser.gd` | GDScriptParser | ~1200 | 递归下降语法分析 + 运算符优先级 |
| `gds_symbol_resolver.gd` | GDScriptSymbolResolver | ~500 | 符号解析 + 调用图/信号图/定义链构建 |
| `gds_analysis_result.gd` | GDScriptAnalysisResult 等 | ~300 | 结果容器 + 查询 API |
| `plugin.gd` | GDScriptUtil | ~100 | EditorPlugin 编辑器入口 |
| `plugin.cfg` | — | ~10 | 插件元数据配置 |
| **总计** | | **~2810** | |

文件均位于 `addons/gdscript_util/` 目录下。

### 2.3 错误处理策略

管道各阶段的错误处理遵循统一策略：

**分词器 (Tokenizer)：**
- 遇到非法字符时生成 `Token.ERROR` 令牌，其 `literal` 为错误描述字符串
- 不中断扫描——后续字符继续正常分词
- 未终止的字符串/多行注释生成 ERROR 并继续
- 缩进/括号不匹配尽可能在扫描层检测，生成 ERROR 令牌通知下游

**语法分析器 (Parser)：**
- 采用 **fail-soft** 策略：遇到语法错误时记录到 `self.error`，跳过当前语句/表达式继续解析后续内容
- 跳过策略：遇到错误后，前进到下一个语句边界（NEWLINE 或 DEDENT 处）恢复解析
- `parse()` 始终返回一个（可能不完整的）ClassNode——调用方通过检查 `error` 是否为空来判断解析是否成功
- 每个 AST 节点记录其源代码位置（line, column），便于错误定位

**符号解析器 (SymbolResolver)：**
- 未解析的标识符引用（即 `resolve(name)` 返回 null）：
  - 对于读取引用：记录到 `AnalysisResult.errors` 作为警告（不影响继续分析）
  - 对于调用目标：CallEdge 的 callee 设为 `"<unresolved: name>"`
  - 不中断整个解析过程

**错误传播：**
- 管道阶段之间通过返回值传递状态：
  - Tokenizer：通过检查 Token 流中是否存在 `ERROR` 类型令牌来判断
  - Parser：通过 `parser.error` 是否为空来判断
  - SymbolResolver：通过 `AnalysisResult.errors` 数组是否为空来判断
- 即使前一阶段有错误，后一阶段也会被调用（只要输出数据存在）——上游尽力而为，下游处理不完整数据
- 每个阶段的错误信息独立记录在最终 `AnalysisResult.errors` 中，按 `[阶段] 行:列: 描述` 格式

```gdscript
# 使用示例——带错误检查的完整管道
var tokens = tokenizer.tokenize(source)
# 检查是否有词法错误
for token in tokens:
    if token.type == Token.ERROR:
        push_warning("Lexer error at line %d: %s" % [token.start_line, token.literal])

var ast = parser.parse(tokens)
if parser.error != "":
    push_warning("Parser error: %s" % parser.error)
# 即使有警告也继续符号解析
var result = resolver.resolve(ast, path)
for err in result.errors:
    push_warning(err)
```

## 三、组件 1：GDScriptTokenizer（词法分析器）

### 3.1 Token 数据结构

```gdscript
class_name GDScriptToken
var type: int          # Token.Type 枚举值
var literal            # Variant — 标识符名称或字面量值
var start_line: int    # 起始行号 (1-based)
var start_column: int  # 起始列号 (1-based)
var end_line: int
var end_column: int
```

### 3.2 扫描算法

逐字符扫描 + 状态机分发：

```
scan():
    skip_whitespace_and_comments()
    if at_line_start: check_indent()    → INDENT / DEDENT
    c = advance()
    match c:
        "\n"     → NEWLINE
        '"', "'"  → scan_string()
        "0"-"9"  → scan_number()
        "_", a-z → scan_identifier_or_keyword()
        "@"      → scan_annotation()
        "$"      → scan_node_path()
        "#"      → skip_comment(), recurse
        多字符运算符 → scan_multi_char_op()  (==, !=, >=, <=, **, .., ...)
        单字符   → 直接返回对应 Token
```

### 3.3 缩进处理

使用 Python 风格的 INDENT/DEDENT 显式令牌：

- 维护 `indent_stack: Array[int]`，栈顶为当前缩进列号
- 每个 NEWLINE 之后检查新行的起始列号
- 列号 > 栈顶 → push + 生成 INDENT
- 列号 < 栈顶 → pop + 生成 DEDENT（可能需要多个）
- 列号 == 栈顶 → 不生成缩进令牌
- 括号内部（`()`, `[]`, `{}`）忽略缩进变化
- 支持 lambda 独立缩进栈（`push_expression_indented_block / pop_expression_indented_block`）

**Lambda 缩进规则：**
- 当分词器在表达式上下文中遇到 `func` 关键字时，调用 `push_expression_indented_block()` 保存当前缩进栈
- lambda 函数体开始于 `:` 之后，如果 lambda 体在同一行则不需要缩进处理；如果 lambda 体跨行则需要独立缩进栈
- Lambda 体解析结束后调用 `pop_expression_indented_block()` 恢复外层缩进栈
- 适用于以下场景：`var f = func(x):\n\treturn x * 2`
- 括号内的 lambda（如 `arr.map(func(x): return x * 2)`）不需要独立栈——缩进在括号内已被忽略

### 3.4 Token 类型枚举

核心子集，与 Godot 4.7 `GDScriptTokenizer::Token::Type` 对齐：

**关键字：** IF, ELIF, ELSE, FOR, WHILE, BREAK, CONTINUE, PASS, RETURN, MATCH, WHEN, FUNC, CLASS, CLASS_NAME, EXTENDS, SUPER, SELF, VAR, TK_CONST, ENUM, SIGNAL, STATIC, IS, AS, AWAIT, ASSERT, PRELOAD, YIELD, BREAKPOINT, VOID, IN, NOT, AND, OR

**字面量：** IDENTIFIER, LITERAL, CONST_PI, CONST_TAU, CONST_INF, CONST_NAN

**运算符：** EQUAL, PLUS_EQUAL, MINUS_EQUAL, STAR_EQUAL, STAR_STAR_EQUAL, SLASH_EQUAL, PERCENT_EQUAL, LESS_LESS_EQUAL, GREATER_GREATER_EQUAL, AMPERSAND_EQUAL, PIPE_EQUAL, CARET_EQUAL, EQUAL_EQUAL, BANG_EQUAL, LESS, LESS_EQUAL, GREATER, GREATER_EQUAL, PLUS, MINUS, STAR, STAR_STAR, SLASH, PERCENT, LESS_LESS, GREATER_GREATER, AMPERSAND, PIPE, TILDE, CARET, PERIOD_PERIOD, PERIOD_PERIOD_PERIOD

**标点：** PAREN_OPEN, PAREN_CLOSE, BRACKET_OPEN, BRACKET_CLOSE, BRACE_OPEN, BRACE_CLOSE, COMMA, SEMICOLON, COLON, PERIOD, FORWARD_ARROW, DOLLAR, UNDERSCORE

**空白：** NEWLINE, INDENT, DEDENT

**其他：** ANNOTATION, ERROR, TK_EOF, TK_MAX

共约 60 种令牌。暂不包含 NAMESPACE, TRAIT（Phase 3 扩展时添加）。

**关于 `or`/`||` 和 `and`/`&&`：** Godot 4.x 同时支持英文关键字形式和符号形式，两种形式在分词时生成相同的 Token 类型（`OR` 和 `AND`），不区分为不同令牌。运算符优先级表引用同一个 Token 类型。

## 四、组件 2：GDScriptParser（语法分析器）

### 4.1 AST 节点体系

所有节点继承自 `ASTNode` 基类（包含 `line`、`column` 位置信息）。

#### 声明节点
- **ClassNode**: `extends_id: String`, `classname_id: String`, `is_tool: bool`, `annotations: Array[AnnotationNode]`, `members: Array[ASTNode]`
- **FunctionNode**: `name: String`, `params: Array[ParameterNode]`, `return_type: TypeNode`, `body: SuiteNode`, `is_static: bool`, `is_coroutine: bool`
- **VariableNode**: `name: String`, `datatype: TypeNode`, `initializer: ExpressionNode`, `setter: FunctionNode`, `getter: FunctionNode`, `is_onready: bool`, `is_export: bool`
- **SignalNode**: `name: String`, `params: Array[ParameterNode]`
- **EnumNode**: `name: String`, `values: Array[{name: String, value: ExpressionNode}]`
- **ParameterNode**: `name: String`, `datatype: TypeNode`, `default_value: ExpressionNode`

#### 语句节点
- **SuiteNode**: `statements: Array[StatementNode]` — 语句块容器
- **IfNode**: `condition: ExpressionNode`, `true_branch: SuiteNode`, `false_branch: ASTNode` (IfNode 或 SuiteNode)
- **WhileNode**: `condition: ExpressionNode`, `body: SuiteNode`
- **ForNode**: `var_name: String`, `iterable: ExpressionNode`, `body: SuiteNode`
- **MatchNode**: `test: ExpressionNode`, `branches: Array[MatchBranchNode]`
- **MatchBranchNode**: `patterns: Array[ExpressionNode]`, `guard: ExpressionNode`, `body: SuiteNode`
- **ReturnNode**: `value: ExpressionNode`
- **BreakNode**, **ContinueNode**, **PassNode** — 无额外字段
- **AssertNode**: `condition: ExpressionNode`, `message: ExpressionNode`
- **AwaitNode**: `expression: ExpressionNode`
- **ExpressionStatementNode**: `expression: ExpressionNode` — 表达式作为语句

#### 表达式节点
- **BinaryOpNode**: `op: int` (Token.Type), `left: ExpressionNode`, `right: ExpressionNode`
- **UnaryOpNode**: `op: int`, `operand: ExpressionNode`
- **TernaryOpNode**: `condition: ExpressionNode`, `true_expr: ExpressionNode`, `false_expr: ExpressionNode`
- **CallNode**: `callee: ExpressionNode`, `arguments: Array[ExpressionNode]`
- **SubscriptNode**: `base: ExpressionNode`, `index: ExpressionNode` — `a[b]`
- **AttributeNode**: `base: ExpressionNode`, `name: String` — `a.b`
- **CastNode**: `expression: ExpressionNode`, `type: TypeNode` — `x as Type`
- **TypeTestNode**: `expression: ExpressionNode`, `type: TypeNode` — `x is Type`
- **AssignmentNode**: `target: ExpressionNode`, `value: ExpressionNode`, `op: int` — `=`, `+=`, `-=` 等
- **LambdaNode**: `params: Array[ParameterNode]`, `body: ExpressionNode`, `captured_vars: Array[String]` (由 SymbolResolver 填充，记录 lambda 引用的外部变量名)
- **ArrayNode**: `elements: Array[ExpressionNode]`
- **DictionaryNode**: `pairs: Array[{key: ExpressionNode, value: ExpressionNode}]`
- **IdentifierNode**: `name: String`
- **LiteralNode**: `value: Variant`
- **SelfNode**, **SuperNode**, **PreloadNode**: `path: String` (仅 Preload)

#### 辅助节点
- **AnnotationNode**: `name: String`, `arguments: Array[ExpressionNode]`
- **TypeNode**: `type_name: String`, `container_element_types: Array[TypeNode]`

### 4.2 递归下降解析

```gdscript
class_name GDScriptParser
var tokens: Array[GDScriptToken]
var pos: int
var error: String

func parse(tokens: Array) -> ClassNode:
    # 1. 处理文件级注解 (@tool, @icon...)
    # 2. 解析类体成员循环
    # 3. 返回 ClassNode
```

**语句解析入口：**
- `_parse_class_member()` → 按 Token 类型分发到 `_parse_function()`, `_parse_variable()`, `_parse_signal()`, `_parse_enum()`, `_parse_class()`, `_parse_annotation()`
- `_parse_suite()` → 期望 `COLON + NEWLINE + INDENT`，循环解析语句直到 `DEDENT`
- `_parse_statement()` → 按 Token 类型分发到各语句解析器

**表达式解析：** `_parse_expression(lv=0)` 递归下降，`_parse_atom()` 处理叶子节点。

### 4.3 运算符优先级表

| lv | 名称 | 结合性 | Token | AST 节点类型 |
|----|------|--------|-------|------------|
| 0 | 赋值 | 右 | `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `**=`, `&=`, `\|=`, `^=`, `<<=`, `>>=` | AssignmentNode |
| 1 | 类型转换 | 左 | `as` | CastNode |
| 2 | 三目 | 三目 | `if ... else` | TernaryOpNode |
| 3 | 逻辑或 | 左 | `or`, `\|\|` | BinaryOpNode |
| 4 | 逻辑与 | 左 | `and`, `&&` | BinaryOpNode |
| 5 | 逻辑非 | 单目 | `not`, `!` | UnaryOpNode |
| 6 | 成员检测 | 左 | `in` | BinaryOpNode |
| 7 | 比较 | 左 | `<`, `>`, `==`, `!=`, `<=`, `>=` | BinaryOpNode |
| 8 | 类型检测 | 左 | `is` | TypeTestNode |
| 9 | 位或 | 左 | `\|` | BinaryOpNode |
| 10 | 位异或 | 左 | `^` | BinaryOpNode |
| 11 | 位与 | 左 | `&` | BinaryOpNode |
| 12 | 移位 | 左 | `<<`, `>>` | BinaryOpNode |
| 13 | 减法 | 左 | `-` (二元) | BinaryOpNode |
| 14 | 加法 | 左 | `+` | BinaryOpNode |
| 15 | 乘除模 | 左 | `*`, `/`, `%` | BinaryOpNode |
| 16 | 幂 | 右 | `**` | BinaryOpNode |
| 17 | 负号 | 单目 | `-` (一元) | UnaryOpNode |
| 18 | 位取反 | 单目 | `~` | UnaryOpNode |
| 19 | 后缀 | 左 | `.`, `[`, `(` | AttributeNode / SubscriptNode / CallNode |

**与 3.4 op_table 的差异：**
- 新增 lv 1 (`as`), lv 8 (`is`), lv 16 (`**`)
- `.` 和 `[` 拆分为 AttributeNode 和 SubscriptNode（3.4 统一为 ExprSubscription）
- `BINOP_LEFT_PERIOD` 移除，统一使用 `BINOP_LEFT`
- 令牌名全部映射为 4.7 命名

### 4.4 SuiteNode 缩进模型

使用 INDENT/DEDENT 令牌（替代 3.4 的 `NEWLINE.param` 缩进值）：

```
解析 COLON → 期望 NEWLINE → 期望 INDENT
循环: 解析语句 → 期望 NEWLINE 或 DEDENT
DEDENT 结束块
```

## 五、组件 3：GDScriptSymbolResolver（符号解析器）

### 5.1 输出数据结构

#### SymbolTable — 嵌套作用域符号表

```gdscript
class_name SymbolTable
var parent: SymbolTable           # 外层作用域
var symbols: Dictionary           # String → Symbol

func define(name: String, kind: int, node: ASTNode, datatype: String = "") -> Symbol
func resolve(name: String) -> Symbol  # 递归向 parent 查找

class_name Symbol
enum Kind {
    CLASS = 0,       # class / inner class 定义
    FUNCTION = 1,    # func 定义
    VARIABLE = 2,    # var 定义
    SIGNAL = 3,      # signal 声明
    ENUM = 4,        # enum 定义
    PARAMETER = 5,   # 函数参数
    CONSTANT = 6,    # const 定义
    ENUM_VALUE = 7   # enum 中的值（如 enum { A, B } 中的 A）
}
var name: String
var kind: int
var declaration: ASTNode          # 指向 AST 中的声明节点
var datatype: String              # 类型标注
var is_exported: bool
```

查找优先级：当前局部作用域 → 外层块作用域 → 类成员 → 内置函数 → 全局单例

#### CallGraph — 方法调用图

```gdscript
class_name CallGraph
var edges: Array[CallEdge]

class_name CallEdge
var caller: String                # 调用方函数名
var callee: String                # 被调用方函数名
var site_line: int                # 调用所在行
var arguments: Array[ExpressionNode]
enum CallType {
    SELF = 0,         # self.method() 或隐式 self 调用
    SUPER = 1,        # super.method()
    EXTERNAL = 2,     # obj.method() —— 外部对象调用
    CONNECT = 3,      # .connect("sig", cb) 中的回调
    SIGNAL_CONNECT = 4, # signal_name.connect(cb) 中的回调
    LAMBDA = 5,       # lambda 表达式作为回调
    STATIC = 6,       # ClassName.static_method()
    EMIT = 7          # emit("signal") 信号发射
}
var call_type: int
var target_object: String         # 调用目标对象名 (外部调用时)
```

覆盖 6 种调用模式：
1. `self.foo()` — AttributeNode(base=SelfNode)
2. `foo()` — 隐式 self，IdentifierNode → 解析到类方法
3. `super.method()` — AttributeNode(base=SuperNode)
4. `obj.method()` — 标记为外部调用，记录 target_object
5. `.connect("sig", callable)` — 提取信号名和回调
6. `signal_name.connect(callable)` — 4.7 新增的 Signal.connect() 模式

#### SignalGraph — 信号流程图

```gdscript
class_name SignalGraph
var signals: Dictionary           # String → SignalInfo

class_name SignalInfo
var name: String
var declaration: SignalNode
var params: Array[String]
var emit_sites: Array[Site]       # emit("name") / name.emit()
var connect_sites: Array[Site]    # .connect("name", cb) / name.connect(cb)

class_name Site
var line: int
var node: ASTNode
var enclosing_function: String
var arguments: Array
```

#### DefUseChain — 变量定义使用链

```gdscript
class_name DefUseChain
var variables: Dictionary         # String → DefUseInfo

class_name DefUseInfo
var name: String
var def_site: DefUseSite          # 定义位置 (var / func param)
var read_sites: Array[DefUseSite] # 所有读位置
var write_sites: Array[DefUseSite] # 所有写位置

class_name DefUseSite
var line: int
var node: ASTNode
var enclosing_function: String
enum AccessType {
    DEFINE = 0,      # var x = ... 的定义
    READ = 1,        # 读取变量值
    WRITE = 2,       # 赋值写入
    READ_WRITE = 3   # 读+写（如 x += 1）
}
var access_type: int
```

### 5.2 解析策略

遍历 AST 树：
1. **进入 ClassNode** → 创建 class_scope (SymbolTable)
2. **遍历 members**：
   - VariableNode → define 变量到 class_scope
   - FunctionNode → define 函数到 class_scope，然后进入函数体：
     - 创建 local_scope (parent = class_scope)
     - define 参数到 local_scope
     - 遍历 body.statements → 递归处理语句节点
   - SignalNode → define 信号到 class_scope + 注册到 SignalGraph
3. **处理表达式中的 IdentifierNode**：
   - 写上下文 (AssignmentNode 左侧, var 声明) → 记录为 WRITE/DEFINE
   - 读上下文 (其余位置) → 记录为 READ
   - resolve 标识符名 → 关联到 Symbol
4. **进入 LambdaNode** → 创建独立的 local_scope（parent = 当前作用域）：
   - 将 lambda 参数 define 到 lambda_scope
   - 遍历 lambda.body 表达式/语句 → 递归处理
   - Lambda 引用的外部变量（不在 lambda_scope 中的标识符）标记为"捕获变量"（captured variable）——记录在 LambdaNode 附加字段 `captured_vars: Array[String]` 中
   - 如果 LambdaNode 作为 `.connect()` 的参数，其捕获变量信息用于追踪信号回调闭包
5. **处理 CallNode**：
   - 解析 callee → 确定调用目标 → 添加 CallEdge

## 六、组件 4：GDScriptAnalysisResult + EditorPlugin

### 6.1 结果容器

```gdscript
class_name GDScriptAnalysisResult
extends RefCounted

var file_path: String
var ast: ClassNode
var symbol_table: SymbolTable
var call_graph: CallGraph
var signal_graph: SignalGraph
var def_use_chain: DefUseChain
var extends_path: String
var class_name: String
var preloads: Array[String]
var errors: Array[String]

func get_all_functions() -> Array[FunctionNode]
func get_all_signals() -> Array[SignalNode]
func get_callers_of(func_name: String) -> Array[CallEdge]
func get_callees_of(func_name: String) -> Array[CallEdge]
func get_signal_flow(signal_name: String) -> SignalInfo  # 完整链路
func get_variable_usages(var_name: String) -> DefUseInfo # 完整读写链
func get_dependency_tree() -> Dictionary                 # extends + preload
```

### 6.2 使用方式

```gdscript
# 基本用法（三步管道）
var source = FileAccess.get_file_as_string("res://player.gd")
var tokens = GDScriptTokenizer.new().tokenize(source)
var ast = GDScriptParser.new().parse(tokens)
var result = GDScriptSymbolResolver.new().resolve(ast, "res://player.gd")

# 查询信号流
var flow = result.get_signal_flow("health_changed")
# → SignalInfo {
#     declaration @line 3,
#     emit_sites: [@line 8 (take_damage), @line 15 (heal)],
#     connect_sites: [@line 12 (hud.gd → _on_health_changed)]
#   }

# 查询调用者
var callers = result.get_callers_of("take_damage")
# → [_on_body_entered @line 22, _process @line 30]

# 查询变量使用
var usage = result.get_variable_usages("hp")
# → DefUseInfo {
#     def @line 2,
#     reads: [line 6, 8, 14],
#     writes: [line 7, 15]
#   }
```

### 6.3 EditorPlugin 集成

#### 6.3.1 插件生命周期

```gdscript
class_name GDScriptUtil
extends EditorPlugin

var analysis_cache: Dictionary = {}  # String(path) → GDScriptAnalysisResult

func _enter_tree():
    add_tool_menu_item("GDScript Analysis", _on_analyze_current)
    # 可选 Phase 3: 添加底部面板可视化
    # analysis_panel = preload("analysis_panel.tscn").instantiate()
    # add_control_to_bottom_panel(analysis_panel, "GDScript Analysis")

func _exit_tree():
    remove_tool_menu_item("GDScript Analysis")
    # remove_control_from_bottom_panel(analysis_panel)
    analysis_cache.clear()
```

#### 6.3.2 分析触发方式

支持三种触发模式：

1. **手动触发**（Phase 1）：用户通过 工具菜单 → "GDScript Analysis" 分析当前打开脚本
2. **保存自动分析**（Phase 2）：通过 `resource_saved` 信号监听，GDScript 文件保存时自动重新分析
3. **批量分析**（Phase 3）：分析指定目录下所有 `.gd` 文件，构建跨文件调用图

```gdscript
# 手动分析当前脚本
func _on_analyze_current():
    var editor = get_editor_interface()
    var script = editor.get_script_editor().get_current_script()
    if script and script is GDScript:
        var result = analyze_script(script.resource_path)

# 自动分析（Phase 2）
func _handles(p_object: Object) -> bool:
    return p_object is GDScript

func _edited(p_script: Object):
    if p_script is GDScript and p_script.resource_path.ends_with(".gd"):
        analyze_script(p_script.resource_path)
```

#### 6.3.3 结果呈现

- **Phase 1：** 日志输出——`print_rich()` 输出分析摘要到编辑器输出面板
- **Phase 2：** 结构化输出——通过 `GDScriptAnalysisResult` 的查询 API 在 GDScript 中程序化使用
- **Phase 3：** 可视化面板——信号图/调用图的 UI 呈现（Dock 面板）

```gdscript
# Phase 1 日志输出示例
func _print_analysis_summary(result: GDScriptAnalysisResult):
    print("[b]%s[/b] — %d functions, %d signals, %d variables" % [
        result.file_path,
        result.get_all_functions().size(),
        result.get_all_signals().size(),
        result.def_use_chain.variables.size()
    ])
    for edge in result.call_graph.edges:
        print("  %s() → %s() @line %d" % [edge.caller, edge.callee, edge.site_line])
```

#### 6.3.4 缓存策略

- 每次调用 `analyze_script(path)` 时更新缓存
- 缓存 key 为文件路径，value 为 `GDScriptAnalysisResult`
- 文件修改时间戳检查：文件未变化时跳过重新分析（Phase 3 优化）
- 插件卸载时（`_exit_tree`）清空所有缓存
- 不执行跨会话持久化缓存（避免反序列化 AST 的复杂性和内存占用）

## 七、实现阶段

### Phase 1: 基础管道（优先）

**目标：** 建立完整的"源码 → AST"解析管路。交付后可将任意 `.gd` 文件解析为结构化 AST 树，覆盖核心 GDScript 语法（类/函数/变量/控制流/表达式/lambda/注解），通过 10 个验收测试用例验证正确性。为 Phase 2 的符号分析提供基础。

1. Token 类型枚举 + AST 节点类定义 (`gds_ast_nodes.gd`)
2. GDScriptTokenizer 词法分析器
3. GDScriptParser 语法分析器（核心子集语法）
4. 基础单元测试（解析 `.gd` 源文件 → 验证 AST 结构）

**交付物：** 可解析 `.gd` 源文件并生成 AST

### Phase 2: 符号分析

**目标：** 在 AST 之上构建符号表和逻辑流图，实现信号连接/方法调用/变量读写的跨函数追踪能力。交付后可回答"这个信号在哪里发射？谁连接了它？"、"`take_damage()` 被哪些函数调用？"、"变量 `hp` 在哪些位置被读写？"等问题。

1. SymbolTable + 嵌套作用域
2. CallGraph 构建（6 种调用模式）
3. SignalGraph 构建（声明 → emit → connect 链路）
4. DefUseChain 构建（变量读写追踪）
5. GDScriptAnalysisResult 查询 API

**交付物：** 完整逻辑流分析能力（调用图 + 信号链 + 变量追踪）

### Phase 3: 扩展完善

**目标：** 将分析工具融入 Godot 编辑器工作流，支持完整 4.7 语法，达到实用级别的性能和错误容忍度。Phase 3 完成后，工具可在编辑器内部直接使用，覆盖所有 GDScript 语言特性，并能处理大型项目（1000+ 行脚本）。

1. EditorPlugin 编辑器面板集成
2. 完整 4.7 语法覆盖（NAMESPACE, TRAIT, 格式化字符串等）
3. 性能优化（1000 行 `.gd` 文件解析 < 500ms）
4. 错误恢复（部分解析失败时继续，最大化分析覆盖）
5. 泛用性增强（跨文件类型追踪、多文件批量分析）

**交付物：** 编辑器就绪的完整分析工具

## 八、与当前工程的差异总结

| 维度 | 3.4 当前工程 | 4.7 目标工程 |
|------|------------|------------|
| 输入 | `.gdc` 字节码 | `.gd` 源码文本 |
| 词法 | 无需分词器（字节码直接解码） | 完整 GDScript 分词器 |
| 令牌数 | ~120 (OP_/CF_/PR_ 前缀) | ~60 (无前缀) |
| 缩进 | NEWLINE.param 表示缩进值 | INDENT/DEDENT 显式令牌 |
| AST 节点 | ~15 (TreeBase 族) | ~30 (ASTNode 族) |
| 类型系统 | 无 | TypeNode + DataType |
| 语义分析 | 无 | SymbolTable + CallGraph + SignalGraph + DefUseChain |
| 文件数 | 2 | 6 |
| 预估行数 | ~1478 | ~2810 |
| 插件入口 | EditorPlugin (空实现) | EditorPlugin (功能入口) |
