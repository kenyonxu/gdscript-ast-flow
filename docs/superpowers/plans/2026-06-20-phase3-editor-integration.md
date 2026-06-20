# Phase 3: 编辑器集成 + 完整语法 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Phase 1/2 的分析能力通过编辑器 UI 暴露（1 个底部面板 + 3 子 Tab + Dock），覆盖完整 GDScript 4.7 语法，达到实用级性能。

**Architecture:** 三子系统 — A) 编辑器 UI（Bridge 中继 + Bootstrap 启动 + MainPanel TabBar + 3 子面板）; B) 语法覆盖（Tokenizer/Parser/AST 扩展）; C) 工程化（时间戳缓存 + 错误恢复）。UI 层纯 GDScript 程序化构建（参考 clef-dev/fuse 模式），不依赖 .tscn。

**Tech Stack:** Godot 4.7, GDScript, EditorPlugin API, TabBar, Tree, RichTextLabel, ConfigFile

**Spec reference:** `docs/superpowers/specs/2026-06-20-phase3-editor-integration-design.md`
**Reference projects:** `E:\GitHub\clef-dev` (程序化 UI、Bridge、_draw()), `E:\Godot\GodotProjects\project-juicy-godot` (Bootstrap、Tree 拓扑、变量监视器)

---

## 文件结构

```
addons/gdscript_util/
├── [Phase 1+2 不变] gds_tokenizer.gd, gds_parser.gd, gds_ast_nodes.gd
├── [Phase 1+2 不变] gds_symbol_resolver.gd, gds_analysis_result.gd
├── [Phase 1+2 不变] gds_symbol.gd ... gds_def_use_chain.gd (10 数据类)
├── [Phase 1+2 不变] gds_self_node.gd, gds_super_node.gd
├── [修改] plugin.gd, plugin.cfg
│
├── editor/                                  # [Phase 3 新增]
│   ├── gds_editor_bootstrap.gd              # 模块化启动
│   ├── gds_analysis_bridge.gd               # 信号中继桥
│   │
│   ├── panels/
│   │   ├── gds_analysis_main_panel.gd       # 底部主面板 — TabBar + 3 子面板
│   │   ├── gds_call_graph_panel.gd          # 调用图子面板
│   │   ├── gds_signal_flow_panel.gd         # 信号流子面板
│   │   ├── gds_def_use_panel.gd             # 变量读写子面板
│   │   └── gds_analysis_summary.gd          # Dock 摘要面板
│   │
│   ├── widgets/
│   │   └── gds_graph_canvas.gd              # 通用图 _draw() 可视化
│   │
│   └── dialogs/
│       └── gds_export_report_dialog.gd      # 导出报告弹窗
│
└── tests/
    └── test_phase3_editor.gd                # Phase 3 验收测试
```

**职责边界：**
- `gds_analysis_bridge.gd` — 分析引擎与 UI 之间的信号中继。不持有 UI 引用，不直接操作 DOM。
- `gds_editor_bootstrap.gd` — 插件启动/关闭时的面板注册/销毁。调用 Bridge.setup()。
- `gds_analysis_main_panel.gd` — 底部面板容器。TabBar 切换子面板可见性。不包含具体分析逻辑。
- 3 个子面板 — 各自独立读 Bridge 数据渲染。通过 Bridge 信号联动。
- `gds_analysis_summary.gd` — Dock 面板。显示文件级摘要 + 错误列表。

---

## Chunk A: 编辑器 UI 基础设施

### Task A1: 创建 GDSAnalysisBridge — 信号中继桥

