extends Node

#
# GDScript AST Parser for Godot Engine 3.4.4
# Programmed by あるる（きのもと 結衣） @arlez80
#
# MIT License
#

class_name GDScriptASTParser

const ByteCode = preload("gds_bc_parser.gd")

# -----------------------------------------------------------------------------

class TreeBase:
	pass

class TreeClass extends TreeBase:
	var identifier_id:int = -1
	var extends_identifier_id:int = -1
	var class_name_identifier_id:int = -1
	var is_tool:bool = false

	var children:Array = []

class TreeBlock extends TreeBase:
	var children:Array = []

class TreeConst extends TreeBase:
	var identifier_id:int

	var type:TypeBase = null
	var init:ExprBase = null

class TreeVar extends TreeBase:
	var identifier_id:int

	var type:TypeBase = null
	var init:ExprBase = null

	var set_identifier_id:int = -1
	var get_identifier_id:int = -1

class TreeOnReady extends TreeBase:
	var body:TreeVar = null

class TreeFunction extends TreeBase:
	var is_static:bool = false
	var identifier_id:int

	var args:Array = []			# of TreeArgument
	var super_args:Array = []	# of TreeArgument
	var type:TypeBase = null

	var body:TreeBase = null

class TreeArgument extends TreeBase:
	var identifier_id:int
	var type:TypeBase = null
	var init:ExprBase = null

class TreeIf extends TreeBase:
	var cond:ExprBase = null
	var true_block:TreeBase = null
	var false_block:TreeBase = null

class TreeWhile extends TreeBase:
	var cond:ExprBase = null
	var block:TreeBase = null

class TreeFor extends TreeBase:
	var identifier_id:int
	var expr_range:ExprBase = null
	var block:TreeBase = null

class TreeMatch extends TreeBase:
	var cond:ExprBase = null
	var cases:Array = []

class TreeCase extends TreeBase:
	var conds:Array = [] # of ExprBase
	var body:TreeBase = null

class TreeCaseVar extends TreeBase:
	var identifier_id:int
	var body:TreeBase = null

class TreeBreak extends TreeBase:
	pass

class TreeContinue extends TreeBase:
	pass

class TreePass extends TreeBase:
	pass

class TreeBreakPoint extends TreeBase:
	pass

class TreeReturn extends TreeBase:
	var expr:ExprBase = null

class TreeAssert extends TreeBase:
	var expr:ExprBase = null

class TreeExpr extends TreeBase:
	var expr:ExprBase = null

class TreeSignal extends TreeBase:
	var identifier_id:int
	var args:Array	# of identifier_id

class TreeEnum extends TreeBase:
	var identifier_id:int = -1
	var enums:Array # of TreeEnumColumn

class TreeEnumColumn extends TreeBase:
	var identifier_id:int
	var expr:ExprBase

# -----------------------------------------------------------------------------

class TypeBase:
	pass

class TypeBuiltInType extends TypeBase:
	var type_id:int

	func _init( _type_id:int ):
		self.type_id = _type_id

class TypeIdentifier extends TypeBase:
	var identifier_id:int

	func _init( _identifier_id:int ):
		self.identifier_id = _identifier_id

# -----------------------------------------------------------------------------

class ExprBase:
	pass

class ExprBinOp extends ExprBase:
	var op:int		# GDScriptByteCodeParser.Token
	var a:ExprBase = null
	var b:ExprBase = null

class ExprUnOp extends ExprBase:
	var op:int		# GDScriptByteCodeParser.Token
	var a:ExprBase = null

class ExprIf extends ExprBase:
	var cond_expr:ExprBase = null
	var true_expr:ExprBase = null
	var false_expr:ExprBase = null

class ExprCallFunc extends ExprBase:
	# callee( args )
	var callee:ExprBase = null
	var args:Array = []

class ExprSubscription extends ExprBase:
	# a[b]
	var a:ExprBase = null
	var b:ExprBase = null

class ExprIdentifier extends ExprBase:
	var identifier_id:int

class ExprBuiltInFunc extends ExprBase:
	var built_in_func_id:int

class ExprArray extends ExprBase:
	var list:Array # of ExprBase

class ExprDictionary extends ExprBase:
	var dict:Array = [] # of ExprDictionaryColumn

class ExprDictionaryColumn extends ExprBase:
	var key:ExprBase = null
	var value:ExprBase = null

class ExprConstant extends ExprBase:
	var constant_id:int

class ExprYield extends ExprBase:
	pass

