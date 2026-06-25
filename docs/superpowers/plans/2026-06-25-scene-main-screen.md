# 场景可视化主屏模式 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: 使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 按任务逐个实现。步骤用 `- [ ]` 复选框跟踪。

**Goal:** 在主屏加「场景」mode，3 视角（节点树/脚本反查/信号图）可视化 tscn/tres 解析数据 + 视角联动。

**Architecture:** `GDSGraphMainScreen` 顶部加 mode 切换 `[代码分析|场景]`；场景 mode = 新 `GDSSceneMainScreen` 容器（视角 toolbar + 3 view + `navigate_to_node` 联动）。复用 P0 数据层（`scenes`/`script_associations`/`scene_signal_connections`）+ 现有 `GDSGraphNode`/`GDSVirtualGraphEdit`。

**Tech Stack:** Godot 4.7 GDScript，EditorPlugin 主屏，Tree/GraphEdit/OptionButton/ItemList 控件。

**SPEC:** [2026-06-25-scene-main-screen-design](../specs/2026-06-25-scene-main-screen-design.md)
**状态:** ✅ PLAN 完成（2026-06-25）

---

## File Structure

**新增**（统一放 `addons/gdscript_ast/editor/scene/`）：
- `gds_scene_main_screen.gd` — `GDSSceneMainScreen` 容器（视角 toolbar + 主体 + `navigate_to_node`）
- `scene_node_tree_view.gd` — `SceneNodeTreeView` 节点树视角
- `scene_script_lookup_view.gd` — `SceneScriptLookupView` 脚本反查视角
- `scene_signal_graph_view.gd` — `SceneSignalGraphView` 信号图视角

**改动**：
- `editor/gds_graph_main_screen.gd` — 顶部加 mode 切换

**测试**：
- `tests/test_scene_main_screen.gd` + `tests/test_scene_main_screen.tscn` — 视图层 headless 测试

**UI 装配参考模板**：`editor/gds_graph_main_screen.gd::_build_ui()`（OptionButton + Container + GraphEdit 装配模式）。

---

## Chunk A: 容器骨架 + mode 接入

### Task A1: GDSGraphMainScreen 加 mode 切换
**Files:** Modify `editor/gds_graph_main_screen.gd`

- [ ] **Step 1:** `_build_ui` 顶部加 mode OptionButton（在现有 toolbar 最前）：
```gdscript
var mode_box = OptionButton.new()
mode_box.add_item(_l10n.t("mode.code_analysis"), 0)  # 代码分析
mode_box.add_item(_l10n.t("mode.scene"), 1)          # 场景
mode_box.item_selected.connect(_on_mode_changed)
toolbar.add_child(mode_box)
```
- [ ] **Step 2:** 加 `_scene_main_screen`（懒实例化）+ `_on_mode_changed(i)`：i=0 显现有 Scope×Graph（toolbar 内 scope/kind/relayout/thresh/export + _legend + _graph_edit），隐 _scene_main_screen；i=1 反之。
```gdscript
var _scene_main_screen: GDSSceneMainScreen = null
func _on_mode_changed(i: int) -> void:
    var code_mode := (i == 0)
    # 现有代码分析控件
    for c in [_scope_box_ref, _graph_edit, _legend]:  # 按 _build_ui 实际引用调整
        if c: c.visible = code_mode
    if i == 1:
        if _scene_main_screen == null:
            _scene_main_screen = GDSSceneMainScreen.new()
            _scene_main_screen.setup(_bridge, _l10n)
            add_child(_scene_main_screen)
        _scene_main_screen.visible = true
        _scene_main_screen.rebuild_active()
    else:
        if _scene_main_screen: _scene_main_screen.visible = false
```
- [ ] **Step 3:** l10n 加 `mode.code_analysis`/`mode.scene` 两条（中英 csv）。
- [ ] **Step 4:** Godot 里开主屏，切 mode 两边都能显隐。commit `feat(scene): 主屏加 [代码分析|场景] mode 切换`

### Task A2: GDSSceneMainScreen 容器
**Files:** Create `editor/scene/gds_scene_main_screen.gd`

