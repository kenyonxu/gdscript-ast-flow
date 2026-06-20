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

    # 解析文件级注解 — 仅 @tool 和 @icon 是文件级的
    # 成员注解 (@export, @onready...) 在 _parse_class_member 中处理
    while _peek() and _peek().type == GDScriptToken.Type.ANNOTATION:
        var ann_name = _peek().literal
        if ann_name in ["tool", "icon"]:
            root.annotations.append(_parse_annotation())
        else:
            break  # 成员注解留给 _parse_class_member

    # 解析 extends (文件级, 在 class body 之前)
    if _peek() and _peek().type == GDScriptToken.Type.EXTENDS:
        _advance()
        var id_t = _expect(GDScriptToken.Type.IDENTIFIER, "extends 后需要类名")
        if id_t:
            root.extends_id = id_t.literal
        _match(GDScriptToken.Type.NEWLINE)  # extends 后的换行

    # 解析 class_name (文件级, 可能在 extends 之后)
    _skip_newlines()  # 跳过 extends 和 class_name 之间的空行
    if _peek() and _peek().type == GDScriptToken.Type.CLASS_NAME:
        _advance()
        var id_t = _expect(GDScriptToken.Type.IDENTIFIER, "class_name 后需要类名")
        if id_t:
            root.classname_id = id_t.literal
    _skip_newlines()

    # 解析类体成员
    while _peek() and _peek().type != GDScriptToken.Type.TK_EOF:
        var member = _parse_class_member()
        if member != null:
            root.members.append(member)
        else:
            # 错误恢复: 跳过当前行
            _skip_to_newline()

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
    if error == "":  # 只记录第一个错误
        error = p_msg
        if _peek():
            _error_line = _peek().start_line
            _error_column = _peek().start_column

func _skip_newlines():
    while _peek() and _peek().type == GDScriptToken.Type.NEWLINE:
        _advance()

func _skip_to_newline():
    while _peek() and _peek().type != GDScriptToken.Type.NEWLINE and _peek().type != GDScriptToken.Type.TK_EOF:
        _advance()


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

func _parse_const(p_annotations: Array):
    _advance()  # CONST token (已在 _parse_class_member 中匹配)
    var name_t = _expect(GDScriptToken.Type.IDENTIFIER, "const 后需要常量名")
    var node = VariableNode.new()
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
            var bp = BreakNode.new()  # breakpoint 语法上类似 break
            return bp

        GDScriptToken.Type.YIELD:
            _advance()
            # yield() 在 4.x 中仅保留兼容性，内部转为 await
            var node = AwaitNode.new()
            node.expression = _parse_expression()
            return node

        _:
            # 表达式语句
            var expr = _parse_expression()
            if expr != null:
                var es = ExpressionStatementNode.new()
                es.expression = expr
                return es
            return null


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