**Files:** Create: `addons/gdscript_util/editor/gds_analysis_bridge.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/gds_analysis_bridge.gd
# 信号中继桥 — 解耦分析引擎和编辑器 UI 面板
# 参考: clef-dev/addons/clef/editor/clef_station_editor_bridge.gd

class_name GDSAnalysisBridge
extends RefCounted

# 分析生命周期
signal analysis_started(file_path: String)
signal analysis_completed(result: GDScriptAnalysisResult)
signal analysis_failed(file_path: String, error: String)

# 面板间联动 — 用户在某面板选中一项，其他面板联动过滤
signal function_selected(func_name: String)
signal signal_selected(signal_name: String)
signal variable_selected(var_name: String)

var _current_result: GDScriptAnalysisResult = null
var _cache: Dictionary = {}  # String(path) → GDScriptAnalysisResult

func run_analysis(p_file_path: String) -> void:
    analysis_started.emit(p_file_path)
    # 调用 Phase 1+2 管道 — plugin.gd 中已有的 analyze_script()
    var result = GDScriptUtil.analyze_script(p_file_path)
    if result == null:
        analysis_failed.emit(p_file_path, "Parse error or file not found")
        return
    _current_result = result
    _cache[p_file_path] = result
    analysis_completed.emit(result)

func get_current_result() -> GDScriptAnalysisResult:
    return _current_result

func get_cached(file_path: String) -> GDScriptAnalysisResult:
    return _cache.get(file_path, null)

func select_function(func_name: String) -> void:
    function_selected.emit(func_name)

func select_signal(signal_name: String) -> void:
    signal_selected.emit(signal_name)

func select_variable(var_name: String) -> void:
    variable_selected.emit(var_name)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_analysis_bridge.gd
git commit -m "feat: GDSAnalysisBridge — signal relay between analysis engine and UI panels"
```

---

### Task A2: 创建 GDSEditorBootstrap — 模块化启动

**Files:** Create: `addons/gdscript_util/editor/gds_editor_bootstrap.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/gds_editor_bootstrap.gd
# 模块化启动 — 将 plugin.gd 的 Phase 3 初始化拆分为独立类
# 参考: project-juicy-godot/addons/fuse/editor/bootstrap/fuse_editor_bootstrap.gd

class_name GDSEditorBootstrap
extends RefCounted

var _plugin: EditorPlugin = null
var _bridge: GDSAnalysisBridge = null
var _main_panel: GDSAnalysisMainPanel = null
var _summary_panel: GDSAnalysisSummary = null

func setup(p_plugin: EditorPlugin) -> void:
    _plugin = p_plugin
    _bridge = GDSAnalysisBridge.new()

    _main_panel = GDSAnalysisMainPanel.new()
    _main_panel.setup(_bridge)
    _plugin.add_control_to_bottom_panel(_main_panel, "GDScript Analysis")

    _summary_panel = GDSAnalysisSummary.new()
    _summary_panel.setup(_bridge)
    _plugin.add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BR, _summary_panel)

    _plugin.resource_saved.connect(_on_resource_saved)

func teardown() -> void:
    if _plugin.resource_saved.is_connected(_on_resource_saved):
        _plugin.resource_saved.disconnect(_on_resource_saved)

    if _main_panel and is_instance_valid(_main_panel):
        _plugin.remove_control_from_bottom_panel(_main_panel)
        _main_panel.queue_free()
    if _summary_panel and is_instance_valid(_summary_panel):
        _plugin.remove_control_from_docks(_summary_panel)
        _summary_panel.queue_free()

func _on_resource_saved(resource: Resource) -> void:
    if resource is GDScript and resource.resource_path.ends_with(".gd"):
        _bridge.run_analysis(resource.resource_path)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_editor_bootstrap.gd
git commit -m "feat: GDSEditorBootstrap — modular panel registration and teardown"
```

---

### Task A3: 创建 GDSAnalysisMainPanel — TabBar 主面板

**Files:** Create: `addons/gdscript_util/editor/panels/gds_analysis_main_panel.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/panels/gds_analysis_main_panel.gd
# 底部主面板 — TabBar 切换 3 个子面板（Call Graph / Signal Flow / Def-Use）

class_name GDSAnalysisMainPanel
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _tab_bar: TabBar = null
var _content_stack: Control = null

var _call_graph_panel: GDSCallGraphPanel = null
var _signal_flow_panel: GDSSignalFlowPanel = null
var _def_use_panel: GDSDefUsePanel = null

func setup(p_bridge: GDSAnalysisBridge) -> void:
    _bridge = p_bridge
    _build_ui()

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

    # 3 个子面板（初始只显示第一个）
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

func _on_tab_changed(p_tab: int) -> void:
    _call_graph_panel.visible = (p_tab == 0)
    _signal_flow_panel.visible = (p_tab == 1)
    _def_use_panel.visible = (p_tab == 2)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/panels/gds_analysis_main_panel.gd
git commit -m "feat: GDSAnalysisMainPanel — bottom panel with TabBar and 3 sub-panels"
```

---

## Chunk B: 三个子面板

### Task B1: 创建 GDSCallGraphPanel — 调用图

