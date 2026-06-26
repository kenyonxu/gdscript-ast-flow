# GDScript AST Flow — 开发者指南

> 适用版本: Godot 4.7+ | 语言: 中文

## 目录

### API 参考
1. [架构概览](#api-1-架构概览)
2. [GDScriptTokenizer](#api-2-gdscripttokenizer)
3. [GDScriptParser](#api-3-gdscriptparser)
4. [GDScriptSymbolResolver](#api-4-gdscriptsymbolresolver)
5. [GDScriptAnalysisResult](#api-5-gdscriptanalysisresult)
6. [GDScriptCallGraph / GDScriptCallEdge](#api-6-gdscriptcallgraph--gdscriptcalledge)
7. [GDScriptSignalGraph / GDScriptSignalInfo / GDScriptSite](#api-7-gdscriptsignalgraph--gdscriptsignalinfo--gdscriptsite)
8. [GDScriptDefUseChain / GDScriptDefUseInfo / GDScriptDefUseSite](#api-8-gdscriptdefusechain--gdscriptdefuseinfo--gdscriptdefusesite)
9. [GDScriptProjectAnalyzer](#api-9-gdscriptprojectanalyzer)
10. [GDScriptProjectResult / GDSCrossFileEdge](#api-10-gdscriptprojectresult--gdscrossfileedge)
11. [GDSScanConfig](#api-11-gdsscanconfig)
12. [GDScriptUtil (plugin.gd)](#api-12-gdscriptutil-plugingd)
13. [GDSL10n](#api-13-gdsl10n)

### 集成指南
14. [集成模式](#integration-1-集成概览)
15. [模式 1：分析单个脚本](#integration-2-模式-1分析单个脚本)
16. [模式 2：批量分析项目](#integration-3-模式-2批量分析项目)
17. [模式 3：消费 CodeGraph JSON](#integration-4-模式-3消费-codegraph-json)
18. [模式 4：扩展分析管道](#integration-5-模式-4扩展分析管道)
19. [案例：可视化编程插件](#integration-6-案例可视化编程插件)
20. [案例：文档生成器](#integration-7-案例文档生成器)
21. [最佳实践](#integration-8-最佳实践)

---

# API 参考

## API 1. 架构概览

```
.gd 源码
  → GDScriptTokenizer.tokenize(source) → Array[Token]
  → GDScriptParser.parse(tokens) → ASTNode
  → GDScriptSymbolResolver.resolve(ast, file_path) → GDScriptAnalysisResult
       ├── symbol_table: GDScriptSymbolTable
       ├── call_graph: GDScriptCallGraph
       ├── signal_graph: GDScriptSignalGraph
       ├── def_use_chain: GDScriptDefUseChain
       ├── type_table: Dictionary
       └── errors: Array[String]

项目级:
  → GDScriptProjectAnalyzer.scan_project() → Array[String] (文件路径列表)
  → GDScriptProjectAnalyzer.analyze_full() → GDScriptProjectResult
       ├── files: Dictionary[String, GDScriptAnalysisResult]
       ├── class_registry: Dictionary[String, String]
       ├── cross_edges: Array[GDSCrossFileEdge]
       └── reverse_index: Dictionary
```

## API 2. GDScriptTokenizer

**文件**: `addons/gdscript_ast/gds_tokenizer.gd`
**class_name**: `GDScriptTokenizer`

```
func tokenize(source: String) -> Array[GDScriptToken]
```

词法分析器。将 GDScript 源码字符串转换为 Token 列表。每个 Token 包含 `type`（种类）、`literal`（字面量）、`line`（行号）、`column`（列号）。

## API 3. GDScriptParser

**文件**: `addons/gdscript_ast/gds_parser.gd`
**class_name**: `GDScriptParser`

```
var error: String                       # 非空表示解析失败

func parse(tokens: Array) -> ASTNode    # Token 列表 → AST 根节点
```

语法分析器。递归下降 + 运算符优先级（20 级）。支持 fail-soft 错误恢复——部分解析失败时继续解析剩余代码，错误收集到 `error` 属性。

## API 4. GDScriptSymbolResolver

**文件**: `addons/gdscript_ast/gds_symbol_resolver.gd`
**class_name**: `GDScriptSymbolResolver`

```
func resolve(ast: ASTNode, file_path: String) -> GDScriptAnalysisResult
```

符号解析器。Visitor 模式遍历 AST，建立嵌套作用域符号表，检测 7 种调用模式，追踪信号 emit/connect，记录变量读写。结果封装在 `GDScriptAnalysisResult` 中。

## API 5. GDScriptAnalysisResult

**文件**: `addons/gdscript_ast/gds_analysis_result.gd`
**class_name**: `GDScriptAnalysisResult`

```
var file_path: String
var classname_id: String                # class_name 声明（空串表示无）
var extends_name: String                # extends 父类名
var symbol_table: GDScriptSymbolTable   # 嵌套作用域符号表
var call_graph: GDScriptCallGraph       # 方法调用图
var signal_graph: GDScriptSignalGraph   # 信号流程图
var def_use_chain: GDScriptDefUseChain  # 变量定义-使用链
var type_table: Dictionary              # {变量名: 推断类型}
var errors: Array[String]              # 分析错误列表
var call_out_degree: Dictionary         # {函数名: 出度}
var call_in_degree: Dictionary          # {函数名: 入度}

func get_all_functions() -> Array               # 所有函数符号
func get_all_signals() -> Array                 # 所有信号符号
func get_callers_of(p_func_name: String) -> Array       # 调用者列表
func get_callees_of(p_func_name: String) -> Array       # 被调用者列表
func get_signal_flow(p_signal_name: String) -> GDScriptSignalInfo
func get_variable_usages(p_var_name: String) -> GDScriptDefUseInfo
func get_dependency_tree() -> Dictionary                # 依赖树
func add_error(p_msg: String)                           # 添加分析错误
func to_dict() -> Dictionary                            # 序列化为字典（供 JSON 导出）
```

## API 6. GDScriptCallGraph / GDScriptCallEdge

**文件**: `addons/gdscript_ast/gds_call_graph.gd` · `gds_call_edge.gd`
**class_name**: `GDScriptCallGraph` · `GDScriptCallEdge`

```
# GDScriptCallEdge
var caller: String          # 调用者函数名
var callee: String          # 被调用者函数名
var call_type: int          # CallType 枚举值
var target_object: String   # external 调用时的目标对象名
var site_line: int          # 调用发生行号

enum CallType {
    SELF = 0,
    SUPER = 1,
    EXTERNAL = 2,
    CONNECT = 3,
    SIGNAL_CONNECT = 4,
    LAMBDA = 5,
    EMIT = 6,
}

# GDScriptCallGraph
var edges: Array[GDScriptCallEdge]

func add_edge(p_edge: GDScriptCallEdge)
func get_callers_of(p_func_name: String) -> Array
func get_callees_of(p_func_name: String) -> Array
```

## API 7. GDScriptSignalGraph / GDScriptSignalInfo / GDScriptSite

**文件**: `addons/gdscript_ast/gds_signal_graph.gd` · `gds_signal_info.gd` · `gds_site.gd`
**class_name**: `GDScriptSignalGraph` · `GDScriptSignalInfo` · `GDScriptSite`

```
# GDScriptSite
var file_path: String
var line: int
var function: String

# GDScriptSignalInfo
var declaration: GDScriptSite       # signal 声明位置（null 表示外部信号）
var emit_sites: Array[GDScriptSite]     # emit 位置列表
var connect_sites: Array[GDScriptSite]  # connect 位置列表

# GDScriptSignalGraph
var signals: Dictionary[String, GDScriptSignalInfo]

func get_signal_flow(p_signal_name: String) -> GDScriptSignalInfo
```

## API 8. GDScriptDefUseChain / GDScriptDefUseInfo / GDScriptDefUseSite

**文件**: `addons/gdscript_ast/gds_def_use_chain.gd` · `gds_def_use_info.gd` · `gds_def_use_site.gd`
**class_name**: `GDScriptDefUseChain` · `GDScriptDefUseInfo` · `GDScriptDefUseSite`

```
# GDScriptDefUseSite
var file_path: String
var line: int
var function: String

# GDScriptDefUseInfo
var definition: GDScriptDefUseSite
var reads: Array[GDScriptDefUseSite]
var writes: Array[GDScriptDefUseSite]

# GDScriptDefUseChain
var variables: Dictionary[String, GDScriptDefUseInfo]

func get_variable_usages(p_var_name: String) -> GDScriptDefUseInfo
```

## API 9. GDScriptProjectAnalyzer

**文件**: `addons/gdscript_ast/editor/gds_project_analyzer.gd`
**class_name**: `GDScriptProjectAnalyzer`

```
func scan_project() -> Array[String]                        # 按 GDSScanConfig 配置扫描项目
func analyze_all() -> GDScriptProjectResult                 # 全量单文件分析（无跨文件解析）
func resolve_cross_file(p_result: GDScriptProjectResult)    # 第二遍：跨文件解析
func analyze_full() -> GDScriptProjectResult                # 完整入口：analyze_all() + resolve_cross_file()
```

## API 10. GDScriptProjectResult / GDSCrossFileEdge

**文件**: `addons/gdscript_ast/gds_project_result.gd` · `gds_cross_file_edge.gd`
**class_name**: `GDScriptProjectResult` · `GDSCrossFileEdge`

```
# GDSCrossFileEdge
var kind: int               # Kind 枚举值
var source_file: String     # 源文件路径
var source_symbol: String   # 源符号（函数/信号名）
var target_file: String     # 目标文件路径
var target_class: String    # 目标 class_name
var target_symbol: String   # 目标符号（函数/信号名）
var line: int               # 引用行号

enum Kind {
    CALL = 0,
    SIGNAL_EMIT = 1,
    SIGNAL_CONNECT = 2,
    INSTANCE = 3,
    EXTENDS = 4,
}

# GDScriptProjectResult
var root_path: String
var files: Dictionary[String, GDScriptAnalysisResult]   # {文件路径: 分析结果}
var class_registry: Dictionary[String, String]           # {class_name: file_path}
var cross_edges: Array[GDSCrossFileEdge]                 # 跨文件边列表
var reverse_index: Dictionary                            # {target_class: [引用文件列表]}

func get_callers_across_files(p_class: String, p_method: String) -> Array
func get_signal_flow_across_files(p_signal: String) -> Array
func get_files_referencing(p_file: String) -> Array
func add_edge(p_edge: GDSCrossFileEdge)
func to_dict(p_project_name: String = "") -> Dictionary
func export_json(p_path: String, p_project_name: String = "") -> Error
```

## API 11. GDSScanConfig

**文件**: `addons/gdscript_ast/editor/gds_scan_config.gd`
**class_name**: `GDSScanConfig`

```
const SETTING_ENABLED := "gdscript_ast/scan/enabled"
const SETTING_INCLUDE := "gdscript_ast/scan/include"
const SETTING_EXCLUDE := "gdscript_ast/scan/exclude"

static func is_enabled() -> bool
static func get_include_dirs() -> Array[String]
static func get_exclude_dirs() -> Array[String]
static func save_config(p_include: Array, p_exclude: Array = []) -> void
static func enable_scan() -> void
static func migrate_if_needed() -> void
```

## API 12. GDScriptUtil (plugin.gd)

**文件**: `addons/gdscript_ast/plugin.gd`
**class_name**: `GDScriptUtil`（EditorPlugin 子类）

```
# 静态分析函数（插件内部使用，也可被其他插件调用）
static func analyze_script(p_path: String) -> GDScriptAnalysisResult

# 工具菜单
# GDScript AST Flow → Parse Current
# GDScript AST Flow → Scan Settings...
```

## API 13. GDSL10n

**文件**: `addons/gdscript_ast/editor/gds_l10n.gd`
**class_name**: `GDSL10n`

```
const DOMAIN := "gdscript_ast"

func setup() -> void                 # 加载 locales/ 目录下的 CSV 翻译资源
func t(p_key: String) -> String      # 翻译一个 key（当前语言）
func tf(p_key: String, p_args: Array) -> String  # 翻译 + 格式化
```

---

## API 14. 场景/资源解析（v2.1 新增）

### GDScriptTscnParser / GDScriptTresParser

**文件**: `addons/gdscript_ast/gds_tscn_parser.gd` · `gds_tres_parser.gd`

```
func parse(p_path: String) -> GDSSceneResourceResult
func set_uid_map(p_map: Dictionary) -> void               # uid:// → res:// 映射（uid-only ext_resource）
func set_script_analysis_results(p_results: Dictionary) -> void  # @export 提取用
```

### GDSSceneResourceResult

**文件**: `addons/gdscript_ast/gds_scene_resource_result.gd`

```
var file_path: String
var file_type: int            # FileType { TSCN, TRES }
var root_nodes: Array         # 顶层 SceneNodeData
var nodes_flat: Dictionary    # NodePath → SceneNodeData
var signal_connections: Array # SignalConnectionData
var ext_resources: Dictionary # id → ExtResourceInfo
var sub_resources: Dictionary # id → SubResourceData
var script_associations: Array # 关联的 .gd 路径列表

func get_nodes_by_type(p_type) -> Array
func get_nodes_by_script(p_script_path) -> Array
func get_connections_for_node(p_node_path) -> Array
```

### SceneNodeData

```
var name: String
var type: String
var parent_path: String
var children: Array           # 子 SceneNodeData
var script_resource: String   # 关联脚本路径
var instance_resource: String # instance=ExtResource 指向的子场景路径（v2.1）
var export_overrides: Dictionary  # @export 填充值（v2.1）

func is_instance() -> bool    # 是否为 instance 子场景节点（v2.1）
```

### GDScriptProjectResult 新增字段（v2.1）

```
var scenes: Dictionary             # .tscn 路径 → GDSSceneResourceResult
var resources: Dictionary          # .tres 路径 → GDSSceneResourceResult
var script_associations: Array     # 场景→脚本关联索引
var scene_signal_connections: Array # 跨场景信号连接
var uid_map: Dictionary            # uid:// → res:// 映射
```

---

# 集成指南

## Integration 1. 集成概览

gdscript-ast-flow 可作为其他 Godot 插件的**分析后端**。核心能力：

- **输入**：`.gd` 源码路径
- **输出**：结构化分析结果（调用图、信号流、变量追踪、跨文件引用）
- **消费方式**：直接调用 API、消费 CodeGraph JSON、扩展分析管道

## Integration 2. 模式 1：分析单个脚本

```gdscript
# 在你的插件中分析任意 .gd 文件
var result = GDScriptUtil.analyze_script("res://some_script.gd")
if result == null:
    push_warning("Analysis failed")
    return

# 获取调用图
for edge in result.call_graph.edges:
    print("%s → %s (type: %d)" % [edge.caller, edge.callee, edge.call_type])

# 查询特定函数的调用者
var callers = result.get_callers_of("take_damage")
for c in callers:
    print("Called by: ", c.caller, " at line ", c.site_line)

# 查询信号流
var flow = result.get_signal_flow("health_changed")
if flow:
    print("Signal declared at line ", flow.declaration.line)
    print("Emit sites: ", flow.emit_sites.size())
    print("Connect sites: ", flow.connect_sites.size())
```

## Integration 3. 模式 2：批量分析项目

```gdscript
# 配置扫描目录
GDSScanConfig.save_config(["res://src"], ["res://addons"])
GDSScanConfig.enable_scan()

# 运行全量分析
var pa = GDScriptProjectAnalyzer.new()
var proj = pa.analyze_full()

# 遍历所有跨文件引用
for edge in proj.cross_edges:
    if edge.kind == GDSCrossFileEdge.Kind.CALL:
        print("%s → %s.%s" % [edge.source_file.get_file(), edge.target_class, edge.target_symbol])

# 查询谁引用了 Player 类
var refs = proj.get_files_referencing("res://src/player.gd")
print("Referenced by %d files" % refs.size())
```

## Integration 4. 模式 3：消费 CodeGraph JSON

```gdscript
# 导出 CodeGraph JSON 供外部工具消费
var pa = GDScriptProjectAnalyzer.new()
var proj = pa.analyze_full()

# 导出到文件
proj.export_json("res://codegraph.json", "My Project")

# 或获取字典自行处理
var dict = proj.to_dict("My Project")
# dict.summary / dict.files / dict.cross_file / dict.hubs / dict.coupled
```

## Integration 5. 模式 4：扩展分析管道

在 SymbolResolver 之后插入自定义分析器：

```gdscript
# 标准管道
var tokenizer = GDScriptTokenizer.new()
var tokens = tokenizer.tokenize(source)
var parser = GDScriptParser.new()
var ast = parser.parse(tokens)
var resolver = GDScriptSymbolResolver.new()
var result = resolver.resolve(ast, file_path)

# 自定义分析：统计代码复杂度
var complexity := 0
for edge in result.call_graph.edges:
    if edge.call_type == GDScriptCallEdge.CallType.EXTERNAL:
        complexity += 1
print("External dependency count: ", complexity)

# 自定义分析：检查未连接的信号
for sig_name in result.signal_graph.signals:
    var info = result.signal_graph.signals[sig_name]
    if info.connect_sites.is_empty():
        push_warning("Signal '%s' is never connected!" % sig_name)
```

## Integration 6. 案例：可视化编程插件

使用 CallGraph 生成蓝图节点连线：

```gdscript
# 分析目标脚本，生成可视化节点
func build_blueprint_from_script(p_path: String) -> void:
    var result = GDScriptUtil.analyze_script(p_path)
    if result == null:
        return

    # 为每个函数创建蓝图节点
    var funcs = result.get_all_functions()
    for func_sym in funcs:
        var node = create_blueprint_node(func_sym.name)
        add_child(node)

    # 为每个调用关系创建连线
    for edge in result.call_graph.edges:
        draw_connection(edge.caller, edge.callee, edge.call_type)

# 根据调用类型给连线着色
func draw_connection(p_from: String, p_to: String, p_type: int) -> void:
    var color = Color.WHITE
    match p_type:
        GDScriptCallEdge.CallType.SELF:
            color = Color.GREEN
        GDScriptCallEdge.CallType.EXTERNAL:
            color = Color.ORANGE
        GDScriptCallEdge.CallType.CONNECT:
            color = Color.DODGER_BLUE
    # ... 创建连线，设置颜色
```

## Integration 7. 案例：文档生成器

自动生成 API 文档：

```gdscript
# 分析脚本并生成 Markdown API 文档
func generate_api_doc(p_path: String) -> String:
    var result = GDScriptUtil.analyze_script(p_path)
    if result == null:
        return ""

    var md := "# API: %s\n\n" % p_path.get_file()

    # 函数列表
    var funcs = result.get_all_functions()
    for sym in funcs:
        md += "## %s()\n\n" % sym.name
        # 谁调用了这个函数
        var callers = result.get_callers_of(sym.name)
        if callers.size() > 0:
            md += "**Callers:** %s\n\n" % ", ".join(callers)
        # 这个函数调用了谁
        var callees = result.get_callees_of(sym.name)
        if callees.size() > 0:
            md += "**Calls:** %s\n\n" % ", ".join(callees)

    # 信号列表
    md += "## Signals\n\n"
    var signals = result.get_all_signals()
    for sym in signals:
        md += "- `%s`\n" % sym.name

    return md
```

## Integration 8. 最佳实践

1. **缓存分析结果** — `GDScriptAnalysisResult` 包含大量数据，避免重复分析同一文件
2. **增量更新** — 仅重新分析变更的文件，通过 `GDScriptProjectAnalyzer` 的 per-file API
3. **错误处理** — 始终检查 `result == null` 或 `parser.error != ""`
4. **避免 load()** — 使用 `FileAccess` 读源码而非 `load()`，规避 resource_saved 死锁
5. **type_table 消费** — 调用图边中的 `target_object` 配合 `type_table` 解析外部对象类型
