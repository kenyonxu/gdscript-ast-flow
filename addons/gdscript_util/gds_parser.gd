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
