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

# 关键字映射表
const KEYWORDS := {
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
    # Phase 3: namespace / trait
    "namespace": GDScriptToken.Type.NAMESPACE,
    "trait": GDScriptToken.Type.TRAIT,
    "implements": GDScriptToken.Type.IMPLEMENTS,
}

# 内置常量
const BUILTIN_CONSTS := {
    "PI": GDScriptToken.Type.CONST_PI,
    "TAU": GDScriptToken.Type.CONST_TAU,
    "INF": GDScriptToken.Type.CONST_INF,
    "NAN": GDScriptToken.Type.CONST_NAN,
}

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
    while _pos < source.length() or not _pending_tokens.is_empty():
        var token = _scan()
        if token != null:
            tokens.append(token)
            if token.type == GDScriptToken.Type.ERROR:
                # 记录错误但继续扫描
                pass

    # 文件末尾: 弹出所有剩余缩进级别 (除基线外)
    while indent_stack.size() > 1:
        indent_stack.pop_back()
        tokens.append(_make_token(GDScriptToken.Type.DEDENT))

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
        return ""
    return source[idx]

func _advance() -> String:
    if _pos >= source.length():
        return ""
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

    # 检查缩进 (仅在行首且不在括号内，且非 EOS)
    # indent_stack==[0] 时自动设基线，不产生 INDENT
    if at_line_start and paren_level == 0 and _peek() != "":
        if _peek() != "\n":
            var col = _column
            _check_indent(col)
            # 缩进变化生成的 INDENT/DEDENT 必须优先输出
            if not _pending_tokens.is_empty():
                return _pending_tokens.pop_front()

    var c = _advance()

    # 空字符保护
    if c == "":
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
    # 首行: 设基线缩进，不产生 INDENT
    if indent_stack == [0]:
        indent_stack = [p_column]
        return

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


func _scan_token(p_first: String) -> GDScriptToken:
    # Phase 3: f-string 前缀检测 — 必须在标识符之前
    if p_first == "f":
        var next = _peek()
        if next == "\"" or next == "'":
            _advance()  # skip the opening quote
            return _scan_format_string(next)

    # Godot 4: &"..." StringName 字面量前缀
    if p_first == "&":
        var next = _peek()
        if next == "\"" or next == "'":
            _advance()
            return _scan_string(next)

    # Godot 4.4+: ^"..." NodePath/StringName 字面量前缀
    if p_first == "^":
        var next = _peek()
        if next == "\"" or next == "'":
            _advance()
            return _scan_string(next)

    if p_first == "_" or (p_first >= "a" and p_first <= "z") or (p_first >= "A" and p_first <= "Z"):
        return _scan_identifier(p_first)

    if p_first == "@":
        return _scan_annotation()

    if p_first >= "0" and p_first <= "9":
        return _scan_number(p_first)

    if p_first == "\"" or p_first == "'":
        return _scan_string(p_first[0])

    if p_first == "$":
        if _peek().is_valid_identifier():
            # $NodePath 语法 — 视为特殊的标识符引用
            return _scan_node_path()
        return _make_token(GDScriptToken.Type.DOLLAR)

    return _scan_operator(p_first)

func _scan_identifier(p_first: String) -> GDScriptToken:
    var name = p_first
    while _pos < source.length():
        var c = _peek()
        if c.is_valid_identifier() or (c >= "0" and c <= "9"):
            name += c
            _advance()
        else:
            break

    if KEYWORDS.has(name):
        return _make_token(KEYWORDS[name])

    if BUILTIN_CONSTS.has(name):
        return _make_token(BUILTIN_CONSTS[name])

    # 普通标识符
    return _make_token(GDScriptToken.Type.IDENTIFIER, name)


func _scan_annotation() -> GDScriptToken:
    var name = ""
    while _pos < source.length():
        var c = _peek()
        if c.is_valid_identifier() or (c >= "0" and c <= "9") or c == "_":
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
        if c == "/" or c.is_valid_identifier() or (c >= "0" and c <= "9") or c == "_" or c == "%":
            path += c
            _advance()
        else:
            break
    return _make_token(GDScriptToken.Type.IDENTIFIER, "$" + path)


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
        if c >= "0" and c <= "9":
            num_str += c
            _advance()
        elif c == "." and not is_float and _peek(1) >= "0" and _peek(1) <= "9":
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


func _scan_format_string(p_quote: String) -> GDScriptToken:
    # f"...{expr}..." 格式化字符串
    var segments: Array = []  # of {text: String, expr: Variant}
    var cur_text = ""
    while _pos < source.length():
        var c = _advance()
        if c == "":
            return _make_token(GDScriptToken.Type.ERROR, "Unterminated format string")
        if c == "{" and _peek() != "{":  # {{ 是 literal {
            if cur_text != "":
                segments.append({"text": cur_text, "expr": null})
                cur_text = ""
            # 简化: 读取到 } 作为表达式文本（由 parser 进一步解析）
            var expr_text = ""
            while _pos < source.length() and _peek() != "}":
                expr_text += _advance()
            _advance()  # skip }
            segments.append({"text": "", "expr": expr_text})
        elif c == p_quote:
            if cur_text != "":
                segments.append({"text": cur_text, "expr": null})
            break
        else:
            cur_text += c
    return _make_token(GDScriptToken.Type.FORMAT_STRING_LITERAL, segments)


func _scan_string(p_quote: String) -> GDScriptToken:
	# Godot 4: 三引号多行字符串 """..."""
	if _peek() == p_quote and _peek(1) == p_quote:
		_advance()  # skip 2nd quote
		_advance()  # skip 3rd quote
		return _scan_triple_string(p_quote)
	return _scan_single_string(p_quote)

func _scan_triple_string(p_quote: String) -> GDScriptToken:
	var str_value = ""
	while _pos < source.length():
		var c = _advance()
		if c == "":
			return _make_token(GDScriptToken.Type.ERROR, "未终止的三引号字符串")
		# 三引号结束: """ 检测
		if c == p_quote and _peek() == p_quote and _peek(1) == p_quote:
			_advance()  # skip 2nd
			_advance()  # skip 3rd
			break
		if c == "\\":
			var next = _advance()
			if next == "n":
				str_value += "\n"
			elif next == "t":
				str_value += "\t"
			elif next == "\\":
				str_value += "\\"
			elif next == "\"":
				str_value += "\""
			elif next == "'":
				str_value += "'"
			else:
				str_value += next
		else:
			str_value += c
	return _make_token(GDScriptToken.Type.LITERAL, str_value)

func _scan_single_string(p_quote: String) -> GDScriptToken:
	var str_value = ""
	while _pos < source.length():
		var c = _advance()
		if c == "":
			return _make_token(GDScriptToken.Type.ERROR, "未终止的字符串")
		if c == "\\":
			var next = _advance()
			if next == "n":
				str_value += "\n"
			elif next == "t":
				str_value += "\t"
			elif next == "r":
				str_value += "\r"
			elif next == "\\":
				str_value += "\\"
			elif next == "\"":
				str_value += "\""
			elif next == "'":
				str_value += "'"
			else:
				str_value += next
		elif c == p_quote:
			break
		else:
			str_value += c

	return _make_token(GDScriptToken.Type.LITERAL, str_value)


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
