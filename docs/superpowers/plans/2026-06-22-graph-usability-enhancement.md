# 图可用性强化 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Phase 3.3 的图从"只有拓扑"提升到"信息可用"——边分类型着色、节点带签名/位置、emit/connect 可区分、入口函数标记、tooltip、筛选、点节点跳转。

**Architecture:** 改造现有 3 个 view builder + GDSGraphNode + GDSGraphMainScreen。节点信息靠 configure 扩参（数据 resolver 已有）。边分色靠信号图双 slot + 调用图节点级着色 + 图例。筛选/跳转加在主屏 toolbar。

**Tech Stack:** Godot 4.7, GDScript, GraphEdit, GraphNode

**Spec reference:** `docs/superpowers/specs/2026-06-22-graph-usability-enhancement.md`

---

## 文件结构

```
addons/gdscript_util/editor/
├── graphs/
│   ├── gds_graph_node.gd           # [修改] configure 扩参 + tooltip + 入口标记
│   ├── gds_call_graph_view.gd      # [修改] 签名/位置/着色/筛选
│   ├── gds_signal_graph_view.gd    # [修改] emit/connect 双 slot 分色分向
│   └── gds_project_graph_view.gd   # [修改] 签名/位置/筛选
├── gds_graph_main_screen.gd        # [修改] toolbar 阈值 + legend + node_selected 跳转
└── gds_entry_methods.gd            # [新增] 引擎入口方法集合
```

---

## Chunk P0: 高价值低成本

### Task P0-1: GDSGraphNode 扩展 — 签名/位置/tooltip/入口标记

**Files:** Modify: `addons/gdscript_util/editor/graphs/gds_graph_node.gd`

- [ ] **Step 1: 扩展 configure 签名**

```gdscript
# addons/gdscript_util/editor/graphs/gds_graph_node.gd
class_name GDSGraphNode
extends GraphNode

const ENTRY_METHODS := preload("res://addons/gdscript_util/editor/gds_entry_methods.gd")

# p_kind: "function" / "signal" / "file"
# p_signature: 函数 "(params) -> ret" 或信号 "(params)" 或文件摘要
# p_location: "@file:line" 或文件路径
func configure(p_kind: String, p_name: String, p_subtitle: String, p_degree: int, p_signature: String = "", p_location: String = "") -> void:
	title = p_name
	# 签名副文本
	if p_signature != "":
		var sig_label = Label.new()
		sig_label.text = p_signature
		sig_label.add_theme_font_size_override("font_size", 11)
		sig_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		add_child(sig_label)
	# 位置副文本
	if p_location != "":
		var loc_label = Label.new()
		loc_label.text = p_location
		loc_label.add_theme_font_size_override("font_size", 10)
		loc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		add_child(loc_label)
	# 度数副文本
	var label = Label.new()
	label.text = p_subtitle
	label.add_theme_font_size_override("font_size", 11)
	add_child(label)
	# tooltip — 完整信息
	tooltip_text = "%s\n%s\n%s\n%s" % [p_name, p_signature, p_location, p_subtitle]
	# 入口函数标记（绿色 title）
	if p_kind == "function" and ENTRY_METHODS.is_entry(p_name):
		add_theme_color_override("title_color", Color.LIME_GREEN)
	elif p_degree >= 5:
		# 枢纽高亮
		add_theme_color_override("title_color", Color.ORANGE_RED)
	custom_minimum_size = Vector2(140, 0)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/graphs/gds_graph_node.gd
git commit -m "feat: GDSGraphNode — signature/location/tooltip/entry-mark in configure"
```

---

### Task P0-2: 创建 GDS_EntryMethods — 引擎入口集合

