# 场景可视化主屏模式 设计规范

> 日期: 2026-06-25 | 状态: 设计中 | 依赖: tscn/tres 解析器 (已完成 ✅)、CodeGraph JSON v2 (已完成 ✅)、主屏 GDSGraphMainScreen (已完成 ✅)

## 修订历史

| 日期 | 变更 |
|------|------|
| 2026-06-25 | 初版（brainstorming 产出，方案 A 视角切换）|

## 一、动机

### 1.1 现状

tscn/tres 解析器（P0）已把场景/资源解析为结构化数据（`GDSSceneResourceResult`），并通过 CodeGraph JSON v2 输出 `scenes` / `resources` / `script_associations` / `scene_signal_connections`。但这层数据只对 AI 消费者友好（JSON），**人类开发者无可视化入口**——底部面板和主屏都只有代码分析视图。

### 1.2 目标

为场景/资源数据提供**主屏级可视化**——在主屏 tab 加「场景」mode，与现有「代码分析」并列。让开发者能回答：

- 这个场景的节点树结构长啥样？哪些节点挂了脚本？
- `Player.gd` 被哪些场景的哪些节点使用？（跨场景反查）
- 信号从哪个节点连到哪个节点的哪个方法？（含跨场景）

### 1.3 核心价值

将插件从"代码分析"升级为"代码 + 场景结构"分析。**跨场景关系**（哪些场景用了某脚本、信号跨场景连接）是 Godot 自带编辑器做不到的，是插件差异化护城河。数据层 P0 已就绪，本 spec 补齐消费层（可视化）。

## 二、范围

### MVP

| # | 项 | 说明 |
|---|----|------|
| 1 | 主屏 mode 切换 | `[代码分析 \| 场景]`，代码分析 mode 不动 |
| 2 | `GDSSceneMainScreen` 容器 | 视角 toolbar + 主体容器 + 联动导航 |
| 3 | 节点树视角 | 场景列表 + Tree + 节点详情侧栏 |
| 4 | 脚本反查视角 | 脚本聚合列表 + 跨场景挂载点 |
| 5 | 信号图视角 | GraphEdit，同/跨场景信号边着色 |
| 6 | 视角间联动 | 反查/信号图点击 → 跳节点树视角定位 |
| 7 | 跳转脚本编辑器 | 节点详情点 script_resource 跳转 |
| 8 | 空状态/错误处理 | 无场景/扫描关/解析失败的提示 |

### 后续迭代（非 MVP）

- 过滤（节点类型 / 名称 / 信号名）
- `@export` 填充值显示（依赖 tscn P1 #9）
- 子资源属性展开
- 嵌套场景实例化展开（tscn P2 #15）
- 信号图节点级 / 场景级粒度切换

### 不做（明确边界）

- 场景文件编辑 / 写回（**只读**）
- 运行时场景实例化（静态分析）
- 自定义节点类型深度解析（用 `type` 字符串透传）

## 三、架构设计

### 3.1 主屏接入（关键约束）

**不新增 Godot 主屏 tab**——Godot 限制一个插件只能注册一个主屏 tab。在现有 `GDSGraphMainScreen` 顶部加 mode 切换：

- **代码分析 mode** = 现有 Scope×Graph 下拉矩阵（完全不动）
- **场景 mode** = `GDSSceneMainScreen`（新组件）

视觉效果上「场景」与 current file/project 一样是主屏内的并列选项，只是技术上是 mode 而非独立 Godot tab。

### 3.2 组件分解

```
GDSGraphMainScreen  (改：顶部加 mode 切换 + 按模式显隐主体)
 └─ mode=场景时:
    GDSSceneMainScreen  (新 · 容器)
     ├─ toolbar: 视角切换 [节点树 / 脚本反查 / 信号图]
     ├─ SceneNodeTreeView       (新) — 节点树视角
     ├─ SceneScriptLookupView   (新) — 脚本反查视角
     └─ SceneSignalGraphView    (新) — 信号图视角
        └─ 复用 GDSGraphNode / GDSGraphLayout / GDSVirtualGraphEdit
```

### 3.3 不改动

- `GDSEditorBootstrap`：场景模式寄生在主屏内部，主屏注册不变，bootstrap 无需改
- 数据层：复用 P0 的 `scenes` / `script_associations` / `scene_signal_connections`，不新增解析

## 四、视角 UI 细节

### 4.1 节点树视角（SceneNodeTreeView）

布局：`[场景列表 | 节点树 Tree | 节点详情]`

- **场景列表**：所有 `.tscn` 文件，点击切换当前场景
- **Tree**：当前场景节点树（按 `root_nodes` → `children` 递归），挂脚本节点带 📜 标
- **节点详情**：`name` / `type` / `parent_path` / `groups` / `script_resource` / 该节点参与的信号连接
- **交互**：点 `script_resource` → 跳脚本编辑器；点节点 → 显详情；树可展开/折叠

### 4.2 脚本反查视角（SceneScriptLookupView）

布局：`[脚本聚合列表 | 挂载点列表]`

