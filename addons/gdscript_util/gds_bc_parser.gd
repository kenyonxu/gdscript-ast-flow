extends Node

#
# GDScript Bytecode Parser for Godot Engine 3.4.4
# Programmed by あるる（きのもと 結衣） @arlez80
#
# MIT License
#

class_name GDScriptByteCodeParser

const TOKEN_BITS:int = 8
const TOKEN_BYTE_MASK:int = 0x80
const TOKEN_MASK:int = ( 1 << TOKEN_BITS ) - 1
const TOKEN_LINE_BITS:int = 24
const TOKEN_LINE_MASK:int = (1 << TOKEN_LINE_BITS) - 1

const TOKEN_NAME_TABLE:Array = [
	"EMPTY",
	"IDENTIFIER",
	"CONSTANT",
	"SELF",
	"BUILT_IN_TYPE",
	"BUILT_IN_FUNC",
	"OP_IN",
	"OP_EQUAL",
	"OP_NOT_EQUAL",
	"OP_LESS",
	"OP_LESS_EQUAL",
	"OP_GREATER",
	"OP_GREATER_EQUAL",
	"OP_AND",
	"OP_OR",
	"OP_NOT",
	"OP_ADD",
	"OP_SUB",
	"OP_MUL",
	"OP_DIV",
	"OP_MOD",
	"OP_SHIFT_LEFT",
	"OP_SHIFT_RIGHT",
	"OP_ASSIGN",
	"OP_ASSIGN_ADD",
	"OP_ASSIGN_SUB",
	"OP_ASSIGN_MUL",
	"OP_ASSIGN_DIV",
	"OP_ASSIGN_MOD",
	"OP_ASSIGN_SHIFT_LEFT",
	"OP_ASSIGN_SHIFT_RIGHT",
	"OP_ASSIGN_BIT_AND",
	"OP_ASSIGN_BIT_OR",
	"OP_ASSIGN_BIT_XOR",
	"OP_BIT_AND",
	"OP_BIT_OR",
	"OP_BIT_XOR",
	"OP_BIT_INVERT",
	# "OP_PLUS_PLUS",		# ソース中に存在はするが、コメントアウトされている
	# "OP_MINUS_MINUS",
	"CF_IF",
	"CF_ELIF",
	"CF_ELSE",
	"CF_FOR",
	"CF_WHILE",
	"CF_BREAK",
	"CF_CONTINUE",
	"CF_PASS",
	"CF_RETURN",
	"CF_MATCH",
	"PR_FUNCTION",
	"PR_CLASS",
	"PR_CLASS_NAME",
	"PR_EXTENDS",
	"PR_IS",
	"PR_ONREADY",
	"PR_TOOL",
	"PR_STATIC",
	"PR_EXPORT",
	"PR_SETGET",
	"PR_CONST",
	"PR_VAR",
	"PR_AS",
	"PR_VOID",
	"PR_ENUM",
	"PR_PRELOAD",
	"PR_ASSERT",
	"PR_YIELD",
	"PR_SIGNAL",
	"PR_BREAKPOINT",
	"PR_REMOTE",
	"PR_SYNC",
	"PR_MASTER",
	"PR_SLAVE",	# 4.0で削除される
	"PR_PUPPET",
	"PR_REMOTESYNC",
	"PR_MASTERSYNC",
	"PR_PUPPETSYNC",
	"BRACKET_OPEN",
	"BRACKET_CLOSE",
	"CURLY_BRACKET_OPEN",
	"CURLY_BRACKET_CLOSE",
	"PARENTHESIS_OPEN",
	"PARENTHESIS_CLOSE",
	"COMMA",
	"SEMICOLON",
	"PERIOD",
	"QUESTION_MARK",
	"COLON",
	"DOLLAR",
	"FORWARD_ARROW",
	"NEWLINE",
	"CONST_PI",
	"CONST_TAU",
	"WILDCARD",
	"CONST_INF",
	"CONST_NAN",
	"ERROR",
	"EOF",
	"CURSOR",	# コードコンパイル用
	"MAX"
]

