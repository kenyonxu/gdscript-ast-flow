# tscn/tres 解析器实现计划

**SPEC:** [specs/2026-06-25-tscn-tres-parser-spec.md](../specs/2026-06-25-tscn-tres-parser-spec.md)  
**状态:** ✅ PLAN 完成（2026-06-25）  
**Codex 产出，GLM 5.2 非高峰跑**

---

## Chunk A: 数据模型（Day 1 上午，可与 Chunk B/C 并行）

### Task A1: GDSSceneResourceResult（通用容器）
**新文件:** `addons/gdscript_ast/gds_scene_resource_result.gd`

- ExtResourceInfo: id/type/path/uid
- SubResourceData: id/type/properties
- SceneNodeData: name/type/parent/script_resource/export_overrides（P1预留）
- SignalConnectionData: signal/from_node/to_node/method/flags/binds/unbinds
- GDSSceneResourceResult: root_nodes/nodes_flat/signal_connections/ext_resources/sub_resources/editable_paths/resource_type/resource_properties + to_dict()

### Task A2: GDScriptTscnParser / GDScriptTresParser 骨架
**新文件:** `addons/gdscript_ast/gds_tscn_parser.gd`, `addons/gdscript_ast/gds_tres_parser.gd`

- SectionData: kind/header_params/properties（内部中间结构）
- 注册 class_name

---

## Chunk B: TscnParser 核心（两遍扫描）

### Task B1: 六种节类型 + header 正则
`[gd_scene]`,`[ext_resource]`,`[sub_resource]`,`[node]`,`[connection]`,`[editable]`

- 节头解析：`[<kind> key1="val1"]` → 正则提取

### Task B2: 第一遍——收集 Section + ExtResource/SubResource 索引
- 识别六种节，存 SectionData 数组
- 建立 ext_resources/sub_resources 映射

### Task B3: 第二遍——node + connection + editable 解析
- `parent` 属性构建层级树
- `script = ExtResource("N")` → 关联到 ext_resources[N]

### Task B4: 信号连接解析（flags 修正）
- `[connection] signal=... from=... to=... method=... flags=4 binds=... unbinds=...`
- flags: 1=DEFERRED, 2=PERSIST, 4=ONE_SHOT, 8=REFERENCE_COUNTED

### Task B5: 节点树重建
- `nodes_flat[NodePath]` + `root_nodes` 层级树

---

## Chunk C: TresParser（P0-6）

### Task C1: 基础解析
- `[gd_resource]` type 解析
- `[resource]` 属性采集
- `[ext_resource]`/`[sub_resource]` → ext/sub 映射

---

## Chunk D: 集成

### Task D1: SCRIPT_ATTACH 边类型（P0-8）
- `CrossFileEdge.Kind` 新增 `SCRIPT_ATTACH`（末尾，向后兼容）

### Task D2: 扫描 .tscn/.tres
- `_scan_dir` 支持 `.tscn`/`.tres` 后缀
- P0 默认全扫；ScanConfig UX 为 P1

### Task D3: 场景/资源管道
- `_analyze_scene_file` → GDScriptTscnParser
- `_analyze_resource_file` → GDScriptTresParser
- `analyze_all` 按 ext 分流写入 `result.scenes`/`result.resources`

### Task D4: `_integrate_scene_resources`
**签名:** `func _integrate_scene_resources(p_project: GDScriptProjectResult)`（Codex D10：传入整个 project 以访问 class_registry/files，比 SPEC 的两个 dict 参数更简洁）

**核心逻辑:**
1. 脚本关联 D3 优先级：class_name → 直接路径 → uid(P1)
2. 生成 SCRIPT_ATTACH 跨文件边
3. 信号连接双出口：匹配信号声明+回调 → CrossFileEdge(SIGNAL_CONNECT)；否则 → scene_signal_connections

### Task D5: analyze_full 接线
- `_integrate_scene_resources` 在 `resolve_cross_file` 之后、`return result` 之前调用

---

## Chunk E: CodeGraph JSON 扩展（P0-7）

### Task E1: ProjectResult 新字段
`scenes`, `resources`, `script_associations`, `scene_signal_connections`

### Task E2: to_dict schema_version 2
- bump 版本号
- 挂载 scenes/resources/script_associations/scene_signal_connections
- _build_summary 补 scenes_analyzed/resources_analyzed

### Task E3: 向后兼容验证
- v1 消费者忽略新字段不报错
- 纯 .gd 项目 scenes/resources 为空字典

---

## Chunk F: 验收

### Task F1: 测试 fixtures
`test_scene_full.tscn`（6种节全覆盖 + script关联 + signals + editable）、`test_resource.tres`、`test_script_for_scene.gd`

### Task F2: 测试用例（6 套）
test_tscn_full / test_script_assoc / test_signals / test_tres / test_json_schema / test_script_attach

---

## 集成检查点

```
analyze_full()
 ├─ analyze_all()
 │   ├─ scan_project()           ← D2: .gd/.tscn/.tres 三桶
 │   ├─ _analyze_scene_file(.tscn) → result.scenes
 │   └─ _analyze_resource_file(.tres) → result.resources
 ├─ resolve_cross_file(result)
 └─ _integrate_scene_resources(result)   ← D4/D5
     ├─ _resolve_script_association → SCRIPT_ATTACH 边
     └─ _resolve_scene_signal → 双出口
```

## Codex 判断标记

1. **扫描集成 P0 vs P1**: Chunk D2/D3 做裸扫描+解析（P0 启用），ScanConfig UX + 增量重分析留 P1（item 13）
2. **_integrate_scene_resources 签名**: 改为 `(p_project)` 而非 SPEC 的 `(p_scene_results, p_resource_results)`——需访问 class_registry/files
3. **实现难点**: B1 的引号感知 header 正则 + 首个 `=` 切分（D2）、B5 full_path 计算
