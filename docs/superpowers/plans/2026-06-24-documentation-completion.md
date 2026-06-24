# 文档补完 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 gdscript-ast-flow 建立完整的 6 份中英双语文档体系（README ×2 + user_guide ×2 + dev_guide ×2），覆盖从安装到高级集成的全部使用场景。

**Architecture:** 三文档制 — README（项目首页 + 快速开始）→ user_guide（游戏开发者全流程）→ dev_guide（API 参考 + 集成模式）。中文先写，英文基于中文翻译。所有文档放在 `addons/gdscript_util/docs/` 下，与插件一起分发。

**Tech Stack:** Markdown, GDScript 4.7 API

**Spec reference:** `docs/superpowers/specs/2026-06-24-documentation-completion-design.md`

---

## Task 1: 重写 README.md（中文）

**Files:** Modify: `readme.md`

- [ ] **Step 1: 写入中文 README**

```markdown
# GDScript AST Flow

[![MIT License](https://img.shields.io/badge/license-MIT-green)](LICENSE.txt)

Godot 4.7 GDScript AST 解析 + 逻辑流分析工具。以 EditorPlugin 形式集成，支持信号连接追踪、方法调用图、变量定义-使用链分析、跨文件引用。

**作者**：v3.4 原版 あるる / きのもと 結衣 @arlez80 · v2.0 重写 kenyonxu

---

## 特性

### 三阶段分析管道

```
.gd 源码 → [GDScriptTokenizer] → Token 流 → [GDScriptParser] → AST → [GDScriptSymbolResolver] → AnalysisResult
```

### 分析能力

- **调用图** — 7 种调用模式检测（self/super/external/connect/signal_connect/lambda/emit）
- **信号流** — signal 声明 → emit 位置 → connect 位置全链路追踪
- **Def-Use 链** — 变量定义、读取、写入的完整追踪
- **跨文件分析** — 通过 class_name 解析跨文件方法调用和信号连接
- **图可视化** — GraphEdit 交互式调用图/信号流图，支持枢纽高亮、度数筛选、节点跳转
- **JSON 导出** — 结构化 CodeGraph JSON，供 AI agent 消费

### 编辑器集成

- 底部面板：Summary / Call Graph / Signal Flow / Def-Use / Project 五个 Tab
- 主屏 "Analysis" Tab：Scope × Graph 切换 + 度数筛选 + 图例 + 自动布局
- 工具菜单：`GDScript AST Flow → Parse Current / Scan Settings...`
- 资源保存时自动重新分析

---

## 快速开始

### 安装

1. 将 `addons/gdscript_util/` 复制到你的 Godot 项目 `addons/` 目录
2. 打开 **项目 → 项目设置 → 插件**，启用 **GDScript Util**

### 第一次分析

1. 打开任意 `.gd` 脚本
2. 菜单 **Project → Tools → GDScript AST Flow → Parse Current**
3. 查看底部面板的 Summary / Call Graph 等 Tab

### 项目扫描

1. 菜单 **Project → Tools → GDScript AST Flow → Scan Settings...**
2. 勾选 **Enable Project Scan**，Browse 添加要扫描的目录
3. 点击 **Save**，然后切换到 Project Tab 点击 **Rebuild Project**
4. 查看跨文件调用关系和信号流

---

## 文档

| 文档 | 说明 |
|------|------|
| [用户指南](addons/gdscript_util/docs/user_guide_cn.md) | 安装、单文件分析、项目扫描、图导航、导出 |
| [开发者指南](addons/gdscript_util/docs/dev_guide_cn.md) | API 参考、集成模式、作为其他插件基建 |

---

## 许可

MIT License · 详见 [LICENSE.txt](LICENSE.txt)
```

- [ ] **Step 2: 提交**

```bash
git add readme.md
git commit -m "docs: rewrite README.md — features, quick start, doc navigation"
```

---

## Task 2: 创建 README.en.md（英文）

**Files:** Create: `readme.en.md`

- [ ] **Step 1: 写入英文 README**

