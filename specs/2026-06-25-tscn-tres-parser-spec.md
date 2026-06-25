# .tscn / .tres 场景与资源文件解析器 设计规范

> 日期: 2026-06-25 | 状态: 设计中 | 依赖: CodeGraph JSON 导出 (已完成 ✅)、跨文件分析 Phase 3.2 (已完成 ✅)

## 一、动机

### 1.1 现状痛点

gdscript-ast-flow 目前仅分析 `.gd` 源文件——能回答"代码怎么写的"，但无法回答"代码怎么被用的"。

**当前无法回答的关键问题：**
- "哪个场景实例化了 `Player` 类？`Player.tscn` 里填了哪些 `@export` 槽的值？"
- "`enemy.tscn` 引用了哪个脚本？它的 `speed` 导出变量被设置成了多少？"
- "场景树的节点挂载关系——`Player` 节点下有哪些子节点？`Camera2D` 是谁的子节点？"
- "`button_pressed` 信号在场景里连接到了哪个节点的哪个方法？"
- "`.tres` 资源文件（如 `player_stats.tres`）里的属性值是什么？子资源引用链怎么走？"
- "一个 AI agent 能不能从 CodeGraph JSON 里直接知道：所有场景中哪些节点用了 `Player.gd`，填了什么参数？"

**场景 → 脚本 的关联是 Godot 项目的脊梁骨**，缺乏这层信息，CodeGraph 就只能描述代码，无法描述"项目配置"。

### 1.2 目标

为 `gdscript-ast-flow` 新增 **Godot 4.x `.tscn`（场景）和 `.tres`（资源）文件解析器**，实现：

1. **`.tscn` 解析**：提取节点树（父子层级、node type、node name）、信号连接、脚本关联、`@export` 槽填充值
2. **`.tres` 解析**：提取资源类型、属性值、子资源引用链（`SubResource`）
3. **与现有 AST 管线集成**：通过 `class_name` / 资源路径将 `.tscn`/`.tres` 中的引用与已解析的 `.gd` 文件关联
4. **CodeGraph JSON 扩展**：输出格式兼容或扩展现有 CodeGraph JSON Schema

### 1.3 核心价值：AI 可消费的项目全貌

将 CodeGraph 从"纯代码图"升级为"代码 + 配置 + 场景结构"三位一体的项目知识图谱。AI agent 可以：

```
用户: "Player 的 max_health 初始值是多少？"
AI: 查 CodeGraph JSON
    → scenes 中 player.tscn 节点 Player 的导出变量 max_health = 100
    → player_stats.tres 的资源属性 max_health = 100
    → 回答: "Player 在 player.tscn 中将 max_health 导出为 100"
```

## 二、范围

### P0（核心——必须做，阻塞后续集成）

| # | 项 | 说明 |
|---|----|------|
| 1 | **`.tscn` INI-like 节解析** | 解析 `[gd_scene]`、`[ext_resource]`、`[sub_resource]`、`[node]`、`[connection]`、`[editable]` 六种节点类型 |
| 2 | **`ExtResource` / `SubResource` 引用追踪** | 解析 `ExtResource("id")` 和 `SubResource("id")` 的 ID → 实际资源映射链 |
| 3 | **节点树重建** | 从 `parent` 属性重建完整节点树（父子层级、node name、node type） |
| 4 | **脚本关联提取** | 识别 `script = ExtResource("1_script")` 并按 `ext_resource` 的 `path` 属性关联到具体 `.gd` 文件 |
| 5 | **信号连接提取** | 解析 `[connection]` 节：`signal`、`from`（发射节点）、`to`（接收节点）、`method`（回调方法） |
| 6 | **`.tres` 基础解析** | 解析 `[gd_resource]` + `[ext_resource]` + `[resource]` 三节，提取资源类型和属性键值对 |
| 7 | **CodeGraph JSON 扩展** | `to_dict()` 新增 `scenes` / `resources` 字段，与现有 schema 兼容 |
| 8 | **跨文件边：SCRIPT_ATTACH** | 新增 `GDSCrossFileEdge.Kind.SCRIPT_ATTACH`，记录 `.tscn`/`.tres` 关联到哪个脚本 / 子场景——这是查询层回答"哪些场景用了 Player.gd"的基础，必须在 P0 落边 |

### P1（高价值——P0 之后）

