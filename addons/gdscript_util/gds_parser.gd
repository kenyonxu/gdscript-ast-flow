# addons/gdscript_util/gds_parser.gd
# GDScript 4.7 语法分析器 — 递归下降解析 Token 流 → AST

class_name GDScriptParser
extends RefCounted

var tokens: Array[GDScriptToken] = []
var pos: int = 0
var error: String = ""
var _error_line: int = 0
var _error_column: int = 0

# Phase 3: 错误恢复 — 错误计数和上限
var _error_count: int = 0
const MAX_ERRORS := 20

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

func parse(p_tokens: Array) -> GDScriptToken.ClassNode:
    tokens = p_tokens
    pos = 0
    error = ""
    _error_count = 0

    var root = GDScriptToken.ClassNode.new()

    # 跳过文件开头的空行/注释残留的 NEWLINE（真实文件常有注释头或开头空行）
    # 否则下面的 extends/class_name 检测会因首个 token 是 NEWLINE 而被跳过，
    # 进而 extends 被误判为"出现在类体中"
    _skip_newlines()

    # 解析文件级注解 — 仅 @tool 和 @icon 是文件级的
    # 成员注解 (@export, @onready...) 在 _parse_class_member 中处理
    while _peek() and _peek().type == GDScriptToken.Type.ANNOTATION:
        var ann_name = _peek().literal
        if ann_name in ["tool", "icon"]:
            root.annotations.append(_parse_annotation())
            _skip_newlines()  # 注解后可能跟空行
        else:
            break  # 成员注解留给 _parse_class_member

    # 解析 extends / class_name (文件级, 任意顺序)
    # GDScript 允许 class_name 在 extends 之前或之后，用循环兼容两种写法
    _skip_newlines()
    var _header_done := false
    while not _header_done:
        if _peek() and _peek().type == GDScriptToken.Type.EXTENDS:
            _advance()
            var id_t = _expect(GDScriptToken.Type.IDENTIFIER, "extends 后需要类名")
            if id_t:
                root.extends_id = id_t.literal
            _match(GDScriptToken.Type.NEWLINE)
            _skip_newlines()
        elif _peek() and _peek().type == GDScriptToken.Type.CLASS_NAME:
            _advance()
            var id_t = _expect(GDScriptToken.Type.IDENTIFIER, "class_name 后需要类名")
            if id_t:
                root.classname_id = id_t.literal
            _skip_newlines()
        else:
            _header_done = true
    _skip_newlines()

    # 解析类体成员
    while _peek() and _peek().type != GDScriptToken.Type.TK_EOF:
        _skip_newlines()
        if _peek() and _peek().type == GDScriptToken.Type.TK_EOF:
            break
        var member = _parse_class_member()
        if member != null:
            root.members.append(member)
        elif _error_count >= MAX_ERRORS:
            break
        else:
            # Phase 3: 错误恢复 — 跳过到下一个有效的成员关键字
            _skip_to_next_member()

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
    _set_error(p_error if p_error != "" else "期望 %s" % GDScriptToken.Type.find_key(p_type))
    return null

func _set_error(p_msg: String):
    _error_count += 1
    if _error_count > MAX_ERRORS:
        if error == "":
            error = p_msg
        return
    if error == "":  # 只记录第一个错误
        if _peek():
            error = "%s (line %d, token: %s)" % [p_msg, _peek().start_line, _peek().get_name()]
        else:
            error = p_msg

func _skip_newlines():
    while _peek() and _peek().type == GDScriptToken.Type.NEWLINE:
        _advance()

func _skip_to_newline():
    while _peek() and _peek().type != GDScriptToken.Type.NEWLINE and _peek().type != GDScriptToken.Type.TK_EOF:
        _advance()

# Phase 3: 跳过到下一个有效的顶级成员关键字（错误恢复）
func _skip_to_next_member():
    var member_keywords = [
        GDScriptToken.Type.FUNC, GDScriptToken.Type.VAR,
        GDScriptToken.Type.TK_CONST, GDScriptToken.Type.SIGNAL,
        GDScriptToken.Type.ENUM, GDScriptToken.Type.CLASS,
        GDScriptToken.Type.NAMESPACE, GDScriptToken.Type.TRAIT,
        GDScriptToken.Type.DEDENT, GDScriptToken.Type.TK_EOF,
        GDScriptToken.Type.STATIC,
    ]
    while _peek() and _peek().type not in member_keywords:
        _advance()


