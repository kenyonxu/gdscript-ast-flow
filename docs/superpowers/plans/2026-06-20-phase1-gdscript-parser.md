# Phase 1: GDScript 基础解析管道 实现计划

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立完整的"`.gd` 源码 → AST"解析管路，覆盖核心 GDScript 4.7 语法，通过 10 个验收测试用例验证。

**Architecture:** 三文件管道 — `gds_ast_nodes.gd`(令牌枚举+节点类) → `gds_tokenizer.gd`(词法分析) → `gds_parser.gd`(语法分析)，通过 `plugin.gd` 暴露 EditorPlugin 入口。纯 GDScript 实现，无外部依赖。

**Tech Stack:** Godot 4.7, GDScript, EditorPlugin API

**Spec reference:** `docs/superpowers/specs/2026-06-20-godot47-gdscript-parser-design.md`

---

## 文件结构

```
addons/gdscript_util/
├── gds_ast_nodes.gd    # Token 枚举 + AST 节点类 (~300行)
├── gds_tokenizer.gd    # 词法分析器 (~400行)
├── gds_parser.gd       # 语法分析器 (~1200行)
├── plugin.gd           # EditorPlugin 入口 (~100行)
└── plugin.cfg          # 插件配置

tests/                  # 测试脚本
├── test_tokenizer.gd   # 分词器单元测试
└── test_parser.gd      # 解析器单元测试 + 10 个验收测试
```

**职责边界：**
- `gds_ast_nodes.gd` — 纯数据定义：Token.Type 枚举、GDScriptToken、所有 AST 节点类。零逻辑，只有 `class ... extends RefCounted` 定义。
- `gds_tokenizer.gd` — 接收 `String` 源码 → 返回 `Array[GDScriptToken]`。不涉及 AST。
- `gds_parser.gd` — 接收 `Array[GDScriptToken]` → 返回 `ClassNode`（AST 根）。不涉及字符处理。
- `plugin.gd` — EditorPlugin 胶水代码，调用分词器+解析器，输出到编辑器面板。

---

## Chunk 1: Token 类型 + AST 节点定义

### Task 1: 创建项目骨架

**Files:** Create: `addons/gdscript_util/plugin.cfg`

- [ ] **Step 1: 更新 plugin.cfg**

```cfg
[plugin]

name="gdscript_util"
description="GDScript Analysis Utilities for Godot 4.7"
author="arlez80"
version="2.0.0"
script="plugin.gd"
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/plugin.cfg
git commit -m "feat: 更新 plugin.cfg 至 v2.0.0"
```

---

### Task 2: Token 类型枚举 + GDScriptToken

**Files:** Create: `addons/gdscript_util/gds_ast_nodes.gd`

- [ ] **Step 1: 创建 Token.Type 枚举（关键字部分）**

```gdscript
# addons/gdscript_util/gds_ast_nodes.gd
# GDScript 4.7 Token 类型枚举 + AST 节点类定义
# 纯数据定义，零逻辑

class_name GDScriptToken
extends RefCounted

# Token 类型枚举 — 与 Godot 4.7 GDScriptTokenizer::Token::Type 对齐
enum Type {
    EMPTY,
    # 关键字
    IF, ELIF, ELSE, FOR, WHILE, BREAK, CONTINUE, PASS,
    RETURN, MATCH, WHEN,
    FUNC, CLASS, CLASS_NAME, EXTENDS, SUPER, SELF,
    VAR, TK_CONST, ENUM, SIGNAL,
    STATIC, IS, AS, AWAIT,
    ASSERT, PRELOAD, YIELD, BREAKPOINT,
    VOID, IN, NOT, AND, OR,
    # 字面量
    IDENTIFIER, LITERAL,
    CONST_PI, CONST_TAU, CONST_INF, CONST_NAN,
    # 比较
    EQUAL_EQUAL, BANG_EQUAL,
    LESS, LESS_EQUAL, GREATER, GREATER_EQUAL,
    # 赋值
    EQUAL,
    PLUS_EQUAL, MINUS_EQUAL, STAR_EQUAL, STAR_STAR_EQUAL,
    SLASH_EQUAL, PERCENT_EQUAL,
    LESS_LESS_EQUAL, GREATER_GREATER_EQUAL,
    AMPERSAND_EQUAL, PIPE_EQUAL, CARET_EQUAL,
    # 数学
    PLUS, MINUS, STAR, STAR_STAR, SLASH, PERCENT,
    # 位运算
    AMPERSAND, PIPE, TILDE, CARET,
    LESS_LESS, GREATER_GREATER,
    # 标点
    PAREN_OPEN, PAREN_CLOSE,
    BRACKET_OPEN, BRACKET_CLOSE,
    BRACE_OPEN, BRACE_CLOSE,
    COMMA, SEMICOLON, COLON, PERIOD,
    PERIOD_PERIOD, PERIOD_PERIOD_PERIOD,
    FORWARD_ARROW, DOLLAR, UNDERSCORE,
    QUESTION_MARK,
    # 空白
    NEWLINE, INDENT, DEDENT,
    # 注解
    ANNOTATION,
    # 特殊
    ERROR, TK_EOF, TK_MAX
}
```

- [ ] **Step 2: 添加 GDScriptToken 类字段**

```gdscript
# Token 实例字段
var type: int = Type.EMPTY
var literal: Variant = null    # 标识符名(StringName) 或 字面量值(Variant)
var start_line: int = 1
var start_column: int = 1
var end_line: int = 1
var end_column: int = 1

func get_name() -> String:
    return Type.keys()[type] if type >= 0 and type < Type.size() else "UNKNOWN"

func _to_string() -> String:
    var name = get_name()
    if literal != null and type in [Type.IDENTIFIER, Type.LITERAL, Type.ANNOTATION]:
        return "%s(%s) @%d:%d" % [name, literal, start_line, start_column]
    return "%s @%d:%d" % [name, start_line, start_column]
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/gds_ast_nodes.gd
git commit -m "feat: Token.Type 枚举 + GDScriptToken 类"
```

---

### Task 3: AST 基类 + 辅助节点

**Files:** Modify: `addons/gdscript_util/gds_ast_nodes.gd` (追加)

- [ ] **Step 1: 添加 ASTNode 基类 + TypeNode + AnnotationNode**

```gdscript
# ---- AST 节点基类 ----
class ASTNode:
    extends RefCounted
    var line: int = 0
    var column: int = 0

# ---- 类型节点 ----
class TypeNode:
    extends RefCounted
    var type_name: String = ""          # "int", "Array", "Node" 等
    var container_element_types: Array[TypeNode] = []  # 泛型参数: Array[int] → [TypeNode("int")]

# ---- 注解节点 ----
class AnnotationNode:
    extends ASTNode
    var name: String = ""               # @export, @onready, @tool ...
    var arguments: Array = []           # of ExpressionNode
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_ast_nodes.gd
git commit -m "feat: ASTNode基类 + TypeNode + AnnotationNode"
```

---

### Task 4: 声明节点

**Files:** Modify: `addons/gdscript_util/gds_ast_nodes.gd` (追加)

- [ ] **Step 1: 添加 ClassNode、FunctionNode、ParameterNode**

```gdscript
class ClassNode:
    extends ASTNode
    var extends_id: String = ""         # extends 的类路径
    var classname_id: String = ""       # class_name 名称
    var is_tool: bool = false           # @tool 注解
    var annotations: Array[AnnotationNode] = []
    var members: Array = []             # of ASTNode (FunctionNode, VariableNode, ...)

class FunctionNode:
    extends ASTNode
    var name: String = ""
    var params: Array = []              # of ParameterNode
    var return_type: TypeNode = null
    var body = null                     # SuiteNode
    var is_static: bool = false
    var is_coroutine: bool = false      # 使用 await 的函数

class ParameterNode:
    extends ASTNode
    var name: String = ""
    var datatype: TypeNode = null
    var default_value = null            # ExpressionNode or null
```

- [ ] **Step 2: 添加 VariableNode、SignalNode、EnumNode**

```gdscript
class VariableNode:
    extends ASTNode
    var name: String = ""
    var datatype: TypeNode = null
    var initializer = null              # ExpressionNode or null
    var setter = null                   # FunctionNode or null (内联 setter)
    var getter = null                   # FunctionNode or null (内联 getter)
    var is_onready: bool = false
    var is_export: bool = false

class SignalNode:
    extends ASTNode
    var name: String = ""
    var params: Array[ParameterNode] = []

class EnumNode:
    extends ASTNode
    var name: String = ""
    var values: Array = []              # of Dictionary {name: String, value: ExpressionNode}
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/gds_ast_nodes.gd
git commit -m "feat: 声明节点 — ClassNode/FunctionNode/VariableNode/SignalNode/EnumNode/ParameterNode"
```

