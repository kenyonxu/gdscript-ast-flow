# addons/gdscript_util/gds_signal_info.gd
# 单个信号的完整流程图

class_name GDScriptSignalInfo
extends RefCounted

var name: String = ""
var declaration = null
var params: Array = []
var emit_sites: Array = []
var connect_sites: Array = []