| # | 项 | 说明 |
|---|----|------|
| 9 | **`@export` 槽填充值解析** | 解析节点在场景中重写的 `@export var` 值，关联到脚本变量定义 |
| 10 | **子资源内联解析** | `.tscn` 中的 `[sub_resource]` 完整解析——不只是引用，还解析内部属性（如 `RectangleShape2D` 的 `size`） |
| 11 | **`[editable]` 节解析** | 场景实例化后允许覆盖的子节点路径列表 |
| 12 | **`.tres` 子资源链追踪** | `.tres` 内的 `SubResource` 引用链完整展开 |
| 13 | **项目扫描集成** | `GDScriptProjectAnalyzer` 增加对 `.tscn`/`.tres` 文件的扫描和分析 |
| 14 | **UID 引用解析** | 支持 `uid://...` 格式（Godot 4.4+）——现代 Godot `ext_resource` 常以 `uid=` 为主标识、`path=` 可能缺失，必须 P1 支持 |

### P2（锦上添花——后续迭代）

| # | 项 | 说明 |
|---|----|------|
| 15 | **嵌套场景实例化追踪** | `PackedScene` 类型子场景（`ExtResource` 指向另一个 `.tscn`）的递归展开 |
| 16 | **资源属性类型推断** | `Vector2(100, 200)` → `{type: "Vector2", x: 100, y: 200}` 结构化解析 |
| 17 | **编辑器集成——场景树面板** | 底部面板新增 "Scenes" tab，可视化节点树 + 脚本关联 |

### 不做（明确边界）

- ❌ **`.gdc` 字节码解析** — 不在范围内（本项目专门针对源码文本格式）
- ❌ **运行时场景序列化/反序列化** — 不做 `pack()` / `instantiate()`，纯静态分析
- ❌ **`.tres` / `.tscn` 文件写回** — 只读不写，不修改用户文件
- ❌ **Godot 3.x `.tscn` 格式** — 仅支持 Godot 4.x `format=3`
- ❌ **二进制资源文件**（`.res`, `.scn`）— 不做二进制解析
- ❌ **`.tscn` 内部的完整 GDScript 调用图** — `.tscn` 里的连接/槽已是结构化数据，不涉及代码逻辑分析，扩展在 AST 管线侧完成

## 三、文件格式协议分析

### 3.1 Godot 4.x `.tscn` 格式

Godot 4.x 场景文件采用**类 INI 文本格式**，包含 6 种节类型：

```
[gd_scene load_steps=<int> format=3 uid="uid://<unique_id>"]
  ↑ 文件头——加载步数、格式版本、唯一 ID

[ext_resource type="<ResourceType>" path="res://path/to/file" id="<id>"]
[ext_resource type="Script" uid="uid://<uid>" path="res://path.gd" id="1_script"]
  ↑ 外部资源声明——type（资源类型）、path（文件路径）、id（引用标识符）
  ↑ 可能包含 uid 作为替代定位方式（Godot 4.4+）

[sub_resource type="<ResourceType>" id="<id>"]
<property> = <value>
[sub_resource type="RectangleShape2D" id="1_shape"]
size = Vector2(32, 32)
  ↑ 内联子资源——完整定义的资源对象，在场景内唯一

[node name="<NodeName>" type="<NodeType>" parent="<NodePath>"]
[node name="Player" type="CharacterBody2D" parent="."]
[node name="Sprite" type="Sprite2D" parent="Player"]
[node name="Camera" type="Camera2D" parent="." groups=["player_cameras"]]
  ↑ 节点声明——name、type、parent（NodePath 相对路径）
  ↑ "." = 根节点的父节点
  ↑ 可能包含 groups 等附加属性

  节点内可嵌属性:
  position = Vector2(100, 200)
  script = ExtResource("1_script")       ← 场景→脚本关联（核心）
  texture = ExtResource("2_tex")         ← 属性引用外部资源
  shape = SubResource("1_shape")         ← 属性引用内联子资源
  visible = false                         ← 简单属性值
  collision_layer = 1                     ← 位掩码
  metadata/_edit_lock_ = true             ← 编辑器元数据

[connection signal="<signal>" from="<NodePath>" to="<NodePath>" method="<method>"]
[connection signal="pressed" from="Button" to="." method="_on_button_pressed"]
[connection signal="health_changed" from="Player" to="UI/HealthBar" method="_on_health_changed"]
  ↑ 信号连接——signal（信号名）、from（发射节点相对路径）、to（接收节点相对路径）、method（回调）

  Godot 4.x 连接的可选字段:
  flags = <int>                           ← 连接标志位（Godot 4 Object.ConnectFlags: 1=DEFERRED, 2=PERSIST, 4=ONE_SHOT, 8=REFERENCE_COUNTED）
  binds = Array[Variant](...)            ← 绑定参数（bind() 的预设参数）
  unbinds = <int>                         ← 解绑参数数

[editable path="<NodePath>"]
[editable path="SubScene/Child"]
  ↑ 可编辑子节点——场景实例化后标记为可在父场景中覆盖的节点路径
```

