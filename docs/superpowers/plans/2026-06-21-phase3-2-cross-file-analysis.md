# Phase 3.2: 跨文件分析 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将分析从单文件扩展到项目级——扫描 `res://` 全部 `.gd`，解析跨文件调用/信号关系，底部新增 Project tab，保存触发增量重分析。

**Architecture:** 两遍设计——①单文件管道产 `AnalysisResult` + 全局类注册表；②用类注册表 + 类型表解析跨文件 `obj.method()` / `obj.connect()`。项目扫描用 `DirAccess`+`FileAccess` 读源码（不用 `load()`，规避 Phase 3 死锁教训）。增量用 reverse_index 反向索引，保存仅重分析受影响文件。

**Tech Stack:** Godot 4.7, GDScript, DirAccess, FileAccess, EditorPlugin

**Spec reference:** `docs/superpowers/specs/2026-06-21-phase3-2-cross-file-analysis.md`

---

## 文件结构

```
addons/gdscript_util/
├── [Phase 1-3v1 不变] 单文件管道
├── gds_cross_file_edge.gd               # [新增] 跨文件边数据类
├── gds_project_result.gd                # [新增] 项目级结果容器 + 查询 API
├── gds_analysis_result.gd               # [修改] 加 type_table 字段
├── gds_symbol_resolver.gd               # [修改] 填充 type_table
└── editor/
    ├── gds_project_analyzer.gd          # [新增] 扫描 + 批量分析 + 跨文件解析
    ├── gds_analysis_bridge.gd           # [修改] 项目分析入口 + 增量
    └── panels/
        ├── gds_project_panel.gd         # [新增] Project tab
        └── gds_analysis_main_panel.gd   # [修改] 加第 5 tab
samples/
├── analysis_demo.gd                     # [已有] Player 等价
├── cross_file_demo/                     # [新增] 多文件样例项目
│   ├── player.gd
│   └── enemy.gd
tests/
└── test_phase3_2_cross_file.gd          # [新增] 跨文件验收测试
```

---

## Chunk A: 数据结构

### Task A1: 创建 GDSCrossFileEdge

**Files:** Create: `addons/gdscript_util/gds_cross_file_edge.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/gds_cross_file_edge.gd
# 跨文件调用/信号边 — 记录跨文件的引用关系

class_name GDSCrossFileEdge
extends RefCounted

enum Kind {
	CALL,            # obj.method() 跨文件调用
	SIGNAL_EMIT,     # obj.emit("sig") 跨文件发射
	SIGNAL_CONNECT,  # obj.connect("sig", cb) 跨文件连接
	INSTANCE,        # T.new() 实例化
	EXTENDS,         # extends T 继承
}

var kind: int = Kind.CALL
var source_file: String = ""       # 调用方/连接方文件
var source_symbol: String = ""     # 所在函数名
var target_file: String = ""       # 目标类所在文件
var target_class: String = ""      # 目标类名
var target_symbol: String = ""     # 目标方法/信号名
var line: int = 0
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_cross_file_edge.gd
git commit -m "feat: GDSCrossFileEdge — cross-file reference edge data class"
```

---

### Task A2: 创建 GDScriptProjectResult

