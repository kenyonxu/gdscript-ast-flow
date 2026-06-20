# addons/gdscript_util/gds_super_node.gd
# AST Super 节点 — 独立 class_name 以避免内部类运行时限制

class_name GDScriptSuperNode
extends RefCounted

var line: int = 0
var column: int = 0
