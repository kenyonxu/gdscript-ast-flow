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

# Token 实例字段
var type: int = Type.EMPTY
var literal: Variant = null    # 标识符名(StringName) 或 字面量值(Variant)
var start_line: int = 1
var start_column: int = 1
var end_line: int = 1
var end_column: int = 1

# 注意: Godot 4.x 枚举没有 .keys(), 需要用 find_key() 或手动映射表
func get_name() -> String:
    return Type.find_key(type) if type >= 0 and type < Type.size() else "UNKNOWN"

func _to_string() -> String:
    var name = get_name()
    if literal != null and type in [Type.IDENTIFIER, Type.LITERAL, Type.ANNOTATION]:
        return "%s(%s) @%d:%d" % [name, literal, start_line, start_column]
    return "%s @%d:%d" % [name, start_line, start_column]