```markdown
# GDScript AST Flow

[![MIT License](https://img.shields.io/badge/license-MIT-green)](LICENSE.txt)

A Godot 4.7 GDScript AST parser + logic flow analysis tool. Integrated as an EditorPlugin, supporting signal connection tracing, method call graphs, variable def-use chain analysis, and cross-file reference tracking.

**Authors**: v3.4 original by あるる / きのもと 結衣 @arlez80 · v2.0 rewrite by kenyonxu

---

## Features

### Three-Phase Analysis Pipeline

```
.gd source → [GDScriptTokenizer] → Token stream → [GDScriptParser] → AST → [GDScriptSymbolResolver] → AnalysisResult
```

### Analysis Capabilities

- **Call Graph** — 7 call pattern detection (self/super/external/connect/signal_connect/lambda/emit)
- **Signal Flow** — Full tracing: signal declaration → emit sites → connect sites
- **Def-Use Chain** — Variable define/read/write tracking
- **Cross-File Analysis** — Resolve cross-file method calls and signal connections via class_name
- **Graph Visualization** — Interactive GraphEdit-based call/signal graphs with hub highlighting, degree filtering, and jump-to-definition
- **JSON Export** — Structured CodeGraph JSON consumable by AI agents

### Editor Integration

- Bottom panel: Summary / Call Graph / Signal Flow / Def-Use / Project tabs
- Main screen "Analysis" tab: Scope × Graph switching + degree filter + legend + auto-layout
- Tool menu: `GDScript AST Flow → Parse Current / Scan Settings...`
- Auto re-analysis on resource save

---

## Quick Start

### Installation

1. Copy `addons/gdscript_util/` into your Godot project's `addons/` directory
2. Open **Project → Project Settings → Plugins**, enable **GDScript Util**

### First Analysis

1. Open any `.gd` script
2. Menu **Project → Tools → GDScript AST Flow → Parse Current**
3. Check the bottom panel Summary / Call Graph tabs

### Project Scan

1. Menu **Project → Tools → GDScript AST Flow → Scan Settings...**
2. Check **Enable Project Scan**, Browse to add directories to scan
3. Click **Save**, then switch to Project Tab and click **Rebuild Project**
4. Explore cross-file call relationships and signal flows

---

## Documentation

| Document | Description |
|----------|-------------|
| [User Guide](addons/gdscript_util/docs/user_guide_en.md) | Installation, single-file analysis, project scan, graph navigation, export |
| [Developer Guide](addons/gdscript_util/docs/dev_guide_en.md) | API reference, integration patterns, as infrastructure for other plugins |

---

## License

MIT License · See [LICENSE.txt](LICENSE.txt)
```

- [ ] **Step 2: 提交**

```bash
git add readme.en.md
git commit -m "docs: create README.en.md — English project homepage"
```

---

## Task 3: 创建 user_guide_cn.md（中文用户指南）

**Files:** Create: `addons/gdscript_util/docs/user_guide_cn.md`

- [ ] **Step 1: 创建 docs 目录并写入中文用户指南**

```bash
mkdir -p addons/gdscript_util/docs
```