func _parse_annotation() -> GDScriptToken.AnnotationNode:
    var t = _advance()  # ANNOTATION token
    var node = GDScriptToken.AnnotationNode.new()
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
    var annotations: Array[GDScriptToken.AnnotationNode] = []
    while t and t.type == GDScriptToken.Type.ANNOTATION:
        annotations.append(_parse_annotation())
        t = _peek()

    if t == null:
        return null

    match t.type:
        GDScriptToken.Type.EXTENDS, GDScriptToken.Type.CLASS_NAME:
            # extends/class_name 已在 parse() 中作为文件级声明解析
            # 这里出现在类体中作为错误处理
            _set_error("extends/class_name 只能出现在文件顶部")
            _advance()
            return null

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

        GDScriptToken.Type.NAMESPACE:
            return _parse_namespace()

        GDScriptToken.Type.TRAIT:
            return _parse_trait()

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


func _parse_inner_class() -> GDScriptToken.ClassNode:
    _advance()  # CLASS token
    var name_t = _expect(GDScriptToken.Type.IDENTIFIER, "class 后需要类名")
    var node = GDScriptToken.ClassNode.new()
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
        _skip_newlines()
        if _peek() == null or _peek().type in [GDScriptToken.Type.DEDENT, GDScriptToken.Type.TK_EOF]:
            break
        var m = _parse_class_member()
        if m:
            node.members.append(m)
        else:
            # 错误恢复: 防止 null 返回导致死循环
            _skip_to_newline()
    _expect(GDScriptToken.Type.DEDENT)
    return node

func _parse_namespace() -> GDScriptToken.NamespaceNode:
    _advance()  # NAMESPACE
    var node = GDScriptToken.NamespaceNode.new()
    var id_t = _expect(GDScriptToken.Type.IDENTIFIER, "namespace 后需要名称")
    if id_t:
        node.name = id_t.literal
    _expect(GDScriptToken.Type.COLON)
    _match(GDScriptToken.Type.NEWLINE)
    _expect(GDScriptToken.Type.INDENT)
    while _peek() and _peek().type not in [GDScriptToken.Type.DEDENT, GDScriptToken.Type.TK_EOF]:
        _skip_newlines()
        if _peek() and _peek().type == GDScriptToken.Type.TK_EOF:
            break
        var member = _parse_class_member()
        if member != null:
            node.members.append(member)
        else:
            _skip_to_newline()
    _expect(GDScriptToken.Type.DEDENT)
    return node

func _parse_trait() -> GDScriptToken.TraitNode:
    _advance()  # TRAIT
    var node = GDScriptToken.TraitNode.new()
    var id_t = _expect(GDScriptToken.Type.IDENTIFIER, "trait 后需要名称")
    if id_t:
        node.name = id_t.literal
    _expect(GDScriptToken.Type.COLON)
    _match(GDScriptToken.Type.NEWLINE)
    _expect(GDScriptToken.Type.INDENT)
    while _peek() and _peek().type not in [GDScriptToken.Type.DEDENT, GDScriptToken.Type.TK_EOF]:
        _skip_newlines()
        if _peek() and _peek().type == GDScriptToken.Type.TK_EOF:
            break
        var member = _parse_class_member()
        if member != null:
            if member is GDScriptToken.FunctionNode:
                node.methods.append(member)
            elif member is GDScriptToken.VariableNode:
                node.properties.append(member)
        else:
            _skip_to_newline()
    _expect(GDScriptToken.Type.DEDENT)
    return node

func _parse_function(p_annotations: Array) -> GDScriptToken.FunctionNode:
    _advance()  # FUNC token
    var name_t = _expect(GDScriptToken.Type.IDENTIFIER, "func 后需要函数名")
    var node = GDScriptToken.FunctionNode.new()
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