**Files:** Create: `addons/gdscript_util/editor/panels/gds_call_graph_panel.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/panels/gds_call_graph_panel.gd
# 调用图子面板 — Tree 按 caller 分组 + 右侧详情
# 参考: project-juicy-godot/addons/fuse/editor/topology/fuse_topology.gd

class_name GDSCallGraphPanel
extends HSplitContainer

var _bridge: GDSAnalysisBridge = null
var _tree: Tree = null
var _detail: RichTextLabel = null

const COLORS := {
    0: Color.GREEN,      # SELF
    1: Color.DODGER_BLUE, # SUPER
    2: Color.ORANGE,      # EXTERNAL
    3: Color.MEDIUM_PURPLE, # CONNECT
    4: Color.PURPLE,       # SIGNAL_CONNECT
    5: Color.CYAN,         # LAMBDA
    7: Color.RED,          # EMIT
}

func setup(p_bridge: GDSAnalysisBridge) -> void:
    _bridge = p_bridge
    _bridge.analysis_completed.connect(_refresh)
    _bridge.function_selected.connect(_on_function_selected)
    _build_ui()

func _build_ui() -> void:
    # 左侧 Tree
    _tree = Tree.new()
    _tree.size_flags_horizontal = 3  # expand
    _tree.hide_root = true
    _tree.columns = 1
    _tree.item_selected.connect(_on_item_selected)
    add_child(_tree)

    # 右侧详情
    _detail = RichTextLabel.new()
    _detail.size_flags_horizontal = 3
    _detail.bbcode_enabled = true
    _detail.fit_content = true
    add_child(_detail)

func _refresh(p_result: GDScriptAnalysisResult) -> void:
    _tree.clear()
    if p_result.call_graph == null or p_result.call_graph.edges.is_empty():
        return

    # 按 caller 分组
    var groups: Dictionary = {}
    for edge in p_result.call_graph.edges:
        if not groups.has(edge.caller):
            groups[edge.caller] = []
        groups[edge.caller].append(edge)

    var root = _tree.create_item()
    for caller in groups:
        var caller_item = _tree.create_item(root)
        caller_item.set_text(0, caller + "()")
        for edge in groups[caller]:
            var child = _tree.create_item(caller_item)
            var arrow = "→"
            child.set_text(0, "  %s %s()" % [arrow, edge.callee])
            if COLORS.has(edge.call_type):
                child.set_custom_color(0, COLORS[edge.call_type])

func _on_item_selected() -> void:
    var item = _tree.get_selected()
    if item == null:
        return
    # 找到对应的 CallEdge
    var result = _bridge.get_current_result()
    if result == null:
        return
    var callee_name = item.get_text(0).strip_edges().trim_prefix("→ ")
    # 查找匹配的 edge 并填充详情
    for edge in result.call_graph.edges:
        if edge.callee == callee_name:
            _detail.clear()
            _detail.append_text("[b]Caller:[/b] %s()\n" % edge.caller)
            _detail.append_text("[b]Callee:[/b] %s()\n" % edge.callee)
            _detail.append_text("[b]Type:[/b] %d\n" % edge.call_type)
            _detail.append_text("[b]Line:[/b] %d\n" % edge.site_line)
            _bridge.select_function(edge.callee)
            break

func _on_function_selected(p_name: String) -> void:
    # 外部联动 — 高亮匹配项
    pass  # Phase 3.1: 简单实现，后续迭代加高亮
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/panels/gds_call_graph_panel.gd
git commit -m "feat: GDSCallGraphPanel — call graph tree grouped by caller with detail pane"
```

---

### Task B2: 创建 GDSSignalFlowPanel — 信号流

