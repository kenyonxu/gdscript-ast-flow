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
var _pending_tokens: Array = []        # 待输出的 INDENT/DEDENT (在 NEWLINE 后插入)
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


func _scan() -> GDScriptToken:
    # 优先输出待处理的 INDENT/DEDENT
    if not _pending_tokens.is_empty():
        return _pending_tokens.pop_front()

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

    var c = _advance()

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


func _flush_indents(p_tokens: Array):
    # 文件末尾的剩余 DEDENT
    for i in range(abs(pending_indents)):
        p_tokens.append(_make_token(GDScriptToken.Type.DEDENT))


func _skip_comment():
    while _pos < source.length() and _peek() != "\n":
        _advance()
