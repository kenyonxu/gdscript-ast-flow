# Phase 3.3: 图可视化 设计规范

> 日期: 2026-06-21 | 状态: Phase 3.3 已完成 ✅ | 依赖: Phase 3 v1 + Phase 3.2 (已完成 ✅)

## 一、目标

把 Tree 数据升级为**节点-边图**——在编辑器主屏 tab 用 GraphEdit 渲染函数调用图与信号流图，单文件 + 项目级，可交互（点节点跳转、布局、缩放）。

**核心问题（Phase 3.2 无法直观回答）：**
- "这个文件的函数调用关系长什么样？"（Tree 看不出整体拓扑）
- "哪些函数是枢纽（被很多函数调用）？"（图里节点大/连线密一眼可见）
- "`health_changed` 信号怎么流的？"（emit → connect 的图路径）
- "项目里哪些类耦合最紧？"（跨文件图边密集区）

## 二、范围

### Phase 3.3 做：

1. **主屏 tab** — `_has_main_screen` 全屏图视图（与 2D/3D/Script 并列）
2. **调用图视图** — 函数为节点，调用为有向边，按 call_type 着色
3. **信号流视图** — 信号为节点，emit/connect 为边
4. **项目级图** — 跨文件节点 + 边（复用 Phase 3.2 CrossFileEdge）
5. **度数统计** — 入度/出度（resolver 增强，驱动节点大小/枢纽高亮）
6. **交互** — 点节点跳转定义、GraphEdit 原生缩放/拖拽/自动布局
7. **视图切换** — 单文件 / 项目 / 调用图 / 信号流 四象限

### Phase 3.3 不做（Phase 3.4 / 后续）：

- ❌ **热路径 custom-draw** — 需运行时调用频率数据（静态分析无），Phase 3.4 若引入 profiling
- ❌ **类型推断** — 独立关注点（让更多边可解析），Phase 3.4
- ❌ **性能基准 + 大图分批** — 1000 节点以上虚拟化，Phase 3.4
- ❌ **f-string `{expr}` 真解析** — 独立小项
- ❌ **图导出**（PNG/DOT）— YAGNI

## 三、为什么用 GraphEdit 而非 Tree/custom-draw

| 方案 | 适合 | 本项目适用性 |
|------|------|-------------|
| Tree（limboai 模式） | 严格层次（行为树） | 调用图是**一般有向图**（可有环、非树）→ 不适合 |
| GraphEdit | 一般有向图，节点+边，原生布局/缩放/拖拽 | ✅ 调用图/信号流天然契合 |
| custom `_draw()` | 完全自定义渲染 | 工作量大，GraphEdit 已够用 |

调用图允许环（A 调 B，B 调 A）和非树连接，GraphEdit 是正确选择。

## 四、架构

```
addons/gdscript_util/editor/
├── gds_editor_bootstrap.gd           # [修改] 注册主屏 tab
├── gds_graph_main_screen.gd          # [新增] 主屏 tab 容器（_has_main_screen）
├── graphs/                            # [新增]
│   ├── gds_call_graph_view.gd        # 调用图 GraphEdit 视图
│   ├── gds_signal_graph_view.gd      # 信号流 GraphEdit 视图
│   ├── gds_project_graph_view.gd     # 项目级跨文件图
│   └── gds_graph_node.gd             # 通用 GraphNode 子类（函数/信号/文件节点）
├── gds_analysis_bridge.gd            # [修改] 暴露当前文件 + 项目结果给图视图
└── panels/                            # [不变] 底部 4+1 tab 保留

addons/gdscript_util/
├── gds_symbol_resolver.gd            # [修改] 统计 call-site 度数
└── gds_analysis_result.gd            # [修改] 加 degree 表
```

### 4.1 数据流

```
Bridge（当前文件 AnalysisResult + 项目 ProjectResult）
   ↓ 提供
GDSGraphMainScreen（主屏 tab）
   ↓ 按视图模式分发
   ├─ CallGraphView   ← 读 call_graph.edges + degree
   ├─ SignalGraphView ← 读 signal_graph.signals
   └─ ProjectGraphView ← 读 project_result.cross_edges
   ↓ 构建
GraphEdit（GraphNode 节点 + graphConnect 边）
```

## 五、模块 1: 主屏 tab 集成

### 5.1 EditorPlugin 主屏

`GDSGraphMainScreen` 实现 `_has_main_screen()` 返回 true，`_make_visible(bool)` 控制显隐。Bootstrap 注册：

```gdscript
# bootstrap.gd setup:
_main_screen = GDSGraphMainScreen.new()
_main_screen.setup(_bridge)
_plugin.add_control_to_editor_main_screen(_main_screen)  # 或 get_editor_main_screen().add_child
# plugin.gd:
func _has_main_screen() -> bool: return true
func _make_visible(p_visible: bool): _phase3_bootstrap.set_main_screen_visible(p_visible)
func _get_plugin_name() -> String: return "Analysis"
func _get_plugin_icon() -> Texture2D: return preload(...)
```

