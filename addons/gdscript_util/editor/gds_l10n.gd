# addons/gdscript_util/editor/gds_l10n.gd
# 插件本地化辅助 — 基于 Godot TranslationServer 自定义域
# 参考: clef-dev/addons/clef/editor/clef_l10n.gd

class_name GDSL10n
extends RefCounted

const DOMAIN := "gdscript_util"
const LOCALES_DIR := "res://addons/gdscript_util/locales/"

var _loaded := false

func setup() -> void:
	if _loaded:
		return
	var dir = DirAccess.open(LOCALES_DIR)
	if dir == null:
		push_warning("[GDSL10n] Cannot open locales dir: " + LOCALES_DIR)
		return
	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		if file.ends_with(".translation"):
			var translation = load(LOCALES_DIR + file) as Translation
			if translation:
				translation.message = DOMAIN
				TranslationServer.add_translation(translation)
		file = dir.get_next()
	dir.list_dir_end()
	_loaded = true

func t(p_key: String) -> String:
	if not _loaded:
		return p_key
	var result = TranslationServer.translate(p_key, DOMAIN)
	# translate 返回空串或 key 本身时降级
	if result == null or result == "" or result == p_key:
		return p_key
	return result

# 支持格式化: t("msg.parse_error") % "具体错误"
func tf(p_key: String, p_args: Array) -> String:
	return t(p_key) % p_args