- [ ] **Step 1:** 骨架 + setup + _build_ui（视角 toolbar + 主体 Container）：
```gdscript
class_name GDSSceneMainScreen
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _l10n: GDSL10n = null
var _node_tree_view: SceneNodeTreeView = null
var _script_lookup_view: SceneScriptLookupView = null
var _signal_graph_view: SceneSignalGraphView = null
var _active_view: Control = null  # 当前活跃视角

func setup(p_bridge, p_l10n = null) -> void:
    _bridge = p_bridge
    _l10n = p_l10n if p_l10n else GDSL10n.new()
    _bridge.project_analysis_completed.connect(_on_data_changed)
    _node_tree_view = SceneNodeTreeView.new()
    _script_lookup_view = SceneScriptLookupView.new()
    _signal_graph_view = SceneSignalGraphView.new()
    for v in [_node_tree_view, _script_lookup_view, _signal_graph_view]:
        v.setup(_bridge, _l10n, Callable(self, "_navigate_to_node"))
    _build_ui()

func _build_ui() -> void:
    set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    size_flags_horizontal = SIZE_EXPAND_FILL
    size_flags_vertical = SIZE_EXPAND_FILL
    var toolbar = HBoxContainer.new()
    var box = OptionButton.new()
    box.add_item(_l10n.t("view.node_tree"), 0)
    box.add_item(_l10n.t("view.script_lookup"), 1)
    box.add_item(_l10n.t("view.signal_graph"), 2)
    box.item_selected.connect(_on_view_changed)
    toolbar.add_child(box)
    add_child(toolbar)
    for v in [_node_tree_view, _script_lookup_view, _signal_graph_view]:
        v.size_flags_horizontal = SIZE_EXPAND_FILL
        v.size_flags_vertical = SIZE_EXPAND_FILL
        v.visible = false
        add_child(v)
    _active_view = _node_tree_view
    _node_tree_view.visible = true

func _on_view_changed(i: int) -> void:
    _active_view.visible = false
    _active_view = [_node_tree_view, _script_lookup_view, _signal_graph_view][i]
    _active_view.visible = true
    _active_view.rebuild()

func rebuild_active() -> void:
    if _active_view: _active_view.rebuild()

func _on_data_changed(_arg = null) -> void:
    rebuild_active()

# 视角联动入口：切节点树视角 + 定位
func _navigate_to_node(scene_path: String, node_path: String) -> void:
    _active_view.visible = false
    _active_view = _node_tree_view
    _node_tree_view.visible = true
    _node_tree_view.focus_node(scene_path, node_path)
```
- [ ] **Step 2:** 3 个 view 先建空骨架（extends VBoxContainer + setup/rebuild/focus_node 空方法），让 A2 能编译。
- [ ] **Step 3:** commit `feat(scene): GDSSceneMainScreen 容器 + 视角切换 + navigate_to_node`

---

## Chunk B: 节点树视角（SceneNodeTreeView）

### Task B1: 场景列表 + Tree 渲染
**Files:** Create `editor/scene/scene_node_tree_view.gd`

- [ ] **Step 1:** 骨架：
```gdscript
class_name SceneNodeTreeView
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _l10n: GDSL10n = null
var _navigate: Callable = Callable()
var _scene_list: ItemList = null
var _tree: Tree = null
var _detail: VBoxContainer = null
var _current_scene: String = ""

func setup(p_bridge, p_l10n, p_navigate: Callable) -> void:
    _bridge = p_bridge; _l10n = p_l10n; _navigate = p_navigate
    _build_ui()

func _build_ui() -> void:
    # HSplitContainer: [场景列表 | Tree | 详情]，参考 gds_graph_main_screen 装配模式
    ...
    _scene_list.item_selected.connect(_on_scene_selected)
    _tree.item_selected.connect(_on_tree_node_selected)

func rebuild() -> void:
    _scene_list.clear(); _tree.clear()
    var proj = _bridge.get_project_result()
    if proj == null: return
    for path in proj.scenes: _scene_list.add_item(path)
    # 空状态见 Task E1

func _on_scene_selected() -> void:
    var idx = _scene_list.get_selected_items()
    if idx.is_empty(): return
    _current_scene = _scene_list.get_item_text(idx[0])
    _build_tree()

func _build_tree() -> void:
    _tree.clear()
    var proj = _bridge.get_project_result()
    if not proj or not proj.scenes.has(_current_scene): return
    var scene: GDSSceneResourceResult = proj.scenes[_current_scene]
    var root = _tree.create_item()
    for n in scene.root_nodes:
        _add_tree_node(root, n)

func _add_tree_node(parent: TreeItem, node) -> void:
    var item = _tree.create_item(parent)
    var label = node.name + " (" + node.type + ")"
    if node.script_resource != "": label = "📜 " + label
    item.set_text(0, label)
    item.set_metadata(0, {"path": _node_full_path(node), "node": node})
    for child in node.children: _add_tree_node(item, child)
```
- [ ] **Step 2:** `_node_full_path(node)` 递归算 NodePath（参考 tscn parser 的 full_path 逻辑）。