class ExprPreload extends ExprBase:
	pass

class ExprSelf extends ExprBase:
	pass

class ExprReservedConst extends ExprBase:
	var token_id:int = 0	# GDScriptByteCodeParser.Token
	func _init( _token_id:int ):
		self.token_id = _token_id

# -----------------------------------------------------------------------------

# エラーが発生したか？
var error:bool = false
# トークンリスト
var token_list:Array
# トークンリストサイズ
var token_list_len:int
# 現在の位置
var p:int = 0
# パース結果
var result:TreeBase = null

# -----------------------------------------------------------------------------

func _back( ) -> void:
	if 0 < self.p:
		self.p -= 1

func _next( ) -> void:
	if self.p + 1 < self.token_list_len:
		self.p += 1

func _get_token_and_next( ) -> GDScriptByteCodeParser.ByteToken:
	var n:GDScriptByteCodeParser.ByteToken = self.token_list[self.p]
	if self.p + 1 < self.token_list_len:
		self.p += 1
	return n

func _get_token( ) -> GDScriptByteCodeParser.ByteToken:
	return self.token_list[self.p]

# -----------------------------------------------------------------------------

func _optimize_token_list( ) -> void:
	# 連続改行を最後の1つにまとめる
	# 括弧内部の改行を全て削除
	var i:int = 0
	var paren_level:int = 0

	while i < len( self.token_list ):
		var t:GDScriptByteCodeParser.ByteToken = self.token_list[i]

		match t.token_id:
			GDScriptByteCodeParser.Token.PARENTHESIS_OPEN, GDScriptByteCodeParser.Token.BRACKET_OPEN, GDScriptByteCodeParser.Token.CURLY_BRACKET_OPEN:
				paren_level += 1
				i += 1
			GDScriptByteCodeParser.Token.PARENTHESIS_CLOSE, GDScriptByteCodeParser.Token.BRACKET_CLOSE, GDScriptByteCodeParser.Token.CURLY_BRACKET_CLOSE:
				paren_level -= 1
				i += 1

			GDScriptByteCodeParser.Token.NEWLINE:
				if 0 < paren_level:
					self.token_list.remove_at( i )
				else:
					while i+1 < len( self.token_list ):
						t = self.token_list[i+1]
						if t.token_id == GDScriptByteCodeParser.Token.NEWLINE:
							self.token_list.remove_at( i )
						else:
							break
					i += 1

			_:
				i += 1

# -----------------------------------------------------------------------------

func parse( _token_list:Array ) -> bool:
	self.token_list = _token_list
	self.error = false
	self.p = 0

	self._optimize_token_list( )
	self.token_list_len = len( self.token_list )
	self.result = self._parse_class_block( 0 )

	# ホントは Error.OK とか Error.ERR_INVALID_DATA とか使いたいけど
	return not self.error

# -----------------------------------------------------------------------------

func _parse_type( ) -> TypeBase:
	var t: = self._get_token_and_next( )

	match t.token_id:
		GDScriptByteCodeParser.Token.BUILT_IN_TYPE:
			return TypeBuiltInType.new( t.param )
		GDScriptByteCodeParser.Token.IDENTIFIER:
			return TypeIdentifier.new( t.param )
		_:
			return null

# -----------------------------------------------------------------------------

func _parse_class( ) -> TreeClass:
	var t: = self._get_token_and_next( )
	if t.token_id != GDScriptByteCodeParser.Token.IDENTIFIER:
		self.error = true
		return null

	var identifier_id:int = t.token_id
	var extends_identifier_id:int = -1

	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.PR_EXTENDS:
		self._next( )
		if self._get_token( ).token_id != GDScriptByteCodeParser.Token.IDENTIFIER:
			self.error = true
			return null
		extends_identifier_id = t.param
		self._next( )

	if self._get_token( ).token_id != GDScriptByteCodeParser.Token.COLON:
		self.error = true
		return null

	# Godot Engine 3.4.4のパーサーと挙動が違う
	# class AAA: pass
	# 1行で定義されたclassがあるとそれ以下が全てAAAのメンバとなってしまう
	# バグ報告があるので、この挙動は実装しない
	#    https://github.com/godotengine/godot/issues/56703
	var cl: = self._parse_class_block( )
	cl.identifier_id = identifier_id
	cl.extends_identifier_id = extends_identifier_id

	return cl

