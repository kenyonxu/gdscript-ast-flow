# tests/benchmark.gd
# 性能基准 — 测量 tokenize/parse/resolve 各阶段耗时
# 用法: Script Editor 打开此文件 → File → Run (Ctrl+Shift+X)
# 参考 ADR-0001: profile first, 再决定是否需要 C# 优化

@tool
extends EditorScript

func _run():
	print("=== GDScript Analysis Pipeline Benchmark ===\n")
	var files := [
		"res://samples/analysis_demo.gd",
		"res://addons/gdscript_util/gds_tokenizer.gd",
		"res://addons/gdscript_util/gds_parser.gd",
		"res://addons/gdscript_util/gds_symbol_resolver.gd",
		"res://addons/gdscript_util/editor/gds_project_analyzer.gd",
	]
	for path in files:
		_bench_file(path)
	print("\n=== Done ===")

func _bench_file(p_path: String) -> void:
	var f = FileAccess.open(p_path, FileAccess.READ)
	if f == null:
		print("SKIP (not found): %s" % p_path)
		return
	var source = f.get_as_text()
	f.close()
	var lines = source.count("\n") + 1

	# Tokenize
	var t0 = Time.get_ticks_usec()
	var tokenizer = GDScriptTokenizer.new()
	var tokens = tokenizer.tokenize(source)
	var t_tok = Time.get_ticks_usec() - t0

	# Parse
	var t1 = Time.get_ticks_usec()
	var parser = GDScriptParser.new()
	var ast = parser.parse(tokens)
	var t_parse = Time.get_ticks_usec() - t1

	var parse_err = parser.error != ""

	# Resolve
	var t2 = Time.get_ticks_usec()
	var resolver = GDScriptSymbolResolver.new()
	var result = resolver.resolve(ast, p_path)
	var t_resolve = Time.get_ticks_usec() - t2

	var total = t_tok + t_parse + t_resolve
	var edges = 0
	var sigs = 0
	if result and result.call_graph:
		edges = result.call_graph.edges.size()
	if result and result.signal_graph:
		sigs = result.signal_graph.signals.size()

	print("%-50s %5d lines | tok %6.1fms  parse %6.1fms  resolve %6.1fms  = %6.1fms  | %3d edges %2d sigs %s" % [
		p_path.get_file(), lines,
		t_tok / 1000.0, t_parse / 1000.0, t_resolve / 1000.0,
		total / 1000.0, edges, sigs,
		" [PARSE_ERR]" if parse_err else ""
	])
