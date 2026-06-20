# Phase 2 内部类提取 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `gds_analysis_result.gd` 中 10 个内部类提取为独立 `class_name` 文件，根治 Godot 4.7 内部类运行时限制（`is` 失败、方法静默失效）。

**Architecture:** 每个内部类 → 一个 `.gd` 文件 (`class_name Xxx extends RefCounted`)。`GDScriptAnalysisResult` 保留为容器类，字段类型引用全部更新。外部引用从 `GDScriptAnalysisResult.Xxx` 改为 `GDScriptXxx`。

**Tech Stack:** Godot 4.7 GDScript

**Spec reference:** `docs/superpowers/specs/2026-06-20-phase2-extract-inner-classes.md`

---

## 文件结构

```
addons/gdscript_util/
├── gds_analysis_result.gd    # 修改: 删除内部类，更新字段类型
├── gds_symbol.gd              # 新建: class_name GDScriptSymbol
├── gds_symbol_table.gd        # 新建: class_name GDScriptSymbolTable
├── gds_call_edge.gd           # 新建: class_name GDScriptCallEdge
├── gds_call_graph.gd          # 新建: class_name GDScriptCallGraph
├── gds_site.gd                # 新建: class_name GDScriptSite
├── gds_signal_info.gd         # 新建: class_name GDScriptSignalInfo
├── gds_signal_graph.gd        # 新建: class_name GDScriptSignalGraph
├── gds_def_use_site.gd        # 新建: class_name GDScriptDefUseSite
├── gds_def_use_info.gd        # 新建: class_name GDScriptDefUseInfo
├── gds_def_use_chain.gd       # 新建: class_name GDScriptDefUseChain
├── gds_symbol_resolver.gd     # 修改: 全部引用替换
├── plugin.gd                  # 修改: CallEdge.CallType 引用替换
tests/
└── test_symbol_resolver.gd    # 修改: 引用替换
```

---

## Task 1: 创建 GDScriptSymbol

**Files:** Create: `addons/gdscript_util/gds_symbol.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/gds_symbol.gd
# 符号表条目 — 表示 SymbolTable 中的一个符号（函数/变量/信号/枚举等）

class_name GDScriptSymbol
extends RefCounted

enum Kind {
    CLASS = 0,        # class / inner class 定义
    FUNCTION = 1,     # func 定义
    VARIABLE = 2,     # var 定义
    SIGNAL = 3,       # signal 声明
    ENUM = 4,         # enum 定义
    PARAMETER = 5,    # 函数参数
    CONSTANT = 6,     # const 定义
    ENUM_VALUE = 7,   # enum 中的值
    FOR_VAR = 8       # for 循环变量
}

var name: String = ""
var kind: int = Kind.VARIABLE
var declaration = null
var datatype: String = ""
var is_exported: bool = false
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_symbol.gd
git commit -m "feat: extract GDScriptSymbol as class_name"
```

---

## Task 2: 创建 GDScriptSymbolTable

**Files:** Create: `addons/gdscript_util/gds_symbol_table.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/gds_symbol_table.gd
# 嵌套作用域符号表 — 支持父作用域链式查找

class_name GDScriptSymbolTable
extends RefCounted

var parent: GDScriptSymbolTable = null
var symbols: Dictionary = {}
var scope_name: String = ""

func define(p_name: String, p_kind: int, p_node, p_datatype: String = "") -> GDScriptSymbol:
    var sym = GDScriptSymbol.new()
    sym.name = p_name
    sym.kind = p_kind
    sym.declaration = p_node
    sym.datatype = p_datatype
    symbols[p_name] = sym
    return sym

func resolve(p_name: String) -> GDScriptSymbol:
    if symbols.has(p_name):
        return symbols[p_name]
    if parent != null:
        return parent.resolve(p_name)
    return null

func resolve_local(p_name: String) -> GDScriptSymbol:
    return symbols.get(p_name, null)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_symbol_table.gd
git commit -m "feat: extract GDScriptSymbolTable as class_name"
```

---

## Task 3: 创建 GDScriptCallEdge