**Files:** Create: `addons/gdscript_util/editor/gds_entry_methods.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/gds_entry_methods.gd
# 引擎虚拟/生命周期方法集合 — 图中标记执行入口

class_name GDS_EntryMethods
extends RefCounted

const METHODS := {
	# 生命周期
	"_ready": true,
	"_enter_tree": true,
	"_exit_tree": true,
	"_init": true,
	# 帧循环
	"_process": true,
	"_physics_process": true,
	# 输入
	"_input": true,
	"_unhandled_input": true,
	"_unhandled_key_input": true,
	"_shortcut_input": true,
	# 绘制
	"_draw": true,
	# 信号回调约定（常见命名）
	"_on": true,  # 前缀匹配，下面用 is_entry 单独处理
	# EditorPlugin 虚拟
	"_has_main_screen": true,
	"_make_visible": true,
	"_get_plugin_name": true,
	"_handles": true,
	"_edit": true,
	# Notification
	"_notification": true,
	# 资源/场景
	"_to_string": true,
	"_get": true,
	"_set": true,
}

static func is_entry(p_name: String) -> bool:
	if METHODS.has(p_name):
		return true
	# _on_ 前缀的信号回调也算入口（约定）
	return p_name.begins_with("_on_")
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_entry_methods.gd
git commit -m "feat: GDS_EntryMethods — engine virtual/lifecycle method set for entry marking"
```

---

### Task P0-3: 调用图视图 — 签名/位置/着色

**Files:** Modify: `addons/gdscript_util/editor/graphs/gds_call_graph_view.gd`

- [ ] **Step 1: build 时传签名/位置 + 节点级着色**

```gdscript
func build(p_graph: GraphEdit, p_result: GDScriptAnalysisResult) -> void:
	if p_result == null or p_result.call_graph == null:
		return
	# 收集所有函数名 + 从 symbol_table 取 FunctionNode（拿签名/行号）
	var func_nodes: Dictionary = {}  # name → FunctionNode
	if p_result.symbol_table != null:
		for sym_name in p_result.symbol_table.symbols:
			var sym = p_result.symbol_table.symbols[sym_name]
			if sym.kind == GDScriptSymbol.Kind.FUNCTION and sym.declaration != null:
				func_nodes[sym.declaration.name] = sym.declaration
	var all_names: Dictionary = {}
	for edge in p_result.call_graph.edges:
		all_names[edge.caller] = true
		all_names[edge.callee] = true
	# 节点
	var nodes: Dictionary = {}
	var col := 0
	var row := 0
	for name in all_names:
		if name == "" or name == "<class>":
			continue
		var deg = p_result.call_in_degree.get(name, 0) + p_result.call_out_degree.get(name, 0)
		var sig := ""
		var loc := ""
		if func_nodes.has(name):
			var fn = func_nodes[name]
			sig = _format_signature(fn)
			loc = "@%s:%d" % [p_result.file_path.get_file(), fn.line]
		var node = GDSGraphNode.new()
		node.configure("function", name, "in:%d out:%d" % [p_result.call_in_degree.get(name, 0), p_result.call_out_degree.get(name, 0)], deg, sig, loc)
		node.name = "fn_" + name
		node.position_offset = Vector2(col * 180, row * 90)
		p_graph.add_child(node)
		nodes[name] = node
		col += 1
		if col >= 5:
			col = 0
			row += 1
	# 边
	for edge in p_result.call_graph.edges:
		var from_node = nodes.get(edge.caller)
		var to_node = nodes.get(edge.callee)
		if from_node == null or to_node == null:
			continue
		p_graph.connect_node(from_node.name, 0, to_node.name, 0)

func _format_signature(p_fn) -> String:
	# 参数列表
	var params: Array = []
	for p in p_fn.params:
		var pname = p.name
		var ptype = ""
		if p.datatype != null and p.datatype.type_name != "":
			ptype = ": " + p.datatype.type_name
		params.append(pname + ptype)
	var ret = ""
	if p_fn.return_type != null and p_fn.return_type.type_name != "":
		ret = " -> " + p_fn.return_type.type_name
	return "(%s)%s" % [", ".join(params), ret]
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/graphs/gds_call_graph_view.gd
git commit -m "feat: call graph view — function signatures + location in nodes"
```