```markdown
# GDScript AST Flow — 用户指南

> 适用版本: Godot 4.7+ | 语言: 中文

## 目录

1. [安装与启用](#1-安装与启用)
2. [单文件分析](#2-单文件分析)
3. [分析面板说明](#3-分析面板说明)
4. [项目扫描](#4-项目扫描)
5. [图视图导航](#5-图视图导航)
6. [CodeGraph JSON 导出](#6-codegraph-json-导出)
7. [常见问题](#7-常见问题)

---

## 1. 安装与启用

1. 将 `addons/gdscript_util/` 目录复制到你 Godot 项目的 `addons/` 目录下
2. 打开 Godot 编辑器，菜单 **项目 → 项目设置 → 插件**
3. 找到 **GDScript Util**，勾选 **启用**
4. 底部出现 **Summary / Call Graph / Signal Flow / Def-Use / Project** 面板

---

## 2. 单文件分析

分析当前打开的 `.gd` 脚本：

1. 打开任意 `.gd` 文件
2. 菜单 **Project → Tools → GDScript AST Flow → Parse Current**
3. 分析结果立即显示在底部面板

> 保存脚本时也会自动触发重新分析。

---

## 3. 分析面板说明

### Summary

显示当前文件的分析摘要：函数数量、信号数量、变量数量、调用边数、错误数。

### Call Graph

- 按函数列出所有调用关系：谁调用了谁（caller → callee）
- 边类型标注：`[self]`（自身调用）、`[super]`（父类调用）、`[ext]`（外部对象调用）、`[connect]`（信号连接）、`[emit]`（信号发射）
- 内置函数（`print`、`range` 等 60+ 个）自动过滤，不显示

### Signal Flow

- 列出文件中所有 signal 声明
- 每个 signal 显示：声明行、emit 位置列表、connect 位置列表

### Def-Use

- 列出文件中所有变量
- 每个变量显示：定义位置、读取位置列表、写入位置列表

### Project

- 显示项目扫描结果：文件列表 + 每个文件的跨文件引用数
- 展开文件可看到出向引用（→）和入向引用（←）

---

## 4. 项目扫描

扫描整个项目（或指定目录）下所有 `.gd` 文件，建立跨文件分析。

### 配置扫描目录

1. 菜单 **Project → Tools → GDScript AST Flow → Scan Settings...**
2. 勾选 **Enable Project Scan**
3. 点击 **Browse...** 选择要扫描的目录，添加到 Include 列表
4. 如需排除目录，在 Exclude 区点击 **Browse...** 添加（默认排除 `res://addons`、`res://.godot`、`res://.git`）
5. 点击 **Save**

> 也可在 Project Tab 直接点击 **Scan Settings** 按钮打开配置弹窗。

### 运行扫描

1. 切换到 **Project** Tab
2. 点击 **Rebuild Project**
3. 等待扫描完成，文件列表显示所有 `.gd` 文件及其被引用次数

### 查看跨文件关系

- 展开文件 → `→ references` 显示本文件调用了哪些其他文件的方法/信号
- 展开文件 → `← referenced by` 显示哪些文件引用了本文件的方法/信号

---

## 5. 图视图导航

主屏 "Analysis" Tab 提供交互式图视图。

### Scope 切换

| Scope | 说明 |
|-------|------|
| Current File | 当前打开文件的调用图/信号流图 |
| Project | 项目级文件耦合图 / 跨文件信号流图 |

### Graph 类型切换

| Graph | 说明 |
|-------|------|
| Call | 方法调用关系图。入口函数绿色 ▶ 标记，枢纽函数（度≥5）橙色 ● 标记 |
| Signal | 信号流图。emit 边红色，connect 边蓝色 |

### 工具栏

| 按钮 | 功能 |
|------|------|
| Re-layout | 自动整理节点布局 + 居中视图 |
| Min degree | 筛选：隐藏度数低于阈值的节点 |
| Export JSON | 导出 CodeGraph JSON 到文件 |

### 节点交互

- **点击节点** → 关联节点高亮，非关联节点淡化
- **双击节点** → 跳转到对应源码位置
- **图例** → 显示当前视图的颜色含义，随 Scope/Graph 切换自动更新

---

## 6. CodeGraph JSON 导出

导出结构化代码图谱供 AI agent 或外部工具消费。

1. 打开 Analysis Tab
2. 确保已完成项目扫描（Project 面板有数据）
3. 点击 **Export JSON**，选择保存路径
4. 导出 JSON 包含：
   - `summary` — 项目统计
   - `files` — 每个文件的函数/信号/变量/调用边/信号流/DefUse
   - `cross_file` — 跨文件调用/信号边
   - `hub` — 枢纽函数列表
   - `coupled` — 高耦合文件对

---

## 7. 常见问题

**Q: Project Tab 显示 "Project scan is OFF"？**
A: 点击 **Scan Settings** 按钮 → 勾选 Enable Project Scan → 添加扫描目录 → Save。

**Q: 分析结果不更新？**
A: 保存脚本会自动触发重新分析。也可手动 **Parse Current**。

**Q: 大型项目扫描很慢？**
A: 当前管道在 GDScript 中实现，分析 ~100 个文件约需数秒。性能优化参考 ADR-0002。