**Files:** Create: `addons/gdscript_util/gds_project_result.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/gds_project_result.gd
# 项目级结果容器 — 汇总所有文件分析结果 + 跨文件边 + 查询 API

class_name GDScriptProjectResult
extends RefCounted

var root_path: String = ""
var files: Dictionary = {}            # String(path) → GDScriptAnalysisResult
var class_registry: Dictionary = {}   # String(class_name) → String(file_path)
var reverse_index: Dictionary = {}    # String(target_file) → Array[source_file]
var cross_edges: Array = []           # of GDSCrossFileEdge

# 查询: 谁跨文件调用了 p_class.p_method
func get_callers_across_files(p_class: String, p_method: String) -> Array:
	var result: Array = []
	for edge in cross_edges:
		if edge.kind == GDSCrossFileEdge.Kind.CALL \
				and edge.target_class == p_class \
				and edge.target_symbol == p_method:
			result.append(edge)
	return result

# 查询: 信号的跨文件 emit/connect
func get_signal_flow_across_files(p_signal: String) -> Array:
	var result: Array = []
	for edge in cross_edges:
		if edge.kind in [GDSCrossFileEdge.Kind.SIGNAL_EMIT, GDSCrossFileEdge.Kind.SIGNAL_CONNECT] \
				and edge.target_symbol == p_signal:
			result.append(edge)
	return result

# 查询: 哪些文件引用了 p_file
func get_files_referencing(p_file: String) -> Array:
	return reverse_index.get(p_file, [])

func add_edge(p_edge) -> void:
	cross_edges.append(p_edge)
	# 维护反向索引
	if not reverse_index.has(p_edge.target_file):
		reverse_index[p_edge.target_file] = []
	var sources = reverse_index[p_edge.target_file]
	if not sources.has(p_edge.source_file):
		sources.append(p_edge.source_file)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_project_result.gd
git commit -m "feat: GDScriptProjectResult — project-level result container + query API"
```

---

### Task A3: AnalysisResult 加 type_table

**Files:** Modify: `addons/gdscript_util/gds_analysis_result.gd`

- [ ] **Step 1: 在核心数据字段区追加 type_table**

在 `var def_use_chain` 那一行之后追加：

```gdscript
var type_table: Dictionary = {}  # String(var/param name) → String(类型名) — 供跨文件解析用
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_analysis_result.gd
git commit -m "feat: GDScriptAnalysisResult — add type_table field for cross-file resolution"
```

---

### Task A4: SymbolResolver 填充 type_table

**Files:** Modify: `addons/gdscript_util/gds_symbol_resolver.gd`

在变量和参数解析处把声明类型写入 type_table。

- [ ] **Step 1: `_resolve_variable` 中定义后填充**

在 `_resolve_variable` 的 `var sym = p_scope.define(...)` 之后追加：

```gdscript
	# Phase 3.2: 记录变量声明类型到 type_table（供跨文件解析）
	var vtype = _type_to_string(p_node.datatype)
	if vtype != "":
		result.type_table[p_node.name] = vtype
```

- [ ] **Step 2: `_resolve_function` 参数循环中填充**

在参数定义循环里（`func_scope.define(param.name, ...)` 之后）追加：

```gdscript
			# Phase 3.2: 参数声明类型
			var ptype = _type_to_string(param.datatype)
			if ptype != "":
				result.type_table[param.name] = ptype
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/gds_symbol_resolver.gd
git commit -m "feat: SymbolResolver — populate type_table for variables and parameters"
```

---

## Chunk B: 项目分析器

### Task B1: 创建 GDScriptProjectAnalyzer — 扫描

**Files:** Create: `addons/gdscript_util/editor/gds_project_analyzer.gd`

- [ ] **Step 1: 创建文件（扫描部分）**

```gdscript
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
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_project_analyzer.gd
git commit -m "feat: GDScriptProjectAnalyzer — recursive .gd scan + source-read pipeline"
```

---

### Task B2: 批量分析 + 类注册表

**Files:** Modify: `addons/gdscript_util/editor/gds_project_analyzer.gd` (追加)

- [ ] **Step 1: 追加 analyze_all + build_class_registry**

```gdscript
# 全量分析: 扫描 + 单文件管道，返回 GDScriptProjectResult（无跨文件边，待 B3）
func analyze_all(p_root: String) -> GDScriptProjectResult:
	var result = GDScriptProjectResult.new()
	result.root_path = p_root
	var paths = scan_project(p_root)
	for path in paths:
		var file_result = _analyze_file(path)
		if file_result != null:
			result.files[path] = file_result
	_build_class_registry(result)
	return result

# 从各文件的 classname_id 建 {class_name: file_path}
func _build_class_registry(p_result: GDScriptProjectResult) -> void:
	for path in p_result.files:
		var file_result = p_result.files[path]
		if file_result.classname_id != "":
			p_result.class_registry[file_result.classname_id] = path
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_project_analyzer.gd
git commit -m "feat: ProjectAnalyzer — analyze_all + class_registry builder"
```

