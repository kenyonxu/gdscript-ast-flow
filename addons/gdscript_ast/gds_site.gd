# addons/gdscript_ast/gds_site.gd
# emit/connect 位置信息

class_name GDScriptSite
extends RefCounted

var line: int = 0
var node = null
var enclosing_function: String = ""
var arguments: Array = []
var target_object: String = ""   # emit/connect 的 base 对象名（player.health_changed 的 player）
var target_type: String = ""     # target_object 推断的类型名（type_table）