---

### Task 5: 语句节点

**Files:** Modify: `addons/gdscript_util/gds_ast_nodes.gd` (追加)

- [ ] **Step 1: 添加 SuiteNode + IfNode/WhileNode/ForNode**

```gdscript
class SuiteNode:
    extends ASTNode
    var statements: Array = []          # of ASTNode (语句)

class IfNode:
    extends ASTNode
    var condition = null                # ExpressionNode
    var true_branch: SuiteNode = null
    var false_branch = null             # IfNode or SuiteNode or null

class WhileNode:
    extends ASTNode
    var condition = null                # ExpressionNode
    var body: SuiteNode = null

class ForNode:
    extends ASTNode
    var var_name: String = ""
    var iterable = null                 # ExpressionNode
    var body: SuiteNode = null
```

- [ ] **Step 2: 添加 Match 相关 + 剩余语句节点**

```gdscript
class MatchNode:
    extends ASTNode
    var test = null                     # ExpressionNode
    var branches: Array = []            # of MatchBranchNode

class MatchBranchNode:
    extends ASTNode
    var patterns: Array = []            # of ExpressionNode
    var guard = null                    # ExpressionNode or null (Phase 3)
    var body: SuiteNode = null

class ReturnNode:
    extends ASTNode
    var value = null                    # ExpressionNode or null

class BreakNode:
    extends ASTNode

class ContinueNode:
    extends ASTNode

class PassNode:
    extends ASTNode

class AssertNode:
    extends ASTNode
    var condition = null                # ExpressionNode
    var message = null                  # ExpressionNode or null

class AwaitNode:
    extends ASTNode
    var expression = null               # ExpressionNode

class ExpressionStatementNode:
    extends ASTNode
    var expression = null               # ExpressionNode
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/gds_ast_nodes.gd
git commit -m "feat: 语句节点 — Suite/If/While/For/Match/Return/Break/Continue/Pass/Assert/Await"
```

---

### Task 6: 表达式节点

**Files:** Modify: `addons/gdscript_util/gds_ast_nodes.gd` (追加)

- [ ] **Step 1: 添加二元/一元/三目/赋值节点**

```gdscript
class BinaryOpNode:
    extends ASTNode
    var op: int = GDScriptToken.Type.EMPTY
    var left = null                     # ExpressionNode
    var right = null                    # ExpressionNode

class UnaryOpNode:
    extends ASTNode
    var op: int = GDScriptToken.Type.EMPTY
    var operand = null                  # ExpressionNode

class TernaryOpNode:
    extends ASTNode
    var condition = null                # ExpressionNode
    var true_expr = null                # ExpressionNode
    var false_expr = null               # ExpressionNode

class AssignmentNode:
    extends ASTNode
    var target = null                   # ExpressionNode
    var value = null                    # ExpressionNode
    var op: int = GDScriptToken.Type.EQUAL  # =, +=, -=, 等
```

- [ ] **Step 2: 添加调用/访问/类型操作节点**

```gdscript
class CallNode:
    extends ASTNode
    var callee = null                   # ExpressionNode
    var arguments: Array = []           # of ExpressionNode

class SubscriptNode:
    extends ASTNode
    var base = null                     # ExpressionNode  — a[b] 中的 a
    var index = null                    # ExpressionNode  — a[b] 中的 b

class AttributeNode:
    extends ASTNode
    var base = null                     # ExpressionNode  — a.b 中的 a
    var name: String = ""               # a.b 中的 b

class CastNode:
    extends ASTNode
    var expression = null               # ExpressionNode
    var type: TypeNode = null           # 目标类型

class TypeTestNode:
    extends ASTNode
    var expression = null               # ExpressionNode
    var type: TypeNode = null           # 测试类型
```

- [ ] **Step 3: 添加 Lambda/字面量/叶子节点**

```gdscript
class LambdaNode:
    extends ASTNode
    var params: Array[ParameterNode] = []
    var body = null                     # ExpressionNode (单表达式) 或 SuiteNode (多语句)
    var captured_vars: Array[String] = []  # 由 SymbolResolver 填充

class ArrayNode:
    extends ASTNode
    var elements: Array = []            # of ExpressionNode

class DictionaryNode:
    extends ASTNode
    var pairs: Array = []               # of Dictionary {key: ExpressionNode, value: ExpressionNode}

class IdentifierNode:
    extends ASTNode
    var name: String = ""

class LiteralNode:
    extends ASTNode
    var value: Variant = null

class SelfNode:
    extends ASTNode

class SuperNode:
    extends ASTNode

class PreloadNode:
    extends ASTNode
    var path: String = ""
```

- [ ] **Step 4: 提交**

```bash
git add addons/gdscript_util/gds_ast_nodes.gd
git commit -m "feat: 表达式节点 — 15种表达式 AST 节点类型"
```

---

## Chunk 2: 词法分析器

### Task 7: Tokenizer 框架 + 空白/注释/换行处理

**Files:** Create: `addons/gdscript_util/gds_tokenizer.gd`

- [ ] **Step 1: 创建类骨架和 tokenize() 入口**

```gdscript
# addons/gdscript_util/gds_tokenizer.gd
# GDScript 4.7 词法分析器 — 将源码文本转换为 GDScriptToken 流

class_name GDScriptTokenizer
extends RefCounted

var source: String = ""
var _pos: int = 0
var _line: int = 1
var _column: int = 1
var _start_line: int = 1
var _start_column: int = 1

# 缩进状态
var indent_stack: Array[int] = [0]     # 栈顶 = 当前缩进级别
var pending_indents: int = 0           # >0 需要生成 INDENT, <0 需要生成 DEDENT
var paren_level: int = 0               # 括号嵌套深度
var at_line_start: bool = true         # 是否在行首（用于缩进检测）
var last_was_newline: bool = false

func tokenize(p_source: String) -> Array[GDScriptToken]:
    source = p_source
    _pos = 0
    _line = 1
    _column = 1
    indent_stack = [0]
    pending_indents = 0
    paren_level = 0
    at_line_start = true
    last_was_newline = false

    var tokens: Array[GDScriptToken] = []
    while _pos < source.length():
        var token = _scan()
        if token != null:
            tokens.append(token)
            if token.type == GDScriptToken.Type.ERROR:
                # 记录错误但继续扫描
                pass

    # 文件末尾生成剩余的 DEDENT + NEWLINE + EOF
    _flush_indents(tokens)
    tokens.append(_make_token(GDScriptToken.Type.TK_EOF))
    return tokens
```

- [ ] **Step 2: 添加辅助方法**

```gdscript
func _make_token(p_type: int, p_literal = null) -> GDScriptToken:
    var t = GDScriptToken.new()
    t.type = p_type
    t.literal = p_literal
    t.start_line = _start_line
    t.start_column = _start_column
    t.end_line = _line
    t.end_column = _column
    return t

func _peek(p_offset: int = 0) -> String:
    var idx = _pos + p_offset
    if idx >= source.length():
        return "\0"
    return source[idx]

func _advance() -> String:
    if _pos >= source.length():
        return "\0"
    var c = source[_pos]
    _pos += 1
    if c == "\n":
        _line += 1
        _column = 1
    else:
        _column += 1
    return c

func _match(p_expected: String) -> bool:
    if _peek() == p_expected:
        _advance()
        return true
    return false
```

- [ ] **Step 3: 实现 _scan() 主分发 + 空白/注释/换行**

```gdscript
func _scan() -> GDScriptToken:
    _start_line = _line
    _start_column = _column

    # 跳过空白
    while _peek() in [" ", "\t", "\r"]:
        _advance()

    # 检查缩进 (仅在行首且不在括号内)
    if at_line_start and paren_level == 0:
        if _peek() != "\n":
            var col = _column
            _check_indent(col)

    c = _advance()

    # 空字符保护
    if c == "\0":
        return null

    match c:
        "\n":
            # 括号内的换行被忽略
            if paren_level > 0:
                return null
            if last_was_newline:
                return null  # 合并连续空行
            last_was_newline = true
            at_line_start = true
            return _make_token(GDScriptToken.Type.NEWLINE)

        "#":
            _skip_comment()
            return null

        _:
            last_was_newline = false
            at_line_start = false
            return _scan_token(c)
```

- [ ] **Step 4: 实现缩进检测 _check_indent**