---

### Task B3: 跨文件解析（核心）

**Files:** Modify: `addons/gdscript_util/editor/gds_project_analyzer.gd` (追加)

遍历每文件的 call_graph EXTERNAL 边 + signal edges，用 type_table + class_registry 解析跨文件目标。

- [ ] **Step 1: 追加 resolve_cross_file**

```gdscript
# 第二遍: 用 type_table + class_registry 解析跨文件调用/信号
func resolve_cross_file(p_result: GDScriptProjectResult) -> void:
	for path in p_result.files:
		var file_result = p_result.files[path]
		_resolve_file_cross_edges(path, file_result, p_result)

func _resolve_file_cross_edges(p_path: String, p_file: GDScriptAnalysisResult, p_project: GDScriptProjectResult) -> void:
	if p_file.call_graph == null:
		return
	for edge in p_file.call_graph.edges:
		# EXTERNAL 调用: obj.method() — 尝试解析 obj 的类型
		if edge.call_type == GDScriptCallEdge.CallType.EXTERNAL and edge.target_object != "":
			var obj_type = p_file.type_table.get(edge.target_object, "")
			if obj_type != "":
				_try_resolve_cross_call(p_path, edge, obj_type, edge.callee, GDSCrossFileEdge.Kind.CALL, p_project)
		# EMIT / SIGNAL_CONNECT / CONNECT: callee 是信号名，target_object 可能是类信号
		# （跨文件信号流主要靠 obj.connect("sig") 形式，edge.target_object 存对象名）
		if edge.call_type in [GDSCallEdge.CallType.CONNECT, GDSCallEdge.CallType.SIGNAL_CONNECT] \
				and edge.target_object != "":
			var obj_type = p_file.type_table.get(edge.target_object, "")
			if obj_type != "":
				_try_resolve_cross_call(p_path, edge, obj_type, edge.callee, GDSCrossFileEdge.Kind.SIGNAL_CONNECT, p_project)

func _try_resolve_cross_call(p_source_file: String, p_edge, p_obj_type: String, p_symbol: String, p_kind: int, p_project: GDScriptProjectResult) -> void:
	# obj 类型是否是用户类？
	var target_file = p_project.class_registry.get(p_obj_type, "")
	if target_file == "":
		return  # 内置类（Node/Object 等）— 跳过
	# 目标文件是否定义了这个方法/信号？
	var target_result = p_project.files.get(target_file, null)
	if target_result == null:
		return
	if not _file_defines_symbol(target_result, p_symbol):
		return
	# 产出跨文件边
	var xedge = GDSCrossFileEdge.new()
	xedge.kind = p_kind
	xedge.source_file = p_source_file
	xedge.source_symbol = p_edge.caller
	xedge.target_file = target_file
	xedge.target_class = p_obj_type
	xedge.target_symbol = p_symbol
	xedge.line = p_edge.site_line
	p_project.add_edge(xedge)

# 检查某文件的 symbol_table 是否定义了该方法/信号
func _file_defines_symbol(p_result: GDScriptAnalysisResult, p_name: String) -> bool:
	if p_result.symbol_table == null:
		return false
	for sym_name in p_result.symbol_table.symbols:
		var sym = p_result.symbol_table.symbols[sym_name]
		if sym.name == p_name and sym.kind in [GDScriptSymbol.Kind.FUNCTION, GDScriptSymbol.Kind.SIGNAL]:
			return true
	return false

# 完整入口
func analyze_full(p_root: String) -> GDScriptProjectResult:
	var result = analyze_all(p_root)
	resolve_cross_file(result)
	return result
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_project_analyzer.gd
git commit -m "feat: ProjectAnalyzer — cross-file call/signal resolution (two-pass core)"
```

