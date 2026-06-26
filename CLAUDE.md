# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

**gdscript-ast-flow** — Godot Engine 4.7 用 GDScript AST 解析 + 逻辑流分析工具。以 EditorPlugin 形式集成，支持信号连接追踪、方法调用图、变量定义-使用链分析。

- **作者**: 原版 あるる / きのもと 結衣 @arlez80（Godot 3.x 字节码解析器） · 本版 kenyonxu（Godot 4.7 AST 重写）
- **许可**: MIT
- **目标引擎**: Godot Engine 4.7

## 仓库

- **GitHub**: `https://github.com/kenyonxu/gdscript-ast-flow`
- **本地**: `git@github.com:kenyonxu/gdscript-ast-flow.git`

## 项目结构

```
addons/gdscript_ast/
├── plugin.cfg                   # 插件配置 (v2.1.0)
├── plugin.gd                    # EditorPlugin 入口 (class_name: GDScriptUtil)
├── gds_ast_nodes.gd             # Token.Type 枚举 + AST 节点类
├── gds_tokenizer.gd             # 词法分析器
├── gds_parser.gd                # 语法分析器（递归下降，含表达式后缀 + 错误恢复）
├── gds_symbol_resolver.gd       # 符号解析器
├── gds_analysis_result.gd       # 单文件分析结果
├── gds_tscn_parser.gd           # .tscn 场景解析器（含 instance 子场景展开）
├── gds_tres_parser.gd           # .tres 资源解析器
├── gds_scene_resource_result.gd # 场景/资源数据模型 + 结果容器
├── gds_project_result.gd        # 项目级结果（scenes/resources/cross_file 边 + CodeGraph JSON）
├── gds_cross_file_edge.gd       # 跨文件边（CALL/SIGNAL_CONNECT/SCRIPT_ATTACH 等）
├── editor/
│   ├── gds_project_analyzer.gd  # 项目级分析器（扫描 + 集成 + uid_map + include 优先 exclude）
│   ├── gds_analysis_bridge.gd   # 分析桥（单文件实时 + 项目批量）
│   ├── gds_editor_bootstrap.gd  # 插件启动编排（底部面板 + 主屏 + 焦点跟随）
│   ├── gds_graph_main_screen.gd # 主屏（代码分析 Scope×Graph + 场景 mode 切换）
│   ├── gds_scan_config.gd       # 扫描配置（ProjectSettings 持久化 + include/exclude）
│   ├── gds_l10n.gd              # 本地化（中英）
│   ├── graphs/                  # GraphEdit 渲染（节点 + 虚拟化 + 布局）
│   ├── panels/                  # 底部面板（Summary/Call/Signal/DefUse/Project + ScanSettings 对话框）
│   └── scene/                   # 场景可视化（v2.1 新增）
│       ├── gds_scene_main_screen.gd    # 场景模式容器（3 视角 + 联动）
│       ├── scene_node_tree_view.gd     # 节点树视角
│       ├── scene_script_lookup_view.gd # 脚本反查视角
│       └── scene_signal_graph_view.gd  # 信号图视角
└── tests/
    └── test_*.gd                # 多套验收测试（parser/symbol/cross_file/graph/tscn_tres/scene_main_screen/parser_syntax）

docs/superpowers/
├── specs/                       # 设计规范（parser/tscn_tres/scene_main_screen 等）
└── plans/                       # 实现计划（对应 spec）
```

## 架构：三阶段管道

```
.gd 源码  →  [GDScriptTokenizer]  →  Token列表  →  [GDScriptParser]  →  AST  →  [GDScriptSymbolResolver]  →  AnalysisResult
```

- **Phase 1-3**（已完成）：Tokenizer + Parser + SymbolResolver + EditorPlugin 集成 + 跨文件分析 + 图可视化
- **tscn/tres 解析**（已完成）：.tscn/.tres 解析 + CodeGraph JSON v2 + instance 子场景展开
- **场景可视化**（v2.1，已完成）：主屏「场景」mode + 三视角（节点树/脚本反查/信号图）+ 视角联动
- **解析器语法增强**（v2.1，已完成）：表达式后缀 + `%Node` + 分号 + extends 字符串 + true/false + 行续接 + 错误恢复

详细设计参考 `docs/superpowers/specs/2026-06-20-godot47-gdscript-parser-design.md`。
实现计划参考 `docs/superpowers/plans/2026-06-20-phase1-gdscript-parser.md`。

## 开发命令

本项目为 Godot 4.7 插件，没有传统 CLI 构建/测试命令。开发流程：

1. 在 Godot 4.7 编辑器中打开此项目作为 Godot 项目（需要 `project.godot` 文件）
2. 编辑 `addons/` 下的 `.gd` 文件
3. 通过编辑器 工具菜单 → "GDScript Analysis – Parse Current" 触发分析
4. 运行 `tests/test_parser.gd` 场景验证 10 个验收测试

## GDScript 编码注意事项

- **关键字勿作标识符**：GDScript 关键字不可作变量名或参数名，编辑器会报错。常见关键字：`class_name`、`extends`、`signal`、`func`、`var`、`const`、`enum`、`if`、`else`、`elif`、`for`、`while`、`return`、`match`、`pass`、`break`、`continue`、`and`、`or`、`not`、`in`、`is`、`as`、`self`、`super`、`static`、`await`、`preload`、`tool`、`breakpoint`。
  - 典型坑：遍历 class_registry 时 `for class_name in ...` → `class_name` 是关键字，编辑器报错；改 `for cls_name in ...`（见 commit `79461fe`，`addons/gdscript_ast/editor/gds_project_analyzer.gd::_resolve_script_path`）
  - 解析 `.tscn`/`.tres` header 时，`class_name`/`extends` 等作为**字符串键**使用是安全的（`params.get("class_name")`），但作变量名不行

## 语言

所有与用户的交互及代码注释应使用**中文**。
