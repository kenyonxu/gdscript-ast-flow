# 大图虚拟化 设计规范

> 日期: 2026-06-22 | 状态: 已完成 ✅ | 依赖: Phase 3.3 图可视化

## 一、目标

当前 GraphEdit 一次性把所有节点加进去。分析 100+ 函数的文件或 200+ 文件的项目时，GraphEdit 塞几百节点 → 卡顿、布局乱、内存涨。

虚拟化 = 只渲染**视口可见**的节点（滚动/缩放时动态增删），让大图也流畅。

**核心问题：**
- 一个大文件 200 函数 → 200 GraphNode 全加 → 帧率掉
- 项目图 300 文件 → 同上
- 当前无任何虚拟化，小项目无感，大项目不可用

## 二、范围

### 做：

1. **视口裁剪** — 根据 GraphEdit 的滚动/缩放计算可见区域，只实例化区域内的 GraphNode
2. **动态增删** — 滚动时，移出视口的节点 queue_free，新进入的创建
3. **节点布局缓存** — 节点逻辑位置（含未渲染的）存在 Dictionary，渲染时按位置取
4. **缩放感知** — 缩小到一定程度时聚合（显示"区域含 N 个节点"占位节点），避免密集不可读
5. **节点上限保护** — 硬上限（如 500），超过提示切项目级聚合视图或筛选

### 不做：

- ❌ **边虚拟化** — GraphEdit 连线依赖两端节点存在；节点虚拟化后，跨视口的边难画。简化：只虚拟化节点，边在两端都可见时才连（跨视口边不画，接受信息损失）
- ❌ **物理引擎布局** — 力导向布局另算（布局质量是独立问题）
- ❌ **无限滚动** — 节点位置固定（缓存），不动态生成新节点

## 三、架构

```
addons/gdscript_util/editor/graphs/
├── gds_graph_main_screen.gd       # [修改] 滚动/缩放信号 → 触发虚拟化更新
├── gds_virtual_graph_edit.gd      # [新增] GraphEdit 子类，视口裁剪 + 动态增删
└── gds_graph_layout.gd            # [新增] 逻辑布局缓存（name → Vector2，含未渲染节点）
```

### 3.1 虚拟化数据流

```
view builder 产出:
  - 逻辑节点表: {name → (data, logical_pos)}
  - 逻辑边表: [(from_name, to_name), ...]
  ↓ 存入
GDSVirtualGraphEdit (布局缓存)
  ↓ 每帧/滚动时
视口裁剪: visible_rect = scroll + zoom * size
  ↓
只实例化 logical_pos ∈ visible_rect 的节点
  ↓ 两端都可见的边才 connect_node
```

### 3.2 GDSVirtualGraphEdit

```gdscript
class_name GDSVirtualGraphEdit
extends GraphEdit

var _logical_nodes: Dictionary = {}  # name → {data, pos}
var _logical_edges: Array = []       # [from_name, to_name]
var _rendered: Dictionary = {}       # name → GraphNode (当前已实例化)
var _dirty := true

func set_graph(p_nodes: Dictionary, p_edges: Array) -> void:
	_logical_nodes = p_nodes
	_logical_edges = p_edges
	for c in _rendered.values():
		c.queue_free()
	_rendered.clear()
	clear_connections()
	_dirty = true
	_update_viewport()

func _update_viewport() -> void:
	var vis_rect = _visible_rect()
	# 实例化进入视口的节点
	for name in _logical_nodes:
		if _rendered.has(name):
			continue
		var info = _logical_nodes[name]
		if vis_rect.has_point(info.pos):
			_instantiate(name)
		# 缩放小时未实例化的不创建（性能）
	# 移出视口的节点释放
	for name in _rendered.keys():
		var node = _rendered[name]
		if not vis_rect.has_point(node.position_offset):
			node.queue_free()
			_rendered.erase(name)
	# 两端都可见的边连接
	_connect_visible_edges()

func _visible_rect() -> Rect2:
	var zoom = get_zoom()
	var origin = get_scroll_offset() / zoom
	var size = get_viewport_rect().size / zoom
	# 留 margin 提前渲染
	return Rect2(origin - size * 0.2, size * 1.4)
```

### 3.3 滚动/缩放触发

GraphEdit 的 `scroll_offset_changed` + `zoom_changed` 信号 → `_update_viewport()`（节流，避免高频）。

### 3.4 缩放聚合

当 zoom < 阈值（如 0.3），密集区域用一个占位 GraphNode "区域: N 个节点" 替代，点击展开。降低视觉密度。

## 四、交付物

| 文件 | 类型 | 说明 |
|------|------|------|
| `editor/graphs/gds_virtual_graph_edit.gd` | 新增 | GraphEdit 子类，视口裁剪虚拟化 |
| `editor/graphs/gds_graph_layout.gd` | 新增 | 逻辑布局缓存 |
| `editor/gds_graph_main_screen.gd` | 修改 | 用 VirtualGraphEdit 替换 GraphEdit |
| 3 个 view | 修改 | 产出逻辑节点/边表（set_graph）而非直接 add_child |

## 五、验收标准

- [x] 100 节点图：初始只渲染可见区，滚动流畅
- [x] 滚出视口的节点释放，滚回重新创建
- [x] 内存稳定（不随滚动无限涨）
- [x] 缩小到阈值显示聚合占位
- [x] 小图（<50 节点）行为不变（全渲染）
- [x] 节点上限保护 >500 提示

## 六、风险

| 风险 | 缓解 |
|------|------|
| 跨视口边不画，信息损失 | 接受；或用占位"…"提示有边连出视口 |
| 虚拟化与 GraphEdit 内部布局/选择冲突 | 充分测试；必要时禁用 arrange_nodes（虚拟化下自动布局语义变了） |
| 缩放聚合实现复杂 | 可先不做聚合，只做基础视口裁剪（MVP） |
| ROI：当前项目规模用不上 | **按需**——小项目无感，只有真上大项目才值得做。优先级最低 |
| 滚动节流不当仍卡 | 用 Timer 节流（50ms） |

## 七、优先级说明

**这是优先级最低的增强。** 当前项目规模（demo + tests）节点数 <30，虚拟化无感知收益。只有当工具被用于真实大项目（100+ 函数文件 / 200+ 文件项目）且明显卡顿时才值得做。建议排在所有功能增强之后，或永久搁置（除非有真实痛点驱动）。