---

### Task P0-4: 信号图视图 — emit/connect 双 slot 分色分向

**Files:** Modify: `addons/gdscript_util/editor/graphs/gds_signal_graph_view.gd`

- [ ] **Step 1: 信号节点双 slot + emit/connect 分色边**

```gdscript
func build(p_graph: GraphEdit, p_result: GDScriptAnalysisResult) -> void:
	if p_result == null or p_result.signal_graph == null:
		return
	var nodes: Dictionary = {}
	var row := 0
	# 信号节点：左 slot=connect(蓝 type 0)，右 slot=emit(红 type 1)
	for sig_name in p_result.signal_graph.signals:
		var info = p_result.signal_graph.signals[sig_name]
		# 信号参数列表
		var params: Array = []
		for p in info.params:
			params.append(str(p))
		var sig_str = "(%s)" % [", ".join(params)] if not params.is_empty() else "()"
		var node = GDSGraphNode.new()
		node.configure("signal", sig_name, "emits:%d conns:%d" % [info.emit_sites.size(), info.connect_sites.size()], info.emit_sites.size() + info.connect_sites.size(), sig_str, "@%s" % p_result.file_path.get_file())
		node.name = "sig_" + sig_name
		node.position_offset = Vector2(500, row * 100)
		# 关键：双 slot — 左(connect,蓝)，右(emit,红)
		node.set_slot(0, true, 0, Color.DODGER_BLUE, true, 1, Color.RED)
		p_graph.add_child(node)
		nodes[sig_name] = node
		row += 1
	# emit 函数（左）→ 信号右 slot（红边）
	var i := 0
	for sig_name in p_result.signal_graph.signals:
		var info = p_result.signal_graph.signals[sig_name]
		var sig_node = nodes[sig_name]
		for site in info.emit_sites:
			var fn = _ensure_fn_node(p_graph, nodes, site.enclosing_function, 150, i * 90, p_result)
			# emit: fn 出 → 信号入。连到信号节点的"入"端。
			# GraphEdit 连线色 = from-port 色。fn 默认 slot 蓝；要让 emit 边红，需 fn 用红 slot。
			# 这里 fn 设红出 slot 模拟 emit 红边
			fn.set_slot(0, true, 0, Color.DODGER_BLUE, true, 1, Color.RED)
			p_graph.connect_node(fn.name, 0, sig_node.name, 0)
			i += 1
		for site in info.connect_sites:
			var fn = _ensure_fn_node(p_graph, nodes, site.enclosing_function, 850, i * 90, p_result)
			# connect: fn 蓝 slot
			fn.set_slot(0, true, 0, Color.DODGER_BLUE, true, 0, Color.DODGER_BLUE)
			p_graph.connect_node(fn.name, 0, sig_node.name, 0)
			i += 1

func _ensure_fn_node(p_graph: GraphEdit, p_nodes: Dictionary, p_name: String, p_x: int, p_y: int, p_result: GDScriptAnalysisResult) -> GraphNode:
	if p_name == "":
		p_name = "<class>"
	if p_nodes.has(p_name):
		return p_nodes[p_name]
	var node = GDSGraphNode.new()
	node.configure("function", p_name, "", 0, "", "@%s" % p_result.file_path.get_file())
	node.name = "fn_" + p_name
	node.position_offset = Vector2(p_x, p_y)
	p_graph.add_child(node)
	p_nodes[p_name] = node
	return node
```

