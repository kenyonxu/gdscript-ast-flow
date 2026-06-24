# addons/gdscript_ast/editor/gds_entry_methods.gd
# 引擎虚拟/生命周期方法集合 — 图中标记执行入口

class_name GDS_EntryMethods
extends RefCounted

const METHODS := {
	# 生命周期
	"_ready": true,
	"_enter_tree": true,
	"_exit_tree": true,
	"_init": true,
	# 帧循环
	"_process": true,
	"_physics_process": true,
	# 输入
	"_input": true,
	"_unhandled_input": true,
	"_unhandled_key_input": true,
	"_shortcut_input": true,
	# 绘制
	"_draw": true,
	# 信号回调约定（常见命名）
	"_on": true,  # 前缀匹配，下面用 is_entry 单独处理
	# EditorPlugin 虚拟
	"_has_main_screen": true,
	"_make_visible": true,
	"_get_plugin_name": true,
	"_handles": true,
	"_edit": true,
	# Notification
	"_notification": true,
	# 资源/场景
	"_to_string": true,
	"_get": true,
	"_set": true,
}

static func is_entry(p_name: String) -> bool:
	if METHODS.has(p_name):
		return true
	# _on_ 前缀的信号回调也算入口（约定）
	return p_name.begins_with("_on_")
