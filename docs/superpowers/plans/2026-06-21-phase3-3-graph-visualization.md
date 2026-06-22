# Phase 3.3: 图可视化 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Tree 数据升级为 GraphEdit 节点-边图——编辑器主屏 "Analysis" tab，渲染调用图 / 信号流 / 项目级图，可交互（点节点跳转、缩放、重布局）。

**Architecture:** 新增主屏 tab（`_has_main_screen`），一个 `GraphEdit` 按 Scope（单文件/项目）+ Graph 类型（调用/信号）切换，由 3 个 view builder 重建。度数（in/out degree）由 resolver 统计，驱动节点大小与枢纽高亮。数据复用 Phase 1-3.2 的 CallGraph/SignalGraph/CrossFileEdge。

**Tech Stack:** Godot 4.7, GDScript, EditorPlugin 主屏 API, GraphEdit, GraphNode

**Spec reference:** `docs/superpowers/specs/2026-06-21-phase3-3-graph-visualization.md`

---

## 文件结构

```
addons/gdscript_util/
├── gds_analysis_result.gd              # [修改] 加 degree 表
├── gds_symbol_resolver.gd              # [修改] _add_call_edge 累加度数
├── plugin.gd                           # [修改] _has_main_screen/_make_visible/_get_plugin_name
└── editor/
    ├── gds_editor_bootstrap.gd         # [修改] 注册主屏 + _make_visible 转发
    ├── gds_analysis_bridge.gd          # [不变] 已有 get_current_result/get_project_result
    ├── gds_graph_main_screen.gd        # [新增] 主屏 tab 容器（toolbar + GraphEdit + 切换）
    └── graphs/                          # [新增]
        ├── gds_graph_node.gd           # 通用 GraphNode（函数/信号/文件节点）
        ├── gds_call_graph_view.gd      # 调用图 builder
        ├── gds_signal_graph_view.gd    # 信号流 builder
        └── gds_project_graph_view.gd   # 项目级 builder
tests/
└── test_phase3_3_graph.gd              # [新增] 图构建验收（节点数/边数/度数）
```

---

## Chunk A: 度数数据

### Task A1: AnalysisResult 加 degree 字段

**Files:** Modify: `addons/gdscript_util/gds_analysis_result.gd`

- [ ] **Step 1: 在核心数据区追加度数字典**

在 `var def_use_chain` / `var type_table` 那组字段之后追加：

```gdscript
# Phase 3.3: 调用度数（驱动图节点大小/枢纽高亮）
var call_in_degree: Dictionary = {}   # String(func) → int（被调次数）
var call_out_degree: Dictionary = {}  # String(func) → int（调用次数）
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_analysis_result.gd
git commit -m "feat: AnalysisResult — add call in/out degree tables for graph sizing"
```

---

### Task A2: resolver 累加度数

**Files:** Modify: `addons/gdscript_util/gds_symbol_resolver.gd:197` (`_add_call_edge`)

- [ ] **Step 1: 在 `_add_call_edge` 记录边时累加度数**

```gdscript
func _add_call_edge(p_caller: String, p_callee: String, p_line: int, p_call_type: int, p_target: String = "", p_arguments: Array = []):
	var edge = GDScriptCallEdge.new()
	edge.caller = p_caller
	edge.callee = p_callee
	edge.site_line = p_line
	edge.call_type = p_call_type
	edge.target_object = p_target
	edge.arguments = p_arguments
	result.call_graph.add_edge(edge)
	# Phase 3.3: 累加度数（caller 出度 +1, callee 入度 +1）
	if p_caller != "" and p_caller != "<class>":
		result.call_out_degree[p_caller] = result.call_out_degree.get(p_caller, 0) + 1
	if p_callee != "":
		result.call_in_degree[p_callee] = result.call_in_degree.get(p_callee, 0) + 1
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_symbol_resolver.gd
git commit -m "feat: resolver — accumulate call in/out degree on each edge"
```

---

## Chunk B: 图节点 + 主屏容器