### Task B2: 节点详情侧栏 + 跳转脚本
- [ ] **Step 1:** `_on_tree_node_selected` → `_detail` 填 name/type/parent/groups/script_resource/该节点信号连接。
- [ ] **Step 2:** script_resource 行做成 Button，点击：
```gdscript
func _on_jump_script(path: String) -> void:
    if path == "" or not ResourceLoader.exists(path): return  # 无效则禁用
    var scr = load(path)
    if scr: EditorInterface.edit_script(scr)
```
- [ ] **Step 3:** `focus_node(scene_path, node_path)`：选场景 → 展开树到 node_path → 选中（供 navigate_to_node 调用）。

### Task B3: 节点树测试
**Files:** Create `tests/test_scene_main_screen.gd`
- [ ] **Step 1:** 测试 build_tree：
```gdscript
func test_node_tree_render():
    var parser = GDScriptTscnParser.new()
    var result = parser.parse("res://tests/fixtures/test_scene_full.tscn")
    # 模拟 view：直接验 scene.root_nodes 结构（15 节点，2 个重名 Icon 不同父）
    assert(result.root_nodes.size() == 1, "1 root (Main)")
    var main = result.root_nodes[0]
    assert(main.name == "Main")
    # Player 在 Main.children
    var found_player = false
    for c in main.children:
        if c.name == "Player": found_player = true
    assert(found_player, "Player is child of Main")
```
- [ ] **Step 2:** headless 跑（见文末跑测命令），绿。commit `feat(scene): 节点树视角 + 详情 + 跳转`

---

## Chunk C: 脚本反查视角（SceneScriptLookupView）

### Task C1: _build_index 聚合
**Files:** Create `editor/scene/scene_script_lookup_view.gd`
- [ ] **Step 1:**
```gdscript
class_name SceneScriptLookupView
extends VBoxContainer
# _build_index: script_associations 平铺 → {script → [{scene,node}]}
func _build_index(script_associations: Array) -> Dictionary:
    var idx: Dictionary = {}
    for entry in script_associations:
        var s = entry.get("script", "")
        if s == "": continue
        if not idx.has(s): idx[s] = []
        idx[s].append({"scene": entry.get("scene",""), "node": entry.get("node","")})
    return idx
```

### Task C2: 脚本列表 + 挂载点 + 联动
- [ ] **Step 1:** `rebuild`：取 `proj.script_associations` → `_build_index` → 脚本列表（按挂载数降序）。
- [ ] **Step 2:** 选脚本 → 挂载点 ItemList（`scene / node`）。
- [ ] **Step 3:** 点挂载条目 → `_navigate.call(scene, node)`（联动跳节点树）。

### Task C3: 反查测试
- [ ] **Step 1:** `test_script_lookup_index`：构造假 script_associations → `_build_index` → 断言聚合正确（player.gd → 3 挂载点）。
- [ ] **Step 2:** 跑测绿。commit `feat(scene): 脚本反查视角 + 聚合 + 联动`

---

## Chunk D: 信号图视角（SceneSignalGraphView）

