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

class PreloadNode:
    extends ASTNode
    var path: String = ""
