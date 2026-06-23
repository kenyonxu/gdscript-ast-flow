# 结构化图谱导出 设计规范

> 日期: 2026-06-23 | 状态: 设计中 | 依赖: Phase 3.2 跨文件分析 (已完成 ✅)

## 一、目标

把分析结果导出为**结构化 JSON**——AI agent 可直接消费的代码知识图谱。等于给 AI 一份压缩版代码地图（~10KB JSON 替代 ~100KB 源码），包含调用关系、信号流、变量读写、跨文件依赖。

**核心场景：**
- AI agent 问"改 `take_damage` 影响谁？" → JSON 查 call_graph + cross_file
- AI agent 问"项目结构？" → summary + files 清单
- MCP 工具数据源 → AI 调 "analyze" → 拿 JSON → 推理
- 外部工具消费（可视化、文档生成、依赖分析）

## 二、范围

### 做：

1. **`to_dict()` 方法** — AnalysisResult + ProjectResult 序列化
2. **JSON 导出** — `FileAccess` 写 `.json` 文件
3. **UI 入口** — 主屏 toolbar 加 "Export JSON" 按钮
4. **自动快照** — 可选：每次项目分析后自动写 `res://.godot/gdscript_util/codegraph.json`
5. **Schema 版本** — JSON 含 `schema_version` 字段，便于消费端兼容

### 不做：

- ❌ **增量导出** — 每次全量写（文件不大，YAGNI）
- ❌ **Mermaid/DOT 导出** — 先做 JSON，其他格式后续按需
- ❌ **API 服务** — 不做 HTTP/WebSocket，纯文件导出

## 三、JSON Schema

```json
{
  "$schema": "gdscript-util/codegraph",
  "schema_version": 1,
  "project": "<项目名>",
  "generated_at": "<ISO8601 时间戳>",
  "source_path": "res://",

  "summary": {
    "files_analyzed": <int>,
    "total_functions": <int>,
    "total_signals": <int>,
    "total_call_edges": <int>,
    "total_cross_file_edges": <int>,
    "parse_errors": <int>
  },

  "files": {
    "<res://path.gd>": {
      "class_name": "<String>",
      "extends": "<String>",
      "functions": [
        {
          "name": "<String>",
          "line": <int>,
          "params": [{"name": "<String>", "type": "<String>"}],
          "return_type": "<String|null>",
          "is_entry": <bool>,
          "is_static": <bool>,
          "in_degree": <int>,
          "out_degree": <int>
        }
      ],
      "signals": [
        {
          "name": "<String>",
          "line": <int>,
          "params": ["<String>"],
          "emit_count": <int>,
          "connect_count": <int>
        }
      ],
      "variables": [
        {"name": "<String>", "type": "<String>", "is_export": <bool>}
      ],
      "errors": ["<String>"]
    }
  },

  "call_graph": [
    {
      "file": "<res://path.gd>",
      "caller": "<String>",
      "callee": "<String>",
      "type": "SELF|SUPER|EXTERNAL|SIGNAL_CONNECT|EMIT",
      "line": <int>
    }
  ],

  "signal_graph": {
    "<signal_name>": {
      "file": "<res://path.gd>",
      "declaration_line": <int>,
      "emit_sites": [{"function": "<String>", "file": "<String>", "line": <int>}],
      "connect_sites": [{"function": "<String>", "file": "<String>", "line": <int>}]
    }
  },

  "cross_file": [
    {
      "source_file": "<res://path.gd>",
      "target_file": "<res://path.gd>",
      "target_class": "<String>",
      "target_symbol": "<String>",
      "kind": "CALL|SIGNAL_EMIT|SIGNAL_CONNECT|INSTANCE|EXTENDS",
      "line": <int>
    }
  ],

  "hub_functions": [
    {"name": "<String>", "file": "<String>", "total_degree": <int>}
  ],

  "coupled_files": [
    {"file_a": "<String>", "file_b": "<String>", "edge_count": <int>}
  ]
}
```

## 四、实现

### 4.1 ProjectResult.to_dict()

```gdscript
# gds_project_result.gd 新增
func to_dict(p_project_name: String = "") -> Dictionary:
    var result := {
        "schema_version": 1,
        "project": p_project_name,
        "source_path": root_path,
        "summary": _build_summary(),
        "files": {},
        "call_graph": [],
        "signal_graph": {},
        "cross_file": [],
        "hub_functions": [],
        "coupled_files": [],
    }
    # 填充 files
    for path in files:
        result.files[path] = files[path].to_dict()
    # 填充 cross_file
    for edge in cross_edges:
        result.cross_file.append(edge.to_dict())
    # 填充 hub_functions + coupled_files
    result.hub_functions = _top_hubs(20)
    result.coupled_files = _top_coupled(20)
    return result

func _build_summary() -> Dictionary:
    var func_count := 0
    var sig_count := 0
    var edge_count := 0
    for path in files:
        var f = files[path]
        func_count += f.get_all_functions().size()
        sig_count += f.get_all_signals().size()
        if f.call_graph:
            edge_count += f.call_graph.edges.size()
    return {
        "files_analyzed": files.size(),
        "total_functions": func_count,
        "total_signals": sig_count,
        "total_call_edges": edge_count,
        "total_cross_file_edges": cross_edges.size(),
    }
```

