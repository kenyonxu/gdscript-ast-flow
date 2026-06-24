# 文档补完设计规范

> 日期: 2026-06-24 | 状态: 设计中 | 依赖: 全部功能阶段 (已完成)
> 参考: clef-dev/addons/clef/docs/ 文档结构

## 一、目标

为 gdscript-ast-flow 建立面向用户的完整文档体系，参考 clef-dev 的中英双语结构，覆盖从安装到高级集成的全部使用场景。

**核心问题：**
- 当前只有 CLAUDE.md（AI 代理向）和 readme.md（344 字节），无面向用户文档
- 用户无法知道插件能做什么、怎么用
- 插件开发者无法了解如何复用分析管道

## 二、文档结构

```
README.md                                    # 项目首页（中文）
README.en.md                                 # Project homepage (English)
addons/gdscript_util/docs/
  user_guide_cn.md                           # 用户指南（议题 1+2）
  user_guide_en.md                           # User Guide (topics 1+2)
  dev_guide_cn.md                            # 开发者指南（议题 3+4）
  dev_guide_en.md                            # Developer Guide (topics 3+4)
```

**设计原则：**
- 三文档制：README + user_guide + dev_guide
- 用户只需看 user_guide 覆盖全部日常使用
- 开发者只需看 dev_guide 覆盖 API 参考 + 集成模式
- 每份文档均中英双语（文件名 `*_cn.md` / `*_en.md`）

## 三、各文档内容

### 3.1 README.md / README.en.md

**定位**：项目首页，面向所有访问者

| 章节 | 内容 |
|------|------|
| 特性列表 | 三阶段管道、调用图、信号流、Def-Use 链、跨文件分析、图可视化、JSON 导出 |
| 快速开始 | 安装插件 → 工具菜单 → 单文件分析 → 查看结果 |
| 截图/动图 | 分析面板 + 图视图截图 |
| 文档导航 | 链接到 user_guide 和 dev_guide |
| 许可/作者 | MIT License，作者信息 |

### 3.2 user_guide_cn.md / user_guide_en.md

**定位**：游戏开发者日常使用指南（议题 1+2）

| 章节 | 内容 | 对应议题 |
|------|------|----------|
| 安装与启用 | 复制 addons 目录、启用插件 | 议题 1 |
| 单文件分析 | `GDScript AST Flow → Parse Current`，理解 Summary/Call Graph/Signal Flow/Def-Use 面板 | 议题 1 |
| 项目扫描 | `Scan Settings...` 配置目录 → `Rebuild Project` → Project 面板文件列表 + 跨文件引用 | 议题 2 |
| 图视图导航 | Scope（单文件/项目）× Graph（调用/信号）切换、Min degree 筛选、节点跳转定义、Re-layout、导出 JSON | 议题 2 |
| CodeGraph 导出 | Export JSON 按钮 → AI agent 可消费的结构化代码图谱 | 议题 2 |
| 常见问题 | 扫描 OFF 怎么开、分析结果不更新、大项目性能 | — |

### 3.3 dev_guide_cn.md / dev_guide_en.md

**定位**：插件开发者 API 参考 + 集成指南（议题 3+4）

#### 上半篇：API 参考

