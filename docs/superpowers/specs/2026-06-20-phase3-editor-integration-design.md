# Phase 3: 编辑器集成 + 完整语法 设计规范

> 日期: 2026-06-20 | 状态: Phase 3 v1 已完成 ✅ | 依赖: Phase 1 (已完成 ✅) + Phase 2 (已完成 ✅)

## 一、目标

将 Phase 1/2 的分析能力通过编辑器 UI 暴露，覆盖完整 GDScript 4.7 语法，达到实用级性能和错误容忍度。

## 二、参考项目

| 项目 | 关键模式 |
|------|---------|
| `E:\GitHub\clef-dev` | 程序化 UI 构建、信号中继桥、`_draw()` 可视化、ConfigFile 持久化、模式切换 |
| `E:\Godot\GodotProjects\project-juicy-godot` | 模块化启动、5 种容器附加、Tree 拓扑视图、变量监视器、定制绘制画布、数据驱动注册 |

## 三、架构

```
addons/gdscript_util/
├── [Phase 1+2] gds_tokenizer.gd, gds_parser.gd, gds_ast_nodes.gd
├── [Phase 1+2] gds_symbol_resolver.gd, gds_analysis_result.gd
├── [Phase 1+2] plugin.gd, plugin.cfg
├── [Phase 1+2] gds_symbol.gd ... gds_def_use_chain.gd (10 数据类)
│
├── editor/                              # [Phase 3 新增] UI 层
│   ├── gds_editor_bootstrap.gd          # 模块化启动（参考 FuseEditorBootstrap）
│   ├── gds_analysis_bridge.gd           # 信号中继桥（参考 clef_station_editor_bridge）
│   │
│   ├── panels/
│   │   ├── gds_analysis_main_panel.gd   # 底部主面板 — TabBar + 3 子面板
│   │   ├── gds_call_graph_panel.gd      # 调用图子面板
│   │   ├── gds_signal_flow_panel.gd     # 信号流子面板
│   │   ├── gds_def_use_panel.gd         # 变量读写子面板
│   │   └── gds_analysis_summary.gd      # Dock 摘要面板
│   │
│   ├── widgets/
│   │   ├── gds_call_graph_canvas.gd     # 调用图 _draw() 可视化
│   │   └── gds_signal_flow_canvas.gd    # 信号流 _draw() 可视化
│   │
│   └── dialogs/
│       ├── gds_find_references_dialog.gd # 查找引用弹窗
│       └── gds_export_report_dialog.gd   # 导出报告弹窗
│
├── [Phase 3 修改] gds_parser.gd         # 完整 4.7 语法
├── [Phase 3 修改] gds_tokenizer.gd      # NAMESPACE, TRAIT 关键字
└── [Phase 3 修改] gds_ast_nodes.gd      # 新 AST 节点类型
```

## 四、模块 1: 编辑器面板集成

### 4.1 容器布局

采用 **1 个 Bottom Panel（内含子 Tab）+ 1 Dock + Toolbar** 的克制方案：

```
┌─ Godot Editor ─────────────────────────────────────────────┐
│ [Toolbar] 🟢 GDScriptUtil: analyzed Player.gd               │
├────────────────────────────────────────────────────────────┤
│                       Viewport                              │
│                                                             │
├────────────────────────────────────────────────────────────┤
│ Bottom: ┌─ GDScript Analysis ────────────────────────────┐ │
│         │ [Call Graph] [Signal Flow] [Def-Use]           │ │
│         ├───────────────────────────────────────────────┤ │
│         │           (当前子 Tab 内容)                     │ │
│         └───────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────┘
```

| 容器 | 内容 | API |
|------|------|-----|
| Bottom Panel (1 个) | 含 3 个内部子 Tab 的主面板 | `add_control_to_bottom_panel(main_panel, "GDScript Analysis")` |
| Dock (右侧) | 分析摘要 + 错误 | `add_control_to_dock(DOCK_SLOT_RIGHT_BR, summary_panel)` |
| Toolbar | 状态指示器 | `add_control_to_container(CONTAINER_TOOLBAR, status_label)` |

### 4.2 主面板 TabBar 结构

`gds_analysis_main_panel.gd` — 使用 `TabBar` + 内容区切换，干净且不侵占底部栏：

