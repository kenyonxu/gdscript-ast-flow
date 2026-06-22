# 图可用性强化 设计规范

> 日期: 2026-06-22 | 状态: 已完成 ✅ | 依赖: Phase 3.3 图可视化 (已完成 ✅)

## 一、目标

Phase 3.3 的图只有**拓扑**，信息太薄——边全同色、节点只有名字。本规范把图从"能看"提升到"信息可用"：边分类型着色、节点带签名/位置、信号 emit/connect 可区分、入口函数可识别、可筛选、可跳转。

**用户视角要解决的问题：**
- "这条边是 emit 还是 connect？" —— 现在全蓝，分不出
- "`take_damage` 长什么样？" —— 看不到参数/返回类型
- "哪个是引擎入口？" —— `_ready`/`_process` 没标记
- "图太满" —— 低度数节点无法隐藏
- "点节点想跳过去看" —— 当前无反应

## 二、范围

### P0（高价值低成本，优先）

| # | 项 | 说明 |
|---|----|------|
| 1 | **边分类型着色** | 调用图按 call_type；信号图 emit(红)/connect(蓝) 可区分 |
| 2 | **节点带签名** | 函数：参数 + 返回类型；信号：参数列表 |
| 3 | **节点带位置** | 所属文件/类 + 定义行号 |
| 4 | **信号图 emit/connect 分向** | emit 边与 connect 边视觉区分（颜色 + 端口） |

### P1（中价值，P0 之后）

| # | 项 | 说明 |
|---|----|------|
| 5 | **入口函数标记** | `_ready`/`_process`/`_enter_tree` 等虚拟方法特殊色 |
| 6 | **hover tooltip** | 悬停显示完整签名 + 位置 |
| 7 | **低度数筛选** | toolbar 阈值滑条，隐藏 degree < N 的节点降噪 |
| 8 | **点节点跳转 + 关联边高亮** | 点节点跳定义；高亮其入/出边，淡化其余 |

### 不做（独立 spec / Phase 3.4+）

- ❌ 内置函数过滤（独立 spec）
- ❌ 类型推断（独立 spec）
- ❌ 大图虚拟化（独立 spec）
- ❌ 性能基准（ADR-0001）
- ❌ Def-Use 图（新视图，后续）

## 三、现状回顾（Phase 3.3 绘制内容）

| 元素 | 调用图 | 信号图 |
|------|--------|--------|
| 节点 title | 函数名 | 信号名 / 函数名 |
| 副文本 | `in:X out:Y` | 信号 `emits:X conns:Y`；函数 **空** |
| 边颜色 | ❌ 全默认 | ❌ emit/connect 同色同向 |
| 位置 | 死网格 | 信号居中、函数左右 |

## 四、模块详述

### 4.1 边分类型着色（#1）

**数据源：** CallEdge.call_type（SELF/SUPER/EXTERNAL/SIGNAL_CONNECT/EMIT）；CrossFileEdge.Kind。

**实现：** GraphEdit 连线颜色取自**端口 slot 颜色**（`set_slot` 的 color 参数）。利用这点：

- **信号图**：信号节点左 slot（connect 入，蓝）+ 右 slot（emit 入，红）。emit 边连到右 slot（红）、connect 边连到左 slot（蓝）→ **2 色清晰区分**。
- **调用图**：函数节点按主要 call_type 着色 slot（emit 重的节点偏红 slot）。**约束**：一个节点一个输出 slot，多类型边共享一色。诚实方案：调用图边着色用**节点 title 色**反映该函数的调用角色 + 加图例（legend）。

**约束说明：** GraphEdit 4.x 的 per-edge 着色能力有限（连线色 = from-port 色）。信号图靠双 slot 实现真分色；调用图用节点级着色 + 图例近似。若后续需精确 per-edge 色，需自定义 GraphEdit 子类 override 连线绘制（成本高，本规范不做）。

### 4.2 节点带签名（#2）

**数据源：** `FunctionNode.params`（ParameterNode[].name + datatype）+ `FunctionNode.return_type`；`SignalNode.params`。

**实现：** `GDSGraphNode.configure` 增加签名参数，副文本显示：
```
take_damage
(amount: int) -> void       ← 新增签名副文本
in:1 out:2
```
信号节点：
```
health_changed
(old_v: int, new_v: int)    ← 新增参数列表
emits:1 conns:1
```

### 4.3 节点带位置（#3）

**数据源：** `result.file_path`（文件）+ `FunctionNode.line` / `SignalNode.line`（行号）+ `classname_id`（类名）。

**实现：** configure 增加位置串，显示为第三行副文本：
```
take_damage
(amount: int) -> void
@Player.gd:9                ← 文件:行号
in:1 out:2
```

### 4.4 信号图 emit/connect 分向（#4）

**实现：** 与 #1 信号图双 slot 配合——
- emit 边：函数节点 → 信号节点**右 slot**（红）
- connect 边：函数节点 → 信号节点**左 slot**（蓝）
- 物理布局：emit 函数放信号左侧（流向→），connect 函数放右侧（←流向）

### 4.5 入口函数标记（#5，P1）

**数据源：** 维护 `ENTRY_METHODS` 集合：`_ready/_process/_physics_process/_enter_tree/_exit_tree/_input/_unhandled_input/_draw/_get_configuration_warnings` 等虚拟/生命周期方法。