func _parse_parameters() -> Array[GDScriptToken.ParameterNode]:
    if not _match(GDScriptToken.Type.PAREN_OPEN):
        return []

    var params: Array[GDScriptToken.ParameterNode] = []
    if _peek() and _peek().type == GDScriptToken.Type.PAREN_CLOSE:
        _advance()
        return params

    while _peek() and _peek().type != GDScriptToken.Type.TK_EOF:
        var p = GDScriptToken.ParameterNode.new()
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


func _parse_variable(p_annotations: Array) -> GDScriptToken.VariableNode:
    _advance()  # VAR token
    var name_t = _expect(GDScriptToken.Type.IDENTIFIER, "var 后需要变量名")
    var node = GDScriptToken.VariableNode.new()
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

    # Phase 3: 内联 setter/getter block — var hp: int:\n    set(value):\n        hp = value
    if _match(GDScriptToken.Type.COLON) and _match(GDScriptToken.Type.NEWLINE) and _match(GDScriptToken.Type.INDENT):
        while _peek() and _peek().type not in [GDScriptToken.Type.DEDENT, GDScriptToken.Type.TK_EOF]:
            _skip_newlines()
            if _peek() == null or _peek().type in [GDScriptToken.Type.DEDENT, GDScriptToken.Type.TK_EOF]:
                break
            if _peek() and _peek().type == GDScriptToken.Type.IDENTIFIER and _peek().literal == "set":
                _advance()  # "set"
                if _match(GDScriptToken.Type.PAREN_OPEN):
                    _match(GDScriptToken.Type.IDENTIFIER)  # param name, ignored
                    _expect(GDScriptToken.Type.PAREN_CLOSE)
                _expect(GDScriptToken.Type.COLON)
                var sg = GDScriptToken.SetterGetterNode.new()
                # getter/setter body 可能是单行表达式或 return 语句 — 统一用 _parse_suite
                sg.setter = _parse_suite()
                node.setter = sg
            elif _peek() and _peek().type == GDScriptToken.Type.IDENTIFIER and _peek().literal == "get":
                _advance()  # "get"
                _expect(GDScriptToken.Type.COLON)
                var sg2 = GDScriptToken.SetterGetterNode.new()
                sg2.getter = _parse_suite()
                node.getter = sg2
            else:
                break
        _match(GDScriptToken.Type.DEDENT)
    # 单行形式: var hp: set(v): expr
    elif _peek() and _peek().type == GDScriptToken.Type.IDENTIFIER and _peek().literal == "set":
        _advance()  # "set"
        if _match(GDScriptToken.Type.PAREN_OPEN):
            _match(GDScriptToken.Type.IDENTIFIER)  # param name, ignored
            _expect(GDScriptToken.Type.PAREN_CLOSE)
        _expect(GDScriptToken.Type.COLON)
        var sg = GDScriptToken.SetterGetterNode.new()
        sg.setter = _parse_expression()
        node.setter = sg
    elif _peek() and _peek().type == GDScriptToken.Type.IDENTIFIER and _peek().literal == "get":
        _advance()  # "get"
        _expect(GDScriptToken.Type.COLON)
        var sg = GDScriptToken.SetterGetterNode.new()
        sg.getter = _parse_expression()
        node.getter = sg
    else:
        # setget (Phase 1: 仅支持声明式)
        if _match(GDScriptToken.Type.IDENTIFIER):
            pass  # 忽略遗留 setget 语法

    return node

func _parse_const(p_annotations: Array):
    _advance()  # CONST token (已在 _parse_class_member 中匹配)
    var name_t = _expect(GDScriptToken.Type.IDENTIFIER, "const 后需要常量名")
    var node = GDScriptToken.VariableNode.new()
    if name_t:
        node.name = name_t.literal
        node.line = name_t.start_line

    # 类型标注
    if _match(GDScriptToken.Type.COLON):
        if _match(GDScriptToken.Type.EQUAL):
            node.initializer = _parse_expression()
        else:
            node.datatype = _parse_type()
            if _match(GDScriptToken.Type.EQUAL):
                node.initializer = _parse_expression()
    elif _match(GDScriptToken.Type.EQUAL):
        node.initializer = _parse_expression()

    # 注意: const 返回 VariableNode (无独立 ConstNode 类型)
    # SymbolResolver Phase 2 通过检查源 Token 区分 const/var
    return node