**Files:** Create: `addons/gdscript_util/editor/panels/gds_signal_flow_panel.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/panels/gds_signal_flow_panel.gd
# 信号流子面板 — Tree 显示每个信号的 emit/connect 站点

class_name GDSSignalFlowPanel
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _tree: Tree = null

func setup(p_bridge: GDSAnalysisBridge) -> void:
    _bridge = p_bridge
    _bridge.analysis_completed.connect(_refresh)
    _build_ui()

func _build_ui() -> void:
    _tree = Tree.new()
    _tree.size_flags_horizontal = SIZE_EXPAND_FILL
    _tree.size_flags_vertical = SIZE_EXPAND_FILL
    _tree.hide_root = true
    _tree.columns = 1
    _tree.item_selected.connect(_on_item_selected)
    add_child(_tree)

func _refresh(p_result: GDScriptAnalysisResult) -> void:
    _tree.clear()
    if p_result.signal_graph == null:
        return

    var root = _tree.create_item()
    for sig_name in p_result.signal_graph.signals:
        var info = p_result.signal_graph.signals[sig_name]
        var sig_item = _tree.create_item(root)
        sig_item.set_text(0, "signal %s" % sig_name)

        for site in info.emit_sites:
            var emit_item = _tree.create_item(sig_item)
            emit_item.set_text(0, "  EMIT: %s() @line %d" % [site.enclosing_function, site.line])
            emit_item.set_custom_color(0, Color.RED)

        for site in info.connect_sites:
            var conn_item = _tree.create_item(sig_item)
            conn_item.set_text(0, "  CONNECT: %s() @line %d" % [site.enclosing_function, site.line])
            conn_item.set_custom_color(0, Color.DODGER_BLUE)

func _on_item_selected() -> void:
    var item = _tree.get_selected()
    if item == null:
        return
    var text = item.get_text(0).strip_edges()
    if text.begins_with("signal "):
        _bridge.select_signal(text.trim_prefix("signal "))
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/panels/gds_signal_flow_panel.gd
git commit -m "feat: GDSSignalFlowPanel — signal emit/connect tree view"
```

---

### Task B3: 创建 GDSDefUsePanel — 变量读写

**Files:** Create: `addons/gdscript_util/editor/panels/gds_def_use_panel.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/panels/gds_def_use_panel.gd
# 变量读写子面板 — Tree 表格式 DEF/READ/WRITE 显示
# 参考: project-juicy-godot/addons/fuse/editor/debugging/variable_watcher.gd

class_name GDSDefUsePanel
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _tree: Tree = null

const COLORS := {
    0: Color.GREEN,         # DEFINE
    1: Color.DODGER_BLUE,    # READ
    2: Color.ORANGE,         # WRITE
    3: Color.RED,            # READ_WRITE
}

func setup(p_bridge: GDSAnalysisBridge) -> void:
    _bridge = p_bridge
    _bridge.analysis_completed.connect(_refresh)
    _bridge.variable_selected.connect(_on_variable_selected)
    _build_ui()

func _build_ui() -> void:
    _tree = Tree.new()
    _tree.size_flags_horizontal = SIZE_EXPAND_FILL
    _tree.size_flags_vertical = SIZE_EXPAND_FILL
    _tree.hide_root = true
    _tree.columns = 3
    _tree.set_column_title(0, "Variable")
    _tree.set_column_title(1, "Kind")
    _tree.set_column_title(2, "Sites")
    _tree.item_selected.connect(_on_item_selected)
    add_child(_tree)

func _refresh(p_result: GDScriptAnalysisResult) -> void:
    _tree.clear()
    if p_result.def_use_chain == null:
        return

    var root = _tree.create_item()
    for var_name in p_result.def_use_chain.variables:
        var info = p_result.def_use_chain.variables[var_name]
        var item = _tree.create_item(root)
        item.set_text(0, var_name)
        item.set_text(1, _kind_string(info))
        item.set_text(2, "%d DEF, %d READ, %d WRITE" % [
            1 if info.def_site != null else 0,
            info.read_sites.size(),
            info.write_sites.size()
        ])

        # 子项 — 每个 site 一行
        _add_site_items(item, info.def_site, "DEF")
        for s in info.read_sites:
            _add_site_items(item, s, "READ")
        for s in info.write_sites:
            _add_site_items(item, s, "WRITE")

func _add_site_items(p_parent: TreeItem, p_site, p_label: String) -> void:
    if p_site == null:
        return
    var child = _tree.create_item(p_parent)
    child.set_text(0, "  %s" % p_label)
    child.set_text(1, p_site.enclosing_function + "()")
    child.set_text(2, "line %d" % p_site.line)
    if COLORS.has(p_site.access_type):
        child.set_custom_color(0, COLORS[p_site.access_type])

func _kind_string(p_info) -> String:
    if p_info.def_site != null and p_info.def_site.access_type == 0:
        return "var/const"
    return "param"

func _on_item_selected() -> void:
    var item = _tree.get_selected()
    if item == null or item.get_parent() == _tree.get_root():
        return
    var var_name = item.get_text(0).strip_edges()
    _bridge.select_variable(var_name)

func _on_variable_selected(p_name: String) -> void:
    pass  # Phase 3.1: 联动预留
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/panels/gds_def_use_panel.gd
git commit -m "feat: GDSDefUsePanel — variable def-use chain tree view with color coding"
```