**Files:** Create: `addons/gdscript_util/gds_call_edge.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/gds_call_edge.gd
# 调用图中的一条边 — 记录一次方法调用关系

class_name GDScriptCallEdge
extends RefCounted

enum CallType {
    SELF = 0,            # self.method() 或隐式 self 调用
    SUPER = 1,           # super.method()
    EXTERNAL = 2,        # obj.method() 外部对象调用
    CONNECT = 3,         # .connect("sig", cb) 中的回调
    SIGNAL_CONNECT = 4,  # signal_name.connect(cb) 中的回调
    LAMBDA = 5,          # lambda 作为回调
    STATIC = 6,          # ClassName.static_method()
    EMIT = 7,            # emit("signal") / signal.emit()
}

var caller: String = ""
var callee: String = ""
var site_line: int = 0
var call_type: int = CallType.SELF
var target_object: String = ""
var arguments: Array = []
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_call_edge.gd
git commit -m "feat: extract GDScriptCallEdge as class_name"
```

---

## Task 4: 创建 GDScriptCallGraph

**Files:** Create: `addons/gdscript_util/gds_call_graph.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/gds_call_graph.gd
# 方法调用图 — 记录所有方法间调用关系

class_name GDScriptCallGraph
extends RefCounted

var edges: Array = []

func add_edge(p_edge):
    edges.append(p_edge)

func get_callers_of(p_func_name: String) -> Array:
    var result: Array = []
    for e in edges:
        if e.callee == p_func_name:
            result.append(e)
    return result

func get_callees_of(p_func_name: String) -> Array:
    var result: Array = []
    for e in edges:
        if e.caller == p_func_name:
            result.append(e)
    return result
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_call_graph.gd
git commit -m "feat: extract GDScriptCallGraph as class_name"
```

---

## Task 5: 创建 GDScriptSite

**Files:** Create: `addons/gdscript_util/gds_site.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/gds_site.gd
# emit/connect 位置信息

class_name GDScriptSite
extends RefCounted

var line: int = 0
var node = null
var enclosing_function: String = ""
var arguments: Array = []
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_site.gd
git commit -m "feat: extract GDScriptSite as class_name"
```

---

## Task 6: 创建 GDScriptSignalInfo

**Files:** Create: `addons/gdscript_util/gds_signal_info.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/gds_signal_info.gd
# 单个信号的完整流程图

class_name GDScriptSignalInfo
extends RefCounted

var name: String = ""
var declaration = null
var params: Array = []
var emit_sites: Array = []
var connect_sites: Array = []
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_signal_info.gd
git commit -m "feat: extract GDScriptSignalInfo as class_name"
```

---

## Task 7: 创建 GDScriptSignalGraph

**Files:** Create: `addons/gdscript_util/gds_signal_graph.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/gds_signal_graph.gd
# 信号流程图 — 管理所有信号的 emit/connect 关系

class_name GDScriptSignalGraph
extends RefCounted

var signals: Dictionary = {}

func get_signal_flow(p_signal_name: String) -> GDScriptSignalInfo:
    return signals.get(p_signal_name, null)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_signal_graph.gd
git commit -m "feat: extract GDScriptSignalGraph as class_name"
```

---

## Task 8: 创建 GDScriptDefUseSite

**Files:** Create: `addons/gdscript_util/gds_def_use_site.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/gds_def_use_site.gd
# 单个读写位置 — 记录变量的一次定义/读取/写入

class_name GDScriptDefUseSite
extends RefCounted

enum AccessType {
    DEFINE = 0,      # var x = ... / const x = ... 的定义
    READ = 1,        # 读取变量值
    WRITE = 2,       # 赋值写入
    READ_WRITE = 3   # 读+写 (复合赋值)
}

var line: int = 0
var node = null
var enclosing_function: String = ""
var access_type: int = AccessType.READ
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_def_use_site.gd
git commit -m "feat: extract GDScriptDefUseSite as class_name"
```

---

## Task 9: 创建 GDScriptDefUseInfo

**Files:** Create: `addons/gdscript_util/gds_def_use_info.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/gds_def_use_info.gd
# 单个变量的完整读写链

class_name GDScriptDefUseInfo
extends RefCounted

var name: String = ""
var def_site: GDScriptDefUseSite = null
var read_sites: Array = []
var write_sites: Array = []

func get_all_sites() -> Array:
    var all: Array = []
    if def_site != null:
        all.append(def_site)
    all.append_array(read_sites)
    all.append_array(write_sites)
    return all
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_def_use_info.gd
git commit -m "feat: extract GDScriptDefUseInfo as class_name"
```

---

## Task 10: 创建 GDScriptDefUseChain

**Files:** Create: `addons/gdscript_util/gds_def_use_chain.gd`

- [ ] **Step 1: 创建文件**