**Q: 图视图节点太多看不清？**
A: 使用 **Min degree** 筛选器隐藏低度数节点，或缩放/平移导航。
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/docs/user_guide_cn.md
git commit -m "docs: create user_guide_cn.md — Chinese user guide (topics 1+2)"
```

---

## Task 4: 创建 user_guide_en.md（英文用户指南）

**Files:** Create: `addons/gdscript_util/docs/user_guide_en.md`

- [ ] **Step 1: 写入英文用户指南**

```markdown
# GDScript AST Flow — User Guide

> Target: Godot 4.7+ | Language: English

## Table of Contents

1. [Installation & Setup](#1-installation--setup)
2. [Single-File Analysis](#2-single-file-analysis)
3. [Analysis Panels](#3-analysis-panels)
4. [Project Scan](#4-project-scan)
5. [Graph View Navigation](#5-graph-view-navigation)
6. [CodeGraph JSON Export](#6-codegraph-json-export)
7. [FAQ](#7-faq)

---

## 1. Installation & Setup

1. Copy the `addons/gdscript_util/` directory into your Godot project's `addons/` directory
2. Open Godot Editor, menu **Project → Project Settings → Plugins**
3. Find **GDScript Util**, check **Enable**
4. Bottom panel shows: **Summary / Call Graph / Signal Flow / Def-Use / Project** tabs

---

## 2. Single-File Analysis

Analyze the currently open `.gd` script:

1. Open any `.gd` file
2. Menu **Project → Tools → GDScript AST Flow → Parse Current**
3. Results appear immediately in the bottom panel

> Saving a script also triggers automatic re-analysis.

---

## 3. Analysis Panels

### Summary

Displays analysis summary for the current file: function count, signal count, variable count, call edges, errors.

### Call Graph

- Lists all call relationships by function: who calls whom (caller → callee)
- Edge type labels: `[self]`, `[super]`, `[ext]` (external object), `[connect]` (signal connection), `[emit]`
- Built-in functions (60+ like `print`, `range`) are automatically filtered out

### Signal Flow

- Lists all signal declarations in the file
- Each signal shows: declaration line, emit site list, connect site list

### Def-Use

- Lists all variables in the file
- Each variable shows: definition location, read site list, write site list

### Project

- Shows project scan results: file list + cross-file reference count per file
- Expand a file to see outbound references (→) and inbound references (←)

---

## 4. Project Scan

Scan all `.gd` files in your project (or specified directories) for cross-file analysis.

### Configure Scan Directories

1. Menu **Project → Tools → GDScript AST Flow → Scan Settings...**
2. Check **Enable Project Scan**
3. Click **Browse...** to select directories, add to Include list
4. To exclude directories, click **Browse...** in the Exclude section (defaults: `res://addons`, `res://.godot`, `res://.git`)
5. Click **Save**

> You can also click the **Scan Settings** button in the Project Tab.

### Run Scan

1. Switch to **Project** Tab
2. Click **Rebuild Project**
3. Wait for scan to complete — file list shows all `.gd` files with reference counts

### Explore Cross-File Relationships

- Expand file → `→ references` shows which other files' methods/signals this file calls
- Expand file → `← referenced by` shows which files reference this file's methods/signals

---

## 5. Graph View Navigation

The main screen "Analysis" Tab provides interactive graph views.

### Scope Switching

| Scope | Description |
|-------|-------------|
| Current File | Call graph / signal flow for the open file |
| Project | Project-level file coupling graph / cross-file signal flow |

### Graph Type Switching

| Graph | Description |
|-------|-------------|
| Call | Method call relationships. Entry functions marked green ▶, hubs (degree≥5) marked orange ● |
| Signal | Signal flow. Emit edges in red, connect edges in blue |

### Toolbar

| Button | Function |
|--------|----------|
| Re-layout | Auto-arrange nodes + center view |
| Min degree | Filter: hide nodes below degree threshold |
| Export JSON | Export CodeGraph JSON to file |

### Node Interaction

- **Click node** → Related nodes highlighted, unrelated nodes dimmed
- **Double-click node** → Jump to source code location
- **Legend** → Shows color meanings for current view, auto-updates on Scope/Graph switch

---

## 6. CodeGraph JSON Export

Export structured code graph for AI agent or external tool consumption.

1. Open Analysis Tab
2. Ensure project scan is complete (Project panel has data)
3. Click **Export JSON**, choose save path
4. Exported JSON includes:
   - `summary` — project statistics
   - `files` — per-file functions/signals/variables/calls/signal flow/def-use
   - `cross_file` — cross-file call/signal edges
   - `hub` — hub function list
   - `coupled` — highly coupled file pairs

---

## 7. FAQ

**Q: Project Tab shows "Project scan is OFF"?**
A: Click **Scan Settings** button → check Enable Project Scan → add directories → Save.

**Q: Analysis results not updating?**
A: Saving a script triggers auto re-analysis. You can also manually **Parse Current**.

**Q: Large project scan is slow?**
A: The current pipeline is implemented in GDScript. Analyzing ~100 files takes a few seconds. See ADR-0002 for performance optimization.

**Q: Too many nodes in graph view?**
A: Use the **Min degree** filter to hide low-degree nodes, or zoom/pan to navigate.
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/docs/user_guide_en.md
git commit -m "docs: create user_guide_en.md — English user guide (topics 1+2)"
```

---

## Task 5: 创建 dev_guide_cn.md（中文开发者指南）

**Files:** Create: `addons/gdscript_util/docs/dev_guide_cn.md`

- [ ] **Step 1: 写入中文开发者指南（上半篇：API 参考）**

```markdown
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

**文件**: `addons/gdscript_util/gds_tokenizer.gd`
**class_name**: `GDScriptTokenizer`

```
func tokenize(source: String) -> Array[GDScriptToken]
```

词法分析器。将 GDScript 源码字符串转换为 Token 列表。每个 Token 包含 `type`（种类）、`literal`（字面量）、`line`（行号）、`column`（列号）。

## API 3. GDScriptParser

**文件**: `addons/gdscript_util/gds_parser.gd`
**class_name**: `GDScriptParser`

```
var error: String                       # 非空表示解析失败

func parse(tokens: Array) -> ASTNode    # Token 列表 → AST 根节点
```

语法分析器。递归下降 + 运算符优先级（20 级）。支持 fail-soft 错误恢复——部分解析失败时继续解析剩余代码，错误收集到 `error` 属性。

## API 4. GDScriptSymbolResolver

**文件**: `addons/gdscript_util/gds_symbol_resolver.gd`
**class_name**: `GDScriptSymbolResolver`

```
func resolve(ast: ASTNode, file_path: String) -> GDScriptAnalysisResult
```

符号解析器。Visitor 模式遍历 AST，建立嵌套作用域符号表，检测 7 种调用模式，追踪信号 emit/connect，记录变量读写。结果封装在 `GDScriptAnalysisResult` 中。

## API 5. GDScriptAnalysisResult

**文件**: `addons/gdscript_util/gds_analysis_result.gd`
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

**文件**: `addons/gdscript_util/gds_call_graph.gd` · `gds_call_edge.gd`
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

**文件**: `addons/gdscript_util/gds_signal_graph.gd` · `gds_signal_info.gd` · `gds_site.gd`
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

**文件**: `addons/gdscript_util/gds_def_use_chain.gd` · `gds_def_use_info.gd` · `gds_def_use_site.gd`
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

**文件**: `addons/gdscript_util/editor/gds_project_analyzer.gd`
**class_name**: `GDScriptProjectAnalyzer`

```
func scan_project() -> Array[String]                        # 按 GDSScanConfig 配置扫描项目
func analyze_all() -> GDScriptProjectResult                 # 全量单文件分析（无跨文件解析）
func resolve_cross_file(p_result: GDScriptProjectResult)    # 第二遍：跨文件解析
func analyze_full() -> GDScriptProjectResult                # 完整入口：analyze_all() + resolve_cross_file()
```

## API 10. GDScriptProjectResult / GDSCrossFileEdge

**文件**: `addons/gdscript_util/gds_project_result.gd` · `gds_cross_file_edge.gd`
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

**文件**: `addons/gdscript_util/editor/gds_scan_config.gd`
**class_name**: `GDSScanConfig`

```
const SETTING_ENABLED := "gdscript_util/scan/enabled"
const SETTING_INCLUDE := "gdscript_util/scan/include"
const SETTING_EXCLUDE := "gdscript_util/scan/exclude"

static func is_enabled() -> bool
static func get_include_dirs() -> Array[String]
static func get_exclude_dirs() -> Array[String]
static func save_config(p_include: Array, p_exclude: Array = []) -> void
static func enable_scan() -> void
static func migrate_if_needed() -> void
```

## API 12. GDScriptUtil (plugin.gd)

**文件**: `addons/gdscript_util/plugin.gd`
**class_name**: `GDScriptUtil`（EditorPlugin 子类）

```
# 静态分析函数（插件内部使用，也可被其他插件调用）
static func analyze_script(p_path: String) -> GDScriptAnalysisResult

# 工具菜单
# GDScript AST Flow → Parse Current
# GDScript AST Flow → Scan Settings...
```

## API 13. GDSL10n

**文件**: `addons/gdscript_util/editor/gds_l10n.gd`
**class_name**: `GDSL10n`

```
const DOMAIN := "gdscript_util"

func setup() -> void                 # 加载 locales/ 目录下的 CSV 翻译资源
func t(p_key: String) -> String      # 翻译一个 key（当前语言）
func tf(p_key: String, p_args: Array) -> String  # 翻译 + 格式化
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
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/docs/dev_guide_cn.md
git commit -m "docs: create dev_guide_cn.md — Chinese dev guide (API ref + integration)"
```

---

## Task 6: 创建 dev_guide_en.md（英文开发者指南）

**Files:** Create: `addons/gdscript_util/docs/dev_guide_en.md`

- [ ] **Step 1: 写入英文开发者指南**

```markdown
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

Symbol resolver. Visitor pattern traversal over AST. Builds nested scope symbol table, detects 7 call patterns, tracks signal emit/connect, records variable reads/writes. Results wrapped in `GDScriptAnalysisResult`.

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

## API 7-8: Signal & Def-Use

See the Chinese dev_guide for full definitions. Key types:

- `GDScriptSignalGraph` / `GDScriptSignalInfo` / `GDScriptSite` — signal flow tracking
- `GDScriptDefUseChain` / `GDScriptDefUseInfo` / `GDScriptDefUseSite` — variable tracking

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
```

- [ ] **Step 2: 提交**

```bash
git add addons/gdscript_util/docs/dev_guide_en.md
git commit -m "docs: create dev_guide_en.md — English dev guide (API ref + integration)"
```

---

## Task 7: 最终验收

- [ ] **Step 1: 文件完整性检查**

```bash
ls -la readme.md readme.en.md
ls -la addons/gdscript_util/docs/user_guide_cn.md addons/gdscript_util/docs/user_guide_en.md
ls -la addons/gdscript_util/docs/dev_guide_cn.md addons/gdscript_util/docs/dev_guide_en.md
```

- [ ] **Step 2: 链接验证** — 确保 README 中的文档链接指向正确路径

- [ ] **Step 3: 代码示例验证** — dev_guide 中的 GDScript 代码片段语法正确、API 签名与源码一致

- [ ] **Step 4: 提交推送**

```bash
git add -A && git status --short
git commit -m "docs: finalize documentation completion — 6 bilingual docs"
git push
```

---

## 完成检查清单

- [ ] readme.md — 重写（中文）
- [ ] readme.en.md — 新建（英文）
- [ ] user_guide_cn.md — 新建（中文用户指南）
- [ ] user_guide_en.md — 新建（英文用户指南）
- [ ] dev_guide_cn.md — 新建（中文开发者指南）
- [ ] dev_guide_en.md — 新建（英文开发者指南）
- [ ] 所有文档内部链接正确
- [ ] 代码示例与当前 API 一致
- [ ] 文档推送至 origin/master
