# 结构化图谱导出 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把分析结果导出为 AI agent 可消费的结构化 JSON——含文件/函数/调用图/信号流/跨文件边/枢纽/耦合。

**Architecture:** 三个数据类加 `to_dict()` 方法；ProjectResult 加 `export_json()`；主屏 toolbar 加 Export 按钮。

**Tech Stack:** Godot 4.7, GDScript, JSON, FileAccess, FileDialog

**Spec reference:** `docs/superpowers/specs/2026-06-23-codegraph-export.md`

---

## Task 1: CrossFileEdge.to_dict()

**Files:** Modify: `addons/gdscript_util/gds_cross_file_edge.gd`

- [ ] **Step 1: 添加 to_dict 方法**

```gdscript
enum Kind { CALL, SIGNAL_EMIT, SIGNAL_CONNECT, INSTANCE, EXTENDS }

const KIND_NAMES := ["CALL", "SIGNAL_EMIT", "SIGNAL_CONNECT", "INSTANCE", "EXTENDS"]

func to_dict() -> Dictionary:
	return {
		"source_file": source_file,
		"target_file": target_file,
		"target_class": target_class,
		"target_symbol": target_symbol,
		"kind": KIND_NAMES[kind] if kind >= 0 and kind < KIND_NAMES.size() else "UNKNOWN",
		"line": line,
	}
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_cross_file_edge.gd
git commit -m "feat: CrossFileEdge.to_dict() — serialize to JSON-friendly dict"
```

---

## Task 2: AnalysisResult.to_dict()

**Files:** Modify: `addons/gdscript_util/gds_analysis_result.gd`

- [ ] **Step 1: 添加 to_dict + 辅助方法**

```gdscript
const ENTRY_METHODS := preload("res://addons/gdscript_util/editor/gds_entry_methods.gd")

func to_dict() -> Dictionary:
	var funcs: Array = []
	for fn in get_all_functions():
		funcs.append(_function_to_dict(fn))
	var sigs: Array = []
	for sig in get_all_signals():
		sigs.append(_signal_to_dict(sig))
	var call_edges: Array = []
	if call_graph:
		for edge in call_graph.edges:
			call_edges.append({
				"caller": edge.caller,
				"callee": edge.callee,
				"type": _call_type_str(edge.call_type),
				"line": edge.site_line,
			})
	return {
		"class_name": classname_id,
		"extends": extends_path,
		"functions": funcs,
		"signals": sigs,
		"call_edges": call_edges,
		"errors": errors,
	}

func _function_to_dict(p_fn) -> Dictionary:
	var params: Array = []
	for p in p_fn.params:
		params.append({"name": p.name, "type": _type_str(p.datatype)})
	return {
		"name": p_fn.name,
		"line": p_fn.line,
		"params": params,
		"return_type": _type_str(p_fn.return_type),
		"is_entry": ENTRY_METHODS.is_entry(p_fn.name),
		"is_static": p_fn.is_static,
		"in_degree": call_in_degree.get(p_fn.name, 0),
		"out_degree": call_out_degree.get(p_fn.name, 0),
	}

func _signal_to_dict(p_sig) -> Dictionary:
	var params: Array = []
	for p in p_sig.params:
		params.append(_type_str(p.datatype))
	var info = signal_graph.get_signal_flow(p_sig.name) if signal_graph else null
	return {
		"name": p_sig.name,
		"line": p_sig.line,
		"params": params,
		"emit_count": info.emit_sites.size() if info else 0,
		"connect_count": info.connect_sites.size() if info else 0,
	}

static func _type_str(p_type) -> String:
	if p_type == null:
		return ""
	return p_type.type_name if "type_name" in p_type else ""

static func _call_type_str(p_type: int) -> String:
	const NAMES := ["SELF", "SUPER", "EXTERNAL", "CONNECT", "SIGNAL_CONNECT", "LAMBDA", "STATIC", "EMIT"]
	return NAMES[p_type] if p_type >= 0 and p_type < NAMES.size() else "UNKNOWN"
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_analysis_result.gd
git commit -m "feat: AnalysisResult.to_dict() — serialize functions/signals/call_edges"
```

---

## Task 3: ProjectResult.to_dict() + export_json()

**Files:** Modify: `addons/gdscript_util/gds_project_result.gd`

- [ ] **Step 1: 添加序列化 + 导出方法**