```gdscript
class_name GDSAnalysisMainPanel
extends VBoxContainer

var _bridge: GDSAnalysisBridge
var _tab_bar: TabBar
var _content_stack: Control  # 当前子面板的容器 (VBoxContainer/MarginContainer)
var _call_graph_panel: GDSCallGraphPanel
var _signal_flow_panel: GDSSignalFlowPanel
var _def_use_panel: GDSDefUsePanel

func setup(bridge: GDSAnalysisBridge) -> void:
    _bridge = bridge
    _build_ui()
    _connect_bridge()

func _build_ui() -> void:
    # TabBar
    _tab_bar = TabBar.new()
    _tab_bar.add_tab("Call Graph")
    _tab_bar.add_tab("Signal Flow")
    _tab_bar.add_tab("Def-Use")
    _tab_bar.tab_changed.connect(_on_tab_changed)
    add_child(_tab_bar)

    # 内容区
    _content_stack = Control.new()
    _content_stack.size_flags_horizontal = SIZE_EXPAND_FILL
    _content_stack.size_flags_vertical = SIZE_EXPAND_FILL
    add_child(_content_stack)

    # 子面板
    _call_graph_panel = GDSCallGraphPanel.new()
    _call_graph_panel.setup(_bridge)
    _content_stack.add_child(_call_graph_panel)

    _signal_flow_panel = GDSSignalFlowPanel.new()
    _signal_flow_panel.setup(_bridge)
    _signal_flow_panel.visible = false
    _content_stack.add_child(_signal_flow_panel)

    _def_use_panel = GDSDefUsePanel.new()
    _def_use_panel.setup(_bridge)
    _def_use_panel.visible = false
    _content_stack.add_child(_def_use_panel)

func _on_tab_changed(tab: int) -> void:
    _call_graph_panel.visible = (tab == 0)
    _signal_flow_panel.visible = (tab == 1)
    _def_use_panel.visible = (tab == 2)
```

### 4.3 模块化启动（Bootstrap）

```gdscript
class_name GDSEditorBootstrap
extends RefCounted

func _register_panels() -> void:
    # 底部面板 — 1 个 Tab，内含 3 个子 Tab
    var main_panel = GDSAnalysisMainPanel.new()
    main_panel.setup(_bridge)
    _plugin.add_control_to_bottom_panel(main_panel, "GDScript Analysis")
    _panels.append(main_panel)

    # 右侧 Dock — 摘要
    var summary_panel = GDSAnalysisSummary.new()
    summary_panel.setup(_bridge)
    _plugin.add_control_to_dock(DOCK_SLOT_RIGHT_BR, summary_panel)
    _panels.append(summary_panel)
```

### 4.3 信号中继桥（Bridge）

`gds_analysis_bridge.gd` 解耦分析引擎和 UI 面板（参考 `clef_station_editor_bridge.gd`）：

```gdscript
class_name GDSAnalysisBridge
extends RefCounted

# 分析结果变更
signal analysis_started(file_path: String)
signal analysis_completed(result: GDScriptAnalysisResult)
signal analysis_failed(file_path: String, error: String)

# 选定项变更（面板间联动）
signal function_selected(func_name: String)
signal signal_selected(signal_name: String)
signal variable_selected(var_name: String)

var _current_result: GDScriptAnalysisResult
var _cache: Dictionary = {}  # String(path) → GDScriptAnalysisResult

func run_analysis(file_path: String) -> void:
    analysis_started.emit(file_path)
    # 调用 Phase 1+2 管道
    var result = GDScriptUtil.analyze_script(file_path)  # plugin.gd 中已有
    if result == null:
        analysis_failed.emit(file_path, "Parse error")
        return
    _current_result = result
    _cache[file_path] = result
    analysis_completed.emit(result)

func get_result(file_path: String = "") -> GDScriptAnalysisResult:
    if file_path == "":
        return _current_result
    return _cache.get(file_path, null)
```

### 4.4 面板联动

所有面板监听 Bridge 的相同信号，实现跨面板联动：

```
用户点击调用图中的 "take_damage"
  → Bridge.function_selected.emit("take_damage")
  → CallGraphPanel 高亮该项
  → DefUsePanel 过滤显示该函数内的变量读写
  → SignalFlowPanel 过滤显示该函数内的信号操作
  → ErrorPanel 过滤显示该函数相关的错误
```

## 五、模块 2: 调用图面板

### 5.1 布局