### Task B1: 创建 GDSGraphNode — 通用图节点

**Files:** Create: `addons/gdscript_util/editor/graphs/gds_graph_node.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/graphs/gds_graph_node.gd
# 通用 GraphNode — 表示函数/信号/文件节点，度数驱动视觉
# GraphNode 有左右 slot：左=入边，右=出边

class_name GDSGraphNode
extends GraphNode

# kind: "function" / "signal" / "file"
func configure(p_kind: String, p_name: String, p_subtitle: String, p_degree: int) -> void:
	title = p_name
	# 副文本：@line / in:out / 文件路径
	var label = Label.new()
	label.text = p_subtitle
	label.add_theme_font_size_override("font_size", 11)
	add_child(label)
	# 枢纽高亮：度数 >= 5 用暖色（找"上帝函数"/高耦合文件）
	if p_degree >= 5:
		add_theme_color_override("title_color", Color.ORANGE_RED)
	# slot: 左 enable（入边），右 enable（出边）；type 用于着色分组
	var in_type := 0
	var out_type := 1
	var in_color := Color.DODGER_BLUE
	var out_color := Color.DODGER_BLUE
	set_slot(0, true, in_type, in_color, true, out_type, out_color)
	# 默认尺寸
	custom_minimum_size = Vector2(140, 0)
```

> **注意：** Godot 4.7 GraphNode API（`set_slot` 参数顺序、`title` 属性）实现时若签名有变，查 `mcp__godot__class-info GraphNode` 确认。

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/graphs/gds_graph_node.gd
git commit -m "feat: GDSGraphNode — generic GraphNode with degree-driven highlight"
```

---

### Task B2: 创建 GDSGraphMainScreen — 主屏容器

**Files:** Create: `addons/gdscript_util/editor/gds_graph_main_screen.gd`

拥有 toolbar（Scope + Graph 切换）+ 一个 GraphEdit + 3 个 view builder。

- [ ] **Step 1: 创建文件（骨架 + UI）**

```gdscript
# addons/gdscript_util/editor/graphs/../gds_graph_main_screen.gd
# 主屏 tab — Scope(单文件/项目) × Graph(调用/信号) 切换，重建 GraphEdit

class_name GDSGraphMainScreen
extends Control

var _bridge: GDSAnalysisBridge = null
var _graph_edit: GraphEdit = null
var _scope: int = 0  # 0=当前文件, 1=项目
var _graph_kind: int = 0  # 0=调用, 1=信号
var _call_view: GDSCallGraphView = null
var _signal_view: GDSSignalGraphView = null
var _project_view: GDSProjectGraphView = null

func setup(p_bridge: GDSAnalysisBridge) -> void:
	_bridge = p_bridge
	_bridge.analysis_completed.connect(_on_data_changed)
	_bridge.project_analysis_completed.connect(_on_data_changed)
	_call_view = GDSCallGraphView.new()
	_signal_view = GDSSignalGraphView.new()
	_project_view = GDSProjectGraphView.new()
	_build_ui()
	_rebuild()

func _build_ui() -> void:
	# 顶部 toolbar
	var toolbar = HBoxContainer.new()
	toolbar.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(toolbar)
	# Scope 切换
	var scope_box = OptionButton.new()
	scope_box.add_item("Scope: Current File", 0)
	scope_box.add_item("Scope: Project", 1)
	scope_box.item_selected.connect(func(i): _scope = i; _rebuild())
	toolbar.add_child(scope_box)
	# Graph 类型切换
	var kind_box = OptionButton.new()
	kind_box.add_item("Graph: Call", 0)
	kind_box.add_item("Graph: Signal", 1)
	kind_box.item_selected.connect(func(i): _graph_kind = i; _rebuild())
	toolbar.add_child(kind_box)
	# Re-layout
	var relayout = Button.new()
	relayout.text = "Re-layout"
	relayout.pressed.connect(_on_relayout)
	toolbar.add_child(relayout)
	# GraphEdit
	_graph_edit = GraphEdit.new()
	_graph_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_graph_edit.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_graph_edit)