---

### Task B4: 创建 GDSAnalysisSummary — Dock 摘要

**Files:** Create: `addons/gdscript_util/editor/panels/gds_analysis_summary.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/editor/panels/gds_analysis_summary.gd
# Dock 摘要面板 — 文件级分析摘要 + 错误列表

class_name GDSAnalysisSummary
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _summary_label: RichTextLabel = null
var _error_list: Tree = null

func setup(p_bridge: GDSAnalysisBridge) -> void:
    _bridge = p_bridge
    _bridge.analysis_completed.connect(_refresh)
    _build_ui()

func _build_ui() -> void:
    _summary_label = RichTextLabel.new()
    _summary_label.bbcode_enabled = true
    _summary_label.fit_content = true
    add_child(_summary_label)

    _error_list = Tree.new()
    _error_list.size_flags_horizontal = SIZE_EXPAND_FILL
    _error_list.size_flags_vertical = SIZE_EXPAND_FILL
    _error_list.hide_root = true
    _error_list.columns = 1
    add_child(_error_list)

func _refresh(p_result: GDScriptAnalysisResult) -> void:
    _summary_label.clear()
    _summary_label.append_text("[b]File:[/b] %s\n" % p_result.file_path)
    _summary_label.append_text("[b]Class:[/b] %s\n" % p_result.classname_id)
    _summary_label.append_text("[b]Functions:[/b] %d\n" % p_result.get_all_functions().size())
    _summary_label.append_text("[b]Signals:[/b] %d\n" % p_result.get_all_signals().size())

    if p_result.call_graph:
        _summary_label.append_text("[b]Call Edges:[/b] %d\n" % p_result.call_graph.edges.size())
    if p_result.signal_graph:
        _summary_label.append_text("[b]Signal Flows:[/b] %d\n" % p_result.signal_graph.signals.size())

    # 错误列表
    _error_list.clear()
    var root = _error_list.create_item()
    for err in p_result.errors:
        var item = _error_list.create_item(root)
        item.set_text(0, err)
        item.set_custom_color(0, Color.YELLOW)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/panels/gds_analysis_summary.gd
git commit -m "feat: GDSAnalysisSummary — dock panel with file-level stats and error list"
```

---

### Task B5: 集成 Bootstrap 到 plugin.gd

**Files:** Modify: `addons/gdscript_util/plugin.gd`

- [ ] **Step 1: 修改 plugin.gd — 添加 Bootstrap**

在 `plugin.gd` 顶部添加成员变量，并在 `_enter_tree` / `_exit_tree` 中调用：

```gdscript
# 在 plugin.gd 顶部 var analysis_cache 下方添加:
var _phase3_bootstrap: GDSEditorBootstrap = null

# 在 _enter_tree() 末尾添加:
_phase3_bootstrap = GDSEditorBootstrap.new()
_phase3_bootstrap.setup(self)

# 在 _exit_tree() 开头添加:
if _phase3_bootstrap:
    _phase3_bootstrap.teardown()
    _phase3_bootstrap = null
```

- [ ] **Step 2: 更新 plugin.cfg 版本号**

```cfg
version="3.0.0"
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/plugin.gd addons/gdscript_util/plugin.cfg
git commit -m "feat: integrate GDSEditorBootstrap into plugin.gd, bump to v3.0.0"
```

---

## Chunk C: 语法覆盖

### Task C1: Tokenizer — 新关键字

**Files:** Modify: `addons/gdscript_util/gds_ast_nodes.gd` (Token.Type 枚举追加)

- [ ] **Step 1: 在 Token.Type 枚举末尾（TK_MAX 之前）追加**

```gdscript
    # Phase 3: namespace / trait
    NAMESPACE,
    TRAIT,
    TRAIT_EXTENDS,
    IMPLEMENTS,
    # Phase 3: f-string / StringName
    FORMAT_STRING_LITERAL,
    STRING_NAME_LITERAL,
    # Phase 3: Callable
    CALLABLE,
```

- [ ] **Step 2: Tokenizer 关键字表追加**

Modify: `addons/gdscript_util/gds_tokenizer.gd` — 在 `KEYWORDS` const 中追加：

```gdscript
    "namespace": GDScriptToken.Type.NAMESPACE,
    "trait": GDScriptToken.Type.TRAIT,
    "implements": GDScriptToken.Type.IMPLEMENTS,
```