参考 `fuse_topology.gd` 的 Tree + 详情布局：

```
┌─ Call Graph ──────────────────────────────┐
│ [搜索: ________] [SELF] [SUPER] [EXT] ... │  ← 过滤按钮
├──────────────────┬─────────────────────────┤
│ Tree:            │ 详情:                   │
│  ├ _ready()      │ Caller: _ready()        │
│  │ ├→ _on_hp_chg │ Callee: _on_hp_changed  │
│  │ ├→ play_anim  │ Type: SIGNAL_CONNECT    │
│  ├ take_damage() │ Line: 42                │
│     ├→ emit("hp")│ Args: [hp]              │
│                  │ [Jump to Definition]     │
└──────────────────┴─────────────────────────┘
```

### 5.2 实现要点

- Tree 按 caller 分组，子项为 callee
- 颜色编码 call_type（绿色=SELF, 蓝色=SUPER, 橙色=EXTERNAL, 紫色=SIGNAL_CONNECT, 红色=EMIT）
- 搜索过滤：`LineEdit.text_changed` 实时过滤
- 详情面板：选中时展示 CallEdge 的所有字段
- "Jump to Definition" 按钮：用 `EditorInterface.edit_script()` 跳转到对应行

## 六、模块 3: 信号流面板

### 6.1 布局

```
┌─ Signal Flow ─────────────────────────────┐
│ [搜索: ________]                           │
├────────────────────────────────────────────┤
│ Tree:                                      │
│  ├ signal health_changed (line 5)          │
│  │  ├ EMIT: take_damage() @line 42         │
│  │  ├ EMIT: _on_timer() @line 55          │
│  │  └ CONNECT: _ready()→_on_health @line 8│
│  ├ signal died (line 6)                    │
│     ├ EMIT: _on_zero_hp() @line 68        │
│     └ CONNECT: obj.connect("died", cb)    │
└────────────────────────────────────────────┘
```

## 七、模块 4: 变量读写面板

### 7.1 布局

参考 `variable_watcher.gd` 的周期性刷新 + 彩色编码：

```
┌─ Def-Use ──────────────────────────────────┐
│ [搜索: ________] [Auto-refresh] [Export]    │
├──────────┬──────────┬───────────────────────┤
│ Variable │ Type     │ Sites                 │
├──────────┼──────────┼───────────────────────┤
│ hp       │ int      │ DEF:5  READ:42 WRITE:43│
│ amount   │ int      │ DEF:3  READ:42        │
│ health   │ float    │ DEF:10 READ:55,68,72  │
└──────────┴──────────┴───────────────────────┘
```

- 点击行展开详细 site 列表
- DEF = 绿色, READ = 蓝色, WRITE = 橙色, READ_WRITE = 红色
- 支持导出 JSON

### 4.5 参考 LimboAI 的可视化经验

LimboAI（成熟 BT 插件）验证了**Tree + 自定义绘制回调**对层次数据比 GraphEdit 更优。Phase 3 v1 采纳其核心模式：

| LimboAI 模式 | Phase 3 v1 采纳 |
|-------------|----------------|
| `set_metadata(col, obj)` 存节点对象引用 | ✅ 所有子面板用 metadata 存 CallEdge/Site/DefUseSite，避免文本反查 |
| `TreeSearch` 高亮系统（保留上下文，叠加高亮） | ✅ 新增 `gds_tree_search.gd`，搜索时高亮而非隐藏 |
| `SELECT_MULTI` + 右键上下文菜单 | ✅ CallGraphPanel 多选 + 右键（Jump to Def / Find Callers / Find Callees） |
| `set_custom_draw_callback` 画状态/频率条 | ⏳ **Phase 3.2 迭代**（v1 用 `set_custom_color` 够用） |
| Drag-drop 重排 | ❌ 不采纳（只读分析工具，YAGNI） |

**Phase 3.2 迭代项（v1 之后）：**
- 调用图热路径：`set_custom_draw_callback` 按调用频率画条形指示
- 信号流连接强度：连线粗细/颜色按 emit 次数

## 八、模块 5: 完整 4.7 语法覆盖

### 8.1 Tokenizer 新增

```gdscript
# gds_ast_nodes.gd — Token.Type 枚举新增
NAMESPACE,      # namespace 关键字
TRAIT,          # trait 关键字
TRAIT_EXTENDS,  # trait extends 关键字
IMPLEMENTS,     # implements 关键字
FORMAT_STRING,  # f"..."
STRING_NAME,    # &"..." StringName 字面量
```

