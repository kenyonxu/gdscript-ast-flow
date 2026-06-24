# GDScript AST Flow — Developer Guide

> Target: Godot 4.7+ | Language: English

## Table of Contents

### API Reference
1. [Architecture Overview](#api-1-architecture-overview)
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

### Integration Guide
14. [Integration Overview](#integration-1-overview)
15. [Pattern 1: Analyze a Single Script](#integration-2-pattern-1-analyze-a-single-script)
16. [Pattern 2: Batch Project Analysis](#integration-3-pattern-2-batch-project-analysis)
17. [Pattern 3: Consume CodeGraph JSON](#integration-4-pattern-3-consume-codegraph-json)
18. [Pattern 4: Extend the Analysis Pipeline](#integration-5-pattern-4-extend-the-analysis-pipeline)
19. [Case Study: Visual Programming Plugin](#integration-6-case-study-visual-programming-plugin)
20. [Case Study: Documentation Generator](#integration-7-case-study-documentation-generator)
21. [Best Practices](#integration-8-best-practices)

---

# API Reference

## API 1. Architecture Overview

```
.gd source
  → GDScriptTokenizer.tokenize(source) → Array[Token]
  → GDScriptParser.parse(tokens) → ASTNode
  → GDScriptSymbolResolver.resolve(ast, file_path) → GDScriptAnalysisResult
       ├── symbol_table: GDScriptSymbolTable
       ├── call_graph: GDScriptCallGraph
       ├── signal_graph: GDScriptSignalGraph
       ├── def_use_chain: GDScriptDefUseChain
       ├── type_table: Dictionary
       └── errors: Array[String]

Project-level:
  → GDScriptProjectAnalyzer.scan_project() → Array[String] (file paths)
  → GDScriptProjectAnalyzer.analyze_full() → GDScriptProjectResult
       ├── files: Dictionary[String, GDScriptAnalysisResult]
       ├── class_registry: Dictionary[String, String]
       ├── cross_edges: Array[GDSCrossFileEdge]
       └── reverse_index: Dictionary
```

## API 2. GDScriptTokenizer

**File**: `addons/gdscript_util/gds_tokenizer.gd`
**class_name**: `GDScriptTokenizer`

```
func tokenize(source: String) -> Array[GDScriptToken]
```

Lexer. Converts GDScript source string into a Token list. Each token has `type`, `literal`, `line`, and `column` fields.

## API 3. GDScriptParser

**File**: `addons/gdscript_util/gds_parser.gd`
**class_name**: `GDScriptParser`

```
var error: String                       # Non-empty means parse failure

func parse(tokens: Array) -> ASTNode    # Token list → AST root node
```

Parser. Recursive descent + operator precedence (20 levels). Fail-soft error recovery — partial failures don't stop parsing; errors accumulate in the `error` property.

## API 4. GDScriptSymbolResolver

**File**: `addons/gdscript_util/gds_symbol_resolver.gd`
**class_name**: `GDScriptSymbolResolver`

```
func resolve(ast: ASTNode, file_path: String) -> GDScriptAnalysisResult
```

Symbol resolver. Visitor pattern traversal over AST. Builds nested scope symbol table, detects 7 call patterns, tracks signal emit/connect, records variable reads/writes.

## API 5. GDScriptAnalysisResult

**File**: `addons/gdscript_util/gds_analysis_result.gd`
**class_name**: `GDScriptAnalysisResult`

```
var file_path: String
var classname_id: String                # class_name declaration ("" = none)
var extends_name: String                # extends parent class
var symbol_table: GDScriptSymbolTable   # Nested scope symbol table
var call_graph: GDScriptCallGraph       # Method call graph
var signal_graph: GDScriptSignalGraph   # Signal flow graph
var def_use_chain: GDScriptDefUseChain  # Variable def-use chain
var type_table: Dictionary              # {var_name: inferred_type}
var errors: Array[String]              # Analysis errors
var call_out_degree: Dictionary         # {func_name: out_degree}
var call_in_degree: Dictionary          # {func_name: in_degree}

func get_all_functions() -> Array
func get_all_signals() -> Array
func get_callers_of(p_func_name: String) -> Array
func get_callees_of(p_func_name: String) -> Array
func get_signal_flow(p_signal_name: String) -> GDScriptSignalInfo
func get_variable_usages(p_var_name: String) -> GDScriptDefUseInfo
func get_dependency_tree() -> Dictionary
func add_error(p_msg: String)
func to_dict() -> Dictionary
```

## API 6. GDScriptCallGraph / GDScriptCallEdge

**File**: `addons/gdscript_util/gds_call_graph.gd` · `gds_call_edge.gd`
**class_name**: `GDScriptCallGraph` · `GDScriptCallEdge`

```
# GDScriptCallEdge
var caller: String
var callee: String
var call_type: int          # CallType enum value
var target_object: String   # Target object name (external calls)
var site_line: int          # Call site line number

enum CallType {
    SELF = 0, SUPER = 1, EXTERNAL = 2,
    CONNECT = 3, SIGNAL_CONNECT = 4, LAMBDA = 5, EMIT = 6,
}

# GDScriptCallGraph
var edges: Array[GDScriptCallEdge]

func add_edge(p_edge: GDScriptCallEdge)
func get_callers_of(p_func_name: String) -> Array
func get_callees_of(p_func_name: String) -> Array
```

## API 7. GDScriptSignalGraph / GDScriptSignalInfo / GDScriptSite

```
# GDScriptSite
var file_path: String
var line: int
var function: String

# GDScriptSignalInfo
var declaration: GDScriptSite
var emit_sites: Array[GDScriptSite]
var connect_sites: Array[GDScriptSite]

# GDScriptSignalGraph
var signals: Dictionary[String, GDScriptSignalInfo]

func get_signal_flow(p_signal_name: String) -> GDScriptSignalInfo
```

## API 8. GDScriptDefUseChain / GDScriptDefUseInfo / GDScriptDefUseSite

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

**File**: `addons/gdscript_util/editor/gds_project_analyzer.gd`
**class_name**: `GDScriptProjectAnalyzer`

```
func scan_project() -> Array[String]
func analyze_all() -> GDScriptProjectResult
func resolve_cross_file(p_result: GDScriptProjectResult)
func analyze_full() -> GDScriptProjectResult
```

## API 10. GDScriptProjectResult / GDSCrossFileEdge

**File**: `addons/gdscript_util/gds_project_result.gd` · `gds_cross_file_edge.gd`
**class_name**: `GDScriptProjectResult` · `GDSCrossFileEdge`

```
# GDSCrossFileEdge
enum Kind { CALL = 0, SIGNAL_EMIT = 1, SIGNAL_CONNECT = 2, INSTANCE = 3, EXTENDS = 4 }

# GDScriptProjectResult
func get_callers_across_files(p_class: String, p_method: String) -> Array
func get_signal_flow_across_files(p_signal: String) -> Array
func get_files_referencing(p_file: String) -> Array
func to_dict(p_project_name: String = "") -> Dictionary
func export_json(p_path: String, p_project_name: String = "") -> Error
```

## API 11. GDSScanConfig

**File**: `addons/gdscript_util/editor/gds_scan_config.gd`
**class_name**: `GDSScanConfig`

```
static func is_enabled() -> bool
static func get_include_dirs() -> Array[String]
static func get_exclude_dirs() -> Array[String]
static func save_config(p_include: Array, p_exclude: Array = []) -> void
static func enable_scan() -> void
```

## API 12. GDScriptUtil (plugin.gd)

```
static func analyze_script(p_path: String) -> GDScriptAnalysisResult
```

## API 13. GDSL10n

```
func setup() -> void
func t(p_key: String) -> String
func tf(p_key: String, p_args: Array) -> String
```

---

# Integration Guide

## Integration 1. Overview

gdscript-ast-flow can serve as an **analysis backend** for other Godot plugins.

- **Input**: `.gd` source file paths
- **Output**: Structured analysis results (call graphs, signal flows, variable tracking, cross-file references)
- **Consumption**: Direct API calls, CodeGraph JSON, pipeline extension

## Integration 2. Pattern 1: Analyze a Single Script

```gdscript
var result = GDScriptUtil.analyze_script("res://some_script.gd")
if result == null:
    return

for edge in result.call_graph.edges:
    print("%s → %s" % [edge.caller, edge.callee])

var callers = result.get_callers_of("take_damage")
for c in callers:
    print("Called by: ", c.caller, " at line ", c.site_line)
```

## Integration 3. Pattern 2: Batch Project Analysis

```gdscript
GDSScanConfig.save_config(["res://src"], ["res://addons"])
GDSScanConfig.enable_scan()

var pa = GDScriptProjectAnalyzer.new()
var proj = pa.analyze_full()

for edge in proj.cross_edges:
    if edge.kind == GDSCrossFileEdge.Kind.CALL:
        print("%s → %s.%s" % [edge.source_file.get_file(), edge.target_class, edge.target_symbol])
```

## Integration 4. Pattern 3: Consume CodeGraph JSON

```gdscript
var proj = GDScriptProjectAnalyzer.new().analyze_full()
proj.export_json("res://codegraph.json", "My Project")
# Or: var dict = proj.to_dict("My Project")
```

## Integration 5. Pattern 4: Extend the Analysis Pipeline

```gdscript
var result = GDScriptSymbolResolver.new().resolve(ast, file_path)

# Custom: count external dependencies
var complexity := 0
for edge in result.call_graph.edges:
    if edge.call_type == GDScriptCallEdge.CallType.EXTERNAL:
        complexity += 1
```

## Integration 6. Case Study: Visual Programming Plugin

```gdscript
func build_blueprint(p_path: String) -> void:
    var result = GDScriptUtil.analyze_script(p_path)
    if result == null: return

    for func_sym in result.get_all_functions():
        create_blueprint_node(func_sym.name)

    for edge in result.call_graph.edges:
        draw_connection(edge.caller, edge.callee, edge.call_type)
```

## Integration 7. Case Study: Documentation Generator

```gdscript
func generate_api_doc(p_path: String) -> String:
    var result = GDScriptUtil.analyze_script(p_path)
    if result == null: return ""
    var md := "# API\n\n"
    for sym in result.get_all_functions():
        md += "## %s()\n" % sym.name
    return md
```

## Integration 8. Best Practices

1. **Cache results** — Avoid re-analyzing the same file repeatedly
2. **Incremental updates** — Only re-analyze changed files
3. **Check for null** — Always check `result == null` or `parser.error != ""`
4. **Use FileAccess, not load()** — Avoids resource_saved deadlock
5. **Consume type_table** — Use `target_object` + `type_table` for external type resolution