- [ ] **Step 3: Tokenizer — f-string 扫描**

在 `_scan_string` 之前添加 `_scan_format_string` 方法，识别 `f"..."` 前缀：

```gdscript
func _scan_format_string(p_quote: String) -> GDScriptToken:
    # f"...{expr}..." 格式化字符串
    var segments: Array = []  # of {text: String, expr: Variant}
    var cur_text = ""
    while _pos < source.length():
        var c = _advance()
        if c == "\x00":
            return _make_token(GDScriptToken.Type.ERROR, "Unterminated format string")
        if c == "{" and _peek() != "{":  # {{ 是 literal {
            if cur_text != "":
                segments.append({"text": cur_text, "expr": null})
                cur_text = ""
            # 简化: 读取到 } 作为表达式文本（由 parser 进一步解析）
            var expr_text = ""
            while _pos < source.length() and _peek() != "}":
                expr_text += _advance()
            _advance()  # skip }
            segments.append({"text": "", "expr": expr_text})
        elif c == p_quote:
            if cur_text != "":
                segments.append({"text": cur_text, "expr": null})
            break
        else:
            cur_text += c
    return _make_token(GDScriptToken.Type.FORMAT_STRING_LITERAL, segments)
```

- [ ] **Step 4: 在 _scan_token 中添加 'f' 前缀检测**

在 `_scan_token` 中，`"\""` / `"'"` 分支之前添加：

```gdscript
        "f":
            var next = _peek()
            if next == "\"" or next == "'":
                _advance()  # skip f
                return _scan_format_string(next)
```

- [ ] **Step 5: 提交**

```bash
git add addons/gdscript_util/gds_ast_nodes.gd addons/gdscript_util/gds_tokenizer.gd
git commit -m "feat: tokenizer — namespace/trait/implements keywords + f-string support"
```

---

### Task C2: AST — 新节点类型

**Files:** Modify: `addons/gdscript_util/gds_ast_nodes.gd` (追加)

- [ ] **Step 1: 在 PreloadNode 定义之后追加新 AST 节点**

```gdscript
# ---- Phase 3: namespace / trait ----
class NamespaceNode:
    extends ASTNode
    var name: String = ""
    var members: Array = []

class TraitNode:
    extends ASTNode
    var name: String = ""
    var methods: Array = []    # of FunctionNode (abstract)
    var properties: Array = []  # of VariableNode

class ImplementsNode:
    extends ASTNode
    var trait_name: String = ""

# ---- Phase 3: match guard ----
class GuardedMatchBranchNode:
    extends MatchBranchNode
    var guard = null  # ExpressionNode

# ---- Phase 3: inline setter/getter ----
class SetterGetterNode:
    extends ASTNode
    var setter: FunctionNode = null
    var getter: FunctionNode = null
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_ast_nodes.gd
git commit -m "feat: AST — NamespaceNode, TraitNode, ImplementsNode, GuardedMatchBranchNode, SetterGetterNode"
```

---

### Task C3: Parser — namespace / trait / guard / inline-setter

**Files:** Modify: `addons/gdscript_util/gds_parser.gd`

- [ ] **Step 1: `_parse_class_member` 中添加 namespace/trait 分支**

```gdscript
        GDScriptToken.Type.NAMESPACE:
            return _parse_namespace()

        GDScriptToken.Type.TRAIT:
            return _parse_trait()
```

- [ ] **Step 2: 实现 `_parse_namespace`**

```gdscript
func _parse_namespace() -> NamespaceNode:
    _advance()  # NAMESPACE
    var node = GDScriptToken.NamespaceNode.new()
    var id_t = _expect(GDScriptToken.Type.IDENTIFIER, "namespace 后需要名称")
    if id_t:
        node.name = id_t.literal
    _expect(GDScriptToken.Type.COLON)
    _match(GDScriptToken.Type.NEWLINE)
    _expect(GDScriptToken.Type.INDENT)
    while _peek() and _peek().type not in [GDScriptToken.Type.DEDENT, GDScriptToken.Type.TK_EOF]:
        _skip_newlines()
        if _peek() and _peek().type == GDScriptToken.Type.TK_EOF:
            break
        var member = _parse_class_member()
        if member != null:
            node.members.append(member)
        else:
            _skip_to_newline()
    _expect(GDScriptToken.Type.DEDENT)
    return node
```

- [ ] **Step 3: 实现 match guard 支持**