func _parse_class_block( indent:int = -1 ) -> TreeClass:
	var cl: = TreeClass.new( )

	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.NEWLINE:
		indent = self._get_token_and_next( ).param

	while ( self.p < self.token_list_len ) and ( not self.error ):
		var t: = self._get_token_and_next( )
		#printt( "CLASS BLOCK", GDScriptByteCodeParser.TOKEN_NAME_TABLE[t.token_id] )

		match t.token_id:
			GDScriptByteCodeParser.Token.PR_EXTENDS:
				self._parse_class_block_extends( cl )
			GDScriptByteCodeParser.Token.PR_CLASS_NAME:
				self._parse_class_block_class_name( cl )
			GDScriptByteCodeParser.Token.PR_TOOL:
				cl.is_tool = true

			GDScriptByteCodeParser.Token.CONSTANT:
				# コメント
				pass

			GDScriptByteCodeParser.Token.PR_CONST:
				cl.children.append( self._parse_const( ) )
			GDScriptByteCodeParser.Token.PR_VAR:
				cl.children.append( self._parse_var( ) )
			GDScriptByteCodeParser.Token.PR_STATIC:
				if self._get_token_and_next( ).token_id == GDScriptByteCodeParser.Token.PR_FUNCTION:
					var f: = self._parse_function( )
					f.is_static = true
					cl.children.append( f )
				else:
					self.error = true
			GDScriptByteCodeParser.Token.PR_ONREADY:
				if self._get_token_and_next( ).token_id == GDScriptByteCodeParser.Token.PR_VAR:
					var onv: = TreeOnReady.new( )
					onv.body = self._parse_var( )
					cl.children.append( onv )
				else:
					self.error = true
			GDScriptByteCodeParser.Token.PR_FUNCTION:
				cl.children.append( self._parse_function( ) )
			GDScriptByteCodeParser.Token.PR_CLASS:
				cl.children.append( self._parse_class( ) )
			GDScriptByteCodeParser.Token.PR_SIGNAL:
				cl.children.append( self._parse_signal( ) )
			GDScriptByteCodeParser.Token.PR_ENUM:
				cl.children.append( self._parse_enum( ) )
			GDScriptByteCodeParser.Token.EOF:
				break
			_:
				self.error = true

		t = self._get_token( )
		match t.token_id:
			GDScriptByteCodeParser.Token.SEMICOLON:
				pass
			GDScriptByteCodeParser.Token.NEWLINE:
				if t.param != indent:
					break
			GDScriptByteCodeParser.Token.EOF:
				break
			_:
				self.error = true
		self._next( )

	return cl

func _parse_class_block_extends( cl:TreeClass ) -> void:
	var t: = self._get_token_and_next( )
	if t.token_id != GDScriptByteCodeParser.Token.IDENTIFIER:
		self.error = true
		return

	cl.extends_identifier_id = t.param

func _parse_class_block_class_name( cl:TreeClass ) -> void:
	var t: = self._get_token_and_next( )
	if t.token_id != GDScriptByteCodeParser.Token.IDENTIFIER:
		self.error = true
		return

	cl.class_name_identifier_id = t.param

func _parse_block( ) -> TreeBlock:
	var block: = TreeBlock.new( )

	var indent:int = -1
	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.NEWLINE:
		indent = self._get_token_and_next( ).param

	while ( self.p < self.token_list_len ) and ( not self.error ):
		var t: = self._get_token_and_next( )
		#printt( "BLOCK", GDScriptByteCodeParser.TOKEN_NAME_TABLE[t.token_id] )

		match t.token_id:
			GDScriptByteCodeParser.Token.PR_VAR:
				block.children.append( self._parse_var( ) )
			GDScriptByteCodeParser.Token.CF_IF:
				block.children.append( self._parse_if( ) )
			GDScriptByteCodeParser.Token.CF_MATCH:
				block.children.append( self._parse_match( ) )
			GDScriptByteCodeParser.Token.CF_WHILE:
				block.children.append( self._parse_while( ) )
			GDScriptByteCodeParser.Token.CF_FOR:
				block.children.append( self._parse_for( ) )
			GDScriptByteCodeParser.Token.CF_BREAK:
				block.children.append( TreeBreak.new( ) )
			GDScriptByteCodeParser.Token.CF_CONTINUE:
				block.children.append( TreeContinue.new( ) )
			GDScriptByteCodeParser.Token.CF_PASS:
				block.children.append( TreePass.new( ) )
			GDScriptByteCodeParser.Token.PR_BREAKPOINT:
				block.children.append( TreeBreakPoint.new( ) )
			GDScriptByteCodeParser.Token.CF_RETURN:
				block.children.append( self._parse_return( ) )
			GDScriptByteCodeParser.Token.PR_ASSERT:
				block.children.append( self._parse_assert( ) )
			GDScriptByteCodeParser.Token.NEWLINE:
				if t.param != indent:
					break
				else:
					continue
			_:
				block.children.append( self._parse_expr( ) )

		t = self._get_token( )
		match t.token_id:
			GDScriptByteCodeParser.Token.SEMICOLON:
				pass
			GDScriptByteCodeParser.Token.NEWLINE:
				if t.param != indent:
					break
			_:
				self.error = true

		self._next( )

	return block