```gdscript
func _check_indent(p_column: int):
    var current_indent = indent_stack[-1]  # peek top
    if p_column > current_indent:
        # 缩进增加 → 待生成 INDENT
        pending_indents += 1
        indent_stack.append(p_column)
    elif p_column < current_indent:
        # 缩进减少 → 待生成 DEDENT
        while p_column < indent_stack[-1]:
            pending_indents -= 1
            indent_stack.pop_back()
            if indent_stack.is_empty():
                indent_stack.append(0)
                break
        # 不允许缩进到未定义级别
        if p_column != indent_stack[-1]:
            return  # (Phase 3: 生成 ERROR token)

func _flush_indents(p_tokens: Array):
    # 在 NEWLINE 后插入 INDENT/DEDENT
    var i = 0
    while i < p_tokens.size():
        var t = p_tokens[i]
        if t.type == GDScriptToken.Type.NEWLINE:
            var next_i = i + 1
            if next_i < p_tokens.size():
                var next_t = p_tokens[next_i]
                # 如果下一行有缩进变化，在 NEWLINE 后插入
                pass
        i += 1
    # 简化方案：文件末尾生成所有待 DEDENT
    while pending_indents < 0:
        p_tokens.append(_make_token(GDScriptToken.Type.DEDENT))
        pending_indents += 1
```

- [ ] **Step 5: 实现 _skip_comment**

```gdscript
func _skip_comment():
    while _pos < source.length() and _peek() != "\n":
        _advance()
```

- [ ] **Step 6: 提交**

```bash
git add addons/gdscript_util/gds_tokenizer.gd
git commit -m "feat: Tokenizer 框架 — 主扫描+空白/注释/换行+缩进检测"
```

---

### Task 8: Tokenizer — 标识符/关键字/注解

**Files:** Modify: `addons/gdscript_util/gds_tokenizer.gd` (追加)

- [ ] **Step 1: 实现 _scan_token 分发入口 + _scan_identifier**

```gdscript
func _scan_token(p_first: String) -> GDScriptToken:
    match p_first:
        "_", "a".."z", "A".."Z":
            return _scan_identifier(p_first)

        "@":
            return _scan_annotation()

        "0".."9":
            return _scan_number(p_first)

        "\"", "'":
            return _scan_string(p_first[0])

        "$":
            if _peek().is_valid_identifier():
                # $NodePath 语法 — 视为特殊的标识符引用
                return _scan_node_path()
            return _make_token(GDScriptToken.Type.DOLLAR)

        _:
            return _scan_operator(p_first)

func _scan_identifier(p_first: String) -> GDScriptToken:
    var name = p_first
    while _pos < source.length():
        var c = _peek()
        if c.is_valid_identifier() or c in ["0".."9"]:
            name += c
            _advance()
        else:
            break

    # 关键字映射表
    const keywords = {
        "if": GDScriptToken.Type.IF,
        "elif": GDScriptToken.Type.ELIF,
        "else": GDScriptToken.Type.ELSE,
        "for": GDScriptToken.Type.FOR,
        "while": GDScriptToken.Type.WHILE,
        "break": GDScriptToken.Type.BREAK,
        "continue": GDScriptToken.Type.CONTINUE,
        "pass": GDScriptToken.Type.PASS,
        "return": GDScriptToken.Type.RETURN,
        "match": GDScriptToken.Type.MATCH,
        "when": GDScriptToken.Type.WHEN,
        "func": GDScriptToken.Type.FUNC,
        "class": GDScriptToken.Type.CLASS,
        "class_name": GDScriptToken.Type.CLASS_NAME,
        "extends": GDScriptToken.Type.EXTENDS,
        "super": GDScriptToken.Type.SUPER,
        "self": GDScriptToken.Type.SELF,
        "var": GDScriptToken.Type.VAR,
        "const": GDScriptToken.Type.TK_CONST,
        "enum": GDScriptToken.Type.ENUM,
        "signal": GDScriptToken.Type.SIGNAL,
        "static": GDScriptToken.Type.STATIC,
        "is": GDScriptToken.Type.IS,
        "as": GDScriptToken.Type.AS,
        "await": GDScriptToken.Type.AWAIT,
        "assert": GDScriptToken.Type.ASSERT,
        "preload": GDScriptToken.Type.PRELOAD,
        "yield": GDScriptToken.Type.YIELD,
        "breakpoint": GDScriptToken.Type.BREAKPOINT,
        "void": GDScriptToken.Type.VOID,
        "in": GDScriptToken.Type.IN,
        "not": GDScriptToken.Type.NOT,
        "and": GDScriptToken.Type.AND,
        "or": GDScriptToken.Type.OR,
    }

    if keywords.has(name):
        return _make_token(keywords[name])

    # 内置常量
    const builtin_consts = {
        "PI": GDScriptToken.Type.CONST_PI,
        "TAU": GDScriptToken.Type.CONST_TAU,
        "INF": GDScriptToken.Type.CONST_INF,
        "NAN": GDScriptToken.Type.CONST_NAN,
    }
    if builtin_consts.has(name):
        return _make_token(builtin_consts[name])

    # 普通标识符
    return _make_token(GDScriptToken.Type.IDENTIFIER, name)
```

- [ ] **Step 2: 实现 _scan_annotation + _scan_node_path**

```gdscript
func _scan_annotation() -> GDScriptToken:
    var name = ""
    while _pos < source.length():
        var c = _peek()
        if c.is_valid_identifier() or c in ["0".."9", "_"]:
            name += c
            _advance()
        else:
            break
    return _make_token(GDScriptToken.Type.ANNOTATION, name)

func _scan_node_path() -> GDScriptToken:
    _advance()  # 跳过 $
    var path = ""
    while _pos < source.length():
        var c = _peek()
        if c == "/" or c.is_valid_identifier() or c in ["0".."9", "_", "%"]:
            path += c
            _advance()
        else:
            break
    return _make_token(GDScriptToken.Type.IDENTIFIER, "$" + path)
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/gds_tokenizer.gd
git commit -m "feat: Tokenizer — 标识符/关键字/注解/$NodePath 扫描"
```

---

### Task 9: Tokenizer — 数字/字符串

**Files:** Modify: `addons/gdscript_util/gds_tokenizer.gd` (追加)

- [ ] **Step 1: 实现 _scan_number**

```gdscript
func _scan_number(p_first: String) -> GDScriptToken:
    var num_str = p_first
    var is_float = false
    var is_hex = false

    # 十六进制前缀
    if p_first == "0" and _peek().to_lower() == "x":
        is_hex = true
        num_str += _advance()
        while _pos < source.length():
            var c = _peek()
            if c.is_valid_hex_number():
                num_str += c
                _advance()
            elif c == "_":  # 数字分隔符
                _advance()
            else:
                break
        var value = num_str.hex_to_int()
        return _make_token(GDScriptToken.Type.LITERAL, value)

    # 整数 / 浮点数
    while _pos < source.length():
        var c = _peek()
        if c in ["0".."9"]:
            num_str += c
            _advance()
        elif c == "." and not is_float and _peek(1) in ["0".."9"]:
            is_float = true
            num_str += c
            _advance()
        elif c == "_":
            _advance()
        else:
            break

    if is_float:
        return _make_token(GDScriptToken.Type.LITERAL, float(num_str))
    return _make_token(GDScriptToken.Type.LITERAL, int(num_str))
```

- [ ] **Step 2: 实现 _scan_string**

```gdscript
func _scan_string(p_quote: String) -> GDScriptToken:
    var str_value = ""
    while _pos < source.length():
        var c = _advance()
        if c == "\0":
            return _make_token(GDScriptToken.Type.ERROR, "未终止的字符串")
        if c == "\\":
            var next = _advance()
            match next:
                "n": str_value += "\n"
                "t": str_value += "\t"
                "r": str_value += "\r"
                "\\": str_value += "\\"
                "\"": str_value += "\""
                "'": str_value += "'"
                _: str_value += next
        elif c == p_quote:
            break
        else:
            str_value += c

    return _make_token(GDScriptToken.Type.LITERAL, str_value)
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/gds_tokenizer.gd
git commit -m "feat: Tokenizer — 数字/字符串扫描"
```

---

### Task 10: Tokenizer — 运算符/标点

**Files:** Modify: `addons/gdscript_util/gds_tokenizer.gd` (追加)

- [ ] **Step 1: 实现 _scan_operator 多字符匹配**

