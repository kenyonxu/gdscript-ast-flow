# Phase 2 内部类提取规范

> 日期: 2026-06-20 | 状态: 设计中 | 依赖: Phase 1 + Phase 2 基础实现

## 问题

`gds_analysis_result.gd` 将 10 个数据类全部定义为 `GDScriptAnalysisResult` 的内部类。在 Godot 4.7 GDScript 运行时，**跨脚本引用内部类**存在限制：

- `is` 运算符对某些内部类运行时返回 `false`（即使对象是该类型）
- 内部类方法（`CallGraph.add_edge`/`get_callers_of`）可能静默失效
- `Object.get()` 无法读取内部类实例的自定义属性

**表现**：Phase 2 测试 Test 3 (`self.bar()` 调用方检测) 始终失败——`is GDScriptSelfNode` 已确认返回 `true`，`_add_call_edge` 已执行，但 `CallGraph.get_callers_of("bar")` 返回空数组。

**已验证的解决方案**：`GDScriptSelfNode`/`GDScriptSuperNode` 提取为独立 `class_name` 后，`is` 检查立即工作。将全部数据类提取为独立 `class_name` 可根治运行时问题。

## 提取清单

| 内部类 | 独立 class_name | 文件 | 功能 |
|--------|----------------|------|------|
| `Symbol` | `GDScriptSymbol` | `gds_symbol.gd` | 符号表条目 |
| `SymbolTable` | `GDScriptSymbolTable` | `gds_symbol_table.gd` | 嵌套作用域符号表 |
| `CallEdge` | `GDScriptCallEdge` | `gds_call_edge.gd` | 调用图边 |
| `CallGraph` | `GDScriptCallGraph` | `gds_call_graph.gd` | 方法调用图 |
| `Site` | `GDScriptSite` | `gds_site.gd` | emit/connect 位置 |
| `SignalInfo` | `GDScriptSignalInfo` | `gds_signal_info.gd` | 信号流程图条目 |
| `SignalGraph` | `GDScriptSignalGraph` | `gds_signal_graph.gd` | 信号流程图 |
| `DefUseSite` | `GDScriptDefUseSite` | `gds_def_use_site.gd` | 读写位置 |
| `DefUseInfo` | `GDScriptDefUseInfo` | `gds_def_use_info.gd` | 变量读写链条目 |
| `DefUseChain` | `GDScriptDefUseChain` | `gds_def_use_chain.gd` | 变量定义-使用链 |

## 引用变更对照

### 类型注解（`is` / `:` / `->`）

| 旧 | 新 |
|----|-----|
| `GDScriptAnalysisResult.Symbol` | `GDScriptSymbol` |
| `GDScriptAnalysisResult.SymbolTable` | `GDScriptSymbolTable` |
| `GDScriptAnalysisResult.CallEdge` | `GDScriptCallEdge` |
| `GDScriptAnalysisResult.CallGraph` | `GDScriptCallGraph` |
| `GDScriptAnalysisResult.Site` | `GDScriptSite` |
| `GDScriptAnalysisResult.SignalInfo` | `GDScriptSignalInfo` |
| `GDScriptAnalysisResult.SignalGraph` | `GDScriptSignalGraph` |
| `GDScriptAnalysisResult.DefUseSite` | `GDScriptDefUseSite` |
| `GDScriptAnalysisResult.DefUseInfo` | `GDScriptDefUseInfo` |
| `GDScriptAnalysisResult.DefUseChain` | `GDScriptDefUseChain` |

### 枚举引用

| 旧 | 新 |
|----|-----|
| `GDScriptAnalysisResult.Symbol.Kind.FUNCTION` | `GDScriptSymbol.Kind.FUNCTION` |
| `GDScriptAnalysisResult.CallEdge.CallType.SELF` | `GDScriptCallEdge.CallType.SELF` |
| `GDScriptAnalysisResult.DefUseSite.AccessType.READ` | `GDScriptDefUseSite.AccessType.READ` |

### `.new()` 调用

| 旧 | 新 |
|----|-----|
| `GDScriptAnalysisResult.Symbol.new()` | `GDScriptSymbol.new()` |
| `GDScriptAnalysisResult.SymbolTable.new()` | `GDScriptSymbolTable.new()` |
| `GDScriptAnalysisResult.CallEdge.new()` | `GDScriptCallEdge.new()` |
| ... | ... |

### 递归引用处理

部分类内部引用自身类型，提取后保持不变：

- `SymbolTable.parent: GDScriptSymbolTable` → `var parent: GDScriptSymbolTable = null`
- `SymbolTable.resolve() -> GDScriptSymbol` → `func resolve(...) -> GDScriptSymbol:`
- `SignalInfo.declaration` — 原类型 `GDScriptToken.SignalNode`（不变）
- `DefUseInfo.def_site: GDScriptDefUseSite` → `var def_site: GDScriptDefUseSite = null`
- `GDScriptAnalysisResult` 的字段类型全部更新为独立类名

## 实施步骤

### Step 1: 创建 10 个独立文件

每个文件包含：文件头注释 + `class_name Xxx` + `extends RefCounted` + 字段/方法/枚举（原样复制）。

### Step 2: 更新 `gds_analysis_result.gd`

- 删除全部内部类定义
- 更新字段类型注解为独立类名
- 更新方法中的枚举引用（`Symbol.Kind.FUNCTION` → `GDScriptSymbol.Kind.FUNCTION`）
- 更新方法返回类型

### Step 3: 更新 `gds_symbol_resolver.gd`

- 全局替换所有 `GDScriptAnalysisResult.ClassName` → 独立类名
- 全局替换所有 `ClassName.EnumType` → `GDScriptClassName.EnumType`

### Step 4: 更新 `plugin.gd`

- 替换 `GDScriptAnalysisResult.CallEdge.CallType` → `GDScriptCallEdge.CallType`

### Step 5: 更新 `tests/test_symbol_resolver.gd`

- 替换所有 `GDScriptAnalysisResult.Symbol.Kind` → `GDScriptSymbol.Kind`
- 替换所有 `GDScriptAnalysisResult.CallEdge.CallType` → `GDScriptCallEdge.CallType`

### Step 6: 验收

- 所有文件 LSP 诊断归零
- Phase 2 验收测试 10/10 通过

## 风险

- **破坏性变更**：所有引用 `GDScriptAnalysisResult.*` 的代码都需更新
- **Godot UID 生成**：新文件需要编辑器生成 `.uid` 文件
- **文件数量增加**：从 6 个 `.gd` 文件变为 16 个
- **循环依赖**：确认无——提取的类只依赖 `RefCounted` 和基本 Variant 类型
