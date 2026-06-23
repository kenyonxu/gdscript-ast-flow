# addons/gdscript_util/editor/gds_scan_config.gd
# 项目扫描配置读写 — 存储在 ProjectSettings，持久化跨编辑器重启

class_name GDSScanConfig
extends RefCounted

const SETTING_ENABLED := "gdscript_util/scan/enabled"
const SETTING_INCLUDE := "gdscript_util/scan/include_dirs"
const SETTING_EXCLUDE := "gdscript_util/scan/exclude_dirs"

const DEFAULT_EXCLUDE := ["res://addons", "res://.godot", "res://.git"]

static func is_enabled() -> bool:
	return ProjectSettings.get_setting(SETTING_ENABLED, false)

static func get_include_dirs() -> Array:
	return ProjectSettings.get_setting(SETTING_INCLUDE, [])

static func get_exclude_dirs() -> Array:
	return ProjectSettings.get_setting(SETTING_EXCLUDE, DEFAULT_EXCLUDE)

# Settings 弹窗 Save 调用 — 保存配置 + 自动关闭扫描
static func save_config(p_include: Array, p_exclude: Array) -> void:
	ProjectSettings.set_setting(SETTING_INCLUDE, p_include)
	ProjectSettings.set_setting(SETTING_EXCLUDE, p_exclude)
	ProjectSettings.set_setting(SETTING_ENABLED, false)
	# 注册到 ProjectSettings 使其在编辑器 Settings 面板可见
	if not ProjectSettings.has_setting(SETTING_ENABLED):
		ProjectSettings.set_initial_value(SETTING_ENABLED, false)
	ProjectSettings.save()

# Enable 勾选调用 — 显式开启扫描
static func enable_scan() -> void:
	ProjectSettings.set_setting(SETTING_ENABLED, true)
	ProjectSettings.save()

static func disable_scan() -> void:
	ProjectSettings.set_setting(SETTING_ENABLED, false)
	ProjectSettings.save()