func _parse_const( ) -> TreeConst:
	var t: = self._get_token_and_next( )
	if t.token_id != GDScriptByteCodeParser.Token.IDENTIFIER:
		self.error = true
		return null

	var v: = TreeConst.new( )
	v.identifier_id = t.param

	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.COLON:
		self._next( )
		v.type = self._parse_type( )
		if v.type == null:
			self._back( )

	if self._get_token( ).token_id != GDScriptByteCodeParser.Token.OP_ASSIGN:
		self.error = true
		return null

	self._get_token_and_next( )
	v.init = self._parse_expr( )

	return v

func _parse_var( ) -> TreeVar:
	var t: = self._get_token_and_next( )
	if t.token_id != GDScriptByteCodeParser.Token.IDENTIFIER:
		self.error = true
		return null

	var v: = TreeVar.new( )
	v.identifier_id = t.param

	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.COLON:
		self._next( )
		v.type = self._parse_type( )
		if v.type == null:
			self._back( )

	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.OP_ASSIGN:
		self._next( )
		v.init = self._parse_expr( )

	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.PR_SETGET:
		self._next( )
		if self._get_token( ).token_id != GDScriptByteCodeParser.Token.IDENTIFIER:
			self.error = true
			return null
		v.set_identifier_id = self._get_token( ).param
		self._next( )
		if self._get_token( ).token_id == GDScriptByteCodeParser.Token.COMMA:
			self._next( )
			if self._get_token( ).token_id != GDScriptByteCodeParser.Token.IDENTIFIER:
				self.error = true
				return null
			v.get_identifier_id = self._get_token( ).param
			self._next( )

	return v

func _parse_signal( ) -> TreeSignal:
	var t: = self._get_token_and_next( )
	if t.token_id != GDScriptByteCodeParser.Token.IDENTIFIER:
		self.error = true
		return null

	var s: = TreeSignal.new( )
	s.identifier_id = t.param

	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.PARENTHESIS_OPEN:
		self._next( )
		s.args = self._parse_signal_args( )
		self._next( )

	return s

func _parse_signal_args( ) -> Array:
	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.PARENTHESIS_CLOSE:
		return []

	var result:Array = []
	while self.p < self.token_list_len:
		if self._get_token( ).token_id != GDScriptByteCodeParser.Token.IDENTIFIER:
			self.error = true
			return []

		result.append( self._get_token( ).param )

		self._next( )
		match self._get_token( ).token_id:
			GDScriptByteCodeParser.Token.COMMA:
				self._next( )
			GDScriptByteCodeParser.Token.PARENTHESIS_CLOSE:
				break
			_:
				self.error = true
				return []

	return result

func _parse_function( ) -> TreeFunction:
	var t: = self._get_token_and_next( )
	if t.token_id != GDScriptByteCodeParser.Token.IDENTIFIER:
		self.error = true
		return null

	var f: = TreeFunction.new( )
	f.identifier_id = t.param
	f.args = self._parse_function_args( )

	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.PERIOD:
		self._next( )
		f.super_args = self._parse_function_args( )

	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.FORWARD_ARROW:
		self._next( )
		f.type = self._parse_type( )

	if self._get_token( ).token_id != GDScriptByteCodeParser.Token.COLON:
		self.error = true
		return null

	self._next( )
	f.body = self._parse_block( )

	return f

