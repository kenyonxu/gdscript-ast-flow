# 大图虚拟化 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> ⚠️ **优先级最低的增强**（spec §七明确说明）。当前项目节点数 <30，虚拟化无感知收益。仅当工具被用于真实大项目（100+ 函数 / 200+ 文件）且明显卡顿时才值得实施。

**Goal:** 100+ 节点的大图也不卡——视口裁剪：只渲染可见区域的 GraphNode，滚动/缩放时动态增删。小图（<50 节点）行为不变。

**Architecture:** 新增 `GDSVirtualGraphEdit`（GraphEdit 子类）替代主屏中的原生 `GraphEdit`。view builder 不再直接 `add_child`，而是产出逻辑节点/边表 → `set_graph(nodes, edges)` → VirtualGraphEdit 按视口可见性实例化。滚动节流 Timer + zoom 轮询触发 `_update_viewport`。

**Tech Stack:** Godot 4.7, GDScript, GraphEdit, Timer

**Spec reference:** `docs/superpowers/specs/2026-06-22-large-graph-virtualization.md`

---

## 文件结构

```
addons/gdscript_util/editor/graphs/
├── gds_virtual_graph_edit.gd    # [新增] GraphEdit 子类，视口裁剪 + 动态增删
├── gds_graph_layout.gd          # [新增] 逻辑布局缓存
├── gds_call_graph_view.gd       # [修改] build → build_logical + set_graph
├── gds_signal_graph_view.gd     # [修改] 同上
├── gds_project_graph_view.gd    # [修改] 同上
└── ../gds_graph_main_screen.gd  # [修改] 用 VirtualGraphEdit 替换 GraphEdit
```

---

## Chunk C0: 核心虚拟化

### Task C0-1: 创建 GDSGraphLayout — 逻辑布局缓存

**Files:** Create: `addons/gdscript_util/editor/graphs/gds_graph_layout.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/graphs/gds_graph_layout.gd
# 逻辑布局缓存 — 网格/双列排列，不依赖 GraphNode 实例

class_name GDSGraphLayout
extends RefCounted

static func assign_grid(p_nodes: Dictionary, p_cols := 5, p_cell: Vector2 = Vector2(200, 110)) -> void:
	var col := 0; var row := 0
	for name in p_nodes:
		p_nodes[name].pos = Vector2(col * p_cell.x, row * p_cell.y)
		col += 1
		if col >= p_cols:
			col = 0; row += 1

static func assign_two_column(p_left: Dictionary, p_center: Dictionary, p_right: Dictionary, p_cell: Vector2 = Vector2(200, 110)) -> void:
	var i := 0
	for name in p_left:
		p_left[name].pos = Vector2(150, i * p_cell.y); i += 1
	i = 0
	for name in p_center:
		p_center[name].pos = Vector2(500, i * p_cell.y); i += 1
	i = 0
	for name in p_right:
		p_right[name].pos = Vector2(850, i * p_cell.y); i += 1
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/graphs/gds_graph_layout.gd
git commit -m "feat: GDSGraphLayout — logical grid/two-column layout cache (no GraphNode needed)"
```

---

### Task C0-2: 创建 GDSVirtualGraphEdit — 视口裁剪

**Files:** Create: `addons/gdscript_util/editor/graphs/gds_virtual_graph_edit.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/graphs/gds_virtual_graph_edit.gd
# 虚拟化 GraphEdit — 只实例化视口可见的节点，滚动/缩放动态增删

class_name GDSVirtualGraphEdit
extends GraphEdit

const MAX_NODES := 500
const MARGIN_RATIO := 0.2

var _logical_nodes: Dictionary = {}
var _logical_edges: Array = []
var _rendered: Dictionary = {}
var _dirty := true
var _throttle_timer: Timer = null

func _init() -> void:
	_throttle_timer = Timer.new()
	_throttle_timer.wait_time = 0.05
	_throttle_timer.one_shot = true
	_throttle_timer.timeout.connect(_update_viewport)
	add_child(_throttle_timer)
	scroll_offset_changed.connect(_on_view_changed)
	# zoom 无直接信号，用 _process 轮询

func set_graph(p_nodes: Dictionary, p_edges: Array) -> void:
	for c in _rendered.values():
		c.queue_free()
	_rendered.clear()
	clear_connections()
	_logical_nodes = p_nodes
	_logical_edges = p_edges
	_dirty = true
	_update_viewport()

func _on_view_changed() -> void:
	_throttle_timer.start()

func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_update_viewport()

func _update_viewport() -> void:
	var vis = _visible_rect()
	for name in _logical_nodes:
		if _rendered.has(name):
			continue
		var info = _logical_nodes[name]
		if vis.has_point(info.pos):
			_instantiate(name)
	for name in _rendered.keys():
		var node = _rendered[name]
		if not vis.has_point(node.position_offset):
			node.queue_free()
			_rendered.erase(name)
	_connect_visible()

func _visible_rect() -> Rect2:
	var z = zoom
	var origin = scroll_offset / z
	var size = get_viewport_rect().size / z
	return Rect2(origin - size * MARGIN_RATIO, size * (1.0 + MARGIN_RATIO * 2))

func _instantiate(p_name: String) -> void:
	var info = _logical_nodes[p_name]
	var gn = GDSGraphNode.new()
	gn.configure(info.kind, info.title, info.subtitle, info.degree, info.get("signature", ""), info.get("location", ""))
	gn.name = info.node_name
	gn.position_offset = info.pos
	if not info.jump.file.is_empty():
		gn.set_meta("jump", info.jump)
	add_child(gn)
	_rendered[p_name] = gn

func _connect_visible() -> void:
	for edge in _logical_edges:
		if _rendered.has(edge[0]) and _rendered.has(edge[1]):
			if not is_node_connected(edge[0], 0, edge[1], 0):
				connect_node(edge[0], 0, edge[1], 0)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/graphs/gds_virtual_graph_edit.gd
git commit -m "feat: GDSVirtualGraphEdit — viewport-clipped GraphEdit with dynamic node lifecycle"
```