```gdscript
func _scan_operator(p_first: String) -> GDScriptToken:
    match p_first:
        "!":
            if _match("="): return _make_token(GDScriptToken.Type.BANG_EQUAL)
            return _make_token(GDScriptToken.Type.NOT)  # 注意: ! 映射为 NOT

        "=":
            if _match("="): return _make_token(GDScriptToken.Type.EQUAL_EQUAL)
            return _make_token(GDScriptToken.Type.EQUAL)

        "<":
            if _match("<"):
                if _match("="): return _make_token(GDScriptToken.Type.LESS_LESS_EQUAL)
                return _make_token(GDScriptToken.Type.LESS_LESS)
            if _match("="): return _make_token(GDScriptToken.Type.LESS_EQUAL)
            return _make_token(GDScriptToken.Type.LESS)

        ">":
            if _match(">"):
                if _match("="): return _make_token(GDScriptToken.Type.GREATER_GREATER_EQUAL)
                return _make_token(GDScriptToken.Type.GREATER_GREATER)
            if _match("="): return _make_token(GDScriptToken.Type.GREATER_EQUAL)
            return _make_token(GDScriptToken.Type.GREATER)

        "+":
            if _match("="): return _make_token(GDScriptToken.Type.PLUS_EQUAL)
            return _make_token(GDScriptToken.Type.PLUS)

        "-":
            if _match("="): return _make_token(GDScriptToken.Type.MINUS_EQUAL)
            # > 是 forward arrow -> (函数返回类型标注)
            if _match(">"): return _make_token(GDScriptToken.Type.FORWARD_ARROW)
            return _make_token(GDScriptToken.Type.MINUS)

        "*":
            if _match("*"):
                if _match("="): return _make_token(GDScriptToken.Type.STAR_STAR_EQUAL)
                return _make_token(GDScriptToken.Type.STAR_STAR)
            if _match("="): return _make_token(GDScriptToken.Type.STAR_EQUAL)
            return _make_token(GDScriptToken.Type.STAR)

        "/":
            if _match("="): return _make_token(GDScriptToken.Type.SLASH_EQUAL)
            return _make_token(GDScriptToken.Type.SLASH)

        "%":
            if _match("="): return _make_token(GDScriptToken.Type.PERCENT_EQUAL)
            return _make_token(GDScriptToken.Type.PERCENT)

        "&":
            if _match("="): return _make_token(GDScriptToken.Type.AMPERSAND_EQUAL)
            if _match("&"): return _make_token(GDScriptToken.Type.AND)  # && → AND
            return _make_token(GDScriptToken.Type.AMPERSAND)

        "|":
            if _match("="): return _make_token(GDScriptToken.Type.PIPE_EQUAL)
            if _match("|"): return _make_token(GDScriptToken.Type.OR)   # || → OR
            return _make_token(GDScriptToken.Type.PIPE)

        "^":
            if _match("="): return _make_token(GDScriptToken.Type.CARET_EQUAL)
            return _make_token(GDScriptToken.Type.CARET)

        "~":
            return _make_token(GDScriptToken.Type.TILDE)

        "(":
            paren_level += 1
            return _make_token(GDScriptToken.Type.PAREN_OPEN)

        ")":
            paren_level = max(0, paren_level - 1)
            return _make_token(GDScriptToken.Type.PAREN_CLOSE)

        "[":
            paren_level += 1
            return _make_token(GDScriptToken.Type.BRACKET_OPEN)

        "]":
            paren_level = max(0, paren_level - 1)
            return _make_token(GDScriptToken.Type.BRACKET_CLOSE)

        "{":
            paren_level += 1
            return _make_token(GDScriptToken.Type.BRACE_OPEN)

        "}":
            paren_level = max(0, paren_level - 1)
            return _make_token(GDScriptToken.Type.BRACE_CLOSE)

        ",":
            return _make_token(GDScriptToken.Type.COMMA)

        ";":
            return _make_token(GDScriptToken.Type.SEMICOLON)

        ":":
            return _make_token(GDScriptToken.Type.COLON)

        ".":
            if _match("."):
                if _match("."): return _make_token(GDScriptToken.Type.PERIOD_PERIOD_PERIOD)
                return _make_token(GDScriptToken.Type.PERIOD_PERIOD)
            return _make_token(GDScriptToken.Type.PERIOD)

        "?":
            return _make_token(GDScriptToken.Type.QUESTION_MARK)

        _:
            return _make_token(GDScriptToken.Type.ERROR, "非法字符: '%s'" % p_first)
```

- [ ] **Step 2: 修改 _flush_indents — 在 NEWLINE 后插入 INDENT/DEDENT**

```gdscript
func _flush_indents(p_tokens: Array):
    # 文件末尾的剩余 DEDENT
    for i in range(abs(pending_indents)):
        p_tokens.append(_make_token(GDScriptToken.Type.DEDENT))

func _check_indent(p_column: int):
    var current_indent = indent_stack[-1]
    if p_column > current_indent:
        indent_stack.append(p_column)
        _pending_tokens.append(_make_token(GDScriptToken.Type.INDENT))
    elif p_column < current_indent:
        while p_column < indent_stack[-1]:
            indent_stack.pop_back()
            _pending_tokens.append(_make_token(GDScriptToken.Type.DEDENT))
            if indent_stack.is_empty():
                indent_stack.append(0)
                break
```

- [ ] **Step 3: 重构 _scan 以正确处理缩进令牌插入**

在 `_scan()` 方法开头添加：优先检查 `_pending_tokens` 队列是否有待输出的 INDENT/DEDENT：

需更新 `_scan()` 方法——在 Tokenizer 类中添加 `var _pending_tokens: Array = []` 字段，并在 `_scan()` 开头检查：

```gdscript
func _scan() -> GDScriptToken:
    # 优先输出待处理的 INDENT/DEDENT
    if not _pending_tokens.is_empty():
        return _pending_tokens.pop_front()
    # ... 原有扫描逻辑
```

- [ ] **Step 4: 提交**

```bash
git add addons/gdscript_util/gds_tokenizer.gd
git commit -m "feat: Tokenizer — 运算符/标点多字符匹配 + 缩进令牌插入"
```

---

## Chunk 3: 语法分析器

### Task 11: Parser 框架

**Files:** Create: `addons/gdscript_util/gds_parser.gd`

- [ ] **Step 1: 创建 Parser 类骨架 + Token 辅助方法**

```gdscript
# addons/gdscript_util/gds_parser.gd
# GDScript 4.7 语法分析器 — 递归下降解析 Token 流 → AST

class_name GDScriptParser
extends RefCounted

var tokens: Array[GDScriptToken] = []
var pos: int = 0
var error: String = ""
var _error_line: int = 0
var _error_column: int = 0

func parse(p_tokens: Array) -> ClassNode:
    tokens = p_tokens
    pos = 0
    error = ""

    var root = ClassNode.new()

    # 解析文件级注解 (@tool, @icon...)
    while _peek() and _peek().type == GDScriptToken.Type.ANNOTATION:
        root.annotations.append(_parse_annotation())

    # 解析类体成员
    while _peek() and _peek().type != GDScriptToken.Type.TK_EOF:
        var member = _parse_class_member()
        if member != null:
            root.members.append(member)
        else:
            # 错误恢复: 跳过当前行
            _skip_to_newline()

    # 提取 extends 和 class_name
    for member in root.members:
        if member is VariableNode and member.name == "":
            # extends 在 parse 阶段已直接设置
            pass

    return root

# ---- 辅助方法 ----
func _peek() -> GDScriptToken:
    if pos < tokens.size():
        return tokens[pos]
    return null

func _advance() -> GDScriptToken:
    if pos < tokens.size():
        var t = tokens[pos]
        pos += 1
        return t
    return null

func _match(p_type: int) -> bool:
    if _peek() and _peek().type == p_type:
        _advance()
        return true
    return false

func _expect(p_type: int, p_error: String = "") -> GDScriptToken:
    if _match(p_type):
        return tokens[pos - 1]
    _set_error(p_error if p_error != "" else "期望 %s" % GDScriptToken.Type.keys()[p_type])
    return null

func _set_error(p_msg: String):
    if error == "":  # 只记录第一个错误
        error = p_msg
        if _peek():
            _error_line = _peek().start_line
            _error_column = _peek().start_column

func _skip_to_newline():
    while _peek() and _peek().type != GDScriptToken.Type.NEWLINE and _peek().type != GDScriptToken.Type.TK_EOF:
        _advance()
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_parser.gd
git commit -m "feat: Parser 框架 — 主循环 + Token 辅助 + 错误恢复"
```

---

### Task 12: Parser — 类解析 + 注解

**Files:** Modify: `addons/gdscript_util/gds_parser.gd` (追加)

- [ ] **Step 1: 实现 _parse_class_member + _parse_annotation**