func _on_data_changed(_arg = null) -> void:
	_rebuild()

func _rebuild() -> void:
	# 清空
	for c in _graph_edit.get_children():
		if c is GraphNode:
			c.queue_free()
	_graph_edit.clear_connections()
	# 按 Scope × Kind 分发
	if _scope == 1:
		# 项目级（调用图语义=文件耦合；信号图=跨文件信号）
		_project_view.build(_graph_edit, _bridge.get_project_result(), _graph_kind)
	else:
		if _graph_kind == 0:
			_call_view.build(_graph_edit, _bridge.get_current_result())
		else:
			_signal_view.build(_graph_edit, _bridge.get_current_result())

func _on_relayout() -> void:
	_graph_edit.arrange_nodes()  # Godot 4 GraphEdit 内置自动布局
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_graph_main_screen.gd
git commit -m "feat: GDSGraphMainScreen — main screen tab with Scope/Graph toggle + GraphEdit"
```

---

## Chunk C: 三个图视图 builder

### Task C1: GDSCallGraphView — 调用图

**Files:** Create: `addons/gdscript_util/editor/graphs/gds_call_graph_view.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/graphs/gds_call_graph_view.gd
# 调用图 builder — 函数为节点，调用为有向边，按 call_type 着色

class_name GDSCallGraphView
extends RefCounted

const COLORS := {
	0: Color.GREEN,          # SELF
	1: Color.DODGER_BLUE,    # SUPER
	2: Color.ORANGE,         # EXTERNAL
	4: Color.MEDIUM_PURPLE,  # SIGNAL_CONNECT
	7: Color.RED,            # EMIT
}

func build(p_graph: GraphEdit, p_result: GDScriptAnalysisResult) -> void:
	if p_result == null or p_result.call_graph == null:
		return
	# 节点：所有出现过的 caller/callee 各一个 GraphNode
	var nodes: Dictionary = {}  # name → GDSGraphNode
	var all_names: Dictionary = {}
	for edge in p_result.call_graph.edges:
		all_names[edge.caller] = true
		all_names[edge.callee] = true
	var col := 0
	var row := 0
	for name in all_names:
		if name == "" or name == "<class>":
			continue
		var node = GDSGraphNode.new()
		var deg = p_result.call_in_degree.get(name, 0) + p_result.call_out_degree.get(name, 0)
		node.configure("function", name, "in:%d out:%d" % [p_result.call_in_degree.get(name, 0), p_result.call_out_degree.get(name, 0)], deg)
		node.name = "fn_" + name
		node.position_offset = Vector2(col * 180, row * 90)
		p_graph.add_child(node)
		nodes[name] = node
		col += 1
		if col >= 5:
			col = 0
			row += 1
	# 边：每条 CallEdge 一条 connection
	for edge in p_result.call_graph.edges:
		var from_node = nodes.get(edge.caller)
		var to_node = nodes.get(edge.callee)
		if from_node == null or to_node == null:
			continue
		p_graph.connect_node(from_node.name, 0, to_node.name, 0)
```

> **注意：** `GraphEdit.connect_node(from_name, from_port, to_name, to_port)` — Godot 4.7 方法名实现时用 `mcp__godot__class-info GraphEdit` 确认（可能是 `connect_node` 或需经 `add_connection` 字典）。

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/graphs/gds_call_graph_view.gd
git commit -m "feat: GDSCallGraphView — function nodes + call edges, degree-labeled"
```

---

### Task C2: GDSSignalGraphView — 信号流