**关键格式约定：**
- 键值格式：`key = value`（注意空格）
- 资源引用：`ExtResource("id")` 或 `SubResource("id")`，括号内是引用 ID 字符串
- 路径：`NodePath` 相对路径，如 `"."`、`"Player"`、`"UI/HealthBar"`
- UID 格式：`"uid://base64string"`（Godot 4.4+ 引入，作为 path 的替代定位符）
- 多行属性：不支持——每个属性一行
- Variant 类型字面量：`Vector2(x, y)`、`Color(r, g, b, a)`、`Array[...]`、`Dictionary{...}`、`NodePath("...")` 等使用 Godot 构造函数语法

### 3.2 Godot 4.x `.tres` 格式

资源文件格式更简单，只包含 2~3 种节：

```
[gd_resource type="<ResourceType>" load_steps=<int> format=3 uid="uid://<uid>"]
  ↑ 文件头——资源类型（如 "Theme", "Material", "AudioStream" 等）

[ext_resource type="Script" path="res://path.gd" id="1_script"]
  ↑ （可选）外部资源引用（如脚本）

[resource]
<property> = <value>
<property> = ExtResource("1")
<property> = SubResource("id")
  ↑ 主资源体——资源类型定义在 [gd_resource] 的 type 字段中

[sub_resource type="<Type>" id="<id>"]
<property> = <value>
  ↑ （可选）内联子资源定义
```

**与 `.tscn` 的核心区别：**
- `.tres` 没有节点树——只有资源属性
- `.tres` 的 `[resource]` 对应 `.tscn` 的 `[node]`（但本质是资源而非节点）
- `.tres` 没有 `[connection]` / `[editable]` 节
- `.tres` 的 `[sub_resource]` 语义相同

### 3.3 解析策略

采用**两遍扫描**：

**第一遍（节收集）：** 扫描全文件，将文本按 `[...]` 节头和后续属性行分组为 `Section` 对象。

```
Section { header: "[node name=\"Player\" type=\"CharacterBody2D\"]", 
          props: ["position = Vector2(100, 200)", "script = ExtResource(\"1_script\")"] }
```

**第二遍（语义解析）：** 
1. 解析 `[ext_resource]` → 建 ID → 外部资源映射表
2. 解析 `[sub_resource]` → 建 ID → 内联资源映射表  
3. 解析 `[node]` → 按 `parent` 重建节点树，解析 `ExtResource()` / `SubResource()` 引用到实际资源
4. 解析 `[connection]` → 按 from/to 关联到具体节点

**引用解析管线：**
```
ExtResource("1_script")
    ↓ ext_resource 节解析器
{type: "Script", path: "res://player.gd", id: "1_script"}
    ↓ 节点解析器（script = ExtResource("1_script")）
节点 → 关联脚本资源路径 "res://player.gd"
    ↓ 与 AST 管线对齐
通过 class_registry / file path 关联到 GDScriptAnalysisResult
```

## 四、架构设计

### 4.1 新增文件

```
addons/gdscript_ast/
├── gds_tscn_parser.gd          # [新增] .tscn 解析器 (class_name: GDScriptTscnParser)
├── gds_tres_parser.gd          # [新增] .tres 解析器 (class_name: GDScriptTresParser)
├── gds_scene_resource_result.gd # [新增] 场景/资源分析结果容器 (class_name: GDSSceneResourceResult)
```
> **集成层不独立成类**：`GDSIntegration` 不作为独立文件/类——关联逻辑直接内置于 `GDScriptProjectAnalyzer` 中（`_integrate_scene_resources()` 私有方法），避免引入不必要的抽象层。

### 4.2 GDScriptTscnParser — .tscn 解析器

```gdscript
class_name GDScriptTscnParser
extends RefCounted

# ---- 输入/输出 ----
var file_path: String = ""
var error: String = ""

# ---- 内部状态 ----
var _ext_resources: Dictionary = {}   # String(id) → {type: String, path: String, uid: String}
var _sub_resources: Dictionary = {}   # String(id) → SubResourceData
var _nodes: Dictionary = {}           # String(path) → SceneNodeData
var _connections: Array = []          # of SignalConnectionData

# ---- 公开 API ----
func parse(p_path: String) -> GDSSceneResourceResult
func parse_text(p_text: String, p_virtual_path: String) -> GDSSceneResourceResult

# ---- 内部方法 ----
func _read_sections(p_text: String) -> Array[Section]
func _parse_ext_resource(p_section: Section) -> void
func _parse_sub_resource(p_section: Section) -> void
func _parse_node(p_section: Section) -> void
func _parse_connection(p_section: Section) -> void
func _build_node_tree() -> Dictionary    # 按 parent 引用重建树
func _resolve_refs(p_value: String)      # ExtResource("id") / SubResource("id") → 实际资源
```