**实现：** 节点 configure 时若名字在 ENTRY_METHODS，title 加前缀图标或用特殊色（如绿色边框）标"引擎入口"。一眼看出执行起点。

### 4.6 hover tooltip（#6，P1）

**实现：** GraphNode 有 `tooltip_text` 属性。设为完整信息串（签名 + 位置 + 度数 + 类型）。悬停显示。

### 4.7 低度数筛选（#7，P1）

**实现：** 主屏 toolbar 加 SpinBox（阈值，默认 0）。build 时跳过 `degree < 阈值` 的节点（及连到它们的边）。大图降噪。

### 4.8 点节点跳转 + 关联边高亮（#8，P1）

**实现：**
- 跳转：GraphEdit `node_selected` 信号 → 取节点 metadata（文件+行号）→ `EditorInterface.edit_script(load(file), line)`。
- 高亮：GraphEdit 无单连接高亮 API；近似用 `set` activity——选中节点时，把非关联节点的 modulate 调暗（alpha 降），关联节点正常。淡化其余突出选中子图。

## 五、通用图例（legend）

主屏加一个常驻 legend 面板（小 Label 列表），说明颜色含义：
```
■ emit (红)   ■ connect (蓝)   ■ SELF (绿)   ■ EXTERNAL (橙)
★ 入口函数   ▲ 枢纽(度≥5)
```
配合 #1/#5 的着色，让颜色可读。

## 六、交付物

| 文件 | 类型 | 说明 |
|------|------|------|
| `editor/graphs/gds_graph_node.gd` | 修改 | configure 加签名/位置/入口标记/tooltip |
| `editor/graphs/gds_call_graph_view.gd` | 修改 | 节点着色 + 签名/位置/入口 + 筛选 |
| `editor/graphs/gds_signal_graph_view.gd` | 修改 | emit/connect 双 slot 分色分向 |
| `editor/graphs/gds_project_graph_view.gd` | 修改 | 签名/位置 + 筛选 |
| `editor/gds_graph_main_screen.gd` | 修改 | toolbar 加阈值 SpinBox + legend 面板 + node_selected 跳转 |
| `gds_entry_methods.gd`（或常量） | 新增 | 引擎入口方法集合 |

## 七、验收标准

- [ ] 信号图 emit 边红、connect 边蓝，视觉可区分
- [ ] 调用图节点 title 色反映调用角色 + 图例说明
- [ ] 函数节点显示签名（参数+返回类型）
- [ ] 信号节点显示参数列表
- [x] 节点显示 `@文件:行号`
- [x] 入口函数（_ready 等）特殊标记
- [x] hover tooltip 显示完整信息
- [x] 阈值筛选：调高阈值，低度数节点隐藏
- [x] 点节点跳转到定义行
- [x] 图例常驻显示颜色含义（按视图动态刷新）

---

## 附录：实现完成记录

**完成日期：** 2026-06-22
**测试结果：** 全部手动验收通过

### 与规范的偏差（均在实现中修复）

| 项目 | 规范 | 实际 |
|------|------|------|
| 边着色机制 | 信号图双 slot + 调用图节点级 | 同规范；项目信号图加 emit(红)/connect(蓝)/both(紫) 分色 |
| 入口标记 | 特殊色 title | **▶ 前缀** + 绿色（title_color override 不存在，改设内部 Label font_color） |
| 文件副文本 | 无 | **彩色 BBcode**（ref 绿/functions 蓝/signals 红，RichTextLabel） |
| 图例 | 常驻 4 色 | **按视图动态刷新**（每个 Scope×Kind 只显真实颜色） |
| Tab 激活 | 无 | 自动 `arrange_nodes`（deferred） |
| 焦点跟随 | 无（仅 save 触发） | **500ms Timer** 轮询当前脚本，双击/切 Tab 自动分析 |

### 验收中发现并修复的 Bug

| Bug | 根因 | 修复 |
|-----|------|------|
| 节点 `fn` 越界 | GDScript 块作用域（var fn 在 if 块内） | 改直接索引 `func_nodes[name]` |
| RichTextLabel 撑高节点 | `fit_content` + autowrap 默认 → 文字换行撑高 | `autowrap_mode = OFF` + 节点加宽 220px |
| title 绿色不生效 | Godot 源码确认：GraphNode title 是内部 Label（`graph_node.cpp:1358`），不是 GraphNode theme color | `get_titlebar_hbox()->child(0)->font_color` |
| 节点虚化不恢复 | `node_deselected` 信号未连 + 切选时旧节点残留 | 连信号 + `_ready` 恢复全部再虚化 |
| 项目信号图全蓝 | project view 忽略 p_graph_kind | 按 kind 分支 call/signal |
| 跨文件 emit 无数据 | resolver 缺 `obj.signal.emit()`（base AttributeNode）分支 | 加对称分支 + analyzer EMIT 解析 |

### 关键经验（GraphEdit/GraphNode）

- **GraphNode title 是内部 Label**（theme type `GraphNodeTitleLabel`），不是 GraphNode 的 theme color 属性 → `get_titlebar_hbox()->child(0)` 设 `font_color`
- **GraphEdit 连线色 = from-node out-slot 色**，per-edge 着色只能通过 slot 实现
- **RichTextLabel `fit_content` 需关 autowrap**，否则窄宽度换行撑高
- **`add_theme_color_override` 在 add_child 前调用可能丢失** → `_ready()` 里应用更可靠