在 `_parse_match` 中，`when` 后可选的 guard 表达式：

```gdscript
# 在 _parse_match 的 when 处理中:
if _match(GDScriptToken.Type.WHEN):
    # 检查是否有 guard 表达式 (when x > 0:)
    if _peek() and _peek().type in [GDScriptToken.Type.IDENTIFIER, GDScriptToken.Type.LITERAL, GDScriptToken.Type.MINUS, GDScriptToken.Type.NOT, GDScriptToken.Type.PAREN_OPEN]:
        var guard_expr = _parse_expression()
        if _peek() and _peek().type == GDScriptToken.Type.COLON:
            # 这是 guard: when x > 0:
            var branch = GuardedMatchBranchNode.new()
            branch.guard = guard_expr
            _advance()  # COLON
            branch.body = _parse_suite()
            node.branches.append(branch)
            continue
```

- [ ] **Step 4: 实现内联 setter/getter**

在 `_parse_variable` 中，检测 `: set(v):` 语法：

```gdscript
    # 内联 setter/getter: var hp: set(v): hp = clamp(v, 0, 100)
    if _peek() and _peek().type == GDScriptToken.Type.IDENTIFIER and _peek().literal == "set":
        _advance()  # "set"
        if _match(GDScriptToken.Type.PAREN_OPEN):
            _match(GDScriptToken.Type.IDENTIFIER)  # param name, ignored
            _expect(GDScriptToken.Type.PAREN_CLOSE)
            _expect(GDScriptToken.Type.COLON)
            var setter_node = SetterGetterNode.new()
            setter_node.setter = _parse_expression()
            node.setter_getter = setter_node
```

- [ ] **Step 5: 提交**

```bash
git add addons/gdscript_util/gds_parser.gd
git commit -m "feat: parser — namespace, trait, match guard, inline setter/getter"
```

---

## Chunk D: 性能 + 错误恢复

### Task D1: 时间戳缓存

**Files:** Modify: `addons/gdscript_util/editor/gds_analysis_bridge.gd`

- [ ] **Step 1: 在 Bridge 中添加缓存逻辑**

```gdscript
# 在 GDSAnalysisBridge 中添加:
var _timestamps: Dictionary = {}  # String(path) → int(mtime)

func should_reanalyze(p_path: String) -> bool:
    if not FileAccess.file_exists(p_path):
        return false
    var mtime = FileAccess.get_modified_time(p_path)
    if _timestamps.has(p_path) and _timestamps[p_path] == mtime:
        return false
    _timestamps[p_path] = mtime
    return true

# 修改 run_analysis:
func run_analysis(p_file_path: String) -> void:
    if not should_reanalyze(p_file_path) and _cache.has(p_file_path):
        _current_result = _cache[p_file_path]
        analysis_completed.emit(_current_result)
        return
    # ... 原有分析逻辑 ...
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/editor/gds_analysis_bridge.gd
git commit -m "feat: timestamp-based cache to skip re-analysis of unchanged files"
```

---

### Task D2: 错误恢复

**Files:** Modify: `addons/gdscript_util/gds_parser.gd`

- [ ] **Step 1: 在 Parser 中添加错误计数器和上限**

```gdscript
# 在 GDScriptParser 类中添加:
var _error_count: int = 0
const MAX_ERRORS := 20

func _set_error(p_msg: String):
    _error_count += 1
    if _error_count > MAX_ERRORS:
        return
    if error == "":
        error = p_msg
        if _peek():
            _error_line = _peek().start_line
            _error_column = _peek().start_column
```

- [ ] **Step 2: 在 parse() 成员循环中使用 `_skip_to_next_member`**

```gdscript
# 替换 _skip_to_newline 为跳过整个损坏的成员:
func _skip_to_next_member():
    # 跳过直到下一个顶级关键字 (func/var/const/signal/enum/class/namespace/trait)
    while _peek() and _peek().type != GDScriptToken.Type.TK_EOF:
        if _peek().type in [
            GDScriptToken.Type.FUNC, GDScriptToken.Type.VAR,
            GDScriptToken.Type.TK_CONST, GDScriptToken.Type.SIGNAL,
            GDScriptToken.Type.ENUM, GDScriptToken.Type.CLASS,
            GDScriptToken.Type.NAMESPACE, GDScriptToken.Type.TRAIT,
            GDScriptToken.Type.DEDENT,
        ]:
            break
        _advance()
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/gds_parser.gd
git commit -m "feat: error recovery — skip to next valid member on parse failure (max 20 errors)"
```

