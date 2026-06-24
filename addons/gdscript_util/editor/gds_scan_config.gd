# addons/gdscript_util/editor/gds_scan_config.gd
# 项目扫描配置 — 存储在 ProjectSettings (PackedStringArray)，原生 Project Settings 编辑

class_name GDSScanConfig
extends RefCounted

const SETTING_ENABLED := "gdscript_util/scan/enabled"
const SETTING_INCLUDE := "gdscript_util/scan/include"
const SETTING_EXCLUDE := "gdscript_util/scan/exclude"

const DEFAULT_EXCLUDE := PackedStringArray("res://addons", "res://.godot", "res://.git")

static func is_enabled() -> bool:
	return ProjectSettings.get_setting(SETTING_ENABLED, false)

static func get_include_dirs() -> Array:
	var arr: PackedStringArray = ProjectSettings.get_setting(SETTING_INCLUDE, PackedStringArray())
	return Array(arr)

static func get_exclude_dirs() -> Array:
	var arr: PackedStringArray = ProjectSettings.get_setting(SETTING_EXCLUDE, DEFAULT_EXCLUDE)
	return Array(arr)

# 迁移旧格式（Array<Dictionary> → PackedStringArray）
static func migrate_if_needed() -> void:
	# include_dirs → include
	var old_include = ProjectSettings.get_setting("gdscript_util/scan/include_dirs", null)
	if old_include != null and old_include is Array and old_include.size() > 0:
		var new_arr := PackedStringArray()
		for entry in old_include:
			var path = entry.get("path", "") if entry is Dictionary else str(entry)
			if path != "":
				new_arr.append(path)
		ProjectSettings.set_setting(SETTING_INCLUDE, new_arr)
		ProjectSettings.set_setting("gdscript_util/scan/include_dirs", null)
	# exclude_dirs → exclude
	var old_exclude = ProjectSettings.get_setting("gdscript_util/scan/exclude_dirs", null)
	if old_exclude != null and old_exclude is Array and old_exclude.size() > 0:
		ProjectSettings.set_setting(SETTING_EXCLUDE, PackedStringArray(old_exclude))
		ProjectSettings.set_setting("gdscript_util/scan/exclude_dirs", null)
