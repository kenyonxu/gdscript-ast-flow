# Phase 3: 编辑器集成 + 完整语法 设计规范

> 日期: 2026-06-20 | 状态: 设计中 | 依赖: Phase 1 (已完成 ✅) + Phase 2 (已完成 ✅)

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

- [ ] 10/10 Phase 1 测试仍通过
- [ ] 10/10 Phase 2 测试仍通过
- [ ] 5 个编辑器面板可正常打开/关闭
- [ ] Bridge 信号联动：点击调用图项 → 其他面板联动过滤
- [ ] 新语法解析测试：namespace/trait/f-string/guard/inline-setter 各 1 个用例
- [ ] 1000 行文件解析 < 50ms
- [ ] 错误恢复：包含语法错误的文件仍可部分分析
- [ ] 缓存命中：未修改文件不重新分析