### 5.2 主屏布局

```
┌─ Analysis (主屏 tab) ──────────────────────────────────────┐
│ [Scope: ○ Current File  ● Project]  [Graph: ● Call  ○ Signal]│
├─────────────────────────────────────────────────────────────┤
│                                                              │
│            GraphEdit（节点+边，可拖拽/缩放）                  │
│                                                              │
│   (take_damage) ──EMIT──▶ (health_changed) ◀─CONNECT── (_ready)│
│                                                              │
├─────────────────────────────────────────────────────────────┤
│ [Re-layout] [Filter: ________]  Selected: take_damage @line 9│
└─────────────────────────────────────────────────────────────┘
```

- 顶部：Scope（单文件/项目）+ Graph 类型（调用/信号）切换
- 中部：GraphEdit 画布
- 底部：重布局按钮 + 过滤 + 选中项详情

## 六、模块 2: 调用图视图

### 6.1 节点

每个**函数**一个 GraphNode：
- 标题：函数名
- 副文本：`@line N · in:X out:Y`（度数）
- 颜色：按 in+out 度数（枢纽函数高亮，如 >5 度数用暖色）
- metadata：存函数名 + 文件路径（供跳转）

### 6.2 边

每条 CallEdge 一条 `GraphEdit.graph_connect`：
- 颜色按 call_type：SELF 绿 / SUPER 蓝 / EXTERNAL 橙 / SIGNAL_CONNECT 紫 / EMIT 红
- 连线方向 caller → callee

### 6.3 度数驱动

- 节点 in-degree（被调次数）+ out-degree（调用次数）→ 决定节点视觉权重
- 枢纽函数（in >= 3 或 out >= 5）用更大尺寸 + 暖色边框，一眼识别"上帝函数"

## 七、模块 3: 信号流视图

### 7.1 节点

每个**信号**一个 GraphNode；可选把发射者/连接者函数也作节点。

### 7.2 边

- emit_site：函数 → 信号（红边，标 EMIT）
- connect_site：函数 → 信号（蓝边，标 CONNECT）

### 7.3 跨文件

复用 Phase 3.2 的 CrossFileEdge(SIGNAL_EMIT/SIGNAL_CONNECT)，节点标注来源文件。

## 八、模块 4: 项目级图

### 8.1 节点

每个**类/文件**一个 GraphNode（聚合层级，非单函数）。

### 8.2 边

CrossFileEdge 汇总：A 文件 → B 文件的边数 → 连线粗细按边数（耦合强度）。

### 8.3 耦合识别

连线最密的文件对 = 高耦合，粗线高亮。方便找"改这个文件会波及哪些"。

## 九、模块 5: 度数统计（resolver 增强）

### 9.1 数据

`GDScriptAnalysisResult` 加 degree 表：

```gdscript
var call_in_degree: Dictionary = {}   # String(func) → int（被调次数）
var call_out_degree: Dictionary = {}  # String(func) → int（调用次数）
```

resolver 在 `_add_call_edge` 时累加：`call_out_degree[caller] += 1`，`call_in_degree[callee] += 1`。

### 9.2 用途

- 节点大小/颜色（枢纽高亮）
- 过滤：只显示 in >= N 的函数（降噪大图）

## 十、交互

| 操作 | 行为 |
|------|------|
| 点节点 | 底部详情栏显示符号信息 + `EditorInterface.edit_script()` 跳转定义 |
| 双击节点 | 跳转到该函数定义行 |
| 拖节点 | GraphEdit 原生重排 |
| 滚轮 | 缩放（GraphEdit 原生） |
| Re-layout 按钮 | 调用 `GraphEdit` 内置 layout 或简单力导向 |
| Filter 输入 | 按函数名过滤节点显隐（参考 GDSTreeSearch 思路） |
| Scope 切换 | 单文件 ↔ 项目，重建图 |
| Graph 类型切换 | 调用图 ↔ 信号流，重建图 |

## 十一、交付物

| 文件 | 类型 | 说明 |
|------|------|------|
| `editor/gds_graph_main_screen.gd` | 新增 | 主屏 tab 容器 + Scope/Graph 切换 |
| `editor/graphs/gds_graph_node.gd` | 新增 | 通用 GraphNode（函数/信号/文件） |
| `editor/graphs/gds_call_graph_view.gd` | 新增 | 调用图 GraphEdit 构建 |
| `editor/graphs/gds_signal_graph_view.gd` | 新增 | 信号流 GraphEdit 构建 |
| `editor/graphs/gds_project_graph_view.gd` | 新增 | 项目级图构建 |
| `editor/gds_editor_bootstrap.gd` | 修改 | 注册主屏 tab + _make_visible 转发 |
| `plugin.gd` | 修改 | `_has_main_screen`/`_make_visible`/`_get_plugin_name` |
| `gds_symbol_resolver.gd` | 修改 | 度数统计 |
| `gds_analysis_result.gd` | 修改 | degree 表字段 |
| `tests/test_phase3_3_graph.gd` | 新增 | 图构建验收（节点数/边数/度数） |

