# addons/gdscript_util/editor/gds_project_analyzer.gd
# 项目级分析器 — 扫描 .gd 文件 + 批量分析 + 跨文件解析
# 注意: 用 DirAccess + FileAccess 读源码，不用 load()（规避 resource_saved 死锁）

class_name GDScriptProjectAnalyzer
extends RefCounted

const SKIP_DIRS := [".", "..", ".godot", ".git", "addons"]  # addons 第三方噪音，可调

# 递归扫描 root 下所有 .gd 文件
func scan_project(p_root: String) -> Array:
	var list: Array = []
	_scan_dir(p_root, list)
	return list

func _scan_dir(p_dir: String, p_list: Array) -> void:
	var da = DirAccess.open(p_dir)
	if da == null:
		return
	da.list_dir_begin()
	var name = da.get_next()
	while name != "":
		if name in SKIP_DIRS:
			name = da.get_next()
			continue
		var full = p_dir.path_join(name)
		if da.current_is_dir():
			_scan_dir(full, p_list)
		elif name.ends_with(".gd"):
			p_list.append(full)
		name = da.get_next()
	da.list_dir_end()

# 单文件管道 — 直接读源码（不 load）
func _analyze_file(p_path: String) -> GDScriptAnalysisResult:
	var f = FileAccess.open(p_path, FileAccess.READ)
	if f == null:
		return null
	var source = f.get_as_text()
	f.close()
	if source == "":
		return null
	var tokenizer = GDScriptTokenizer.new()
	var tokens = tokenizer.tokenize(source)
	var parser = GDScriptParser.new()
	var ast = parser.parse(tokens)
	if parser.error != "":
		push_warning("[ProjectAnalyzer] Parse error in %s: %s" % [p_path, parser.error])
		return null
	var resolver = GDScriptSymbolResolver.new()
	return resolver.resolve(ast, p_path)