func _parse_function_args( ) -> Array:
	if self._get_token_and_next( ).token_id != GDScriptByteCodeParser.Token.PARENTHESIS_OPEN:
		self.error = true
		return []

	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.PARENTHESIS_CLOSE:
		self._next( )
		return []

	var result:Array = []
	while self.p < self.token_list_len:
		if self._get_token( ).token_id != GDScriptByteCodeParser.Token.IDENTIFIER:
			self.error = true
			return []

		var arg: = TreeArgument.new( )
		arg.identifier_id = self._get_token( ).param
		result.append( arg )

		self._next( )
		if self._get_token( ).token_id == GDScriptByteCodeParser.Token.COLON:
			self._next( )
			arg.type = self._parse_type( )
			if arg.type == null:
				self.error = true
				return []

		match self._get_token( ).token_id:
			GDScriptByteCodeParser.Token.COMMA:
				self._next( )
			GDScriptByteCodeParser.Token.PARENTHESIS_CLOSE:
				self._next( )
				return result
			_:
				self.error = true
				return []

	# ホントはいらないんだけど、エラーが出るから仕方なく
	return result

func _parse_if( ) -> TreeIf:
	var tif: = TreeIf.new( )

	tif.cond = self._parse_expr( )
	if self._get_token_and_next( ).token_id != GDScriptByteCodeParser.Token.COLON:
		self.error = true
		return null

	tif.true_block = self._parse_block( )

	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.CF_ELIF:
		self._next( )
		tif.else_block = self._parse_if( )
	elif self._get_token( ).token_id == GDScriptByteCodeParser.Token.CF_ELSE:
		self._next( )
		tif.else_block = self._parse_block( )

	return tif

func _parse_match( ) -> TreeMatch:
	var tm: = TreeMatch.new( )

	tm.cond = self._parse_expr( )
	if self._get_token_and_next( ).token_id != GDScriptByteCodeParser.Token.COLON:
		self.error = true
		return null
	if self._get_token( ).token_id != GDScriptByteCodeParser.Token.NEWLINE:
		self.error = true
		return null

	var indent:int = self._get_token( ).param
	self._next( )

	while ( self.p < self.token_list_len ) and ( not self.error ):
		var t: = self._get_token( )

		if t.token_id == GDScriptByteCodeParser.Token.NEWLINE:
			if indent != t.param:
				break
			self._next( )
		else:
			if self._get_token( ).token_id == GDScriptByteCodeParser.Token.PR_VAR:
				self._next( )
				if self._get_token( ).token_id != GDScriptByteCodeParser.Token.IDENTIFIER:
					self.error = true
					return null
				var tcv: = TreeCaseVar.new( )
				tcv.identifier_id = self._get_token( ).param
				self._next( )
				if self._get_token( ).token_id != GDScriptByteCodeParser.Token.COLON:
					self.error = true
					return null

				self._next( )
				tcv.body = self._parse_block( )
				tm.cases.append( tcv )
			else:
				var tc: = TreeCase.new( )
				while ( self.p < self.token_list_len ) and ( not self.error ):
					tc.conds.append( self._parse_expr( ) )
					if self._get_token( ).token_id == GDScriptByteCodeParser.Token.COMMA:
						pass
					elif self._get_token( ).token_id == GDScriptByteCodeParser.Token.COLON:
						break
					else:
						self.error = true
						return null

				self._next( )
				tc.body = self._parse_block( )
				tm.cases.append( tc )

	return tm

func _parse_while( ) -> TreeWhile:
	var tw: = TreeWhile.new( )

	tw.cond = self._parse_expr( )
	if self._get_token_and_next( ).token_id != GDScriptByteCodeParser.Token.COLON:
		self.error = true
		return null

	tw.block = self._parse_block( )

	return tw

func _parse_for( ) -> TreeFor:
	var tf: = TreeFor.new( )

	if self._get_token( ).token_id != GDScriptByteCodeParser.Token.IDENTIFIER:
		self.error = true
		return null
	tf.identifier_id = self._get_token( ).param
	self._next( )

	if self._get_token_and_next( ).token_id != GDScriptByteCodeParser.Token.OP_IN:
		self.error = true
		return null

	tf.expr_range = self._parse_expr( )
	if self._get_token_and_next( ).token_id != GDScriptByteCodeParser.Token.COLON:
		self.error = true
		return null

	tf.block = self._parse_block( )

	return tf

func _parse_return( ) -> TreeReturn:
	var tr: = TreeReturn.new( )

	if self._get_token( ).token_id != GDScriptByteCodeParser.Token.NEWLINE:
		tr.expr = self._parse_expr( )

	return tr

func _parse_assert( ) -> TreeAssert:
	var ta: = TreeAssert.new( )

	if self._get_token( ).token_id != GDScriptByteCodeParser.Token.NEWLINE:
		ta.expr = self._parse_expr( )

	return ta