func _parse_signal() -> GDScriptToken.SignalNode:
    _advance()  # SIGNAL token
    var name_t = _expect(GDScriptToken.Type.IDENTIFIER, "signal 后需要信号名")
    var node = GDScriptToken.SignalNode.new()
    if name_t:
        node.name = name_t.literal
        node.line = name_t.start_line

    # 信号参数 (_parse_parameters 内部自己消费 PAREN_OPEN)
    node.params = _parse_parameters()
    return node

func _parse_enum() -> GDScriptToken.EnumNode:
    _advance()  # ENUM token
    var node = GDScriptToken.EnumNode.new()

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

func _parse_type() -> GDScriptToken.TypeNode:
    var node = GDScriptToken.TypeNode.new()

    if _peek() and _peek().type == GDScriptToken.Type.VOID:
        _advance()
        node.type_name = "void"
    elif _peek() and _peek().type == GDScriptToken.Type.IDENTIFIER:
        node.type_name = _advance().literal

    # 泛型参数: Array[int], Dictionary[String, int]
    if _match(GDScriptToken.Type.BRACKET_OPEN):
        while _peek() and _peek().type != GDScriptToken.Type.BRACKET_CLOSE:
            node.container_element_types.append(_parse_type())
            if not _match(GDScriptToken.Type.COMMA):
                break
        _expect(GDScriptToken.Type.BRACKET_CLOSE)

    return node


func _parse_suite() -> GDScriptToken.SuiteNode:
    var suite = GDScriptToken.SuiteNode.new()

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
        else:
            # 错误恢复: _parse_statement 返回 null 且未消费 token 时强制推进，
            # 否则本循环会无限自旋（编辑器保存时锁死的根因）
            _set_error("非预期的语句令牌: %s" % _peek().get_name())
            _advance()
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
            return GDScriptToken.BreakNode.new()
        GDScriptToken.Type.CONTINUE:
            _advance()
            return GDScriptToken.ContinueNode.new()
        GDScriptToken.Type.PASS:
            _advance()
            return GDScriptToken.PassNode.new()
        GDScriptToken.Type.ASSERT:
            return _parse_assert()
        GDScriptToken.Type.AWAIT:
            return _parse_await()
        GDScriptToken.Type.VAR:
            return _parse_variable([])
        GDScriptToken.Type.BREAKPOINT:
            _advance()
            var bp = GDScriptToken.BreakNode.new()  # breakpoint 语法上类似 break
            return bp

        GDScriptToken.Type.YIELD:
            _advance()
            # yield() 在 4.x 中仅保留兼容性，内部转为 await
            var node = GDScriptToken.AwaitNode.new()
            node.expression = _parse_expression()
            return node

        _:
            # 表达式语句
            var expr = _parse_expression()
            if expr != null:
                var es = GDScriptToken.ExpressionStatementNode.new()
                es.expression = expr
                return es
            return null


func _parse_if() -> GDScriptToken.IfNode:
    _advance()  # IF token
    var node = GDScriptToken.IfNode.new()
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

func _parse_while() -> GDScriptToken.WhileNode:
    _advance()  # WHILE token
    var node = GDScriptToken.WhileNode.new()
    node.condition = _parse_expression()
    _expect(GDScriptToken.Type.COLON)
    node.body = _parse_suite()
    return node

func _parse_for() -> GDScriptToken.ForNode:
    _advance()  # FOR token
    var node = GDScriptToken.ForNode.new()
    var id_t = _expect(GDScriptToken.Type.IDENTIFIER, "for 需要变量名")
    if id_t:
        node.var_name = id_t.literal
    _expect(GDScriptToken.Type.IN, "for 需要 'in' 关键字")
    node.iterable = _parse_expression()
    _expect(GDScriptToken.Type.COLON)
    node.body = _parse_suite()
    return node