```gdscript
# addons/gdscript_util/gds_def_use_chain.gd
# 变量定义-使用链 — 管理所有变量的读写追踪

class_name GDScriptDefUseChain
extends RefCounted

var variables: Dictionary = {}

func get_variable_usages(p_var_name: String) -> GDScriptDefUseInfo:
    return variables.get(p_var_name, null)

func _ensure_info(p_name: String) -> GDScriptDefUseInfo:
    if not variables.has(p_name):
        var info = GDScriptDefUseInfo.new()
        info.name = p_name
        variables[p_name] = info
    return variables[p_name]
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_def_use_chain.gd
git commit -m "feat: extract GDScriptDefUseChain as class_name"
```

---

## Task 11: 重写 gds_analysis_result.gd

**Files:** Modify: `addons/gdscript_util/gds_analysis_result.gd` (整个文件替换)

移除全部 10 个内部类，用独立 `class_name` 的字段引用替代。

- [ ] **Step 1: 替换文件内容**

```gdscript
# addons/gdscript_util/gds_analysis_result.gd
# Phase 2 符号解析 — 统一结果容器
# 数据结构定义已提取为独立 class_name 文件:
#   gds_symbol.gd, gds_symbol_table.gd, gds_call_edge.gd, gds_call_graph.gd,
#   gds_site.gd, gds_signal_info.gd, gds_signal_graph.gd,
#   gds_def_use_site.gd, gds_def_use_info.gd, gds_def_use_chain.gd

class_name GDScriptAnalysisResult
extends RefCounted

var file_path: String = ""
var classname_id: String = ""
var extends_path: String = ""
var preloads: Array = []

# 核心数据
var ast = null
var symbol_table: GDScriptSymbolTable = null
var call_graph: GDScriptCallGraph = null
var signal_graph: GDScriptSignalGraph = null
var def_use_chain: GDScriptDefUseChain = null

# 错误/告警
var errors: Array = []

# 源码行缓存
var _source_lines: Array = []


# ---- 查询 API ----

func get_all_functions() -> Array:
    var funcs: Array = []
    if symbol_table == null:
        return funcs
    for sym_name in symbol_table.symbols:
        var sym = symbol_table.symbols[sym_name]
        if sym.kind == GDScriptSymbol.Kind.FUNCTION:
            funcs.append(sym.declaration)
    return funcs

func get_all_signals() -> Array:
    var signals: Array = []
    if symbol_table == null:
        return signals
    for sym_name in symbol_table.symbols:
        var sym = symbol_table.symbols[sym_name]
        if sym.kind == GDScriptSymbol.Kind.SIGNAL:
            signals.append(sym.declaration)
    return signals

func get_callers_of(p_func_name: String) -> Array:
    if call_graph == null:
        return []
    return call_graph.get_callers_of(p_func_name)

func get_callees_of(p_func_name: String) -> Array:
    if call_graph == null:
        return []
    return call_graph.get_callees_of(p_func_name)

func get_signal_flow(p_signal_name: String) -> GDScriptSignalInfo:
    if signal_graph == null:
        return null
    return signal_graph.get_signal_flow(p_signal_name)

func get_variable_usages(p_var_name: String) -> GDScriptDefUseInfo:
    if def_use_chain == null:
        return null
    return def_use_chain.get_variable_usages(p_var_name)

func get_dependency_tree() -> Dictionary:
    return {
        "extends": extends_path,
        "preloads": preloads,
        "class_name": classname_id,
    }

func add_error(p_msg: String):
    errors.append(p_msg)
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/gds_analysis_result.gd
git commit -m "refactor: GDScriptAnalysisResult — remove inner classes, use external class_name types"
```

---

## Task 12: 更新 gds_symbol_resolver.gd 引用

**Files:** Modify: `addons/gdscript_util/gds_symbol_resolver.gd` (批量替换)

将所有 `GDScriptAnalysisResult.ClassName` 引用替换为独立 `class_name`。

- [ ] **Step 1: 执行批量替换**