### 8.2 Parser 新增节点

```gdscript
# gds_ast_nodes.gd — 新增 AST 节点
class NamespaceNode:
    extends ASTNode
    var name: String = ""
    var members: Array = []  # of ASTNode
    var trait_impls: Array = []  # of TypeNode

class TraitNode:
    extends ASTNode
    var name: String = ""
    var extends_traits: Array[TypeNode] = []
    var methods: Array = []  # of FunctionNode (抽象方法)
    var properties: Array = []  # of VariableNode

class GuardedMatchBranchNode:
    extends MatchBranchNode
    var guard = null  # ExpressionNode — when x > 0: 中的 x > 0

class FormattedStringNode:
    extends ASTNode
    var segments: Array = []  # of {text: String, expr: ExpressionNode|null}

class InlineSetterGetterNode:
    extends ASTNode
    var setter_body = null  # SuiteNode or ExpressionNode
    var getter_body = null
```

### 8.3 Remaining syntax features

| Feature | Implementation |
|---------|---------------|
| `Callable(obj, "method")` | Parser: special form in `_parse_atom()` |
| `is` pattern in `match` | Parser: `when` branch pattern support |
| `super()` call without method | Parser: bare `super()` |

## 九、模块 6: 性能优化

### 9.1 指标

| 指标 | Phase 2（现状） | Phase 3 目标 |
|------|----------------|-------------|
| 100 行解析 | ~5ms | <5ms |
| 1000 行解析 | ~80ms (估算) | <50ms |
| 文件修改时间戳缓存 | 无 | `ConfigFile` 持久化 |
| 惰性分析 | 无 | 按需 |

### 9.2 实现

```gdscript
# gds_analysis_bridge.gd — 缓存
var _timestamps: Dictionary = {}  # String(path) → int(mtime)

func should_reanalyze(path: String) -> bool:
    var file = FileAccess.open(path, FileAccess.READ)
    if file == null:
        return false
    var mtime = file.get_modified_time(path)  # Godot 4.x API
    if _timestamps.has(path) and _timestamps[path] == mtime:
        return false
    _timestamps[path] = mtime
    return true
```

## 十、模块 7: 错误恢复

### 10.1 目标

部分解析失败时继续，最大化覆盖。

### 10.2 实现

```gdscript
# gds_parser.gd — 错误恢复增强
func parse(p_tokens: Array) -> ClassNode:
    # 当前：第一个错误停止
    # Phase 3：记录所有错误，跳过损坏的成员继续
    while _peek() and _peek().type != TK_EOF:
        var member = _parse_class_member()
        if member != null:
            root.members.append(member)
        elif error_count > MAX_ERRORS:  # 新增：错误上限保护
            break
        else:
            _skip_to_next_valid_member()  # 新增：跳过损坏部分
```

## 十一、交付物