## 十二、验收标准

- [x] Phase 1/2/3v1/3.2 回归全通过
- [x] 主屏出现 "Analysis" tab，可切换显隐
- [x] 单文件调用图：函数节点 + 调用边，按 call_type 着色
- [x] 单文件信号流图：信号节点 + emit/connect 边
- [x] 项目级图：文件节点 + 跨文件边（文件耦合）
- [x] 枢纽函数高亮（度数 >= 阈值，颜色标注）
- [ ] 点节点跳转定义（**Phase 3.4** — 未连线）
- [x] GraphEdit 缩放/拖拽/重布局正常
- [x] 度数统计正确（in/out degree）
- [x] Scope/Graph 切换工作（4 组合全通：File/Project × Call/Signal）

---

## 附录：Phase 3.3 实现完成记录

**完成日期：** 2026-06-22
**关键提交：**
- A1-A2 degree 字段 + resolver 累加
- B1-B2 GDSGraphNode + GDSGraphMainScreen
- C1-C3 三个 view builder（call/signal/project）
- D1-D2 plugin.gd 主屏 overrides + bootstrap 注册
- `2efd8cf` 主屏 VBoxContainer 修复
- `aaab62d` 主屏 EXPAND_FILL 修复
- `2e90a44` project view 按 kind 分支
**测试结果：** 度数/view 构建 3/3，主屏 4 组合手动验收通过

### 与规范的偏差（均在实现中修复）

| 项目 | 规范 | 实际 |
|------|------|------|
| 主屏容器基类 | `Control` | **`VBoxContainer`**——plain Control 不把尺寸传给 GraphEdit（同 Phase 3 教训） |
| 主屏铺满 | 隐含 | 需 `EXPAND_FILL` + `PRESET_FULL_RECT` 双设——编辑器主屏父级是 Container，忽略 anchors，只认 size_flags |
| Project+Signal 视图 | 复用 project view | 初版 project view 忽略 kind，永远画文件耦合 → 按 kind 分支（call=文件耦合 / signal=信号中心节点） |
| 点节点跳转 | spec 列为交互项 | 推迟 Phase 3.4 |

### 验收中发现并修复的 Bug

| Bug | 症状 | 根因 | 修复提交 |
|-----|------|------|---------|
| 主屏不渲染 | 切 Project 无内容 | `extends Control`，GraphEdit 塌缩 0 高度 | `2efd8cf`（Control→VBoxContainer） |
| 渲染只用 800×500 | 不铺满 | 主屏无 size_flags，编辑器主屏父级是 Container 只认 size_flags 不认 anchors | `aaab62d`（加 EXPAND_FILL） |
| Project+Signal 空/同 Call | 切 Signal 无变化 | project view 忽略 p_graph_kind | `2e90a44`（按 kind 分支 call/signal） |

### 关键经验（GDScript 编辑器主屏）

- **主屏容器必须 `extends Container`**（VBoxContainer），plain Control 不传尺寸给子节点
- **编辑器主屏父级是 Container**，按 `size_flags` 分配空间、**忽略子节点 anchors**——所以 `PRESET_FULL_RECT` 无效，必须给主屏自身设 `EXPAND_FILL`
- GraphEdit 兜底加 `custom_minimum_size`，避免布局未完成时 0 高度
- view builder 必须显式分支处理 kind，否则切换无效果

### 已知限制（Phase 3.4）

- 点节点跳转定义未实现
- 大图（>200 节点）无虚拟化
- 边颜色按 call_type 规划但 GraphEdit 连线着色需主题精修
- 度数含内置函数噪声（print/range）
- 性能基准未测（ADR-0001：profile 后再定）

## 十三、风险与边界

| 风险 | 缓解 |
|------|------|
| 大图（100+ 节点）卡顿 | 默认折叠低度数节点；Filter 降噪；>200 节点提示切项目级聚合视图 |
| GraphEdit 自动布局不美观 | 提供手动 Re-layout；初始用简单分层（caller 在上 callee 在下） |
| 环形调用导致布局混乱 | GraphEdit 原生容忍环；必要时按强连通分量聚合 |
| 主屏 tab 与 2D/3D 抢空间 | 这是预期行为（用户主动切到 Analysis tab 才占全屏） |
| 度数含内置函数噪声 | Phase 3.2 已知问题（print/range 记为边），Phase 3.3 度数同样含噪——接受，Phase 3.4 内置过滤 |

## 十四、与 Phase 3.4 的边界

Phase 3.3 产出**静态图可视化**。Phase 3.4 候选：
- 热路径（需运行时 profiling 注入）
- 类型推断（提升边覆盖率）
- 大图虚拟化/性能基准
- 内置函数过滤（清理度数噪声）
- f-string 真解析
