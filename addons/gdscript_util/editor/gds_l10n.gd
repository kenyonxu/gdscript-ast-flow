# addons/gdscript_util/editor/gds_l10n.gd
# 插件本地化辅助 — 基于 Godot 4.7 TranslationDomain 系统
# API: TranslationServer.get_or_add_domain() → domain.add_translation() → domain.translate()

class_name GDSL10n
extends RefCounted

const DOMAIN := "gdscript_util"
const LOCALES_DIR := "res://addons/gdscript_util/locales/"

var _domain: TranslationDomain = null
var _loaded := false

func setup() -> void:
	if _loaded:
		return
	_domain = TranslationServer.get_or_add_domain(DOMAIN)
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
				_domain.add_translation(translation)
		file = dir.get_next()
	dir.list_dir_end()
	_loaded = true

func t(p_key: String) -> String:
	if not _loaded:
		return p_key
	var result = _domain.translate(p_key)
	# translate 返回空串或 key 本身时降级
	if result == null or result == "" or result == p_key:
		return p_key
	return result

# 支持格式化: tf("msg.parse_error") % "具体错误"
func tf(p_key: String, p_args: Array) -> String:
	return t(p_key) % p_args