### Task D1: build_logical 合并信号 + 着色
**Files:** Create `editor/scene/scene_signal_graph_view.gd`
- [ ] **Step 1:**
```gdscript
class_name SceneSignalGraphView
extends VBoxContainer
# build_logical: 合并 scene_signal_connections（跨）+ 各 scene.signal_connections（内）
# → {nodes: [...], edges: [...]}，edge 带 same_scene bool 供着色
func build_logical(proj) -> Dictionary:
    var nodes: Dictionary = {}  # key "scene/node" → {id,label}
    var edges: Array = []
    # 跨场景
    for c in proj.scene_signal_connections:
        var fk = c["from_scene"] + "/" + c["from_node"]
        var tk = c["to_scene"] + "/" + c["to_node"]
        nodes[fk] = {"id": fk, "label": fk}
        nodes[tk] = {"id": tk, "label": tk}
        edges.append({"from": fk, "to": tk, "signal": c["signal"], "same_scene": false})
    # 场景内
    for spath in proj.scenes:
        var scene = proj.scenes[spath]
        for conn in scene.signal_connections:
            var fk2 = spath + "/" + conn.from_node
            var tk2 = spath + "/" + conn.to_node
            nodes[fk2] = {"id": fk2, "label": fk2}
            nodes[tk2] = {"id": tk2, "label": tk2}
            edges.append({"from": fk2, "to": tk2, "signal": conn.signal_name, "same_scene": true})
    return {"nodes": nodes.values(), "edges": edges}
```
- [ ] **Step 2:** `rebuild`：`build_logical` → 复用 `GDSVirtualGraphEdit.set_graph`（同 main_screen）。边着色：same_scene 蓝，跨场景橙（在 GDSGraphNode/边渲染处按 edge.same_scene）。

### Task D2: 点节点联动
- [ ] **Step 1:** GraphEdit `node_selected` → 解析节点 id（`scene/node`）→ `_navigate.call(scene, node)`。

### Task D3: 信号图测试
- [ ] **Step 1:** `test_signal_graph_build`：用 fixture scene 的 `signal_connections` + 构造假跨场景边 → `build_logical` → 断言节点/边数 + same_scene 标记。
- [ ] **Step 2:** 跑测绿。commit `feat(scene): 信号图视角 + 跨/同场景着色 + 联动`

---

## Chunk E: 错误处理 + 验收

### Task E1: 空状态 / 扫描关 / 解析失败
**Files:** Modify `gds_scene_main_screen.gd` + 各 view
- [ ] **Step 1:** `rebuild_active` 前判断：
  - `not GDSScanConfig.is_enabled()` → 主体显 Label "项目扫描未开启"
  - `proj.scenes.is_empty()` → "未扫描到场景文件，检查 Scan Settings"
- [ ] **Step 2:** 场景列表中 `scene.errors` 非空 → ItemList `set_item_custom_fg_color(idx, RED)` + tooltip 显错误。

### Task E2: MVP 验收测试套
**Files:** `tests/test_scene_main_screen.gd`（补全）+ `tests/test_scene_main_screen.tscn`
- [ ] **Step 1:** 9 套用例（对应 spec §八）：
```
test_node_tree_render / test_node_detail_jump / test_script_lookup_index
test_script_lookup_navigate / test_signal_graph_build / test_signal_graph_navigate
test_empty_state / test_scan_disabled / test_parse_error_mark
```
- [ ] **Step 2:** headless 跑 `tests/test_scene_main_screen.tscn`，全绿。

---

## 集成检查点

```
GDSGraphMainScreen
 ├─ mode=代码分析 → 现有 Scope×Graph（不动）
 └─ mode=场景 → GDSSceneMainScreen
     ├─ 视角 toolbar [节点树 / 脚本反查 / 信号图]
     ├─ SceneNodeTreeView    ← navigate_to_node 目标（focus_node）
     ├─ SceneScriptLookupView → _navigate_to_node
     └─ SceneSignalGraphView  → _navigate_to_node
 数据：bridge.get_project_result()
   ├─ .scenes[path]              → 节点树/详情
   ├─ .script_associations       → 反查 _build_index
   └─ .scene_signal_connections  → 信号图（+ 各 scene.signal_connections）
```

## 跑测命令（headless，Godot 4.7）

```bash
"E:/Godot/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64_console.exe" \
  --headless --path "e:/GitHub/gdscript-ast-flow" \
  --quit "res://tests/test_scene_main_screen.tscn"
```
看 stdout `=== All tests completed ===` + 无 SCRIPT ERROR。

## 验收标准（对应 spec §八）

- [ ] mode 切换（A1）
- [ ] 节点树显示 test_scene_full（含重名 Icon）（B1/B3）
- [ ] 节点详情 + 跳转脚本（B2）
- [ ] 反查聚合正确（C1/C3）
- [ ] 反查→节点树联动（C2）
- [ ] 信号图同/跨场景着色（D1/D3）
- [ ] 信号图→节点树联动（D2）
- [ ] 空状态提示（E1）
- [ ] 扫描关提示（E1）
- [ ] 解析失败标红（E1）