**Files:** Create: `addons/gdscript_util/editor/graphs/gds_signal_graph_view.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/graphs/gds_signal_graph_view.gd
# 信号流 builder — 信号为中心节点，emit(红)/connect(蓝) 为边

class_name GDSSignalGraphView
extends RefCounted

func build(p_graph: GraphEdit, p_result: GDScriptAnalysisResult) -> void:
	if p_result == null or p_result.signal_graph == null:
		return
	var nodes: Dictionary = {}
	var row := 0
	# 信号节点（居中一列）
	for sig_name in p_result.signal_graph.signals:
		var info = p_result.signal_graph.signals[sig_name]
		var node = GDSGraphNode.new()
		node.configure("signal", sig_name, "emits:%d conns:%d" % [info.emit_sites.size(), info.connect_sites.size()], info.emit_sites.size() + info.connect_sites.size())
		node.name = "sig_" + sig_name
		node.position_offset = Vector2(400, row * 100)
		p_graph.add_child(node)
		nodes[sig_name] = node
		row += 1
	# emit/connect 站点 → 函数节点 + 边
	for sig_name in p_result.signal_graph.signals:
		var info = p_result.signal_graph.signals[sig_name]
		var sig_node = nodes[sig_name]
		var i := 0
		for site in info.emit_sites:
			var fn = _ensure_fn_node(p_graph, nodes, site.enclosing_function, 100, i * 90)
			p_graph.connect_node(fn.name, 0, sig_node.name, 0)
			i += 1
		for site in info.connect_sites:
			var fn = _ensure_fn_node(p_graph, nodes, site.enclosing_function, 700, i * 90)
			p_graph.connect_node(fn.name, 0, sig_node.name, 0)
			i += 1

func _ensure_fn_node(p_graph: GraphEdit, p_nodes: Dictionary, p_name: String, p_x: int, p_y: int) -> GraphNode:
	if p_nodes.has(p_name):
		return p_nodes[p_name]
	var node = GDSGraphNode.new()
	node.configure("function", p_name, "", 0)
	node.name = "fn_" + p_name
	node.position_offset = Vector2(p_x, p_y)
	p_graph.add_child(node)
	p_nodes[p_name] = node
	return node
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/graphs/gds_signal_graph_view.gd
git commit -m "feat: GDSSignalGraphView — signal-centric nodes with emit/connect edges"
```

---

### Task C3: GDSProjectGraphView — 项目级图

**Files:** Create: `addons/gdscript_util/editor/graphs/gds_project_graph_view.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/graphs/gds_project_graph_view.gd
# 项目级图 builder — 文件/类为节点，CrossFileEdge 汇总为边（粗细按边数=耦合强度）

class_name GDSProjectGraphView
extends RefCounted

func build(p_graph: GraphEdit, p_project: GDScriptProjectResult, p_graph_kind: int) -> void:
	if p_project == null:
		return
	# 聚合: {(source_file, target_file) → edge_count}
	var pair_counts: Dictionary = {}
	for edge in p_project.cross_edges:
		var key = [edge.source_file, edge.target_file]
		pair_counts[key] = pair_counts.get(key, 0) + 1
	# 文件节点
	var nodes: Dictionary = {}
	var col := 0
	var row := 0
	for path in p_project.files:
		var short = path.get_file()
		var refs = p_project.get_files_referencing(path).size()
		var node = GDSGraphNode.new()
		node.configure("file", short, "refs:%d" % refs, refs)
		node.name = "file_" + path.get_file().get_basename()
		node.position_offset = Vector2(col * 200, row * 120)
		p_graph.add_child(node)
		nodes[path] = node
		col += 1
		if col >= 4:
			col = 0
			row += 1
	# 边
	for key in pair_counts:
		var src = key[0]
		var dst = key[1]
		var from_node = nodes.get(src)
		var to_node = nodes.get(dst)
		if from_node and to_node:
			p_graph.connect_node(from_node.name, 0, to_node.name, 0)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/graphs/gds_project_graph_view.gd
git commit -m "feat: GDSProjectGraphView — file nodes + cross-file edges weighted by pair count"
```

---

## Chunk D: 主屏集成

### Task D1: plugin.gd 加主屏 overrides

**Files:** Modify: `addons/gdscript_util/plugin.gd`

- [ ] **Step 1: 添加主屏必需的 EditorPlugin 方法**

在 plugin.gd 末尾追加（`_get_plugin_name`/`_has_main_screen`/`_make_visible`）：