---

## Chunk E: 验收

### Task E1: 回归测试

**Files:** 运行已有测试

- [ ] **Step 1: 运行 Phase 1 测试**

确认 10/10 通过。

- [ ] **Step 2: 运行 Phase 2 测试**

确认 10/10 通过。

- [ ] **Step 3: 提交（如有修改）**

```bash
git add -A
git commit -m "test: Phase 1 & Phase 2 regression tests pass after Phase 3 additions"
```

---

### Task E2: 编辑器面板验收

**Files:** 手动验证

- [ ] **Step 1: 打开编辑器，确认底部面板出现**

"GDScript Analysis" Tab 应出现在底部面板区域。

- [ ] **Step 2: 打开任意 .gd 文件，手动触发分析**

→ 调用图 Tab 应显示调用关系
→ 信号流 Tab 应显示信号 emit/connect
→ Def-Use Tab 应显示变量读写

- [ ] **Step 3: 保存 .gd 文件**

→ 自动触发分析（`resource_saved` 信号）
→ Dock 摘要面板应更新统计信息

- [ ] **Step 4: 验证面板可见性**

切换 TabBar → 对应子面板显示/隐藏。关闭底部面板 → 重新打开仍正常。

---

### Task E3: 语法验收 (Phase 3 语法测试)

**Files:** Create: `tests/test_phase3_syntax.gd`

- [ ] **Step 1: 创建测试文件**

```gdscript
# tests/test_phase3_syntax.gd
extends Node

func _ready():
    print("=== Phase 3 Syntax Tests ===\n")
    test_f_string()
    test_match_guard()
    test_namespace()
    print("\n=== Done ===")

func parse(p_source: String) -> GDScriptToken.ClassNode:
    var tokenizer = GDScriptTokenizer.new()
    var tokens = tokenizer.tokenize(p_source)
    var parser = GDScriptParser.new()
    var ast = parser.parse(tokens)
    assert(parser.error == "", "Parse error: %s" % parser.error)
    return ast

func test_f_string():
    print("Test: f-string...")
    var source = 'var msg = f"Hello, {name}!"\n'
    var ast = parse(source)
    assert(ast.members.size() > 0, "Expected member")
    print("  PASS")

func test_match_guard():
    print("Test: match with guard...")
    var source = "func f(x):\n\tmatch x:\n\t\twhen y:\n\t\t\ty > 0:\n\t\t\t\tpass\n"
    var ast = parse(source)
    assert(ast.members.size() > 0, "Expected function")
    print("  PASS")

func test_namespace():
    print("Test: namespace...")
    var source = "namespace Test:\n\tfunc foo():\n\t\tpass\n"
    var ast = parse(source)
    assert(ast.members.size() > 0, "Expected namespace")
    print("  PASS")
```

- [ ] **Step 2: 运行语法测试**

创建 `tests/test_phase3_syntax.tscn` 并运行。

- [ ] **Step 3: 提交**

```bash
git add tests/test_phase3_syntax.gd tests/test_phase3_syntax.tscn
git commit -m "test: Phase 3 syntax — f-string, match guard, namespace"
```

---

## 完成检查清单

- [ ] `editor/gds_analysis_bridge.gd` — 信号中继桥
- [ ] `editor/gds_editor_bootstrap.gd` — 模块化启动
- [ ] `editor/panels/gds_analysis_main_panel.gd` — TabBar 主面板
- [ ] `editor/panels/gds_call_graph_panel.gd` — 调用图子面板
- [ ] `editor/panels/gds_signal_flow_panel.gd` — 信号流子面板
- [ ] `editor/panels/gds_def_use_panel.gd` — 变量读写子面板
- [ ] `editor/panels/gds_analysis_summary.gd` — Dock 摘要面板
- [ ] `plugin.gd` + `plugin.cfg` — Bootstrap 集成 + v3.0.0
- [ ] Tokenizer — namespace/trait/implements/f-string
- [ ] AST — NamespaceNode/TraitNode/GuardedMatchBranchNode/SetterGetterNode
- [ ] Parser — namespace/trait/match-guard/inline-setter + 错误恢复
- [ ] 时间戳缓存 — 未修改文件跳过分析
- [ ] Phase 1 回归 10/10
- [ ] Phase 2 回归 10/10
- [ ] Phase 3 语法测试 3/3