---

## Chunk C: Bridge 集成 + 增量

### Task C1: Bridge 加项目分析入口

**Files:** Modify: `addons/gdscript_util/editor/gds_analysis_bridge.gd`

- [ ] **Step 1: 增加项目结果 + 分析入口 + 信号**

在 Bridge 类中增加：

```gdscript
signal project_analysis_started()
signal project_analysis_completed(result: GDScriptProjectResult)

var _project_result: GDScriptProjectResult = null
var _project_analyzer: GDScriptProjectAnalyzer = null

# 全量项目分析（deferred，不阻塞）
func run_project_analysis(p_root: String = "res://") -> void:
	project_analysis_started.emit()
	# deferred 跑重活
	call_deferred("_do_project_analysis", p_root)

func _do_project_analysis(p_root: String) -> void:
	if _project_analyzer == null:
		_project_analyzer = GDScriptProjectAnalyzer.new()
	_project_result = _project_analyzer.analyze_full(p_root)
	project_analysis_completed.emit(_project_result)

func get_project_result() -> GDScriptProjectResult:
	return _project_result
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_analysis_bridge.gd
git commit -m "feat: Bridge — project analysis entry (deferred) + signals"
```

---

### Task C2: 增量分析（保存触发受影响重解析）

**Files:** Modify: `addons/gdscript_util/editor/gds_editor_bootstrap.gd`

保存单文件时：重分析该文件 + 若 class_name 变则重建注册表 + 重解析跨文件边。

- [ ] **Step 1: 修改 `_run_queued_analysis` 支持增量**

```gdscript
func _run_queued_analysis() -> void:
	if _analysis_queued == "":
		return
	_is_analyzing = true
	var path = _analysis_queued
	_analysis_queued = ""
	_bridge.run_analysis(path)
	# Phase 3.2 增量: 若已有项目结果，重分析该文件 + 重解析跨文件边
	_bridge.refresh_file_in_project(path)
	_is_analyzing = false
	if _analysis_queued != "":
		call_deferred("_run_queued_analysis")
```

- [ ] **Step 2: Bridge 加 refresh_file_in_project**

```gdscript
# 增量: 重分析单文件 + 重建注册表 + 重解析跨文件边
func refresh_file_in_project(p_path: String) -> void:
	if _project_result == null or _project_analyzer == null:
		return  # 项目尚未全量分析过，跳过增量
	var new_result = _project_analyzer._analyze_file(p_path)
	if new_result == null:
		return
	# 检查 class_name 是否变化
	var old_cn = ""
	if _project_result.files.has(p_path):
		old_cn = _project_result.files[p_path].classname_id
	_project_result.files[p_path] = new_result
	if new_result.classname_id != old_cn:
		# class_name 变了 → 重建注册表
		_project_result.class_registry.clear()
		_project_analyzer._build_class_registry(_project_result)
	# 重解析跨文件边（简化: 全量重算 cross_edges，反向索引随之更新）
	_project_result.cross_edges.clear()
	_project_result.reverse_index.clear()
	_project_analyzer.resolve_cross_file(_project_result)
	project_analysis_completed.emit(_project_result)
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/editor/gds_editor_bootstrap.gd addons/gdscript_util/editor/gds_analysis_bridge.gd
git commit -m "feat: incremental cross-file re-analysis on save (single file + affected edges)"
```

---

## Chunk D: UI

### Task D1: 创建 GDSProjectPanel — Project tab