```gdscript
# Phase 3.3: 主屏 tab
func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "Analysis"

func _make_visible(p_visible: bool) -> void:
	if _phase3_bootstrap:
		_phase3_bootstrap.set_main_screen_visible(p_visible)

func _get_plugin_icon() -> Texture2D:
	# 简单用内置图标，避免额外资源依赖
	return get_editor_interface().get_base_control().get_theme_icon("GDScript", "EditorIcons")
```

> **注意：** `_get_plugin_icon` 返回值若 `get_theme_icon` 找不到 "GDScript" 可能返回 null，可改为 `return null`（用默认）。实现时验证。

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/plugin.gd
git commit -m "feat: plugin.gd — main screen overrides (_has_main_screen/_make_visible/_get_plugin_name)"
```

---

### Task D2: bootstrap 注册主屏 + 转发 _make_visible

**Files:** Modify: `addons/gdscript_util/editor/gds_editor_bootstrap.gd`

- [ ] **Step 1: setup 中注册主屏 + teardown 移除**

```gdscript
var _graph_main_screen: GDSGraphMainScreen = null

# setup() 末尾（resource_saved.connect 之后）追加:
	_graph_main_screen = GDSGraphMainScreen.new()
	_graph_main_screen.setup(_bridge)
	# 主屏控件加到 EditorInterface.get_editor_main_screen()
	EditorInterface.get_editor_main_screen().add_child(_graph_main_screen)
	_graph_main_screen.visible = false  # 默认隐藏，切到 Analysis tab 才显示

# teardown() 追加:
	if _graph_main_screen and is_instance_valid(_graph_main_screen):
		_graph_main_screen.get_parent().remove_child(_graph_main_screen)
		_graph_main_screen.queue_free()

# 新增方法 — 供 plugin.gd 的 _make_visible 调用
func set_main_screen_visible(p_visible: bool) -> void:
	if _graph_main_screen and is_instance_valid(_graph_main_screen):
		_graph_main_screen.visible = p_visible
		if p_visible:
			_graph_main_screen._rebuild()
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_editor_bootstrap.gd
git commit -m "feat: bootstrap — register main screen, forward _make_visible, rebuild on show"
```

---

## Chunk E: 验收

### Task E1: 图构建验收测试

**Files:** Create: `tests/test_phase3_3_graph.gd`

- [ ] **Step 1: 创建测试**

```gdscript
# tests/test_phase3_3_graph.gd
# Phase 3.3 图构建验收 — 度数 + view builder 产出节点/边数
extends Node

func _ready():
	print("=== Phase 3.3 Graph Tests ===\n")
	test_degree()
	test_call_graph_view()
	test_project_graph_view()
	print("\n=== Done ===")

# 用 analysis_demo.gd 单文件
func analyze_demo() -> GDScriptAnalysisResult:
	var f = FileAccess.open("res://samples/analysis_demo.gd", FileAccess.READ)
	var source = f.get_as_text()
	f.close()
	var tokenizer = GDScriptTokenizer.new()
	var parser = GDScriptParser.new()
	var ast = parser.parse(tokenizer.tokenize(source))
	assert(parser.error == "", "Parse error: %s" % parser.error)
	return GDScriptSymbolResolver.new().resolve(ast, "res://samples/analysis_demo.gd")

func test_degree():
	print("Test: call degree...")
	var r = analyze_demo()
	# analysis_demo.gd: _ready 调 take_damage + connect; take_damage emit 2 信号
	# _ready 应有出度 >= 2; take_damage 应有入度 >= 1
	assert(r.call_out_degree.get("_ready", 0) >= 2, "_ready out-degree >= 2 expected, got %d" % r.call_out_degree.get("_ready", 0))
	assert(r.call_in_degree.get("take_damage", 0) >= 1, "take_damage in-degree >= 1 expected, got %d" % r.call_in_degree.get("take_damage", 0))
	print("  PASS")

