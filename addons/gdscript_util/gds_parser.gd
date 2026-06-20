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