func _parse_enum( ) -> TreeEnum:
	var te: = TreeEnum.new( )

	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.IDENTIFIER:
		te.identifier_id = self._get_token( ).param
		self._next( )

	if self._get_token( ).token_id != GDScriptByteCodeParser.Token.CURLY_BRACKET_OPEN:
		self.error = true
		return null

	self._next( )

	while self.p < self.token_list_len:
		if self._get_token( ).token_id != GDScriptByteCodeParser.Token.IDENTIFIER:
			self.error = true
			return null

		var e: = TreeEnumColumn.new( )
		e.identifier_id = self._get_token( ).param
		self._next( )
		if self._get_token( ).token_id == GDScriptByteCodeParser.Token.OP_ASSIGN:
			self._next( )
			e.expr = self._parse_expr( )
		te.enums.append( e )

		if self._get_token( ).token_id == GDScriptByteCodeParser.Token.COMMA:
			self._next( )
			if self._get_token( ).token_id == GDScriptByteCodeParser.Token.CURLY_BRACKET_CLOSE:
				break
		elif self._get_token( ).token_id == GDScriptByteCodeParser.Token.CURLY_BRACKET_CLOSE:
			break
		else:
			self.error = true

	self._next( )

	return te

# -----------------------------------------------------------------------------

enum OperatorType {
	UNOP,				# 単項演算子
	BINOP_LEFT,			# 二項演算子、左結合
	BINOP_LEFT_PERIOD,	# ピリオドのアクセス a.b （二項演算子、左結合） super時に特殊扱い
	BINOP_RIGHT,		# 二項演算子、右結合
	TRIOP,				# 三項演算子
	FUNC,				# 関数呼びだし f(a)
	INDEX,				# インデックス a[b]
}

class Operator:
	# トークン
	var op:int
	# トークン（三項演算子用）
	var op2:int
	# 結合種類
	var operator_type:int

	func _init( _op:int, _operator_type:int, _op2:int = -1 ):
		self.op = _op
		self.operator_type = _operator_type
		self.op2 = _op2

var op_table:Array = [	# of Array of Operator
	# low
	[
		# = += -= *= /= %= &= |= <<= >>=
		Operator.new( GDScriptByteCodeParser.Token.OP_ASSIGN, OperatorType.BINOP_RIGHT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_ASSIGN_ADD, OperatorType.BINOP_RIGHT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_ASSIGN_SUB, OperatorType.BINOP_RIGHT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_ASSIGN_MUL, OperatorType.BINOP_RIGHT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_ASSIGN_DIV, OperatorType.BINOP_RIGHT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_ASSIGN_MOD, OperatorType.BINOP_RIGHT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_ASSIGN_SHIFT_LEFT, OperatorType.BINOP_RIGHT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_ASSIGN_SHIFT_RIGHT, OperatorType.BINOP_RIGHT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_ASSIGN_BIT_AND, OperatorType.BINOP_RIGHT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_ASSIGN_BIT_OR, OperatorType.BINOP_RIGHT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_ASSIGN_BIT_XOR, OperatorType.BINOP_RIGHT ),
	],
	[
		# as
		Operator.new( GDScriptByteCodeParser.Token.PR_AS, OperatorType.BINOP_LEFT ),
	],
	[
		# if x else
		Operator.new( GDScriptByteCodeParser.Token.CF_IF, OperatorType.TRIOP, GDScriptByteCodeParser.Token.CF_ELSE ),
	],
	[
		# or ||
		Operator.new( GDScriptByteCodeParser.Token.OP_OR, OperatorType.BINOP_LEFT ),
	],
	[
		# and &&
		Operator.new( GDScriptByteCodeParser.Token.OP_AND, OperatorType.BINOP_LEFT ),
	],
	[
		# ! not
		Operator.new( GDScriptByteCodeParser.Token.OP_NOT, OperatorType.UNOP ),
	],
	[
		# in
		Operator.new( GDScriptByteCodeParser.Token.OP_IN, OperatorType.BINOP_LEFT ),
	],
	[
		# < > == != >= <=
		Operator.new( GDScriptByteCodeParser.Token.OP_LESS, OperatorType.BINOP_LEFT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_GREATER, OperatorType.BINOP_LEFT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_EQUAL, OperatorType.BINOP_LEFT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_NOT_EQUAL, OperatorType.BINOP_LEFT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_LESS_EQUAL, OperatorType.BINOP_LEFT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_GREATER_EQUAL, OperatorType.BINOP_LEFT ),
	],
	[
		# |
		Operator.new( GDScriptByteCodeParser.Token.OP_BIT_OR, OperatorType.BINOP_LEFT ),
	],
	[
		# ^
		Operator.new( GDScriptByteCodeParser.Token.OP_BIT_XOR, OperatorType.BINOP_LEFT ),
	],
	[
		# &
		Operator.new( GDScriptByteCodeParser.Token.OP_BIT_AND, OperatorType.BINOP_LEFT ),
	],
	[
		# << >>
		Operator.new( GDScriptByteCodeParser.Token.OP_SHIFT_LEFT, OperatorType.BINOP_LEFT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_SHIFT_RIGHT, OperatorType.BINOP_LEFT ),
	],
	[
		# -
		Operator.new( GDScriptByteCodeParser.Token.OP_SUB, OperatorType.BINOP_LEFT ),
	],
	[
		# +
		Operator.new( GDScriptByteCodeParser.Token.OP_ADD, OperatorType.BINOP_LEFT ),
	],
	[
		# * / %
		Operator.new( GDScriptByteCodeParser.Token.OP_MUL, OperatorType.BINOP_LEFT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_DIV, OperatorType.BINOP_LEFT ),
		Operator.new( GDScriptByteCodeParser.Token.OP_MOD, OperatorType.BINOP_LEFT ),
	],
	[
		# -
		Operator.new( GDScriptByteCodeParser.Token.OP_SUB, OperatorType.UNOP ),
	],
	[
		# ~
		Operator.new( GDScriptByteCodeParser.Token.OP_BIT_INVERT, OperatorType.UNOP ),
	],
	[
		# is
		Operator.new( GDScriptByteCodeParser.Token.PR_IS, OperatorType.BINOP_LEFT ),
	],
	[
		# foo()
		Operator.new( GDScriptByteCodeParser.Token.PARENTHESIS_OPEN, OperatorType.FUNC, GDScriptByteCodeParser.Token.PARENTHESIS_CLOSE ),
	],
	[
		# x.attribute
		Operator.new( GDScriptByteCodeParser.Token.PERIOD, OperatorType.BINOP_LEFT_PERIOD ),
	],
	[
		# x[index]
		Operator.new( GDScriptByteCodeParser.Token.BRACKET_OPEN, OperatorType.INDEX, GDScriptByteCodeParser.Token.BRACKET_CLOSE ),
	]
	# high
]

