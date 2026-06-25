# tscn/tres 解析器增强 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: 使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 按任务逐个实现。步骤用 `- [ ]` 复选框跟踪。

**Goal:** 补齐 tscn/tres spec P1+P2 的 5 项数据层增强（UID 引用 / @export 填充 / 子资源内联 / .tres 子资源链 / 扫描 UX），让解析器支持现代 Godot 项目，并为场景主屏 @export 显示供数。

**Architecture:** 改现有 `gds_tscn_parser` / `gds_tres_parser` / `gds_project_analyzer`，填充已预留字段（`ExtResourceInfo.uid` / `SceneNodeData.export_overrides`）。**无新数据模型**。

**Tech Stack:** Godot 4.7 GDScript，`ResourceUID`（编辑器态）+ `.uid` 文件扫描。

**SPEC:** [tscn/tres spec §二 P1/P2](../specs/2026-06-25-tscn-tres-parser-spec.md)
**状态:** ✅ PLAN 完成（2026-06-25）

---

## File Structure

**改动**：
- `addons/gdscript_ast/gds_tscn_parser.gd` — UID 解析 / @export 提取 / sub_resource 内联
- `addons/gdscript_ast/gds_tres_parser.gd` — 子资源引用链展开
- `addons/gdscript_ast/editor/gds_project_analyzer.gd` — `_resolve_script_path` 加 uid 匹配 / 扫描增量
- `addons/gdscript_ast/editor/gds_scan_settings_dialog.gd` + `gds_scan_config.gd` — `.tscn`/`.tres` 扫描开关

**测试**：扩展 `tests/test_tscn_tres_parser.gd` + 新 fixtures（`test_scene_uid.tscn` uid-only）

**字段已预留**（核对确认，本 plan 只填逻辑）：`ExtResourceInfo.uid`、`SceneNodeData.export_overrides`、`SceneNodeData.to_dict` 已含 export_overrides。

---

## Chunk A: UID 引用解析（#14，🔴 最阻塞）

> 现代 Godot `.tscn` 的 `ext_resource` 常只有 `uid="uid://..."` 无 `path=`。没这项解析器对真实项目静默失败。

### Task A1: ext_resource `uid=` 提取
**Files:** Modify `gds_tscn_parser.gd::_parse_ext_resource`（及 `_parse_header`）
- [ ] header 解析提取 `uid="uid://..."` → `ExtResourceInfo.uid`（字段已存在，当前未填）
```gdscript
# _parse_header 已提取 key="val" 对；ext_resource 节额外取 uid
var uid := params.get("uid", "")
ext.uid = uid  # "uid://xxxxx" 或 ""
```

### Task A2: uid-only 时通过 `.uid` 文件反查 path
- [ ] path 为空且 uid 非空时，扫项目所有 `.uid` 文件建 `{uid_string → res_path}` 映射（`.uid` 文件内容就是 uid 字符串），查映射得 path。
- [ ] 映射在 `GDScriptProjectAnalyzer` 扫描阶段建一次（`_scan_dir` 遇 `.uid` 收集），传给 parser 或 parser 查 analyzer。
```gdscript
# analyzer 扫描时
func _collect_uid_map() -> Dictionary:
    var m: Dictionary = {}
    for uid_file in _scan_dir_for_ext(".uid"):
        var uid_str = FileAccess.get_file_as_string(uid_file).strip_edges()
        var res_path = uid_file.trim_suffix(".uid")
        m[uid_str] = res_path
    return m
```

### Task A3: `_resolve_script_path` uid 匹配（spec §5.3 优先级 3）
**Files:** Modify `gds_project_analyzer.gd::_resolve_script_path`
- [ ] 现有优先级：class_name → path。加第 3 级：`ext.uid` 非空 → 查 uid_map → path。
- [ ] **测试** `test_uid_resolve`：fixture `test_scene_uid.tscn`（ext_resource 只有 uid= 无 path=）→ 解析后 `ext_resources["1_script"].path` 正确还原。

---

## Chunk B: @export 填充值（#9，🔴 scene 主屏依赖）

> scene-main-screen 节点详情「后续迭代」依赖此项显示导出变量值。

### Task B1: 节点 `export_overrides` 提取
**Files:** Modify `gds_tscn_parser.gd::_parse_node`
- [ ] 节点 script_resource 非空时，关联脚本 `AnalysisResult` 的 `@export var` 声明列表；节点属性行中匹配这些变量名 → `node.export_overrides[var_name] = value`。
- [ ] 关联通过 `_bridge.get_project_result().files[script_path]` 拿 AnalysisResult；export 变量从 symbol_table/AST 提取（参考现有变量定义提取）。
```gdscript
# _parse_node 内，解析完 properties 后
if node.script_resource != "":
    var exports = _get_script_exports(node.script_resource)  # [String] @export 变量名
    for key in node.properties:
        if key in exports:
            node.export_overrides[key] = node.properties[key]
```

### Task B2: `to_dict` 验证 + 测试
- [ ] `SceneNodeData.to_dict` 已含 `export_overrides`（核对确认），无需改。
- [ ] **测试** `test_export_overrides`：fixture 节点挂脚本含 `@export var max_health`，场景填 `max_health = 100` → `node.export_overrides["max_health"] == "100"`。