| 章节 | 类/模块 | 内容 |
|------|---------|------|
| 三阶段管道 | — | 架构概览图：源码 → Tokenizer → Parser → SymbolResolver → AnalysisResult |
| 词法分析 | `GDScriptTokenizer` | `tokenize(source: String) → Array[GDScriptToken]` |
| 语法分析 | `GDScriptParser` | `parse(tokens: Array) → ASTNode`，error 属性 |
| AST 节点 | `gds_ast_nodes.gd` | ASTNode 基类、主要节点类型（ClassNode, FunctionNode, CallNode 等） |
| 符号解析 | `GDScriptSymbolResolver` | `resolve(ast: ASTNode, file_path: String) → GDScriptAnalysisResult` |
| 结果容器 | `GDScriptAnalysisResult` | 属性列表：symbol_table, call_graph, signal_graph, def_use_chain, errors, type_table |
| 调用图 | `GDScriptCallGraph` / `GDScriptCallEdge` | 边类型枚举（SELF/SUPER/EXTERNAL/CONNECT/EMIT 等） |
| 信号流 | `GDScriptSignalGraph` / `GDScriptSignalInfo` / `GDScriptSite` | 信号声明 → emit → connect 链路 |
| Def-Use 链 | `GDScriptDefUseChain` / `GDScriptDefUseInfo` / `GDScriptDefUseSite` | 变量定义-读取-写入追踪 |
| 项目分析 | `GDScriptProjectAnalyzer` | `scan_project()`, `analyze_all()`, `analyze_full()`, `resolve_cross_file()` |
| 项目结果 | `GDScriptProjectResult` | files, class_registry, cross_edges, to_dict(), export_json() |
| 扫描配置 | `GDSScanConfig` | `is_enabled()`, `get_include_dirs()`, `get_exclude_dirs()`, `save_config()`, `enable_scan()` |
| 跨文件边 | `GDSCrossFileEdge` | Kind 枚举（CALL/SIGNAL_CONNECT/SIGNAL_EMIT），source_file → target_file |
| 本地化 | `GDSL10n` | `setup()`, `t(key)`，如何使用自定义域 |

#### 下半篇：集成模式（议题 4）

| 章节 | 内容 |
|------|------|
| 集成概览 | gdscript-ast-flow 作为分析后端的定位：输入 `.gd` 源码 → 输出结构化分析结果 |
| 模式 1：分析单个脚本 | 调 `GDScriptUtil.analyze_script(path) → GDScriptAnalysisResult`，消费调用图/信号流 |
| 模式 2：批量分析项目 | 调 `GDScriptProjectAnalyzer.analyze_full() → GDScriptProjectResult`，消费跨文件图谱 |
| 模式 3：消费 CodeGraph JSON | `export_json()` 输出 → 外部工具/AI agent 读取 |
| 模式 4：扩展分析管道 | 在 SymbolResolver 之后再插入自定义分析器 |
| 案例：可视化编程插件集成 | 示例代码：如何使用 CallGraph 生成节点编辑器连线、如何用 type_table 做类型推断补全 |
| 案例：文档生成器集成 | 示例代码：如何使用分析结果自动生成 API 文档 |
| 最佳实践 | 缓存分析结果、增量更新、错误处理 |

## 四、文档风格约定

| 约定 | 说明 |
|------|------|
| 中英双语 | `_cn.md` / `_en.md` 后缀，内容独立翻译，非逐句对照 |
| 代码示例 | 最小可运行片段，注释用文档语言 |
| API 文档格式 | 方法签名 + 参数说明 + 返回值 + 使用场景一句话 |
| Godot 版本 | 标注 "Godot 4.7+" |

## 五、交付物

| 文件 | 类型 | 说明 |
|------|------|------|
| `README.md` | 重写 | 项目首页（中文） |
| `README.en.md` | 新建 | Project homepage (English) |
| `addons/gdscript_util/docs/user_guide_cn.md` | 新建 | 用户指南（中文） |
| `addons/gdscript_util/docs/user_guide_en.md` | 新建 | User Guide (English) |
| `addons/gdscript_util/docs/dev_guide_cn.md` | 新建 | 开发者指南（中文） |
| `addons/gdscript_util/docs/dev_guide_en.md` | 新建 | Developer Guide (English) |

## 六、验收标准

- [ ] README 包含特性列表 + 快速开始 + 文档导航
- [ ] user_guide 覆盖安装、单文件分析、项目扫描、图导航、导出（全流程）
- [ ] dev_guide 上半篇列出所有 public class 的 API 签名
- [ ] dev_guide 下半篇提供至少 2 个集成模式代码示例
- [ ] 中英双语各 3 份文档内容完整
- [ ] 所有代码示例经过实际测试可运行
- [ ] 文档导航链接互相正确指向

## 七、风险

| 风险 | 缓解 |
|------|------|
| API 文档与代码不同步 | dev_guide 中的 API 签名直接摘录源码，标注版本日期 |
| 翻译质量不一致 | 中文版先写，英文版基于中文版翻译（非机翻） |
| 截图需要 Godot 运行环境 | 截图统一 1920×1080，编辑器英文界面 |
