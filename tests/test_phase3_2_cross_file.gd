# tests/test_phase3_2_cross_file.gd
# Phase 3.2 跨文件验收测试
extends Node

func _ready():
	print("=== Phase 3.2 Cross-File Tests ===\n")
	test_scan()
	test_class_registry()
	test_cross_file_call()
	test_cross_file_signal()
	print("\n=== Done ===")

func analyze_project() -> GDScriptProjectResult:
	var pa = GDScriptProjectAnalyzer.new()
	# 测试用临时配置
	GDSScanConfig.save_config([{"path": "res://samples/cross_file_demo", "recursive": true}], [])
	GDSScanConfig.enable_scan()
	return pa.analyze_full()

func test_scan():
	print("Test: project scan...")
	var pa = GDScriptProjectAnalyzer.new()
	GDSScanConfig.save_config([{"path": "res://samples/cross_file_demo", "recursive": true}], [])
	var files = pa.scan_project()
	assert(files.size() >= 2, "Expected >=2 files, got %d" % files.size())
	print("  PASS (%d files)" % files.size())

func test_class_registry():
	print("Test: class registry...")
	var result = analyze_project()
	assert(result.class_registry.has("Player"), "Player should be in registry")
	assert(result.class_registry["Player"].ends_with("player.gd"), "Player path wrong")
	print("  PASS")

func test_cross_file_call():
	print("Test: cross-file call resolution...")
	var result = analyze_project()
	var callers = result.get_callers_across_files("Player", "take_damage")
	assert(callers.size() >= 1, "Expected >=1 cross-file caller of Player.take_damage")
	if callers.size() > 0:
		assert(callers[0].source_file.ends_with("enemy.gd"), "Caller should be enemy.gd")
	print("  PASS")

func test_cross_file_signal():
	print("Test: cross-file signal connect...")
	var result = analyze_project()
	var conns = result.get_signal_flow_across_files("health_changed")
	assert(conns.size() >= 1, "Expected >=1 cross-file signal edge")
	print("  PASS")