### 4.2 AnalysisResult.to_dict()

```gdscript
# gds_analysis_result.gd 新增
func to_dict() -> Dictionary:
    var funcs: Array = []
    for fn in get_all_functions():
        funcs.append(_function_to_dict(fn))
    var sigs: Array = []
    for sig in get_all_signals():
        sigs.append(_signal_to_dict(sig))
    return {
        "class_name": classname_id,
        "extends": extends_path,
        "functions": funcs,
        "signals": sigs,
        "errors": errors,
    }

func _function_to_dict(p_fn) -> Dictionary:
    # 提取函数信息
    var params: Array = []
    for p in p_fn.params:
        params.append({"name": p.name, "type": _type_str(p.datatype)})
    return {
        "name": p_fn.name,
        "line": p_fn.line,
        "params": params,
        "return_type": _type_str(p_fn.return_type),
        "is_entry": GDS_EntryMethods.is_entry(p_fn.name),
        "is_static": p_fn.is_static,
        "in_degree": call_in_degree.get(p_fn.name, 0),
        "out_degree": call_out_degree.get(p_fn.name, 0),
    }
```

### 4.3 CrossFileEdge.to_dict()

```gdscript
# gds_cross_file_edge.gd 新增
func to_dict() -> Dictionary:
    return {
        "source_file": source_file,
        "target_file": target_file,
        "target_class": target_class,
        "target_symbol": target_symbol,
        "kind": _kind_string(),
        "line": line,
    }
```

### 4.4 导出函数

```gdscript
# gds_project_result.gd 新增
func export_json(p_path: String, p_project_name: String = "") -> Error:
    var data = to_dict(p_project_name)
    var json_str = JSON.stringify(data, "  ")
    var f = FileAccess.open(p_path, FileAccess.WRITE)
    if f == null:
        return ERR_CANT_OPEN
    f.store_string(json_str)
    f.close()
    return OK
```

## 五、UI 入口

主屏 toolbar 加 "Export JSON" 按钮：

```gdscript
var export_btn = Button.new()
export_btn.text = "Export JSON"
export_btn.pressed.connect(_on_export)
toolbar.add_child(export_btn)

func _on_export() -> void:
    var dialog = FileDialog.new()
    dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
    dialog.add_filter("*.json", "JSON files")
    dialog.access = FileDialog.ACCESS_FILESYSTEM
    dialog.file_selected.connect(_on_export_path)
    EditorInterface.get_base_control().add_child(dialog)
    dialog.popup_centered()

func _on_export_path(p_path: String) -> void:
    var result = _bridge.get_project_result()
    if result:
        result.export_json(p_path)
```

## 六、交付物

| 文件 | 类型 | 说明 |
|------|------|------|
| `gds_project_result.gd` | 修改 | `to_dict()` + `export_json()` + `_build_summary()` + `_top_hubs()` + `_top_coupled()` |
| `gds_analysis_result.gd` | 修改 | `to_dict()` + `_function_to_dict()` + `_signal_to_dict()` |
| `gds_cross_file_edge.gd` | 修改 | `to_dict()` |
| `gds_graph_main_screen.gd` | 修改 | Export JSON 按钮 + FileDialog |

## 七、验收标准

- [ ] "Export JSON" 按钮导出有效 JSON 文件
- [ ] JSON 含 schema_version、summary、files、call_graph、signal_graph、cross_file
- [ ] files 内每个函数有 name/line/params/return_type/in_degree/out_degree
- [ ] hub_functions 按 total_degree 降序排列
- [ ] coupled_files 按 edge_count 降序排列
- [ ] JSON 可被 `JSON.parse()` 成功解析
- [ ] cross_file_demo 导出的 JSON ≤ 10KB
- [ ] 单文件导出也工作（无 project_result 时导 current_result）

## 八、AI agent 消费示例

```
用户: "改 take_damage 会影响谁？"
AI: 读取 codegraph.json
    → call_graph 中 callee="take_damage" → _ready 调用它
    → cross_file 中 target_symbol="take_damage" → enemy.gd 跨文件调用
    → 回答: "take_damage 被 _ready (player.gd:28) 和 attack (enemy.gd:6) 调用"
```

## 九、风险

| 风险 | 缓解 |
|------|------|
| JSON 太大（大项目） | summary 先给概览，files 按需展开；可加 `compact` 模式 |
| 函数信息提取依赖 AST 结构 | `_function_to_dict` 防御性访问（null check） |
| 导出路径权限 | 用 FileDialog 让用户选，不自动写项目目录 |
| 时间戳生成 | 用 `Time.get_datetime_string_from_system()` |
