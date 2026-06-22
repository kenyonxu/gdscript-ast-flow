# Graph Report - godot-byte-code-parser  (2026-06-22)

## Corpus Check
- 22 files · ~43,719 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 559 nodes · 547 edges · 30 communities (27 shown, 3 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `9ce05d26`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]

## God Nodes (most connected - your core abstractions)
1. `Phase 2 内部类提取 实现计划` - 19 edges
2. `Phase 3.3: 图可视化 设计规范` - 16 edges
3. `Phase 2: GDScript 符号解析器 设计规范` - 14 edges
4. `Phase 3: 编辑器集成 + 完整语法 设计规范` - 14 edges
5. `Phase 3.2: 跨文件分析 设计规范` - 13 edges
6. `TreeBase` - 13 edges
7. `Phase 2: GDScript 符号解析器 实现计划` - 11 edges
8. `_parse_expr(lv)` - 11 edges
9. `Phase 3.2: 跨文件分析 实现计划` - 10 edges
10. `Phase 3.3: 图可视化 实现计划` - 10 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Import Cycles
- None detected.

## Communities (30 total, 3 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.09
Nodes (28): ExprBase, ExprBinOp, ExprCallFunc, ExprConstant, ExprIdentifier, GDScriptASTParser (extends Node), TreeBase, TreeBlock (+20 more)

### Community 1 - "Community 1"
Cohesion: 0.10
Nodes (20): 4.1 边分类型着色（#1）, 4.2 节点带签名（#2）, 4.3 节点带位置（#3）, 4.4 信号图 emit/connect 分向（#4）, 4.5 入口函数标记（#5，P1）, 4.6 hover tooltip（#6，P1）, 4.7 低度数筛选（#7，P1）, 4.8 点节点跳转 + 关联边高亮（#8，P1） (+12 more)

### Community 2 - "Community 2"
Cohesion: 0.23
Nodes (13): parse(_token_list: Array), _parse_block(), _parse_class_block(indent), _parse_const(), _parse_enum(), _parse_expr(lv), _parse_for(), _parse_function() (+5 more)

### Community 3 - "Community 3"
Cohesion: 0.05
Nodes (43): 1.1 目标, 1.2 范围, 1.3 与 Phase 1 的关系, 2.1 入口与签名, 2.2 内部遍历架构, 2.3 文件规划, 3.1 SymbolTable — 嵌套作用域符号表, 3.2 CallGraph — 方法调用图 (+35 more)

### Community 4 - "Community 4"
Cohesion: 0.06
Nodes (31): 1. 哨兵值, 2. 匹配分发方式, 3. 内部类引用, 4. 旧版文件兼容, 5. 解析器 Bug 修复, 6. 文件结构差异, Chunk 1: Token 类型 + AST 节点定义, Chunk 2: 词法分析器 (+23 more)

### Community 11 - "Community 11"
Cohesion: 0.06
Nodes (34): 10.1 目标, 10.2 实现, 4.1 容器布局, 4.2 主面板 TabBar 结构, 4.3 信号中继桥（Bridge）, 4.3 模块化启动（Bootstrap）, 4.4 面板联动, 4.5 参考 LimboAI 的可视化经验 (+26 more)

### Community 12 - "Community 12"
Cohesion: 0.05
Nodes (37): 1.1 背景, 1.2 目标, 1.3 约束, 1.4 Phase 1 核心子集 — 语法覆盖精确定义, 2.1 管道架构, 2.2 文件规划, 2.3 错误处理策略, 3.1 Token 数据结构 (+29 more)

### Community 13 - "Community 13"
Cohesion: 0.06
Nodes (33): 1. 数据类架构, 2. AST 节点类型, 3. 方法调用图 — 前向引用, 4. connect 路由, 5. 表达式解析, 6. 其他 Bug 修复, 7. 文件结构差异, Chunk 1: 数据结构 + 框架 (+25 more)

### Community 14 - "Community 14"
Cohesion: 0.06
Nodes (31): 1. 面板架构（规范为 3 底部 tab + 右侧 Dock）, 2. Bridge 实现, 3. 验收中修复的关键 Bug, 4. f-string 简化, 5. 文件结构差异, Chunk A: 编辑器 UI 基础设施, Chunk B: 三个子面板 + 搜索工具, Chunk C: 语法覆盖 (+23 more)

### Community 15 - "Community 15"
Cohesion: 0.10
Nodes (19): Phase 2 内部类提取 实现计划, Task 10: 创建 GDScriptDefUseChain, Task 11: 重写 gds_analysis_result.gd, Task 12: 更新 gds_symbol_resolver.gd 引用, Task 13: 更新 plugin.gd 引用, Task 14: 更新 test_symbol_resolver.gd 引用, Task 15: 验收测试, Task 1: 创建 GDScriptSymbol (+11 more)

### Community 16 - "Community 16"
Cohesion: 0.10
Nodes (20): 4.1.1 作用域创建时机, 4.1.2 标识符解析流程, 4.1.3 变量声明处理, 4.1 作用域链, 4.2.1 CallNode 检测, 4.2.2 emit("sig") 检测, 4.2 调用图构建, 4.3.1 信号声明 (+12 more)