```gdscript
func _parse_annotation() -> AnnotationNode:
    var t = _advance()  # ANNOTATION token
    var node = AnnotationNode.new()
    node.line = t.start_line
    node.name = t.literal
    # 注解参数（如 @export_range(0, 100)）
    if _match(GDScriptToken.Type.PAREN_OPEN):
        while _peek() and _peek().type != GDScriptToken.Type.PAREN_CLOSE:
            node.arguments.append(_parse_expression())
            if not _match(GDScriptToken.Type.COMMA):
                break
        _expect(GDScriptToken.Type.PAREN_CLOSE)
    return node

func _parse_class_member():
    var t = _peek()
    if t == null:
        return null

    # 处理成员注解 (@export, @onready, @static...)
    var annotations: Array[AnnotationNode] = []
    while t and t.type == GDScriptToken.Type.ANNOTATION:
        annotations.append(_parse_annotation())
        t = _peek()

    if t == null:
        return null

    match t.type:
        GDScriptToken.Type.EXTENDS:
            _advance()
            var id_t = _expect(GDScriptToken.Type.IDENTIFIER, "extends 后需要类名")
            # extends 信息由 ClassNode 级别处理
            return null  # Phase 2: 存入 ClassNode.extends_id

        GDScriptToken.Type.CLASS_NAME:
            _advance()
            var id_t = _expect(GDScriptToken.Type.IDENTIFIER, "class_name 后需要类名")
            return null  # Phase 2: 存入 ClassNode.classname_id

        GDScriptToken.Type.FUNC:
            return _parse_function(annotations)

        GDScriptToken.Type.VAR:
            return _parse_variable(annotations)

        GDScriptToken.Type.TK_CONST:
            return _parse_const(annotations)

        GDScriptToken.Type.SIGNAL:
            return _parse_signal()

        GDScriptToken.Type.ENUM:
            return _parse_enum()

        GDScriptToken.Type.CLASS:
            return _parse_inner_class()

        GDScriptToken.Type.STATIC:
            _advance()
            if _peek() and _peek().type == GDScriptToken.Type.FUNC:
                var f = _parse_function([])
                f.is_static = true
                return f
            _set_error("static 只能用于函数")
            return null

        _:
            _set_error("非预期的令牌: %s" % t.get_name())
            _advance()
            return null
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_parser.gd
git commit -m "feat: Parser — 类成员分发 + 注解解析"
```

---

### Task 13: Parser — 函数/变量/信号/枚举解析

**Files:** Modify: `addons/gdscript_util/gds_parser.gd` (追加)

- [ ] **Step 1: 实现 _parse_function + _parse_parameters**

```gdscript
func _parse_inner_class() -> ClassNode:
    _advance()  # CLASS token
    var name_t = _expect(GDScriptToken.Type.IDENTIFIER, "class 后需要类名")
    var node = ClassNode.new()
    if name_t:
        node.classname_id = name_t.literal

    # extends
    if _match(GDScriptToken.Type.EXTENDS):
        var ext_t = _expect(GDScriptToken.Type.IDENTIFIER, "extends 后需要类名")
        if ext_t:
            node.extends_id = ext_t.literal

    _expect(GDScriptToken.Type.COLON)
    _match(GDScriptToken.Type.NEWLINE)

    # 类体
    _expect(GDScriptToken.Type.INDENT)
    while _peek() and _peek().type not in [GDScriptToken.Type.DEDENT, GDScriptToken.Type.TK_EOF]:
        var m = _parse_class_member()
        if m:
            node.members.append(m)
    _expect(GDScriptToken.Type.DEDENT)
    return node

func _parse_function(p_annotations: Array) -> FunctionNode:
    _advance()  # FUNC token
    var name_t = _expect(GDScriptToken.Type.IDENTIFIER, "func 后需要函数名")
    var node = FunctionNode.new()
    if name_t:
        node.name = name_t.literal
        node.line = name_t.start_line

    node.params = _parse_parameters()

    # 返回类型
    if _match(GDScriptToken.Type.FORWARD_ARROW):
        node.return_type = _parse_type()

    # 函数体
    _expect(GDScriptToken.Type.COLON)
    node.body = _parse_suite()

    return node

func _parse_parameters() -> Array[ParameterNode]:
    if not _match(GDScriptToken.Type.PAREN_OPEN):
        return []

    var params: Array[ParameterNode] = []
    if _peek() and _peek().type == GDScriptToken.Type.PAREN_CLOSE:
        _advance()
        return params

    while _peek() and _peek().type != GDScriptToken.Type.TK_EOF:
        var p = ParameterNode.new()
        var id_t = _expect(GDScriptToken.Type.IDENTIFIER, "参数需要标识符")
        if id_t == null:
            break
        p.name = id_t.literal
        p.line = id_t.start_line

        # 类型标注
        if _match(GDScriptToken.Type.COLON):
            p.datatype = _parse_type()

        # 默认值
        if _match(GDScriptToken.Type.EQUAL):
            p.default_value = _parse_expression()

        params.append(p)

        if _match(GDScriptToken.Type.COMMA):
            continue
        elif _peek() and _peek().type == GDScriptToken.Type.PAREN_CLOSE:
            break
        else:
            _set_error("参数列表语法错误")
            break

    _expect(GDScriptToken.Type.PAREN_CLOSE)
    return params
```

- [ ] **Step 2: 实现 _parse_variable + _parse_const**

```gdscript
func _parse_variable(p_annotations: Array) -> VariableNode:
    _advance()  # VAR token
    var name_t = _expect(GDScriptToken.Type.IDENTIFIER, "var 后需要变量名")
    var node = VariableNode.new()
    if name_t:
        node.name = name_t.literal
        node.line = name_t.start_line

    # 注解处理
    for ann in p_annotations:
        match ann.name:
            "export": node.is_export = true
            "onready": node.is_onready = true

    # 类型标注或推断
    if _match(GDScriptToken.Type.COLON):
        if _match(GDScriptToken.Type.EQUAL):
            # var x := value (类型推断)
            node.initializer = _parse_expression()
            node.datatype = null  # 推断类型
        else:
            node.datatype = _parse_type()
            if _match(GDScriptToken.Type.EQUAL):
                node.initializer = _parse_expression()
    elif _match(GDScriptToken.Type.EQUAL):
        node.initializer = _parse_expression()

    # setget (Phase 1: 仅支持声明式，不支持内联 setter/getter)
    if _match(GDScriptToken.Type.IDENTIFIER):
        # 忽略遗留 setget 语法
        pass

    return node

func _parse_const(p_annotations: Array) -> VariableNode:
    _advance()  # CONST token
    var node = _parse_variable([])  # 复用 var 解析
    return node  # Phase 2: 标记为常量
```

- [ ] **Step 3: 实现 _parse_signal + _parse_enum + _parse_type**

```gdscript
func _parse_signal() -> SignalNode:
    _advance()  # SIGNAL token
    var name_t = _expect(GDScriptToken.Type.IDENTIFIER, "signal 后需要信号名")
    var node = SignalNode.new()
    if name_t:
        node.name = name_t.literal
        node.line = name_t.start_line

    # 信号参数
    if _match(GDScriptToken.Type.PAREN_OPEN):
        node.params = _parse_parameters()
    return node

func _parse_enum() -> EnumNode:
    _advance()  # ENUM token
    var node = EnumNode.new()

    # 可选枚举名
    if _peek() and _peek().type == GDScriptToken.Type.IDENTIFIER:
        node.name = _advance().literal

    _expect(GDScriptToken.Type.BRACE_OPEN, "enum 需要 {")

    while _peek() and _peek().type != GDScriptToken.Type.BRACE_CLOSE:
        var key_t = _expect(GDScriptToken.Type.IDENTIFIER, "enum 成员需要标识符")
        if key_t == null:
            break
        var entry = {"name": key_t.literal, "value": null}
        if _match(GDScriptToken.Type.EQUAL):
            entry["value"] = _parse_expression()
        node.values.append(entry)

        if not _match(GDScriptToken.Type.COMMA):
            break

    _expect(GDScriptToken.Type.BRACE_CLOSE)
    return node

func _parse_type() -> TypeNode:
    var node = TypeNode.new()

    if _peek() and _peek().type == GDScriptToken.Type.IDENTIFIER:
        node.type_name = _advance().literal

    # 泛型参数: Array[int], Dictionary[String, int]
    if _match(GDScriptToken.Type.BRACKET_OPEN):
        while _peek() and _peek().type != GDScriptToken.Type.BRACKET_CLOSE:
            node.container_element_types.append(_parse_type())
            if not _match(GDScriptToken.Type.COMMA):
                break
        _expect(GDScriptToken.Type.BRACKET_CLOSE)

    return node
```

- [ ] **Step 4: 提交**