**Files:** Create: `addons/gdscript_util/editor/panels/gds_project_panel.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/panels/gds_project_panel.gd
# Project tab — 文件列表 + 引用数 + 跨文件边

class_name GDSProjectPanel
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _tree: Tree = null
var _rebuild_btn: Button = null

func setup(p_bridge: GDSAnalysisBridge) -> void:
	_bridge = p_bridge
	_bridge.project_analysis_completed.connect(_refresh)
	_build_ui()

func _build_ui() -> void:
	var toolbar = HBoxContainer.new()
	add_child(toolbar)

	_rebuild_btn = Button.new()
	_rebuild_btn.text = "Rebuild Project"
	_rebuild_btn.pressed.connect(_on_rebuild)
	toolbar.add_child(_rebuild_btn)

	_tree = Tree.new()
	_tree.size_flags_horizontal = SIZE_EXPAND_FILL
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 2
	_tree.set_column_title(0, "File / Symbol")
	_tree.set_column_title(1, "Refs")
	add_child(_tree)

func _refresh(p_result: GDScriptProjectResult) -> void:
	_tree.clear()
	var root = _tree.create_item()
	# 文件列表 + 引用数
	for path in p_result.files:
		var refs = p_result.get_files_referencing(path).size()
		var item = _tree.create_item(root)
		var short = path.get_file()
		item.set_text(0, short)
		item.set_metadata(0, {"kind": "file", "path": path})
		item.set_text(1, str(refs))
		# 展开跨文件边
		_add_cross_edges(item, path, p_result)

func _add_cross_edges(p_parent: TreeItem, p_path: String, p_result: GDScriptProjectResult) -> void:
	for edge in p_result.cross_edges:
		if edge.source_file == p_path:
			var child = _tree.create_item(p_parent)
			var arrow = "→"
			child.set_text(0, "  %s %s.%s (%s)" % [arrow, edge.target_class, edge.target_symbol, edge.target_file.get_file()])
			child.set_custom_color(0, Color.DODGER_BLUE)

func _on_rebuild() -> void:
	_rebuild_btn.disabled = true
	_bridge.run_project_analysis("res://")
	# 完成后通过 project_analysis_completed 重启用按钮
	_rebuild_btn.set_deferred("disabled", false)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/panels/gds_project_panel.gd
git commit -m "feat: GDSProjectPanel — file list + ref count + cross-file edges tree"
```

---

### Task D2: MainPanel 加第 5 tab "Project"

**Files:** Modify: `addons/gdscript_util/editor/panels/gds_analysis_main_panel.gd`

- [ ] **Step 1: 加 Project tab + 面板**

在 `_build_ui` 中 TabBar 加第 5 个 tab，并创建 `_project_panel`：

```gdscript
	_tab_bar.add_tab("Project")       # tab 4
```

在内容区追加（同其他子面板模式）：

```gdscript
	_project_panel = GDSProjectPanel.new()
	_project_panel.setup(_bridge)
	_make_fill(_project_panel)
	_project_panel.visible = false
	_content_stack.add_child(_project_panel)
```

声明成员变量：

```gdscript
var _project_panel: GDSProjectPanel = null
```

更新 `_on_tab_changed`：

```gdscript
func _on_tab_changed(p_tab: int) -> void:
	_summary_panel.visible = (p_tab == 0)
	_call_graph_panel.visible = (p_tab == 1)
	_signal_flow_panel.visible = (p_tab == 2)
	_def_use_panel.visible = (p_tab == 3)
	_project_panel.visible = (p_tab == 4)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/panels/gds_analysis_main_panel.gd
git commit -m "feat: MainPanel — add 5th 'Project' tab"
```

---

### Task D3: Bootstrap 启动时触发首次项目分析

**Files:** Modify: `addons/gdscript_util/editor/gds_editor_bootstrap.gd`

- [ ] **Step 1: setup 末尾触发首次全量项目分析（deferred）**

在 `setup()` 的 `resource_saved.connect(...)` 之后追加：

```gdscript
	# Phase 3.2: 首次启动 deferred 全量项目分析
	call_deferred("_initial_project_scan")

func _initial_project_scan() -> void:
	_bridge.run_project_analysis("res://")
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_editor_bootstrap.gd
git commit -m "feat: trigger initial deferred project scan on plugin setup"
```

---

## Chunk E: 验收

### Task E1: 跨文件样例项目