### 4.3 SceneNodeData — 场景节点

```gdscript
class_name SceneNodeData
extends RefCounted

var name: String = ""               # 节点名称（如 "Player"）
var type: String = ""               # 节点类型（如 "CharacterBody2D"）
var parent_path: String = ""        # 父节点 NodePath（如 "." 或 "Player"）
var children: Array[SceneNodeData] = []  # 子节点列表
var groups: Array[String] = []      # 节点所属 group

# 属性
var properties: Dictionary = {}     # String(属性名) → Variant 值
var script_resource: String = ""    # 关联脚本资源路径（如 "res://player.gd"），解析后填充
var export_overrides: Dictionary = {}  # String(变量名) → 填充值（P1）

# ExtResource/SubResource 引用
var ext_refs: Dictionary = {}       # String(属性名) → ExtResourceInfo
var sub_refs: Dictionary = {}       # String(属性名) → SubResourceData
```

### 4.4 GDSSceneResourceResult — 统一结果容器

```gdscript
class_name GDSSceneResourceResult
extends RefCounted

var file_path: String = ""          # 源文件路径
var file_type: int = TYPE_UNKNOWN   # TSCN / TRES
enum FileType { TSCN, TRES }

# .tscn 专属
var scene_uid: String = ""
var load_steps: int = 0
var root_nodes: Array[SceneNodeData] = []   # 顶层节点列表
var nodes_flat: Dictionary = {}             # String(NodePath) → SceneNodeData（平铺）
var signal_connections: Array[SignalConnectionData] = []  # 所有信号连接
var editable_paths: Array[String] = []    # 可编辑子节点路径

# .tres 专属
var resource_type: String = ""
var resource_properties: Dictionary = {}   # 主资源属性
var sub_resources: Dictionary = {}         # String(id) → SubResourceData

# 通用
var ext_resources: Dictionary = {}         # String(id) → ExtResourceInfo
var errors: Array[String] = []
var script_associations: Array[String] = []  # 关联的 .gd 文件路径列表

# ---- 查询 API ----
func get_nodes_by_type(p_type: String) -> Array[SceneNodeData]
func get_nodes_by_script(p_script_path: String) -> Array[SceneNodeData]
func get_node_by_path(p_path: String) -> SceneNodeData
func get_connections_for_node(p_node_path: String) -> Array[SignalConnectionData]
func get_connections_for_signal(p_signal_name: String) -> Array[SignalConnectionData]

# ---- 序列化 ----
func to_dict() -> Dictionary
```

### 4.5 数据结构

```gdscript
# 节——解析中间产物
class SectionData:
    var header: String            # 原始节头（如 "[node name=\"Player\" type=\"Node2D\"]"）
    var kind: int                 # SectionKind { GD_SCENE, EXT_RESOURCE, SUB_RESOURCE, NODE, CONNECTION, EDITABLE, GD_RESOURCE, RESOURCE }
    var header_params: Dictionary # 节头解析出的键值对（如 {name: "Player", type: "Node2D", parent: "."}）
    var properties: Array         # 属性行数组 ["key = value", ...]
    var start_line: int           # 节起始行号
    var end_line: int             # 节结束行号

# 外部资源引用
class ExtResourceInfo:
    var id: String = ""           # 引用 ID（如 "1_script"）
    var type: String = ""         # 资源类型（如 "Script", "Texture2D", "PackedScene"）
    var path: String = ""         # 文件路径（如 "res://player.gd"）
    var uid: String = ""          # UID（Godot 4.4+，如 "uid://abc123"）

# 子资源数据
class SubResourceData:
    var id: String = ""
    var type: String = ""
    var properties: Dictionary = {}  # 完整属性键值对
    var refs: Dictionary = {}        # 对其他 SubResource 的引用

# 信号连接数据
class SignalConnectionData:
    var signal_name: String = ""  # 信号名（如 "pressed", "health_changed"）
    var from_node: String = ""    # 发射节点 NodePath（相对路径）
    var to_node: String = ""      # 接收节点 NodePath（相对路径）
    var method: String = ""       # 回调方法名
    var flags: int = 0            # 连接标志位
    var binds: Array = []         # 绑定参数
    var unbinds: int = 0          # 解绑参数数
```

### 4.6 GDScriptTresParser