```bash
sed -i \
  -e 's/GDScriptAnalysisResult\.Symbol\./GDScriptSymbol./g' \
  -e 's/GDScriptAnalysisResult\.SymbolTable/GDScriptSymbolTable/g' \
  -e 's/GDScriptAnalysisResult\.CallEdge\./GDScriptCallEdge./g' \
  -e 's/GDScriptAnalysisResult\.CallGraph/GDScriptCallGraph/g' \
  -e 's/GDScriptAnalysisResult\.Site/GDScriptSite/g' \
  -e 's/GDScriptAnalysisResult\.SignalInfo/GDScriptSignalInfo/g' \
  -e 's/GDScriptAnalysisResult\.SignalGraph/GDScriptSignalGraph/g' \
  -e 's/GDScriptAnalysisResult\.DefUseSite\./GDScriptDefUseSite./g' \
  -e 's/GDScriptAnalysisResult\.DefUseInfo/GDScriptDefUseInfo/g' \
  -e 's/GDScriptAnalysisResult\.DefUseChain/GDScriptDefUseChain/g' \
  addons/gdscript_util/gds_symbol_resolver.gd
```

- [ ] **Step 2: 验证替换完整性**

```bash
# 确认无残留的 GDScriptAnalysisResult. 引用
grep -n 'GDScriptAnalysisResult\.\(Symbol\|Table\|Call\|Site\|Signal\|DefUse\)' \
  addons/gdscript_util/gds_symbol_resolver.gd || echo "CLEAN"
```

- [ ] **Step 3: 提交**

```bash
git add addons/gdscript_util/gds_symbol_resolver.gd
git commit -m "refactor: update GDScriptSymbolResolver to use independent class_name types"
```

---

## Task 13: 更新 plugin.gd 引用

**Files:** Modify: `addons/gdscript_util/plugin.gd:131-137`

- [ ] **Step 1: 替换 CallEdge.CallType 引用**

```bash
sed -i 's/GDScriptAnalysisResult\.CallEdge\./GDScriptCallEdge./g' \
  addons/gdscript_util/plugin.gd
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/plugin.gd
git commit -m "refactor: update plugin.gd CallEdge references"
```

---

## Task 14: 更新 test_symbol_resolver.gd 引用

**Files:** Modify: `tests/test_symbol_resolver.gd` (批量替换)

- [ ] **Step 1: 执行批量替换**

```bash
sed -i \
  -e 's/GDScriptAnalysisResult\.Symbol\./GDScriptSymbol./g' \
  -e 's/GDScriptAnalysisResult\.SymbolTable/GDScriptSymbolTable/g' \
  -e 's/GDScriptAnalysisResult\.CallEdge\./GDScriptCallEdge./g' \
  -e 's/GDScriptAnalysisResult\.DefUseChain/GDScriptDefUseChain/g' \
  tests/test_symbol_resolver.gd
```

- [ ] **Step 2: 验证替换完整性**

```bash
grep -n 'GDScriptAnalysisResult\.' \
  tests/test_symbol_resolver.gd || echo "CLEAN"
```

- [ ] **Step 3: 提交**

```bash
git add tests/test_symbol_resolver.gd
git commit -m "refactor: update tests to use independent class_name types"
```

---

## Task 15: 验收测试

**Files:** 验证全部

- [ ] **Step 1: 在 Godot 编辑器中打开项目**

```bash
# 重启编辑器加载新文件
```

- [ ] **Step 2: 检查 LSP 诊断**

对每个文件运行 LSP 诊断，确认无错误：
`res://addons/gdscript_util/gds_analysis_result.gd`
`res://addons/gdscript_util/gds_symbol_resolver.gd`
`res://addons/gdscript_util/plugin.gd`
`res://tests/test_symbol_resolver.gd`

- [ ] **Step 3: 运行 Phase 1 测试**

确认 Phase 1 验收测试不受影响，10/10 通过。

- [ ] **Step 4: 运行 Phase 2 测试**

确认 Phase 2 验收测试 10/10 全部通过（包括 Test 3 `self.bar()` 调用方检测）。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "test: Phase 1 & Phase 2 acceptance tests all pass after inner class extraction"
```

---

## 完成检查清单

- [ ] 10 个独立 `class_name` 文件全部创建
- [ ] `gds_analysis_result.gd` 移除内部类，字段类型全部更新
- [ ] `gds_symbol_resolver.gd` 所有引用替换无残留
- [ ] `plugin.gd` `CallEdge.CallType` 引用更新
- [ ] `tests/test_symbol_resolver.gd` 引用更新
- [ ] Phase 1 验收测试 10/10 通过
- [ ] Phase 2 验收测试 10/10 通过（含 Test 3）
- [ ] 全项目 LSP 诊断归零

## 预期结果

Test 3 (`self.bar()` 调用方检测) 将通过——`GDScriptCallGraph.add_edge` 和 `get_callers_of` 作为独立 `class_name` 的方法将正确执行。