**Files:** Create: `samples/cross_file_demo/player.gd`, `samples/cross_file_demo/enemy.gd`

- [ ] **Step 1: player.gd**

```gdscript
# samples/cross_file_demo/player.gd
class_name Player
extends Node

signal health_changed(old_v: int, new_v: int)

var hp: int = 100

func take_damage(amount: int) -> void:
	hp -= amount
	health_changed.emit(hp + amount, hp)
```

- [ ] **Step 2: enemy.gd（跨文件引用 Player）**

```gdscript
# samples/cross_file_demo/enemy.gd
extends Node

func attack(player: Player) -> void:
	# 跨文件调用: player.take_damage()
	player.take_damage(10)
	# 跨文件信号连接: player.health_changed.connect
	player.health_changed.connect(_on_player_hit)

func _on_player_hit(o: int, n: int) -> void:
	print(o, " -> ", n)
```

- [ ] **Step 3: 提交**

```bash
git add samples/cross_file_demo/
git commit -m "test: cross-file demo project (Player + Enemy referencing it)"
```

---

### Task E2: 跨文件验收测试

**Files:** Create: `tests/test_phase3_2_cross_file.gd`

- [ ] **Step 1: 创建测试**

```gdscript
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
	return pa.analyze_full("res://samples/cross_file_demo")

func test_scan():
	print("Test: project scan...")
	var pa = GDScriptProjectAnalyzer.new()
	var files = pa.scan_project("res://samples/cross_file_demo")
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
```

- [ ] **Step 2: 创建测试场景 + 运行**

创建 `tests/test_phase3_2_cross_file.tscn`（参考已有 .tscn 格式），设为 main_scene 运行。

- [ ] **Step 3: 提交**

```bash
git add tests/test_phase3_2_cross_file.gd tests/test_phase3_2_cross_file.tscn
git commit -m "test: Phase 3.2 cross-file acceptance — scan/registry/call/signal"
```

---

### Task E3: 回归 + UI 手动验收

- [ ] **Step 1: 运行 Phase 1/2/3v1 测试** — 确认全通过
- [ ] **Step 2: 运行 Phase 3.2 测试** — 4/4 通过
- [ ] **Step 3: 编辑器手动验收**
  - 重启插件 → Project tab 自动填充文件列表
  - 打开 `samples/cross_file_demo/enemy.gd` → 保存 → Project tab 增量更新
  - 点 Player.gd 行 → 展开"Enemy.gd 引用它"
  - "Rebuild Project" 按钮 → 全量重扫
- [ ] **Step 4: 提交**

```bash
git add -A
git commit -m "test: Phase 3.2 regression + UI acceptance pass"
```

---

## 完成检查清单

- [ ] `gds_cross_file_edge.gd` — 跨文件边数据类
- [ ] `gds_project_result.gd` — 项目级结果 + 查询 API + reverse_index
- [ ] `gds_analysis_result.gd` — 加 type_table 字段
- [ ] `gds_symbol_resolver.gd` — 填充 type_table
- [ ] `gds_project_analyzer.gd` — 扫描 + 批量分析 + 类注册表 + 跨文件解析
- [ ] Bridge — 项目分析入口（deferred）+ 增量 refresh
- [ ] `gds_project_panel.gd` — Project tab
- [ ] MainPanel — 第 5 tab
- [ ] Bootstrap — 启动首次项目扫描 + 保存增量触发
- [ ] Phase 1/2/3v1 回归全通过
- [ ] Phase 3.2 测试 4/4
- [ ] Project tab 手动验收

## 已知限制（Phase 3.3）

- 动态类型 `var x = func()` 返回值不解析（无类型推断）
- 跨文件边用 EXTERNAL edge 的 target_object 查 type_table，未标注类型的对象跳过
- 增量 cross_edges 全量重算（未做精细反向边局部更新，YAGNI）
- 首次大项目扫描可能慢（deferred 分批未实现，按需 Phase 3.3）