func _parse_match() -> GDScriptToken.MatchNode:
    _advance()  # MATCH token
    var node = GDScriptToken.MatchNode.new()
    node.test = _parse_expression()
    _expect(GDScriptToken.Type.COLON)
    _match(GDScriptToken.Type.NEWLINE)
    _expect(GDScriptToken.Type.INDENT)

    while _peek() and _peek().type not in [GDScriptToken.Type.DEDENT, GDScriptToken.Type.TK_EOF]:
        var branch: GDScriptToken.MatchBranchNode = null

        # Phase 3: match guard — when 后跟表达式而非逗号分隔模式
        if _match(GDScriptToken.Type.WHEN):
            # 检查是否 guard 表达式 (when x > 0:)
            # 尝试解析一个表达式，如果下一个 token 是 COLON 则为 guard
            var saved_pos = pos
            var guard_expr = _parse_expression()
            if guard_expr != null and _peek() and _peek().type == GDScriptToken.Type.COLON:
                # 这是 guard 分支: when x > 0:
                branch = GDScriptToken.GuardedMatchBranchNode.new()
                branch.guard = guard_expr
                _advance()  # COLON
            else:
                # 不是 guard，恢复位置并走普通 when 分支
                pos = saved_pos
                branch = GDScriptToken.MatchBranchNode.new()

        if branch == null:
            branch = GDScriptToken.MatchBranchNode.new()

        # 如果还没处理完整分支（没有 guard），解析模式列表
        if branch.guard == null:
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

func _parse_return() -> GDScriptToken.ReturnNode:
    _advance()  # RETURN token
    var node = GDScriptToken.ReturnNode.new()
    if _peek() and _peek().type != GDScriptToken.Type.NEWLINE:
        node.value = _parse_expression()
    return node

func _parse_assert() -> GDScriptToken.AssertNode:
    _advance()  # ASSERT token
    var node = GDScriptToken.AssertNode.new()
    node.condition = _parse_expression()
    if _match(GDScriptToken.Type.COMMA):
        node.message = _parse_expression()
    return node

