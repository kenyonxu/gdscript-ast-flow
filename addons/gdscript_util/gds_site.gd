# addons/gdscript_util/gds_site.gd
# emit/connect 位置信息

class_name GDScriptSite
extends RefCounted

var line: int = 0
var node = null
var enclosing_function: String = ""
var arguments: Array = []