```bash
git add addons/gdscript_util/gds_parser.gd
git commit -m "feat: Parser — 函数/变量/信号/枚举/类型解析"
```

---

### Task 14: Parser — Suite + 语句解析

**Files:** Modify: `addons/gdscript_util/gds_parser.gd` (追加)

- [ ] **Step 1: 实现 _parse_suite + _parse_statement**

```gdscript
func _parse_suite() -> SuiteNode:
    var suite = SuiteNode.new()

    # 单行语句: func foo(): return 1
    if _peek() == null or _peek().type != GDScriptToken.Type.NEWLINE:
        var stmt = _parse_statement()
        if stmt != null:
            suite.statements.append(stmt)
        return suite

    # 缩进块
    _match(GDScriptToken.Type.NEWLINE)
    if not _match(GDScriptToken.Type.INDENT):
        return suite  # pass (空函数体)

    while _peek() and _peek().type not in [GDScriptToken.Type.DEDENT, GDScriptToken.Type.TK_EOF]:
        var stmt = _parse_statement()
        if stmt != null:
            suite.statements.append(stmt)
        # 每个语句后跳过 NEWLINE
        _match(GDScriptToken.Type.NEWLINE)

    _expect(GDScriptToken.Type.DEDENT)
    return suite

func _parse_statement():
    var t = _peek()
    if t == null:
        return null

    match t.type:
        GDScriptToken.Type.IF:
            return _parse_if()
        GDScriptToken.Type.WHILE:
            return _parse_while()
        GDScriptToken.Type.FOR:
            return _parse_for()
        GDScriptToken.Type.MATCH:
            return _parse_match()
        GDScriptToken.Type.RETURN:
            return _parse_return()
        GDScriptToken.Type.BREAK:
            _advance()
            return BreakNode.new()
        GDScriptToken.Type.CONTINUE:
            _advance()
            return ContinueNode.new()
        GDScriptToken.Type.PASS:
            _advance()
            return PassNode.new()
        GDScriptToken.Type.ASSERT:
            return _parse_assert()
        GDScriptToken.Type.AWAIT:
            return _parse_await()
        GDScriptToken.Type.VAR:
            return _parse_variable([])
        GDScriptToken.Type.BREAKPOINT:
            _advance()
            return null  # Phase 2

        _:
            # 表达式语句
            var expr = _parse_expression()
            if expr != null:
                var es = ExpressionStatementNode.new()
                es.expression = expr
                return es
            return null
```

- [ ] **Step 2: 实现 _parse_if / _parse_while / _parse_for**

```gdscript
func _parse_if() -> IfNode:
    _advance()  # IF token
    var node = IfNode.new()
    node.condition = _parse_expression()
    _expect(GDScriptToken.Type.COLON)
    node.true_branch = _parse_suite()

    # elif / else
    if _peek() and _peek().type == GDScriptToken.Type.ELIF:
        _advance()
        node.false_branch = _parse_if()
    elif _peek() and _peek().type == GDScriptToken.Type.ELSE:
        _advance()
        _expect(GDScriptToken.Type.COLON)
        node.false_branch = _parse_suite()

    return node

func _parse_while() -> WhileNode:
    _advance()  # WHILE token
    var node = WhileNode.new()
    node.condition = _parse_expression()
    _expect(GDScriptToken.Type.COLON)
    node.body = _parse_suite()
    return node

func _parse_for() -> ForNode:
    _advance()  # FOR token
    var node = ForNode.new()
    var id_t = _expect(GDScriptToken.Type.IDENTIFIER, "for 需要变量名")
    if id_t:
        node.var_name = id_t.literal
    _expect(GDScriptToken.Type.IN, "for 需要 'in' 关键字")
    node.iterable = _parse_expression()
    _expect(GDScriptToken.Type.COLON)
    node.body = _parse_suite()
    return node
```

- [ ] **Step 3: 实现 _parse_match / _parse_return / _parse_assert / _parse_await**

```gdscript
func _parse_match() -> MatchNode:
    _advance()  # MATCH token
    var node = MatchNode.new()
    node.test = _parse_expression()
    _expect(GDScriptToken.Type.COLON)
    _match(GDScriptToken.Type.NEWLINE)
    _expect(GDScriptToken.Type.INDENT)

    while _peek() and _peek().type not in [GDScriptToken.Type.DEDENT, GDScriptToken.Type.TK_EOF]:
        var branch = MatchBranchNode.new()

        # when 关键字
        if _match(GDScriptToken.Type.WHEN):
            pass  # when 是可选的

        # 模式列表
        branch.patterns = _parse_match_patterns()
        _expect(GDScriptToken.Type.COLON)
        branch.body = _parse_suite()
        node.branches.append(branch)

        _match(GDScriptToken.Type.NEWLINE)

    _expect(GDScriptToken.Type.DEDENT)
    return node

func _parse_match_patterns() -> Array:
    var patterns: Array = []
    while _peek() and _peek().type != GDScriptToken.Type.COLON:
        patterns.append(_parse_expression())
        if not _match(GDScriptToken.Type.COMMA):
            break
    return patterns

func _parse_return() -> ReturnNode:
    _advance()  # RETURN token
    var node = ReturnNode.new()
    if _peek() and _peek().type != GDScriptToken.Type.NEWLINE:
        node.value = _parse_expression()
    return node

func _parse_assert() -> AssertNode:
    _advance()  # ASSERT token
    var node = AssertNode.new()
    node.condition = _parse_expression()
    if _match(GDScriptToken.Type.COMMA):
        node.message = _parse_expression()
    return node

func _parse_await() -> AwaitNode:
    _advance()  # AWAIT token
    var node = AwaitNode.new()
    node.expression = _parse_expression()
    return node
```

- [ ] **Step 4: 提交**

```bash
git add addons/gdscript_util/gds_parser.gd
git commit -m "feat: Parser — Suite + 全部语句解析 (if/while/for/match/return/assert/await)"
```

---

### Task 15: Parser — 表达式解析（运算符优先级）

**Files:** Modify: `addons/gdscript_util/gds_parser.gd` (追加)

- [ ] **Step 1: 定义运算符优先级表**

```gdscript
# 运算符优先级表 — 从最低(0)到最高(19)
# 每个条目: {tokens: Array[int], type: int, right_assoc: bool}
#
# type: 0=BINOP_LEFT, 1=BINOP_RIGHT, 2=UNOP, 3=TRIOP, 4=POSTFIX

enum OpAssoc { BINOP_LEFT, BINOP_RIGHT, UNOP, TRIOP, POSTFIX }

const OP_TABLE: Array[Dictionary] = [
    # 0: 赋值 (右结合)
    {tokens = [
        GDScriptToken.Type.EQUAL,
        GDScriptToken.Type.PLUS_EQUAL,
        GDScriptToken.Type.MINUS_EQUAL,
        GDScriptToken.Type.STAR_EQUAL,
        GDScriptToken.Type.STAR_STAR_EQUAL,
        GDScriptToken.Type.SLASH_EQUAL,
        GDScriptToken.Type.PERCENT_EQUAL,
        GDScriptToken.Type.AMPERSAND_EQUAL,
        GDScriptToken.Type.PIPE_EQUAL,
        GDScriptToken.Type.CARET_EQUAL,
        GDScriptToken.Type.LESS_LESS_EQUAL,
        GDScriptToken.Type.GREATER_GREATER_EQUAL,
    ], assoc = OpAssoc.BINOP_RIGHT},

    # 1: as
    {tokens = [GDScriptToken.Type.AS], assoc = OpAssoc.BINOP_LEFT},

    # 2: 三目 if ... else
    {tokens = [GDScriptToken.Type.IF], assoc = OpAssoc.TRIOP},

    # 3: or
    {tokens = [GDScriptToken.Type.OR], assoc = OpAssoc.BINOP_LEFT},

    # 4: and
    {tokens = [GDScriptToken.Type.AND], assoc = OpAssoc.BINOP_LEFT},

    # 5: not (一元)
    {tokens = [GDScriptToken.Type.NOT], assoc = OpAssoc.UNOP},

    # 6: in
    {tokens = [GDScriptToken.Type.IN], assoc = OpAssoc.BINOP_LEFT},

    # 7: 比较
    {tokens = [
        GDScriptToken.Type.LESS, GDScriptToken.Type.GREATER,
        GDScriptToken.Type.EQUAL_EQUAL, GDScriptToken.Type.BANG_EQUAL,
        GDScriptToken.Type.LESS_EQUAL, GDScriptToken.Type.GREATER_EQUAL,
    ], assoc = OpAssoc.BINOP_LEFT},

    # 8: is
    {tokens = [GDScriptToken.Type.IS], assoc = OpAssoc.BINOP_LEFT},

    # 9: |
    {tokens = [GDScriptToken.Type.PIPE], assoc = OpAssoc.BINOP_LEFT},

    # 10: ^
    {tokens = [GDScriptToken.Type.CARET], assoc = OpAssoc.BINOP_LEFT},

    # 11: &
    {tokens = [GDScriptToken.Type.AMPERSAND], assoc = OpAssoc.BINOP_LEFT},

    # 12: <<, >>
    {tokens = [GDScriptToken.Type.LESS_LESS, GDScriptToken.Type.GREATER_GREATER], assoc = OpAssoc.BINOP_LEFT},

    # 13: - (二元)
    {tokens = [GDScriptToken.Type.MINUS], assoc = OpAssoc.BINOP_LEFT},

    # 14: + (二元)
    {tokens = [GDScriptToken.Type.PLUS], assoc = OpAssoc.BINOP_LEFT},

    # 15: *, /, %
    {tokens = [GDScriptToken.Type.STAR, GDScriptToken.Type.SLASH, GDScriptToken.Type.PERCENT], assoc = OpAssoc.BINOP_LEFT},

    # 16: ** (右结合)
    {tokens = [GDScriptToken.Type.STAR_STAR], assoc = OpAssoc.BINOP_RIGHT},

    # 17: - (一元)
    {tokens = [GDScriptToken.Type.MINUS], assoc = OpAssoc.UNOP},

    # 18: ~ (一元)
    {tokens = [GDScriptToken.Type.TILDE], assoc = OpAssoc.UNOP},

    # 19: . (属性) / [ (索引) / ( (调用) — postfix
    {tokens = [
        GDScriptToken.Type.PERIOD,
        GDScriptToken.Type.BRACKET_OPEN,
        GDScriptToken.Type.PAREN_OPEN,
    ], assoc = OpAssoc.POSTFIX},
]
```