# 演算子テーブルだと遅いかもしれない ...

func _parse_expr( lv:int = 0 ) -> ExprBase:
	if self.error:
		return null
	if len( self.op_table ) <= lv:
		return self._parse_expr_const( )

	var left: = self._parse_expr( lv + 1 )

	for t in self.op_table[lv]:
		if self._get_token( ).token_id == t.op:
			match t.operator_type:
				OperatorType.BINOP_RIGHT:
					if left == null:
						self.error = true
						return null

					var op: = ExprBinOp.new( )
					op.op = self._get_token( ).token_id
					op.a = left
					self._next( )
					op.b = self._parse_expr( 0 )
					return op
				OperatorType.BINOP_LEFT:
					if left == null:
						self.error = true
						return null

					var op: = ExprBinOp.new( )
					op.op = self._get_token( ).token_id
					op.a = left
					self._next( )
					op.b = self._parse_expr( lv )
					return op
				OperatorType.BINOP_LEFT_PERIOD:
					if left != null:
						var op: = ExprBinOp.new( )
						op.op = self._get_token( ).token_id
						op.a = left
						self._next( )
						op.b = self._parse_expr( lv )
						return op
					else:
						# スーパークラスの呼び出し
						var op: = ExprUnOp.new( )
						op.op = self._get_token( ).token_id
						self._next( )
						op.a = self._parse_expr( lv )
						return op
				OperatorType.UNOP:
					var op: = ExprUnOp.new( )
					op.op = self._get_token( ).token_id
					self._next( )
					op.a = self._parse_expr( lv )
					return op
				OperatorType.TRIOP:
					if left == null:
						self.error = true
						return null

					var cif: = ExprIf.new( )
					cif.true_expr = left
					self._next( )
					cif.cond_expr = self._parse_expr( 0 )
					if self._get_token( ).token_id != GDScriptByteCodeParser.Token.CF_ELSE:
						self.error = true
						return null
					self._next( )
					cif.false_expr = self._parse_expr( 0 )
					return cif
				OperatorType.FUNC:
					if left == null:
						self.error = true
						return null

					var cf: = ExprCallFunc.new( )
					cf.callee = left
					self._next( )
					if self._get_token( ).token_id != GDScriptByteCodeParser.Token.PARENTHESIS_CLOSE:
						while ( self.p < self.token_list_len ) and ( not self.error ):
							cf.args.append( self._parse_expr( 0 ) )
							match self._get_token( ).token_id:
								GDScriptByteCodeParser.Token.PARENTHESIS_CLOSE:
									break
								GDScriptByteCodeParser.Token.COMMA:
									pass
								_:
									self.error = true
									return null
					self._next( )
					return cf
				OperatorType.INDEX:
					if left == null:
						self.error = true
						return null

					var cs: = ExprSubscription.new( )
					cs.a = left
					self._next( )
					cs.b = self._parse_expr( lv )
					return cs

	return left