```gdscript
class_name GDScriptTresParser
extends RefCounted

# .tres 解析器——比 .tscn 简单得多
# 结构： [gd_resource] + [ext_resource]* + [resource] + [sub_resource]*
# 无节点树、无信号连接、无 editable 节

func parse(p_path: String) -> GDSSceneResourceResult
```

## 五、与现有 AST 管线的集成

### 5.1 集成点总览

```
┌──────────────────────────────────────────────────────────────┐
│                     GDScriptProjectAnalyzer                   │
│  analyze_full() — 项目级分析入口                              │
│                                                               │
│  现有流程:                                                     │
│    scan .gd → 单文件管道 → class_registry → cross_file        │
│                                                               │
│  扩展后流程:                                                   │
│    scan .gd + .tscn + .tres                                   │
│    ├─ .gd → Tokenizer → Parser → SymbolResolver → Result      │
│    ├─ .tscn → TscnParser → SceneResourceResult                │
│    └─ .tres → TresParser → SceneResourceResult                │
│    ↓                                                          │
│    GDScriptProjectAnalyzer._integrate_scene_resources()       │
│    ├─ script_associations ← class_registry / res path        │
│    ├─ scene_script_edges ← CrossFileEdge(SCRIPT_ATTACH)       │
│    └─ signal_connections ← CrossFileEdge(SIGNAL_CONNECT)     │
│         + scene_signal_connections 字段（不修改 signal_graph）│
│    ↓                                                          │
│    GDScriptProjectResult (扩展)                               │
│    ├─ files: {.gd → AnalysisResult}          [现有]          │
│    ├─ scenes: {.tscn → SceneResourceResult}  [新增]          │
│    └─ resources: {.tres → SceneResourceResult} [新增]        │
└──────────────────────────────────────────────────────────────┘
```

### 5.2 集成逻辑 — 内置于 GDScriptProjectAnalyzer

集成逻辑不独立成类，作为 `GDScriptProjectAnalyzer` 的私有方法实现：

```gdscript
# GDScriptProjectAnalyzer 新增私有方法

func _integrate_scene_resources(
    p_scene_results: Dictionary,    # String(path) → GDSSceneResourceResult
    p_resource_results: Dictionary  # String(path) → GDSSceneResourceResult
) -> void:
    # 1. 建立 script_associations
    #    对每个 scene_result，遍历所有节点：
    #      if node.script_resource != "":
    #        通过 class_registry 或路径匹配关联到 AnalysisResult

    # 2. 建立 scene→script 跨文件边 (SCRIPT_ATTACH)
    #    for each scene × script association:
    #      CrossFileEdge(SCRIPT_ATTACH, source=tscn_path, target=gd_path)

    # 3. 信号连接 → CrossFileEdge(SIGNAL_CONNECT) + scene_signal_connections
    #    不修改单文件 signal_graph（避免污染单文件模型纯度）
    #    for each SignalConnectionData:
    #      尝试匹配 from/to 脚本中的信号声明和回调方法
    #      生成 CrossFileEdge(SIGNAL_CONNECT)
    #      无法匹配的写入 scene_signal_connections 字段

    # 4. @export 变量覆盖与 DefUseChain 对齐（P1）
    #    匹配节点 export_overrides 到脚本变量定义
```

### 5.3 关联策略

**脚本关联（`node.script_resource` → `.gd` 文件）的解析优先级：**

1. **`class_name` 匹配** — `script = ExtResource("1_script")` 解析到的脚本有 `class_name`，用 `class_registry` 关联
2. **文件路径匹配** — `ext_resource.path` 直接指向 `.gd` 文件路径，匹配 `ProjectResult.files` 的 key
3. **UID 匹配** — `ext_resource.uid` 作为备选关联路径（Godot 4.4+ P1）

**信号连接关联：**

场景信号连接**不修改**单文件 `signal_graph`——回灌会污染单文件模型的纯度。场景连接只走两个出口：

1. **跨文件边** `CrossFileEdge(SIGNAL_CONNECT)` — from_node 所属脚本 → to_node 所属脚本/方法
2. **`scene_signal_connections` 字段** — 在 CodeGraph JSON 顶层记录完整的跨场景信号连接

```
.tscn connection: signal="health_changed" from="Player" to="UI" method="_on_health_changed"
    ↓
Player 节点 → 关联脚本 → AnalysisResult.signal_graph 中有 "health_changed" 声明？
    ↓ YES: 生成 CrossFileEdge(SIGNAL_CONNECT, source=from_script, target=to_script, meta={signal, method, scene})
    ↓ NO:  记录到 scene_signal_connections（from_script 可能尚未解析或信号为内置信号如 "pressed"）
UI 节点 → 关联脚本 → AnalysisResult 有 _on_health_changed() 方法？
    ↓ YES: 同上——CrossFileEdge target 可精确到方法
    ↓ NO:  记录到 scene_signal_connections（回调方法可能定义在未解析的脚本中）
```