func test_call_graph_view():
	print("Test: call graph view build...")
	var r = analyze_demo()
	var view = GDSCallGraphView.new()
	var ge = GraphEdit.new()
	add_child(ge)
	view.build(ge, r)
	var node_count := 0
	for c in ge.get_children():
		if c is GraphNode:
			node_count += 1
	assert(node_count > 0, "Expected >0 graph nodes, got %d" % node_count)
	ge.queue_free()
	print("  PASS (%d nodes)" % node_count)

func test_project_graph_view():
	print("Test: project graph view build...")
	var pa = GDScriptProjectAnalyzer.new()
	var proj = pa.analyze_full("res://samples/cross_file_demo")
	var view = GDSProjectGraphView.new()
	var ge = GraphEdit.new()
	add_child(ge)
	view.build(ge, proj, 0)
	var node_count := 0
	for c in ge.get_children():
		if c is GraphNode:
			node_count += 1
	assert(node_count >= 2, "Expected >=2 file nodes, got %d" % node_count)
	ge.queue_free()
	print("  PASS (%d nodes)" % node_count)
```

- [ ] **Step 2: 创建场景 + 运行**

创建 `tests/test_phase3_3_graph.tscn`（参考已有 .tscn），设为 main_scene 运行。

- [ ] **Step 3: 提交**

```bash
git add tests/test_phase3_3_graph.gd tests/test_phase3_3_graph.tscn
git commit -m "test: Phase 3.3 graph — degree + call/project view build acceptance"
```

---

### Task E2: 回归 + 主屏手动验收

- [ ] **Step 1: 运行 Phase 1/2/3v1/3.2 测试** — 确认全通过（度数字段为新增，不破坏旧测试）
- [ ] **Step 2: 运行 Phase 3.3 测试** — 3/3 通过
- [ ] **Step 3: 编辑器手动验收**
  - 重启插件 → 编辑器顶部出现 "Analysis" 主屏 tab
  - 切到 Analysis → 全屏 GraphEdit，显示当前文件调用图
  - 切 Scope=Project → 文件节点 + 跨文件边
  - 切 Graph=Signal → 信号中心节点 + emit/connect 边
  - "Re-layout" → arrange_nodes 重排
  - 拖节点 / 滚轮缩放正常
  - 枢纽函数（度数>=5）暖色高亮（需样例够大才明显）
- [ ] **Step 4: 提交**

```bash
git add -A
git commit -m "test: Phase 3.3 regression + main-screen graph acceptance pass"
```

---

## 完成检查清单

- [ ] `gds_analysis_result.gd` — call_in_degree / call_out_degree 字段
- [ ] `gds_symbol_resolver.gd` — `_add_call_edge` 累加度数
- [ ] `editor/graphs/gds_graph_node.gd` — 通用 GraphNode + 度数高亮
- [ ] `editor/gds_graph_main_screen.gd` — 主屏容器 + Scope/Graph 切换
- [ ] `editor/graphs/gds_call_graph_view.gd` — 调用图 builder
- [ ] `editor/graphs/gds_signal_graph_view.gd` — 信号流 builder
- [ ] `editor/graphs/gds_project_graph_view.gd` — 项目级 builder
- [ ] `plugin.gd` — `_has_main_screen`/`_make_visible`/`_get_plugin_name`
- [ ] `gds_editor_bootstrap.gd` — 注册主屏 + 转发
- [ ] Phase 1/2/3v1/3.2 回归全通过
- [ ] Phase 3.3 测试 3/3
- [ ] 主屏 Analysis tab 手动验收

## 已知限制（Phase 3.4）

- 节点跳转定义（点节点 → edit_script 跳行）未连线（留 3.4 完善）
- 大图（>200 节点）无虚拟化，可能卡顿（3.4）
- 边颜色按 call_type 在 builder 里规划但 GraphEdit 连线着色需主题 activity 颜色（3.4 精修）
- 度数含内置函数噪声（print/range，3.4 内置过滤后更准）
- 性能基准未测（ADR-0001：profile 后再决定是否优化/C#）