- [ ] **Step 2: 实现 _parse_expression + 递归下降核心**

```gdscript
func _parse_expression(p_level: int = 0):
    if error != "":
        return null
    if p_level >= OP_TABLE.size():
        return _parse_atom()

    # 先解析更高优先级的子表达式
    var left = _parse_expression(p_level + 1)

    var level_ops = OP_TABLE[p_level]
    while true:
        var t = _peek()
        if t == null:
            return left
        if not level_ops.tokens.has(t.type):
            return left

        match level_ops.assoc:
            OpAssoc.BINOP_LEFT:
                if left == null:
                    return null
                var node = BinaryOpNode.new()
                node.op = t.type
                node.left = left
                _advance()
                node.right = _parse_expression(p_level)
                left = node

            OpAssoc.BINOP_RIGHT:
                if left == null:
                    return null
                if t.type == GDScriptToken.Type.EQUAL:
                    # 赋值语句
                    var node = AssignmentNode.new()
                    node.target = left
                    node.op = t.type
                    _advance()
                    node.value = _parse_expression(0)
                    return node
                # 复合赋值
                if t.type in [GDScriptToken.Type.PLUS_EQUAL,
                              GDScriptToken.Type.MINUS_EQUAL,
                              GDScriptToken.Type.STAR_EQUAL,
                              GDScriptToken.Type.STAR_STAR_EQUAL,
                              GDScriptToken.Type.SLASH_EQUAL,
                              GDScriptToken.Type.PERCENT_EQUAL,
                              GDScriptToken.Type.AMPERSAND_EQUAL,
                              GDScriptToken.Type.PIPE_EQUAL,
                              GDScriptToken.Type.CARET_EQUAL,
                              GDScriptToken.Type.LESS_LESS_EQUAL,
                              GDScriptToken.Type.GREATER_GREATER_EQUAL]:
                    var node = AssignmentNode.new()
                    node.target = left
                    node.op = t.type
                    _advance()
                    node.value = _parse_expression(0)
                    return node
                # 二元右结合 (如 **)
                var node = BinaryOpNode.new()
                node.op = t.type
                node.left = left
                _advance()
                node.right = _parse_expression(p_level)
                left = node

            OpAssoc.UNOP:
                # t.type 是相同的令牌但用作一元运算符
                # 区分: 如果 left != null 则是二元, 否则是一元
                if left != null:
                    return left
                var node = UnaryOpNode.new()
                node.op = t.type
                _advance()
                node.operand = _parse_expression(p_level)
                left = node

            OpAssoc.TRIOP:
                # if ... else (三目运算符)
                if left == null:
                    return null
                var node = TernaryOpNode.new()
                node.true_expr = left
                _advance()  # IF token
                node.condition = _parse_expression(0)
                _expect(GDScriptToken.Type.ELSE, "三目运算符需要 else")
                node.false_expr = _parse_expression(0)
                left = node

            OpAssoc.POSTFIX:
                # 后缀操作: . [ (
                if left == null:
                    # . 作为一元(如 .method() 的 super 调用)
                    return _parse_atom()
                if t.type == GDScriptToken.Type.PERIOD:
                    _advance()
                    var attr = AttributeNode.new()
                    attr.base = left
                    var id_t = _expect(GDScriptToken.Type.IDENTIFIER, "属性访问需要标识符")
                    if id_t:
                        attr.name = id_t.literal
                    left = attr
                elif t.type == GDScriptToken.Type.BRACKET_OPEN:
                    _advance()
                    var sub = SubscriptNode.new()
                    sub.base = left
                    sub.index = _parse_expression(0)
                    _expect(GDScriptToken.Type.BRACKET_CLOSE)
                    left = sub
                elif t.type == GDScriptToken.Type.PAREN_OPEN:
                    # 函数调用
                    var call = CallNode.new()
                    call.callee = left
                    call.arguments = _parse_call_args()
                    left = call
                continue  # postfix 可链式调用 a.b().c[0]()

    return left
```

- [ ] **Step 3: 实现 _parse_atom + _parse_call_args**

```gdscript
func _parse_atom():
    var t = _peek()
    if t == null:
        return null

    match t.type:
        GDScriptToken.Type.PAREN_OPEN:
            _advance()
            var expr = _parse_expression()
            _expect(GDScriptToken.Type.PAREN_CLOSE)
            return expr

        GDScriptToken.Type.IDENTIFIER:
            _advance()
            var node = IdentifierNode.new()
            node.name = t.literal
            return node

        GDScriptToken.Type.LITERAL:
            _advance()
            var node = LiteralNode.new()
            node.value = t.literal
            return node

        GDScriptToken.Type.SELF:
            _advance()
            return SelfNode.new()

        GDScriptToken.Type.SUPER:
            _advance()
            return SuperNode.new()

        GDScriptToken.Type.PRELOAD:
            _advance()
            _expect(GDScriptToken.Type.PAREN_OPEN)
            var path_t = _expect(GDScriptToken.Type.LITERAL)
            _expect(GDScriptToken.Type.PAREN_CLOSE)
            var node = PreloadNode.new()
            if path_t:
                node.path = path_t.literal
            return node

        GDScriptToken.Type.MINUS:
            # 一元负号 — 已由上层 UNOP 处理
            return null

        GDScriptToken.Type.BRACKET_OPEN:
            return _parse_array()

        GDScriptToken.Type.BRACE_OPEN:
            return _parse_dictionary()

        GDScriptToken.Type.FUNC:
            return _parse_lambda()

        GDScriptToken.Type.DOLLAR:
            _advance()
            # $NodePath
            var id_t = _peek()
            var node = IdentifierNode.new()
            if id_t and id_t.type == GDScriptToken.Type.IDENTIFIER:
                node.name = "$" + _advance().literal
            else:
                node.name = "$"
            return node

        GDScriptToken.Type.CONST_PI, GDScriptToken.Type.CONST_TAU,
        GDScriptToken.Type.CONST_INF, GDScriptToken.Type.CONST_NAN:
            _advance()
            var node = LiteralNode.new()
            match t.type:
                GDScriptToken.Type.CONST_PI: node.value = PI
                GDScriptToken.Type.CONST_TAU: node.value = TAU
                GDScriptToken.Type.CONST_INF: node.value = INF
                GDScriptToken.Type.CONST_NAN: node.value = NAN
            return node

        _:
            return null

func _parse_call_args() -> Array:
    var args: Array = []
    if _peek() and _peek().type == GDScriptToken.Type.PAREN_CLOSE:
        _advance()
        return args

    while _peek() and _peek().type != GDScriptToken.Type.TK_EOF:
        args.append(_parse_expression())
        if not _match(GDScriptToken.Type.COMMA):
            break

    _expect(GDScriptToken.Type.PAREN_CLOSE)
    return args

func _parse_array():
    _advance()  # [
    var node = ArrayNode.new()
    if _match(GDScriptToken.Type.BRACKET_CLOSE):
        return node

    while _peek() and _peek().type != GDScriptToken.Type.TK_EOF:
        node.elements.append(_parse_expression())
        if not _match(GDScriptToken.Type.COMMA):
            break
    _expect(GDScriptToken.Type.BRACKET_CLOSE)
    return node

func _parse_dictionary():
    _advance()  # {
    var node = DictionaryNode.new()
    if _match(GDScriptToken.Type.BRACE_CLOSE):
        return node

    while _peek() and _peek().type != GDScriptToken.Type.TK_EOF:
        var pair = {"key": _parse_expression(), "value": null}
        _expect(GDScriptToken.Type.COLON, "字典需要 key: value")
        pair["value"] = _parse_expression()
        node.pairs.append(pair)
        if not _match(GDScriptToken.Type.COMMA):
            break
    _expect(GDScriptToken.Type.BRACE_CLOSE)
    return node

func _parse_lambda():
    _advance()  # FUNC token
    var node = LambdaNode.new()

    # 参数
    node.params = _parse_parameters()

    # 返回类型 (可选)
    if _match(GDScriptToken.Type.FORWARD_ARROW):
        pass  # Phase 2: node.return_type

    _expect(GDScriptToken.Type.COLON)

    # lambda 体: 单表达式 或 块
    if _peek() and _peek().type == GDScriptToken.Type.NEWLINE:
        node.body = _parse_suite()
    else:
        node.body = _parse_expression()

    return node
```