### 5.4 CodeGraph JSON 扩展

在 `GDScriptProjectResult.to_dict()` 中新增字段：

```json
{
  "schema_version": 2,              // 从 1 → 2，标注新增字段
  "scenes": {
    "res://scenes/player.tscn": {
      "file_type": "TSCN",
      "uid": "uid://player_scene_001",
      "load_steps": 5,
      "root_nodes": [...],
      "node_tree": {                    // 按 parent 引用的完整树
        "name": "Player",
        "type": "CharacterBody2D",
        "script": "res://player.gd",    // 关联脚本路径
        "script_class": "Player",       // 若脚本有 class_name 则填充
        "export_overrides": {           // @export 槽填充值（P1）
          "max_health": 100,
          "speed": 400.0
        },
        "children": [
          {
            "name": "Sprite",
            "type": "Sprite2D",
            "properties": {
              "texture": "ExtResource(\"2_tex\") → res://assets/player.png"
            }
          }
        ]
      },
      "signal_connections": [
        {
          "signal": "pressed",
          "from_node": ".",
          "from_script": "res://ui/button.gd",
          "to_node": ".",
          "to_script": "res://player.gd",
          "method": "_on_button_pressed",
          "flags": 0
        }
      ]
    }
  },
  "resources": {
    "res://resources/player_stats.tres": {
      "file_type": "TRES",
      "resource_type": "Resource",
      "script": "res://player_stats.gd",
      "properties": {
        "max_health": 100,
        "max_mana": 50
      },
      "sub_resources": {
        "1_buff": {
          "type": "Resource",
          "properties": { "name": "FireResist", "value": 0.3 }
        }
      }
    }
  },
  "script_associations": [            // 场景 ↔ 脚本 关联索引
    {
      "scene": "res://scenes/player.tscn",
      "node": "Player",
      "script": "res://player.gd",
      "script_class": "Player"
    }
  ],
  "scene_signal_connections": [       // 跨场景-脚本信号边
    {
      "signal": "health_changed",
      "from_scene": "res://scenes/player.tscn",
      "from_node": "Player",
      "to_scene": "res://scenes/ui.tscn",
      "to_node": "HealthBar",
      "to_method": "_on_health_changed"
    }
  ]
}
```

**向后兼容策略：**
- `schema_version` 从 1 → 2，标注新增字段
- 旧字段（`files` 字典，每文件内含 `call_graph`/`signal_graph` 等）结构不变，消费端无需修改解析逻辑
- 新字段（`scenes`、`resources`、`script_associations`、`scene_signal_connections`）为可选——没有 `.tscn`/`.tres` 的项目不出现在 JSON 中
- 不使用 `export_json_v2()` 之类的多方法分叉——`to_dict()` 始终输出最新 schema，消费端通过 `schema_version` 区分；项目根 `project_result.gd` 的 `export_json()` 调用 `to_dict()` 后 `JSON.stringify()`，字段新增不破坏旧消费者

### 5.5 扫描配置复用

复用 `GDSScanConfig` 的 include/exclude 机制：
- 默认扫描 `include` 目录下的 `.gd`、`.tscn`、`.tres` 文件
- 用户可通过 "Scan Settings" 对话框控制

## 六、实现计划

### 6.1 交付物

| 文件 | 类型 | 说明 |
|------|------|------|
| `gds_tscn_parser.gd` | 新增 | `.tscn` 解析器——核心组件 |
| `gds_tres_parser.gd` | 新增 | `.tres` 解析器 |
| `gds_scene_resource_result.gd` | 新增 | 统一结果容器 + `to_dict()` |
| `gds_project_analyzer.gd` | 修改 | 扫描增加 `.tscn`/`.tres` + 内置 `_integrate_scene_resources()` 集成逻辑（不另建 `gds_integration.gd`） |
| `gds_project_result.gd` | 修改 | `to_dict()` 扩展（`scenes`/`resources`/`script_associations`/`scene_signal_connections`），单方法 + `schema_version` |
| `gds_cross_file_edge.gd` | 修改 | 新增 `Kind.SCRIPT_ATTACH` |

### 6.2 实现顺序