> **注意：** GraphEdit 连线色 = from-node 的出 slot 色。emit 边要红 → emit 函数节点出 slot 设红；connect 边蓝 → connect 函数节点出 slot 蓝。信号节点的 slot 色不影响连线色（它是 to 端），但保留双 slot 做语义标注。

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/graphs/gds_signal_graph_view.gd
git commit -m "feat: signal graph view — emit(red)/connect(blue) edge coloring via from-node slots"
```

---

### Task P0-5: 项目图视图 — 签名/位置

**Files:** Modify: `addons/gdscript_util/editor/graphs/gds_project_graph_view.gd`

- [ ] **Step 1: 文件节点加规模摘要**

在 `_build_call_view` 和 `_build_signal_view` 的节点创建处，把 `configure` 副文本补上文件规模：

```gdscript
# _build_call_view 内，文件节点创建:
var short = path.get_file()
var refs = p_project.get_files_referencing(path).size()
var file_result = p_project.files[path]
var funcs_n = file_result.get_all_functions().size()
var sigs_n = file_result.get_all_signals().size()
var node = GDSGraphNode.new()
node.configure("file", short, "refs:%d | %d fn, %d sig" % [refs, funcs_n, sigs_n], refs, "", path)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/graphs/gds_project_graph_view.gd
git commit -m "feat: project graph view — file nodes show func/signal counts + path"
```

---

## Chunk P1: 中价值

### Task P1-1: 主屏 toolbar 加 legend（图例）

**Files:** Modify: `addons/gdscript_util/editor/gds_graph_main_screen.gd`

- [ ] **Step 1: _build_ui 加 legend 面板**

在 GraphEdit 之前插入一个常驻 legend：

```gdscript
	# 图例
	var legend = HBoxContainer.new()
	_add_legend_chip(legend, "■ emit", Color.RED)
	_add_legend_chip(legend, "■ connect", Color.DODGER_BLUE)
	_add_legend_chip(legend, "★ 入口", Color.LIME_GREEN)
	_add_legend_chip(legend, "▲ 枢纽", Color.ORANGE_RED)
	add_child(legend)

func _add_legend_chip(p_parent: Control, p_text: String, p_color: Color) -> void:
	var chip = Label.new()
	chip.text = p_text
	chip.add_theme_color_override("font_color", p_color)
	chip.add_theme_font_size_override("font_size", 11)
	p_parent.add_child(chip)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_graph_main_screen.gd
git commit -m "feat: graph main screen — persistent color legend"
```

---

### Task P1-2: 低度数筛选

**Files:** Modify: `addons/gdscript_util/editor/gds_graph_main_screen.gd` + 3 个 view

- [ ] **Step 1: toolbar 加阈值 SpinBox + 传给 view**

```gdscript
	# 主屏 _build_ui，toolbar 内:
	var thresh_label = Label.new()
	thresh_label.text = "Min degree:"
	toolbar.add_child(thresh_label)
	var thresh_box = SpinBox.new()
	thresh_box.min_value = 0
	thresh_box.max_value = 20
	thresh_box.value = 0
	thresh_box.value_changed.connect(func(_v): _rebuild())
	toolbar.add_child(thresh_box)
	# 存为成员变量 _min_degree
```

声明成员 `var _min_degree: int = 0`，SpinBox 改值时更新并 `_rebuild()`。view 的 build 增加阈值参数，跳过 degree < 阈值的节点。

- [ ] **Step 2: view build 接受阈值**

各 view 的 `build` 签名加 `p_min_degree: int = 0`，创建节点前判断 `if deg < p_min_degree: continue`（同步跳过连到它的边）。

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/editor/gds_graph_main_screen.gd addons/gdscript_util/editor/graphs/*.gd
git commit -m "feat: graph main screen — min-degree filter (hide low-degree nodes + their edges)"
```

---

### Task P1-3: 点节点跳转 + 关联边高亮

**Files:** Modify: `addons/gdscript_util/editor/gds_graph_main_screen.gd`

- [ ] **Step 1: 连接 node_selected + 跳转**