func _parse_await() -> GDScriptToken.AwaitNode:
    _advance()  # AWAIT token
    var node = GDScriptToken.AwaitNode.new()
    node.expression = _parse_expression()
    return node


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
                _advance()
                # as → CastNode, is → TypeTestNode (特殊节点类型)
                if t.type == GDScriptToken.Type.AS:
                    var node = GDScriptToken.CastNode.new()
                    node.expression = left
                    node.type = _parse_type()
                    left = node
                elif t.type == GDScriptToken.Type.IS:
                    var node = GDScriptToken.TypeTestNode.new()
                    node.expression = left
                    node.type = _parse_type()
                    left = node
                else:
                    var node = GDScriptToken.BinaryOpNode.new()
                    node.op = t.type
                    node.left = left
                    node.right = _parse_expression(p_level)
                    left = node

            OpAssoc.BINOP_RIGHT:
                if left == null:
                    return null
                if t.type == GDScriptToken.Type.EQUAL:
                    # 赋值语句
                    var node = GDScriptToken.AssignmentNode.new()
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
                    var node = GDScriptToken.AssignmentNode.new()
                    node.target = left
                    node.op = t.type
                    _advance()
                    node.value = _parse_expression(0)
                    return node
                # 二元右结合 (如 **)
                var node = GDScriptToken.BinaryOpNode.new()
                node.op = t.type
                node.left = left
                _advance()
                node.right = _parse_expression(p_level)
                left = node

            OpAssoc.UNOP:
                # 一元运算符 — 始终在此级别被消费（不检查 left）
                # 注意: MINUS 出现在两个级别 (13=二元, 17=一元)。在级别17, _parse_expression(18)
                # 返回的 left 是更高优先级的表达式。如果当前token是 MINUS, 检查它是否作为
                # 一元运算符使用: 需要判断前一个token的上下文。
                # 简化方案: 在 OP_TABLE 中用不同哨兵标记二元/一元MINUS。
                # 实际处理: 如果 left != null 且前一个token是运算符/括号开头 → 一元
                # 如果 left == null → 一定是一元
                #
                # 实践中: 级别17(unary -) 和级别18(unary ~) 中,
                # 如果 left 已存在且前一个token不是运算符 → 这是二元的, 返回left
                # 如果 left 不存在或前一个token是运算符 → 这是一元的
                if left != null:
                    return left  # 二元: 留给低级别处理
                var node = GDScriptToken.UnaryOpNode.new()
                node.op = t.type
                _advance()
                node.operand = _parse_expression(p_level)  # 右结合
                left = node

            OpAssoc.TRIOP:
                # if ... else (三目运算符)
                if left == null:
                    return null
                var node = GDScriptToken.TernaryOpNode.new()
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
                    var attr = GDScriptToken.AttributeNode.new()
                    attr.base = left
                    var id_t = _expect(GDScriptToken.Type.IDENTIFIER, "属性访问需要标识符")
                    if id_t:
                        attr.name = id_t.literal
                    left = attr
                elif t.type == GDScriptToken.Type.BRACKET_OPEN:
                    _advance()
                    var sub = GDScriptToken.SubscriptNode.new()
                    sub.base = left
                    sub.index = _parse_expression(0)
                    _expect(GDScriptToken.Type.BRACKET_CLOSE)
                    left = sub
                elif t.type == GDScriptToken.Type.PAREN_OPEN:
                    # 函数调用
                    _advance()  # 消费 (
                    var call = GDScriptToken.CallNode.new()
                    call.callee = left
                    call.arguments = _parse_call_args()
                    left = call
                continue  # postfix 可链式调用 a.b().c[0]()

    return left


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
            var node = GDScriptToken.IdentifierNode.new()
            node.name = t.literal
            return node

        GDScriptToken.Type.LITERAL:
            _advance()
            var node = GDScriptToken.LiteralNode.new()
            node.value = t.literal
            return node

        GDScriptToken.Type.FORMAT_STRING_LITERAL:
            # f"...{expr}..." — segments 数组 [{text, expr}, ...] 暂存为 LiteralNode
            # (Phase 3.2: 升级为独立 FormattedStringNode 并解析 expr 文本)
            _advance()
            var fnode = GDScriptToken.LiteralNode.new()
            fnode.value = t.literal
            return fnode

        GDScriptToken.Type.SELF:
            _advance()
            return GDScriptSelfNode.new()

        GDScriptToken.Type.SUPER:
            _advance()
            return GDScriptSuperNode.new()

        GDScriptToken.Type.PRELOAD:
            _advance()
            _expect(GDScriptToken.Type.PAREN_OPEN)
            var path_t = _expect(GDScriptToken.Type.LITERAL)
            _expect(GDScriptToken.Type.PAREN_CLOSE)
            var node = GDScriptToken.PreloadNode.new()
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
            var node = GDScriptToken.IdentifierNode.new()
            if id_t and id_t.type == GDScriptToken.Type.IDENTIFIER:
                node.name = "$" + _advance().literal
            else:
                node.name = "$"
            return node

        GDScriptToken.Type.CONST_PI, GDScriptToken.Type.CONST_TAU, GDScriptToken.Type.CONST_INF, GDScriptToken.Type.CONST_NAN:
            _advance()
            var node = GDScriptToken.LiteralNode.new()
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
    var node = GDScriptToken.ArrayNode.new()
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
    var node = GDScriptToken.DictionaryNode.new()
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
    var node = GDScriptToken.LambdaNode.new()

    # 参数
    node.params = _parse_parameters()

    # 返回类型 (可选)
    if _match(GDScriptToken.Type.FORWARD_ARROW):
        node.return_type = _parse_type()

    _expect(GDScriptToken.Type.COLON)

    # lambda 体: 单表达式 或 块
    if _peek() and _peek().type == GDScriptToken.Type.NEWLINE:
        node.body = _parse_suite()
    else:
        # 单行 lambda: func(): return 42 → body = LiteralNode(42) (解包 return)
        if _peek() and _peek().type == GDScriptToken.Type.RETURN:
            _advance()  # 消费 return, body 直接存储返回值表达式
        node.body = _parse_expression()

    return node