1. **Step 1**: `gds_scene_resource_result.gd` — 数据结构定义（`SceneNodeData`, `ExtResourceInfo`, `SubResourceData`, `SignalConnectionData`, `GDSSceneResourceResult`）
2. **Step 2**: `gds_tscn_parser.gd` — `.tscn` 节解析 + 节点树重建 + 引用追踪
3. **Step 3**: `gds_tres_parser.gd` — `.tres` 基础解析
4. **Step 4**: 修改 `gds_project_analyzer.gd` — 扫描增加 `.tscn`/`.tres` + 内置 `_integrate_scene_resources()` 集成逻辑
5. **Step 5**: 修改 `gds_project_result.gd` / `gds_cross_file_edge.gd` — CodeGraph JSON 扩展 + `SCRIPT_ATTACH` 边
6. **Step 6**: 测试文件 `tests/test_tscn_tres_parser.gd` + 测试场景

### 6.3 测试数据

需要在 `tests/` 下创建：
- `test_scene_full.tscn` — 覆盖所有 6 种节点类型的场景文件
- `test_scene_simple.tscn` — 最小场景（单节点）
- `test_resource.tres` — 含子资源的资源文件
- `test_scene_signals.tscn` — 覆盖各种信号连接模式的场景
- `test_script_for_scene.gd` — 被场景引用的伴生测试脚本

## 七、风险与缓解

| 风险 | 级别 | 缓解 |
|------|------|------|
| **Variant 值解析不完备** — Godot Variant 类型众多（Vector2/3/4, Color, Rect2, Transform2D/3D, AABB, Basis, Plane, Projection, Quaternion, 各种数组/字典嵌套），逐个解析工作量大 | 中 | P0 先做字符串透传（存原始值字符串），P1 再做结构化解析常用类型（Vector2, Color, Rect2, NodePath） |
| **节点路径引用复杂性** — `parent` 属性的 NodePath 可能是 `"."`（根）、`"NodeName"`（直接子节点）、`"../Sibling"`（相对路径），需正确解析 | 低 | 建 `nodes_flat` 字典（NodePath → SceneNodePath），用 Godot 引擎内置 `NodePath` 类辅助标准化 |
| **ExtResource ID 格式变化** — Godot 4.4+ 引入 `uid://` 格式替代/补充 `id`，解析器需兼容两种格式；现代 Godot `ext_resource` 常以 `uid=` 为主标识、`path=` 可能缺失 | 中 | P0 支持 `id="1_script"` 格式 + `path` 解析；P1 支持 `uid://` 格式（通过 `ResourceUID` 类解析，包括 uid-only 无 path 的场景） |
| **大文件性能** — 大型 `.tscn` 可能数万行（UI 场景尤甚），递归解析和字典查表需优化 | 低 | 两遍扫描已是线性；`nodes_flat` 用 Dictionary 查找 O(1)；先不做异步（YAGNI），后续按需加 `WorkerThread` |
| **与 Godot 未来格式变更的兼容性** | 中 | 写死 `format=3` 检查（不对 format=2 做兼容）；通过 `schema_version` 字段让消费端感知格式变化 |
| **属性值含 `=` 号导致 `split(" = ")` 解析错误** — NodePath（如 `NodePath("../Enemy=Target")`）、字符串值可能含 `=` | 中 | 只用第一个 `=` 做分割（`split(" = ", true, 1)`，Godot 的 `String.split(limit=1)`），余下部分整体作为值；或在节属性解析层先识别键后取余 |
| **转义引号 `\"` 在属性值中出现** — 字符串值可能含转义双引号，简单引号配对解析会截断 | 低 | 节属性解析时做引号感知的边界识别，处理 `\"` 转义 |
| **CRLF / BOM 格式问题** — Windows 用户或编辑器可能引入 `\r\n` 换行或 UTF-8 BOM | 低 | 解析前统一规范化换行符（`\r\n` → `\n`）并去除 BOM（`﻿`） |
| **SubResource 互引用环** — SubResource A 引用 SubResource B，B 又引用 A，展开时可能无限递归 | 中 | 子资源展开时维护 visited set，遇环时记为循环引用 `{"$circular_ref": "id"}` 而非递归展开 |
| **代码与场景重复连接去重** — 脚本中用 `connect()` 已建立的连接，在 `.tscn` 中又被信号连接节再次声明（Godot 编辑器自动序列化所有连接） | 低 | 不在此层去重——CodeGraph JSON 消费者自行判断；解析器如实记录所有信号连接 |

## 八、验收标准

### P0 验收