### Community 17 - "Community 17"
Cohesion: 0.12
Nodes (16): `.new()` 调用, Phase 2 内部类提取规范, Step 1: 创建 10 个独立文件, Step 2: 更新 `gds_analysis_result.gd`, Step 3: 更新 `gds_symbol_resolver.gd`, Step 4: 更新 `plugin.gd`, Step 5: 更新 `tests/test_symbol_resolver.gd`, Step 6: 验收 (+8 more)

### Community 18 - "Community 18"
Cohesion: 0.05
Nodes (36): 4.1 数据流, 5.1 EditorPlugin 主屏, 5.2 主屏布局, 6.1 节点, 6.2 边, 6.3 度数驱动, 7.1 节点, 7.2 边 (+28 more)

### Community 19 - "Community 19"
Cohesion: 0.25
Nodes (6): 仓库, 开发命令, 架构：三阶段管道, 语言, 项目概述, 项目结构

### Community 20 - "Community 20"
Cohesion: 0.07
Nodes (29): 3.1 分析流程, 3.2 增量分析, 4.1 类型表（加到 GDScriptAnalysisResult）, 4.2 跨文件边, 4.3 项目结果容器, 5.1 类型来源（静态可知）, 5.2 解析 `obj.method()`, 5.3 解析 `obj.connect("sig", cb)` / `obj.emit("sig")` (+21 more)

### Community 21 - "Community 21"
Cohesion: 0.25
Nodes (8): 6.1 结果容器, 6.2 使用方式, 6.3.1 插件生命周期, 6.3.2 分析触发方式, 6.3.3 结果呈现, 6.3.4 缓存策略, 6.3 EditorPlugin 集成, 六、组件 4：GDScriptAnalysisResult + EditorPlugin

### Community 22 - "Community 22"
Cohesion: 0.40
Nodes (4): Author, Documents, GDScript Parsers for Godot Engine 3.4, License

### Community 23 - "Community 23"
Cohesion: 0.07
Nodes (29): 1. resolver 缺 `obj.signal.connect(cb)` 分支（验收修复）, 2. parser extends/class_name 顺序（验收修复）, 3. Project tab 边方向, 4. 增量实现简化, Chunk A: 数据结构, Chunk B: 项目分析器, Chunk C: Bridge 集成 + 增量, Chunk D: UI (+21 more)

### Community 24 - "Community 24"
Cohesion: 0.08
Nodes (24): 1. 主屏容器基类 + 铺满（验收修复）, 2. Project view 按 kind 分支（验收修复）, 3. 点节点跳转推迟, Chunk A: 度数数据, Chunk B: 图节点 + 主屏容器, Chunk C: 三个图视图 builder, Chunk D: 主屏集成, Chunk E: 验收 (+16 more)

### Community 25 - "Community 25"
Cohesion: 0.17
Nodes (11): ADR-0001: 暂缓 C# 重写，先 Profile 再决定, C# 重写预期收益, 关键前提（冷水）, 决策, 参考, 当前优先级, 背景, 触发条件（何时重新评估） (+3 more)

### Community 26 - "Community 26"
Cohesion: 0.12
Nodes (16): Chunk P0: 高价值低成本, Chunk P1: 中价值, Chunk 验收, Task P0-1: GDSGraphNode 扩展 — 签名/位置/tooltip/入口标记, Task P0-2: 创建 GDS_EntryMethods — 引擎入口集合, Task P0-3: 调用图视图 — 签名/位置/着色, Task P0-4: 信号图视图 — emit/connect 双 slot 分色分向, Task P0-5: 项目图视图 — 签名/位置 (+8 more)

### Community 27 - "Community 27"
Cohesion: 0.13
Nodes (14): 3.1 虚拟化数据流, 3.2 GDSVirtualGraphEdit, 3.3 滚动/缩放触发, 3.4 缩放聚合, 一、目标, 七、优先级说明, 三、架构, 不做： (+6 more)

### Community 28 - "Community 28"
Cohesion: 0.13
Nodes (14): 4.1 推断流程, 4.2 GDS_TypeInferrer, 4.3 返回类型表预建, 一、目标, 七、风险, 三、为什么是 L1（务实边界）, 不做（L2+ 复杂，后续）：, 二、范围 (+6 more)

### Community 29 - "Community 29"
Cohesion: 0.15
Nodes (12): 4.1 内置函数表, 4.2 resolver 过滤, 一、目标, 七、风险, 三、数据来源, 不做：, 二、范围, 五、交付物 (+4 more)

## Knowledge Gaps
- **396 isolated node(s):** `项目概述`, `仓库`, `项目结构`, `架构：三阶段管道`, `开发命令` (+391 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Phase 2: GDScript 符号解析器 设计规范` connect `Community 3` to `Community 16`?**
  _High betweenness centrality (0.011) - this node is a cross-community bridge._
- **Why does `四、解析策略` connect `Community 16` to `Community 3`?**
  _High betweenness centrality (0.006) - this node is a cross-community bridge._
- **Why does `GDScript 解析器 Godot 4.7 重写规范` connect `Community 12` to `Community 21`?**
  _High betweenness centrality (0.006) - this node is a cross-community bridge._
- **What connects `项目概述`, `仓库`, `项目结构` to the rest of the system?**
  _396 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.0873015873015873 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.09523809523809523 - nodes in this community are weakly interconnected._
- **Should `Community 3` be split into smaller, more focused modules?**
  _Cohesion score 0.045454545454545456 - nodes in this community are weakly interconnected._