- **脚本列表**：所有被场景引用的 `.gd`，按挂载数降序（如 `player.gd (5)`）
- **挂载点**：选中脚本的跨场景挂载详情（`scene / node_path / node_name`）
- **交互**：点脚本 → 显挂载；点挂载条目 → 跳「节点树视角」并定位该场景该节点（联动）

### 4.3 信号图视角（SceneSignalGraphView）

布局：`[GraphEdit 全屏 + 顶部过滤]`

- **节点**：参与信号的节点（from/to），标签 `scene/node`
- **边**：信号连接，标签 `signal_name`
- **着色**：同场景边蓝、跨场景边橙
- **数据**：合并 `scene_signal_connections`（跨场景）+ 各 `scene.signal_connections`（场景内）
- **交互**：点节点 → 跳节点树视角；顶部按信号名/场景过滤

### 4.4 视角联动（亮点）

`GDSSceneMainScreen` 提供 `navigate_to_node(scene_path, node_path)` 方法：
- 切到节点树视角
- 选中目标场景 + 目标节点（Tree 滚动定位）

反查视角、信号图视角点击节点时调用。3 视角围绕「场景/节点/脚本」互相导航，不是孤岛。

## 五、数据流

### 5.1 数据源

`bridge.get_project_result()`（**不重新解析**，P0 已就绪）：
- `.scenes[path]` → `GDSSceneResourceResult`（`root_nodes` / `nodes_flat` / `signal_connections` / `ext_resources` / `script_associations`）
- `.script_associations` → 平铺数组 `[{scene, node, script, script_class}]`
- `.scene_signal_connections` → 跨场景信号边 `[{signal, from_scene, from_node, to_scene, to_node, to_method}]`

### 5.2 反查聚合（视图层）

`SceneScriptLookupView._build_index()`：遍历 `script_associations`，聚合 `{script_path → [{scene, node}]}`。每次 rebuild 重建。数据量小，O(n) 聚合，**不污染数据层**（不往 ProjectResult 加预计算索引）。

### 5.3 rebuild 触发

`bridge.project_analysis_completed` → `GDSSceneMainScreen._on_data_changed` → **仅 rebuild 当前活跃视角**（惰性；切回非活跃视角时再 rebuild，避免无用功）。mode 切换 / 视角切换不重新解析数据。

## 六、错误处理

| 情况 | 处理 |
|------|------|
| 无 `.tscn`/`.tres`（纯 .gd 项目） | 空状态提示「未扫描到场景文件，检查 Scan Settings」 |
| 项目扫描关闭（`GDSScanConfig.is_enabled() == false`） | 提示「项目扫描未开启」 |
| 单场景解析失败（`result.errors` 非空） | 场景列表该条目标红 + 悬停显错误 |
| 跳转脚本指向不存在的 `.gd` | 禁用跳转按钮 |
| 大场景（节点数千+） | Tree 惰性展开；信号图复用 `GDSVirtualGraphEdit` 虚拟化 |

## 七、测试策略

- **数据层**：复用 `test_tscn_tres_parser.gd`（8 套，解析已覆盖）
- **新增视图层**（headless 跑 build 逻辑）：
  - 反查聚合正确性（`script → 挂载点列表`）
  - 信号图节点/边构建（同/跨场景着色）
  - 空状态 / 扫描关闭 / 解析失败的显示分支
- **联动跳转 + UI 渲染**：手动验收（Godot 里开场景模式点一遍）
- **MVP 验收基准**：3 视角正确显示 `test_scene_full.tscn` fixture 数据 + 反查↔节点树联动工作

## 八、验收标准（MVP）

- [ ] 主屏 `[代码分析 | 场景]` mode 切换工作，代码分析 mode 不受影响
- [ ] 节点树视角正确显示 `test_scene_full.tscn` 节点树（含两个重名 `Icon` 节点）
- [ ] 节点详情显示 `script_resource`，点击跳转脚本编辑器
- [ ] 脚本反查视角聚合正确（`player.gd` 挂载点列表跨场景）
- [ ] 反查点挂载条目 → 跳节点树视角定位正确节点
- [ ] 信号图视角显示 fixture 的信号连接（同/跨场景边着色正确）
- [ ] 信号图点节点 → 跳节点树视角
- [ ] 无场景文件时显空状态提示
- [ ] 项目扫描关闭时显提示
- [ ] 解析失败的场景条目标红

## 九、风险

| 风险 | 级别 | 缓解 |
|------|------|------|
| Tree 大场景性能 | 中 | Godot Tree 默认惰性展开；先不引入异步 |
| 信号图节点爆炸（多场景多信号） | 中 | 复用 `GDSVirtualGraphEdit` 虚拟化；默认只画参与信号的节点 |
| 视角联动状态管理复杂 | 低 | `GDSSceneMainScreen` 集中管理 `navigate_to_node`，视角间不直接耦合 |
| mode 切换破坏现有代码分析视图 | 低 | `mode=代码分析` 时不实例化场景组件，两 mode 隔离 |
| 反查聚合与 script_associations 漂移 | 低 | 每次 rebuild 重建索引，无缓存一致性问题 |
