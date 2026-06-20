# addons/gdscript_util/gds_symbol_table.gd
# 嵌套作用域符号表 — 支持父作用域链式查找

class_name GDScriptSymbolTable
extends RefCounted

var parent: GDScriptSymbolTable = null
var symbols: Dictionary = {}
var scope_name: String = ""

func define(p_name: String, p_kind: int, p_node, p_datatype: String = "") -> GDScriptSymbol:
	var sym = GDScriptSymbol.new()
	sym.name = p_name
	sym.kind = p_kind
	sym.declaration = p_node
	sym.datatype = p_datatype
	symbols[p_name] = sym
	return sym

func resolve(p_name: String) -> GDScriptSymbol:
	if symbols.has(p_name):
		return symbols[p_name]
	if parent != null:
		return parent.resolve(p_name)
	return null

func resolve_local(p_name: String) -> GDScriptSymbol:
	return symbols.get(p_name, null)