---

### Task C0-3: 三个 view 产出逻辑表

**Files:** Modify: `gds_call_graph_view.gd`, `gds_signal_graph_view.gd`, `gds_project_graph_view.gd`

每个 view 新增 `build_logical()` 方法，返回 `Dictionary{name→{pos,kind,title,...}}` + `Array[[from,to]]`。

- [ ] **Step 1: 调用图 view 加 build_logical**

```gdscript
func build_logical(p_result: GDScriptAnalysisResult, p_min_degree: int = 0) -> Dictionary:
	var nodes: Dictionary = {}
	var edges: Array = []
	# ... 同 build 逻辑，但不 add_child/connect_node，改为填充 nodes/edges ...
	return {"nodes": nodes, "edges": edges}
```

- [ ] **Step 2: 信号图 / 项目图同理**

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/editor/graphs/gds_call_graph_view.gd addons/gdscript_util/editor/graphs/gds_signal_graph_view.gd addons/gdscript_util/editor/graphs/gds_project_graph_view.gd
git commit -m "feat: views — add build_logical() to produce flat node/edge tables for virtualization"
```

---

### Task C0-4: 主屏切换 VirtualGraphEdit

**Files:** Modify: `addons/gdscript_util/editor/gds_graph_main_screen.gd`

- [ ] **Step 1: 替换 GraphEdit 类型 + _rebuild 走 set_graph**

```gdscript
var _graph_edit: GDSVirtualGraphEdit = null  # 换类型

func _build_ui() -> void:
	_graph_edit = GDSVirtualGraphEdit.new()  # 替换 GraphEdit.new()
	# ... 其余不变 ...

func _rebuild() -> void:
	# 调 build_logical → set_graph 而非 build
	var logical = _call_view.build_logical(result, _min_degree)
	_graph_edit.set_graph(logical.nodes, logical.edges)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_graph_main_screen.gd
git commit -m "feat: main screen — switch to GDSVirtualGraphEdit with set_graph pipeline"
```

---

## Chunk V: 验收

### Task V-1: 冒烟测试 + 手动验证

- [ ] **Step 1: 创建 200 节点冒烟测试**

```gdscript
func test_virtualization_smoke():
	var ge = GDSVirtualGraphEdit.new()
	add_child(ge)
	var nodes: Dictionary = {}
	for i in 200:
		nodes["fn_n%d" % i] = {
			"pos": Vector2((i % 5) * 200, int(i / 5) * 110),
			"kind": "function", "title": "n%d" % i, "node_name": "fn_n%d" % i,
			"subtitle": "", "degree": 0, "signature": "", "location": "",
			"jump": {"file": "", "line": 0},
		}
	var edges: Array = []
	for i in 199:
		edges.append(["fn_n%d" % i, "fn_n%d" % (i + 1)])
	ge.set_graph(nodes, edges)
	assert(ge._rendered.size() <= nodes.size(), "virtualization should clip")
	ge.queue_free()
```

- [ ] **Step 2: 手动验证**
  - 30+ 函数文件: 节点正常显示
  - 缩小 zoom: 流畅无掉帧
  - 滚动: 移出视口节点释放
  - 滚回: 节点重建
  - 连线: 两端可见才显示

- [ ] **Step 3: 提交**

```bash
git add -A
git commit -m "test: graph virtualization smoke (200-node clip + scroll recycle)"
```

---

## 验收标准

- [ ] 100+ 节点图: 初始只渲染可见区，滚动流畅
- [ ] 滚出视口节点释放，滚回重建
- [ ] 内存稳定
- [ ] 小图（<50 节点）行为不变（全渲染）
- [ ] 节点上限 >500 提示

---

## 完成检查清单

- [ ] GDSGraphLayout — `assign_grid` / `assign_two_column`
- [ ] GDSVirtualGraphEdit — `set_graph` / `_update_viewport` / `_visible_rect` / `_instantiate`
- [ ] GDSVirtualGraphEdit — scroll 节流 Timer + zoom 轮询
- [ ] call/signal/project 三 view — `build_logical()` 产出扁平 config
- [ ] main screen — `_graph_edit` 换类型 + `_rebuild` 走 `set_graph`

## 已知限制

- **跨视口边不画**: 连线依赖两端节点存在，跨视口信息损失。spec 已接受此取舍
- **聚合占位未完整**: 缩放聚合 TODO，spec 风险表列为可选项
- **ROI 极低**: 当前节点数 <30，建议真实大项目卡顿前不实施