enum Token {
	EMPTY,
	IDENTIFIER,
	CONSTANT,
	SELF,
	BUILT_IN_TYPE,
	BUILT_IN_FUNC,
	OP_IN,
	OP_EQUAL,
	OP_NOT_EQUAL,
	OP_LESS,
	OP_LESS_EQUAL,
	OP_GREATER,
	OP_GREATER_EQUAL,
	OP_AND,
	OP_OR,
	OP_NOT,
	OP_ADD,
	OP_SUB,
	OP_MUL,
	OP_DIV,
	OP_MOD,
	OP_SHIFT_LEFT,
	OP_SHIFT_RIGHT,
	OP_ASSIGN,
	OP_ASSIGN_ADD,
	OP_ASSIGN_SUB,
	OP_ASSIGN_MUL,
	OP_ASSIGN_DIV,
	OP_ASSIGN_MOD,
	OP_ASSIGN_SHIFT_LEFT,
	OP_ASSIGN_SHIFT_RIGHT,
	OP_ASSIGN_BIT_AND,
	OP_ASSIGN_BIT_OR,
	OP_ASSIGN_BIT_XOR,
	OP_BIT_AND,
	OP_BIT_OR,
	OP_BIT_XOR,
	OP_BIT_INVERT,
	# OP_PLUS_PLUS,		# ソース中に存在はするが、コメントアウトされている
	# OP_MINUS_MINUS,
	CF_IF,
	CF_ELIF,
	CF_ELSE,
	CF_FOR,
	CF_WHILE,
	CF_BREAK,
	CF_CONTINUE,
	CF_PASS,
	CF_RETURN,
	CF_MATCH,
	PR_FUNCTION,
	PR_CLASS,
	PR_CLASS_NAME,
	PR_EXTENDS,
	PR_IS,
	PR_ONREADY,
	PR_TOOL,
	PR_STATIC,
	PR_EXPORT,
	PR_SETGET,
	PR_CONST,
	PR_VAR,
	PR_AS,
	PR_VOID,
	PR_ENUM,
	PR_PRELOAD,
	PR_ASSERT,
	PR_YIELD,
	PR_SIGNAL,
	PR_BREAKPOINT,
	PR_REMOTE,
	PR_SYNC,
	PR_MASTER,
	PR_SLAVE,	# 4.0で削除される
	PR_PUPPET,
	PR_REMOTESYNC,
	PR_MASTERSYNC,
	PR_PUPPETSYNC,
	BRACKET_OPEN,
	BRACKET_CLOSE,
	CURLY_BRACKET_OPEN,
	CURLY_BRACKET_CLOSE,
	PARENTHESIS_OPEN,
	PARENTHESIS_CLOSE,
	COMMA,
	SEMICOLON,
	PERIOD,
	QUESTION_MARK,
	COLON,
	DOLLAR,
	FORWARD_ARROW,
	NEWLINE,
	CONST_PI,
	CONST_TAU,
	WILDCARD,
	CONST_INF,
	CONST_NAN,
	ERROR,
	EOF,
	CURSOR,	# コードコンパイル用
	MAX
}

class GDScriptByteCodeParseResult:
	var succeed:bool = false
	var byte_code_version:int = 0
	var identifiers:Array = []
	var constants:Array = []
	var lines:Dictionary = {}
	var tokens:Array = []

	func _init( ):
		pass

class ByteToken:
	var token_id:int
	var param:int

	func _init( _token_id:int = Token.MAX, _param:int = 0 ):
		self.token_id = _token_id
		self.param = _param

static func parse( code:PackedByteArray ) -> GDScriptByteCodeParseResult:
	var result: = GDScriptByteCodeParseResult.new( )
	var stream: = StreamPeerBuffer.new( )
	stream.set_data_array( code )

	# ヘッダチェック
	if stream.get_string( 4 ) != "GDSC":
		return result
	result.byte_code_version = stream.get_32( )
	var identifier_map_size:int = stream.get_32( )
	var constant_map_size:int = stream.get_32( )
	var line_map_size:int = stream.get_32( )
	var token_array_size:int = stream.get_32( )

	result.identifiers = _parse_identifiers( stream, identifier_map_size )
	result.constants = _parse_constants( stream, constant_map_size )
	result.lines = _parse_lines( stream, line_map_size )
	result.tokens = _parse_tokens( stream, token_array_size )

	result.succeed = true

	return result

static func _parse_identifiers( stream:StreamPeerBuffer, count:int ) -> Array:
	var r:Array = []

	for i in range( count ):
		var size:int = stream.get_u32( )
		var get_size:int = 0

		var buf: = StreamPeerBuffer.new( )
		for k in range( size ):
			var c:int = stream.get_u8( ) ^ 0xB6
			buf.put_u8( c )
			if c != 0:
				get_size = k

		buf.put_u8( 0 )
		buf.seek( 0 )
		r.append( buf.get_string( get_size + 1 ) )

	return r

static func _parse_constants( stream:StreamPeerBuffer, count:int ) -> Array:
	var r:Array = []

	var start_pos:int = stream.get_position( )
	var all_const_size:int = 0
	var data:PackedByteArray = stream.get_data( stream.get_available_bytes( ) )[1]

	for i in range( count ):
		var c = bytes_to_var( data )
		var const_size:int = var_to_bytes( c ).size( )
		all_const_size += const_size
		r.append( c )
		data = data.slice( const_size, data.size( ) - 1 )

	stream.seek( start_pos + all_const_size )

	return r

static func _parse_lines( stream:StreamPeerBuffer, count:int ) -> Dictionary:
	var r:Dictionary = {}

	for i in range( count ):
		var k:int = stream.get_u32( )
		var v:int = stream.get_u32( )
		r[k] = v

	return r

static func _parse_tokens( stream:StreamPeerBuffer, count:int ) -> Array:
	var r:Array = []

	for i in range( count ):
		var tk: = GDScriptToken.new( )
		var c:int = stream.get_u8( )

		if c & TOKEN_BYTE_MASK != 0:
			tk.token_id = ( c & TOKEN_MASK ) ^ TOKEN_BYTE_MASK
			var p:int = stream.get_u16( )
			p |= stream.get_u8( ) << 16
			tk.param = p
		else:
			tk.token_id = c & TOKEN_MASK

		r.append( tk )

		# printt( i, TOKEN_NAME_TABLE[tk.token_id], tk.param )

	return r