```gdscript
	# _build_ui，GraphEdit 创建后:
	_graph_edit.node_selected.connect(_on_node_selected)

func _on_node_selected(p_node: Node) -> void:
	if not (p_node is GDSGraphNode):
		return
	# metadata 在 configure 时存（需 view 创建节点时 set_meta）
	var meta = p_node.get_meta("jump", {})
	if meta.has("file") and meta.has("line") and meta["file"] != "":
		var script = load(meta["file"])
		if script != null:
			EditorInterface.edit_script(script, int(meta["line"]))
	# 关联高亮：淡化非关联节点
	_highlight_related(p_node)

func _highlight_related(p_selected: GraphNode) -> void:
	# 简化：选中节点 + 与它同名前缀相关的保持正常，其余淡化
	for c in _graph_edit.get_children():
		if c is GraphNode and c != p_selected:
			c.modulate.a = 0.3  # 淡化
	# 再选别的或重建时恢复（_rebuild 重建会重置 modulate）
```

> **注意：** view 创建节点时需 `node.set_meta("jump", {"file": ..., "line": ...})` 供跳转用。在各 view build 的节点创建处补上。

- [ ] **Step 2: 各 view 节点创建处 set_meta**

调用图/信号图 view 在 `node.configure(...)` 后加：
```gdscript
node.set_meta("jump", {"file": p_result.file_path, "line": fn.line if func_nodes.has(name) else 0})
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/editor/gds_graph_main_screen.gd addons/gdscript_util/editor/graphs/*.gd
git commit -m "feat: graph main screen — click node to jump to definition + dim unrelated"
```

---

## Chunk 验收

### Task V-1: 验收

- [ ] **Step 1: 4 组合手动验收**
  - 信号图：emit 边红、connect 边蓝
  - 调用图：函数节点显示签名 + `@file:line`
  - `_ready`/`_on_*` 绿色（入口标记）
  - 枢纽（度≥5）橙红
  - hover tooltip 显示完整信息
  - legend 常驻
  - Min degree 调高 → 低度数节点消失
  - 点节点 → 跳到定义行 + 其他淡化
- [ ] **Step 2: 回归** — Phase 1/2/3v1/3.2/3.3 测试全过
- [ ] **Step 3: 提交**

```bash
git add -A
git commit -m "test: graph usability enhancement acceptance pass"
```

---

## 完成检查清单

P0:
- [x] GDSGraphNode — configure 扩签名/位置/tooltip/入口标记（▶/● 前缀 + RichTextLabel 副文本）
- [x] GDS_EntryMethods — 入口方法集合
- [x] 调用图 — 签名 + 位置 + 度数
- [x] 信号图 — emit/connect 双 slot 分色（红/蓝/紫）
- [x] 项目图 — 文件规模摘要（彩色 ref/func/signal）

P1:
- [x] 主屏 — legend 图例（按视图动态刷新）
- [x] 主屏 — min-degree 筛选
- [x] 主屏 — 点节点跳转 + 关联淡化（node_deselected 恢复）

验收中额外完成：
- [x] 焦点跟随 Timer（500ms 轮询，双击/切 Tab 自动分析）
- [x] Tab 激活自动 arrange_nodes
- [x] 跨文件 emit 支持（resolver + analyzer）

## 已知限制

- 调用图 per-edge 着色受 GraphEdit 限制（连线色=from-port 色），用节点级 + 图例近似
- 关联边高亮用 modulate 淡化近似（无单边 API）
- 签名超长截断未做（先靠 tooltip）
- 函数枢纽阈值 5（小文件不会触发，正确行为）

## 验收中发现并修复的关键 Bug

| Bug | 根因 | 修复 |
|-----|------|------|
| `fn` 越界 | GDScript 块作用域（var 在 if 块内，块外引用） | 直接索引 `func_nodes[name]` |
| RichTextLabel 撑高 | `fit_content` + 默认 autowrap → 换行 | `AUTOWRAP_OFF` + 节点加宽 220px |
| title 绿色不生效 | GraphNode title 是内部 Label，非 GraphNode theme color | `get_titlebar_hbox()->child(0)->font_color` |
| 虚化不恢复 | `node_deselected` 未连 + 切选残留 | 连信号 + 恢复全部再虚化 |
| 项目信号图全蓝 | project view 忽略 kind | 按 kind 分支 call/signal |