```gdscript
func to_dict(p_project_name: String = "") -> Dictionary:
	var summary := _build_summary()
	var files_dict := {}
	for path in files:
		files_dict[path] = files[path].to_dict()
	var cross_arr: Array = []
	for edge in cross_edges:
		cross_arr.append(edge.to_dict())
	return {
		"schema_version": 1,
		"project": p_project_name,
		"source_path": root_path,
		"summary": summary,
		"files": files_dict,
		"cross_file": cross_arr,
		"hub_functions": _top_hubs(20),
		"coupled_files": _top_coupled(20),
	}

func export_json(p_path: String, p_project_name: String = "") -> Error:
	var data = to_dict(p_project_name)
	var json_str = JSON.stringify(data, "  ")
	var f = FileAccess.open(p_path, FileAccess.WRITE)
	if f == null:
		return ERR_CANT_OPEN
	f.store_string(json_str)
	f.close()
	return OK

func _build_summary() -> Dictionary:
	var func_count := 0
	var sig_count := 0
	var edge_count := 0
	for path in files:
		var fr = files[path]
		func_count += fr.get_all_functions().size()
		sig_count += fr.get_all_signals().size()
		if fr.call_graph:
			edge_count += fr.call_graph.edges.size()
	return {
		"files_analyzed": files.size(),
		"total_functions": func_count,
		"total_signals": sig_count,
		"total_call_edges": edge_count,
		"total_cross_file_edges": cross_edges.size(),
	}

func _top_hubs(p_limit: int) -> Array:
	var hubs: Array = []
	for path in files:
		var fr = files[path]
		for name in fr.call_in_degree:
			var total = fr.call_in_degree[name] + fr.call_out_degree.get(name, 0)
			if total > 0:
				hubs.append({"name": name, "file": path, "total_degree": total})
	hubs.sort_custom(func(a, b): return a.total_degree > b.total_degree)
	return hubs.slice(0, mini(p_limit, hubs.size()))

func _top_coupled(p_limit: int) -> Array:
	var pair_counts: Dictionary = {}
	for edge in cross_edges:
		var key = [edge.source_file, edge.target_file]
		key.sort()
		var key_str = key[0] + "|" + key[1]
		pair_counts[key_str] = pair_counts.get(key_str, 0) + 1
	var pairs: Array = []
	for key_str in pair_counts:
		var parts = key_str.split("|")
		pairs.append({"file_a": parts[0], "file_b": parts[1], "edge_count": pair_counts[key_str]})
	pairs.sort_custom(func(a, b): return a.edge_count > b.edge_count)
	return pairs.slice(0, mini(p_limit, pairs.size()))
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_project_result.gd
git commit -m "feat: ProjectResult.to_dict() + export_json() — full codegraph serialization"
```

---

## Task 4: 主屏 Export JSON 按钮

**Files:** Modify: `addons/gdscript_util/editor/gds_graph_main_screen.gd`

- [ ] **Step 1: toolbar 加 Export 按钮 + FileDialog**

```gdscript
# _build_ui toolbar 区域加:
var export_btn = Button.new()
export_btn.text = "Export JSON"
export_btn.pressed.connect(_on_export)
toolbar.add_child(export_btn)

func _on_export() -> void:
	var dialog = FileDialog.new()
	dialog.title = "Export Code Graph"
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.json", "JSON")
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.current_file = "codegraph.json"
	EditorInterface.get_base_control().add_child(dialog)
	dialog.file_selected.connect(_on_export_path)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _on_export_path(p_path: String) -> void:
	var result = _bridge.get_project_result()
	if result and result.files.size() > 0:
		var err = result.export_json(p_path)
		if err == OK:
			print("[GDScriptUtil] Code graph exported to: %s" % p_path)
		else:
			push_warning("[GDScriptUtil] Export failed: error %d" % err)
	else:
		push_warning("[GDScriptUtil] No project data to export. Enable scan first.")
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_graph_main_screen.gd
git commit -m "feat: main screen — Export JSON button + FileDialog"
```

---

## Task 5: 验收

- [ ] **Step 1:** Enable scan → Rebuild → Export JSON → 选路径保存
- [ ] **Step 2:** 打开导出的 JSON，确认含 schema_version/summary/files/cross_file/hub_functions/coupled_files
- [ ] **Step 3:** `JSON.parse(FileAccess.get_as_text(path))` 成功
- [ ] **Step 4:** cross_file_demo 导出 ≤ 10KB
- [ ] **Step 5:** 回归 — Phase 1-3 功能不受影响

---

## 完成检查清单

- [ ] CrossFileEdge.to_dict()
- [ ] AnalysisResult.to_dict()
- [ ] ProjectResult.to_dict() + export_json() + _top_hubs + _top_coupled
- [ ] 主屏 Export JSON 按钮
- [ ] JSON 有效、含全部字段
- [ ] 回归通过