- [ ] 解析 `test_scene_full.tscn`（含所有 6 种节点类型），不报错、不漏节
- [ ] `scene_result.root_nodes` 正确重建节点树（父子层级无误）
- [ ] `scene_result.signal_connections` 列出所有信号连接（含 flags/binds）
- [ ] `node.script_resource` 正确关联到 `.gd` 文件路径
- [ ] `ExtResource("id")` → `ext_resource` 节映射正确
- [ ] `SubResource("id")` → `sub_resource` 节映射正确
- [ ] 解析 `test_resource.tres`，提取资源类型和属性
- [ ] `to_dict()` 输出的 JSON 含 `scenes` / `resources` 字段
- [ ] `schema_version: 2` 正确标注
- [ ] `CrossFileEdge(SCRIPT_ATTACH)` 记录场景→脚本关联（跨文件边落库，查询层可查"哪些场景用了 X.gd"）
- [ ] 旧 `to_dict()` / `export_json()` 不受影响（向后兼容）

### P1 验收

- [ ] 节点 `export_overrides` 提取 `@export` 变量值
- [ ] 子资源属性完整解析（不只 ID，还有内部属性）
- [ ] `[editable]` 路径列表正确提取
- [ ] `.tres` 子资源链完整展开
- [ ] `GDScriptProjectAnalyzer.analyze_full()` 输出含 `.tscn`/`.tres` 结果
- [ ] `uid://` 格式 `ext_resource` 正确解析（包括 uid-only 无 path 的场景）

### P2 验收

- [ ] 嵌套场景实例化的 `PackedScene` 引用链正确展开
- [ ] Vector2/Color/Rect2 等 Variant 类型结构化解析（而非字符串透传）

---

## 附录 A：Godot 4.x `.tscn` 完整格式参考

```
# 节类型枚举
[gd_scene]          — 文件头（仅一次，第一行）
[ext_resource]      — 外部资源声明（0~N 次，通常在 [gd_scene] 之后）
[sub_resource]      — 内联子资源定义（0~N 次，散列在 [ext_resource] 和 [node] 之间）
[node]              — 节点定义（1~N 次，节点树的核心）
[connection]        — 信号连接（0~N 次，通常在所有 [node] 之后）
[editable]          — 可编辑子节点标记（0~N 次，在 [connection] 之后或之前）

# 节头参数解析规则
[node name="Player" type="CharacterBody2D" parent="."]
  ↑ 双引号字符串值，空格分隔键值对
  ↑ name: 节点名称（不含路径）
  ↑ type: Godot 内置类名或自定义类名（若有 script + class_name）
  ↑ parent: 相对于场景根节点的 NodePath

# 属性值格式规则
key = value                              # 简单值（数字、布尔、字符串）
key = ExtResource("id")                  # 外部资源引用
key = SubResource("id")                  # 子资源引用
key = Array[Type]([elem1, elem2, ...])   # 数组
key = Object(Type, "res_path", ...)      # 内联对象
key = NodePath("relative/path")          # 节点路径
key = null                               # 空值
```

## 附录 B：设计决策记录

### B.1 为什么要两遍扫描而非逐行即时解析？

因为 `[node]` 中对 `ExtResource("1")` 的引用可能在文件中靠前，而 `[ext_resource id="1"]` 的声明在更后面。Godot 写 `.tscn` 时通常按 `ext_resource → sub_resource → node → connection → editable` 顺序，但不保证（手工编辑可能乱序）。两遍扫描有轻微内存代价（存 Section 数组），但保证引用解析的健壮性。

### B.2 为什么 `GDScriptTscnParser` 和 `GDScriptTresParser` 分两个文件？

`.tscn` 和 `.tres` 格式差异足够大——前者有节点树/信号连接/editable、后者没有。共用一个文件会导致大量 `if file_type == TSCN` 分支，降低可维护性。但共享的数据结构（`ExtResourceInfo`, `SubResourceData`, `GDSSceneResourceResult`）放在 `gds_scene_resource_result.gd` 中。

### B.3 为什么不用 Godot 内置的 `ResourceLoader.load()` 解析？

`ResourceLoader.load()` 会触发完整的资源加载管线——解析 → 实例化 → `_ready()`/`_init()` 调用 → 可能触发编辑器插件副作用。我们的需求是**静态分析**，不需要运行时实例化和脚本执行。纯文本解析可以完全避免副作用，且不受"脚本有语法错误则加载失败"的困扰。

### B.4 CodeGraph schema_version 为何从 1 → 2？

`files`/`call_graph`/`signal_graph`/`cross_file` 字段结构不变，版本号从 1 → 2 仅表示 JSON 顶层新增了 `scenes`、`resources`、`script_associations`、`scene_signal_connections` 四个可选字段。消费端可通过 `schema_version >= 2` 来安全读取新字段。