---

## Chunk C: 子资源内联解析（#10，🟡）

### Task C1: `[sub_resource]` 完整属性
**Files:** Modify `gds_tscn_parser.gd::_parse_sub_resource`
- [ ] 当前 `SubResourceData.properties` 已存键值对（核对确认）；补**内联对象/Variant 解析**——`size = Vector2(32, 32)` 当前透传字符串，本 task 做常用类型结构化（Vector2/Color/Rect2/NodePath），其余透传。
- [ ] 参考 spec §七风险表：Variant 不完备 → P0 字符串透传，本 task（原 P2 #16 部分合并）做常用类型。
- [ ] **测试** `test_sub_resource_inline`：`RectangleShape2D` 的 `size` 解析为结构化（或确认透传字符串可被 `str_to_var` 还原）。

---

## Chunk D: .tres 子资源链（#12，🟡）

### Task D1: SubResource 引用链展开
**Files:** Modify `gds_tres_parser.gd`
- [ ] `.tres` `[resource]` 属性含 `SubResource("id")` → 递归展开 `sub_resources[id].properties`，生成完整属性视图。
- [ ] **环检测**（spec §七风险表）：展开时维护 visited set，遇环记 `{"$circular_ref": "id"}`。
- [ ] **测试** `test_tres_sub_chain`：fixture `test_resource.tres` 含嵌套 SubResource → 展开后属性完整 + 环 fixture 不无限递归。

---

## Chunk E: 扫描 ScanConfig UX（#13，🟡）

> D2/D3 已做裸扫描（P0），剩 Scan Settings 对话框开关 + 增量重分析。

### Task E1: Scan Settings 加 `.tscn`/`.tres` 开关
**Files:** Modify `gds_scan_settings_dialog.gd` + `gds_scan_config.gd`
- [ ] `GDSScanConfig` 加 `SETTING_SCAN_SCENES := "gdscript_ast/scan/scenes"`（bool，默认 true）+ `SETTING_SCAN_RESOURCES`。
- [ ] 对话框加两个 CheckBox；`_scan_dir` 按开关决定是否收 `.tscn`/`.tres`。

### Task E2: 增量重分析
**Files:** Modify `gds_project_analyzer.gd` + `gds_editor_bootstrap.gd::_on_resource_saved`
- [ ] `resource_saved` 当前只处理 `.gd`；扩展：`.tscn`/`.tres` 保存时 → `_analyze_scene_file`/`_analyze_resource_file` 重解析该文件 + 更新 `result.scenes`/`resources`。
- [ ] **测试** `test_scan_scenes_toggle`：关 scenes 开关 → `result.scenes` 为空；增量重分析后更新。

---

## Chunk F: 验收

### Task F1: 测试套扩展
扩展 `tests/test_tscn_tres_parser.gd`（或新 `test_tscn_enhancements.gd`）：
```
test_uid_resolve / test_export_overrides / test_sub_resource_inline
test_tres_sub_chain / test_scan_scenes_toggle
```
- [ ] headless 跑全绿（命令见下）。

---

## ⏸ 后续（暂缓，标记不实现）

| # | 项 | 暂缓理由 |
|---|----|---------|
| 11 | `[editable]` 节解析 | 边缘价值，无下游消费者 |
| 15 | 嵌套场景实例化追踪（PackedScene 递归） | 依赖场景实例化语义，复杂度高 |
| 16 | 资源属性类型推断（完整 Variant 结构化） | Chunk C 已覆盖常用类型，剩余边际收益低 |

> 这三项在 spec 保留，待有下游需求时单独 plan。

---

## 集成检查点

```
analyze_full()
 ├─ scan_project()
 │   ├─ _collect_uid_map()          ← A2: 扫 .uid 建 uid→path
 │   ├─ _scan_dir (.gd/.tscn/.tres)  ← E1: 按 ScanConfig 开关
 │   ├─ _analyze_scene_file → tscn_parser
 │   │   ├─ _parse_ext_resource (uid 提取)   ← A1
 │   │   ├─ _parse_node (export_overrides)   ← B1
 │   │   └─ _parse_sub_resource (内联)       ← C1
 │   └─ _analyze_resource_file → tres_parser (子链) ← D1
 ├─ resolve_cross_file
 └─ _integrate_scene_resources
     └─ _resolve_script_path (class→path→uid) ← A3
增量：resource_saved(.tscn/.tres) → 重解析 ← E2
```

## 跑测命令（headless，Godot 4.7）

```bash
"E:/Godot/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64_console.exe" \
  --headless --path "e:/GitHub/gdscript-ast-flow" \
  --quit "res://tests/test_tscn_tres_parser.tscn"
```
看 stdout `=== All tests completed ===` + 无 SCRIPT ERROR。

## 验收标准

- [ ] uid-only fixture 的 ext_resource path 正确还原（A3）
- [ ] 节点 @export 填充值提取（B1）
- [ ] sub_resource 内联属性（C1）
- [ ] .tres 子资源链展开 + 环检测（D1）
- [ ] Scan Settings scenes/resources 开关生效（E1）
- [ ] .tscn/.tres 保存触发增量重分析（E2）
- [ ] #11/#15/#16 在本 plan 明确暂缓（不实现）