func _parse_expr_const( ) -> ExprBase:
	match self._get_token( ).token_id:
		GDScriptByteCodeParser.Token.PARENTHESIS_OPEN:
			self._next( )
			var c: = self._parse_expr( )
			if self._get_token( ).token_id != GDScriptByteCodeParser.Token.PARENTHESIS_CLOSE:
				self.error = true
				return null
			self._next( )
			return c

		GDScriptByteCodeParser.Token.CONST_PI, GDScriptByteCodeParser.Token.CONST_TAU, GDScriptByteCodeParser.Token.CONST_INF, GDScriptByteCodeParser.Token.CONST_NAN:
			self._next( )
			return ExprReservedConst.new( self._get_token( ).token_id )

		GDScriptByteCodeParser.Token.PR_YIELD:
			self._next( )
			return ExprYield.new( )

		GDScriptByteCodeParser.Token.PR_PRELOAD:
			self._next( )
			return ExprPreload.new( )

		GDScriptByteCodeParser.Token.SELF:
			self._next( )
			return ExprSelf.new( )

		GDScriptByteCodeParser.Token.IDENTIFIER:
			var ei: = ExprIdentifier.new( )
			ei.identifier_id = self._get_token().param
			self._next( )
			return ei

		GDScriptByteCodeParser.Token.BUILT_IN_FUNC:
			var ebif: = ExprBuiltInFunc.new( )
			ebif.built_in_func_id = self._get_token().param
			self._next( )
			return ebif

		GDScriptByteCodeParser.Token.CONSTANT:
			var ec: = ExprConstant.new( )
			ec.constant_id = self._get_token( ).param
			self._next( )
			return ec

		GDScriptByteCodeParser.Token.BRACKET_OPEN:
			return self._parse_expr_array( )

		GDScriptByteCodeParser.Token.CURLY_BRACKET_OPEN:
			return self._parse_expr_dictionary( )

		_:
			return null

func _parse_expr_array( ) -> ExprArray:
	var ea: = ExprArray.new( )

	self._next( )
	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.BRACKET_CLOSE:
		return ea

	while ( self.p < self.token_list_len ) and ( not self.error ):
		ea.list.append( self._parse_expr( ) )

		if self._get_token( ).token_id == GDScriptByteCodeParser.Token.COMMA:
			self._next( )
			if self._get_token( ).token_id == GDScriptByteCodeParser.Token.BRACKET_CLOSE:
				break
		elif self._get_token( ).token_id == GDScriptByteCodeParser.Token.BRACKET_CLOSE:
			break
		else:
			self.error = true

	self._next( )

	return ea

func _parse_expr_dictionary( ) -> ExprDictionary:
	var ed: = ExprDictionary.new( )

	self._next( )
	if self._get_token( ).token_id == GDScriptByteCodeParser.Token.CURLY_BRACKET_CLOSE:
		return ed

	while ( self.p < self.token_list_len ) and ( not self.error ):
		var edc: = ExprDictionaryColumn.new( )
		edc.key = self._parse_expr( )
		if self._get_token( ).token_id != GDScriptByteCodeParser.Token.COLON:
			self.error = true
			return null
		self._next( )
		edc.value = self._parse_expr( )
		
		ed.dict.append( edc )

		if self._get_token( ).token_id == GDScriptByteCodeParser.Token.COMMA:
			self._next( )
			if self._get_token( ).token_id == GDScriptByteCodeParser.Token.CURLY_BRACKET_CLOSE:
				break
		elif self._get_token( ).token_id == GDScriptByteCodeParser.Token.CURLY_BRACKET_CLOSE:
			break
		else:
			self.error = true

	self._next( )

	return ed