| 文件 | 类型 | 说明 |
|------|------|------|
| `editor/gds_editor_bootstrap.gd` | 新增 | 模块化启动 |
| `editor/gds_analysis_bridge.gd` | 新增 | 信号中继桥 |
| `editor/panels/gds_analysis_main_panel.gd` | 新增 | 底部主面板 — TabBar + 子面板 |
| `editor/panels/gds_call_graph_panel.gd` | 新增 | 调用图子面板 |
| `editor/panels/gds_signal_flow_panel.gd` | 新增 | 信号流子面板 |
| `editor/panels/gds_analysis_summary.gd      # Dock 摘要面板
| `editor/widgets/gds_call_graph_canvas.gd` | 新增 | 调用图可视化 |
| `editor/widgets/gds_signal_flow_canvas.gd` | 新增 | 信号流可视化 |
| `editor/dialogs/gds_find_references_dialog.gd` | 新增 | 查找引用 |
| `editor/dialogs/gds_export_report_dialog.gd` | 新增 | 导出报告 |
| `gds_ast_nodes.gd` | 修改 | 新 Token + AST 节点 |
| `gds_tokenizer.gd` | 修改 | namespace/trait/f-string |
| `gds_parser.gd` | 修改 | 完整语法 + 错误恢复 |
| `gds_symbol_resolver.gd` | 修改 | namespace/trait 符号分析 |
| `plugin.gd` | 修改 | Bootstrap 集成 |

## 十二、验收标准

- [x] 10/10 Phase 1 测试仍通过
- [x] 10/10 Phase 2 测试仍通过
- [x] 编辑器面板可正常打开/关闭（4 tab 整合为单底部面板，非 5 独立面板）
- [x] Bridge 信号联动：点击调用图项 → 其他面板联动过滤
- [x] 新语法解析测试：namespace/trait/f-string/guard/inline-setter（5/5 通过）
- [ ] 1000 行文件解析 < 50ms（**Phase 3.2** — 未做基准）
- [x] 错误恢复：包含语法错误的文件仍可部分分析（suite/inner_class 循环恢复）
- [x] 缓存命中：未修改文件不重新分析（时间戳缓存）

---

## 附录：Phase 3 v1 实现完成记录

**完成日期：** 2026-06-21
**关键提交：**
- `95f1e6f` docs: Phase 3 plan · `6a59fb4` docs: spec
- `9f5e66e`→`6fff1d4` Bridge / Bootstrap / 4 子面板
- `34dc94c`→`cb5c9cc` tokenizer + AST + parser（namespace/trait/f-string/guard/setter）
- `97803b2` Phase 3 语法测试 5/5
- `646364a` 编辑器保存死锁修复
- `e7a92ab` extends 前导换行修复
- `94789d5` 底部面板填满布局修复
**测试结果：** Phase 3 语法 5/5，编辑器面板手动验收通过

### 与规范的偏差（均在实现中修复）

| 项目 | 规范 | 实际 |
|------|------|------|
| 面板布局 | 3 底部 tab + 右侧 Dock 摘要 + Toolbar | **单底部面板 4 子 tab**（Summary 整合进来，去掉右侧 Dock——太侵入检查器） |
| 摘要面板位置 | 右侧 Dock | 底部面板第 1 子 tab |
| f-string AST | FormattedStringNode 解析 `{expr}` | **LiteralNode 暂存 segments**（Phase 3.2 升级） |
| 可视化方式 | spec 4.5 采纳 limboai Tree 模式 | 同规范（Tree + metadata + 多选 + 右键 + 搜索高亮） |
| Custom-draw 热路径 | Phase 3.2 延后 | 同规范（v1 用颜色编码） |

### 验收中发现并修复的 Bug（关键）

| Bug | 症状 | 根因 | 修复提交 |
|-----|------|------|---------|
| 编辑器保存锁死 | Ctrl+S 卡死 | `_parse_suite` 循环 `_parse_statement` 返回 null 不推进 → 无限自旋；且 `resource_saved` 双重连接 + 同步阻塞主线程 | `646364a`（suite/inner_class 循环恢复 + 移除双重连接 + deferred 分析） |
| extends 误判 | 真实文件报"extends 只能在文件顶部" | `parse()` 没跳过注释头产生的 leading NEWLINE | `e7a92ab` |
| 底部面板内容塌缩 | tab 可见区域利用度极低 | `_content_stack` 是 Control（不传尺寸给子节点），size_flags 只在 Container 内生效 | `94789d5`（Control→VBoxContainer） |
| guard 字段冲突 | GuardedMatchBranchNode 编译失败 | 重复声明 MatchBranchNode 已有的 guard | `2321128` |
| f-string 转义 | `\x00` invalid escape | Phase 3 重引入 Phase 1 已修的 bug | `2321128` |
| Bridge 依赖 | GDScriptUtil 未声明 | plugin.gd 无 class_name，Bridge 改直接跑 pipeline | `2321128` |
| 右侧 Dock 无标题/空白 | 摘要面板像未配置容器 | `add_control_to_dock` 用 .name 作标题未设；RichTextLabel 空时塌缩 | `9bc92f7`（后被整合进底部 tab） |

### 已知限制（Phase 3.2 处理）

- **f-string**：`{expr}` 未解析为表达式节点，仅存文本
- **热路径可视化**：调用频率/连接强度需 custom-draw（依赖 resolver 统计次数，当前无）
- **主屏图可视化**：GraphEdit/_draw 调用关系图未做
- **跨文件分析**：仅单文件，无项目级调用图
- **内置函数**：`print`/`range` 等仍记为调用边（前向引用修复的副作用）
- **1000 行性能基准**：未测量