- [ ] **Step 4: 提交**

```bash
git add addons/gdscript_util/gds_parser.gd
git commit -m "feat: Parser — 表达式解析 (20级运算符优先级+递归下降+原子)"
```

---

## Chunk 4: 插件入口 + 验收测试

### Task 16: EditorPlugin 入口

**Files:** Create: `addons/gdscript_util/plugin.gd`

- [ ] **Step 1: 实现 plugin.gd**

```gdscript
@tool
extends EditorPlugin

func _enter_tree():
    add_tool_menu_item("GDScript Analysis – Parse Current", _on_parse_current)
    print("[GDScriptUtil v2.0] Plugin loaded")

func _exit_tree():
    remove_tool_menu_item("GDScript Analysis – Parse Current")
    print("[GDScriptUtil v2.0] Plugin unloaded")

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
    else:
        _print_ast_summary(ast, current.resource_path)

    # Phase 2: var result = GDScriptSymbolResolver.new().resolve(ast, path)

func _print_ast_summary(p_ast: ClassNode, p_path: String):
    var func_count = 0
    var var_count = 0
    var signal_count = 0

    for m in p_ast.members:
        if m is FunctionNode:
            func_count += 1
        elif m is VariableNode:
            var_count += 1
        elif m is SignalNode:
            signal_count += 1

    print("[GDScriptUtil] %s — %d functions, %d variables, %d signals" % [
        p_path, func_count, var_count, signal_count
    ])

func analyze_script(p_path: String):
    var source = load(p_path).source_code
    var tokenizer = GDScriptTokenizer.new()
    var tokens = tokenizer.tokenize(source)
    var parser = GDScriptParser.new()
    return parser.parse(tokens)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/plugin.gd
git commit -m "feat: EditorPlugin 入口 — 工具菜单 + 分析当前脚本"
```

---

### Task 17: 验收测试

**Files:** Create: `tests/test_parser.gd`

- [ ] **Step 1: 创建测试脚本 — 10 个验收测试用例**

```gdscript
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

func parse(p_source: String) -> ClassNode:
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
    # Phase 1: 验证解析不报错
    print("  PASS")

# Test 2: var hp := 100
func test_2_var_declaration():
    print("Test 2: var declaration...")
    var source = "var hp := 100\n"
    var ast = parse(source)
    assert(ast.members.size() > 0, "Expected variable member")
    var v = ast.members[0]
    assert(v is VariableNode, "Expected VariableNode, got %s" % v.get_class())
    assert(v.name == "hp", "Expected name 'hp', got '%s'" % v.name)
    assert(v.initializer is LiteralNode, "Expected LiteralNode initializer")
    assert(v.initializer.value == 100, "Expected value 100, got %s" % v.initializer.value)
    print("  PASS")

# Test 3: func take_damage(amount: int) -> void:\n\tpass
func test_3_function_basic():
    print("Test 3: function with param and return type...")
    var source = "func take_damage(amount: int) -> void:\n\tpass\n"
    var ast = parse(source)
    assert(ast.members.size() > 0, "Expected function member")
    var f = ast.members[0]
    assert(f is FunctionNode, "Expected FunctionNode, got %s" % f.get_class())
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
    assert(s is SignalNode, "Expected SignalNode")
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
    assert(if_node is IfNode, "Expected IfNode, got %s" % if_node.get_class())
    assert(if_node.condition is BinaryOpNode, "Expected BinaryOpNode condition")
    assert(if_node.false_branch != null, "Expected else branch")
    print("  PASS")

# Test 6: @export var speed: float = 10.0
func test_6_export_var():
    print("Test 6: @export variable...")
    var source = "@export var speed: float = 10.0\n"
    var ast = parse(source)
    assert(ast.annotations.size() > 0, "Expected file-level annotation")
    assert(ast.annotations[0].name == "export", "Expected @export annotation")
    var v = ast.members[0]
    assert(v.is_export, "Expected is_export=true")
    assert(v.datatype.type_name == "float", "Expected type 'float'")
    print("  PASS")

# Test 7: for i in range(10):\n\tprint(i)
func test_7_for_loop():
    print("Test 7: for loop...")
    var source = "func f():\n\tfor i in range(10):\n\t\tpass\n"
    var ast = parse(source)
    var f_node = ast.members[0]
    var for_node = f_node.body.statements[0]
    assert(for_node is ForNode, "Expected ForNode")
    assert(for_node.var_name == "i", "Expected var 'i'")
    assert(for_node.iterable is CallNode, "Expected CallNode as iterable")
    print("  PASS")

# Test 8: match x:\n\twhen 1, 2:\n\t\tpass
func test_8_match_basic():
    print("Test 8: match/when...")
    var source = "func f(x):\n\tmatch x:\n\t\twhen 1, 2:\n\t\t\tpass\n"
    var ast = parse(source)
    var f_node = ast.members[0]
    var match_node = f_node.body.statements[0]
    assert(match_node is MatchNode, "Expected MatchNode")
    assert(match_node.branches.size() == 1, "Expected 1 branch")
    assert(match_node.branches[0].patterns.size() == 2, "Expected 2 patterns")
    print("  PASS")

# Test 9: var callback = func(): return 42
func test_9_lambda():
    print("Test 9: lambda expression...")
    var source = "var callback = func(): return 42\n"
    var ast = parse(source)
    var v = ast.members[0]
    assert(v.initializer is LambdaNode, "Expected LambdaNode")
    var lam = v.initializer
    assert(lam.body is ReturnNode, "Expected ReturnNode as lambda body")
    print("  PASS")

# Test 10: await get_tree().process_frame
func test_10_await():
    print("Test 10: await expression...")
    var source = "func f():\n\tawait get_tree().process_frame\n"
    var ast = parse(source)
    var f_node = ast.members[0]
    var await_node = f_node.body.statements[0]
    assert(await_node is AwaitNode, "Expected AwaitNode, got %s" % await_node.get_class())
    assert(await_node.expression is CallNode, "Expected CallNode as await target")
    print("  PASS")
```

- [ ] **Step 2: 提交**

```bash
git add tests/test_parser.gd
git commit -m "test: Phase 1 验收测试 — 10 个测试用例验证解析管道"
```

---

## 完成检查清单

- [ ] `gds_ast_nodes.gd` — Token.Type 枚举 (~60种) + 全部 AST 节点类 (~30种)
- [ ] `gds_tokenizer.gd` — 完整词法分析器 (字符扫描+缩进+关键字+运算符)
- [ ] `gds_parser.gd` — 完整语法分析器 (类/函数/语句/表达式/运算符优先级)
- [ ] `plugin.gd` — EditorPlugin 工具菜单 + 分析入口
- [ ] `plugin.cfg` — 插件配置 v2.0.0
- [ ] `tests/test_parser.gd` — 10 个验收测试用例全部通过
- [ ] 所有错误路径有 ERROR token 或 error 字符串记录，不会崩溃
- [ ] 分支：`feat/godot47-parser` (或直接在 master 上开发)
