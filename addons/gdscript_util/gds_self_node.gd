# addons/gdscript_util/gds_self_node.gd
# AST Self 节点 — 独立 class_name 以避免内部类运行时限制

class_name GDScriptSelfNode
extends RefCounted

var line: int = 0
var column: int = 0
