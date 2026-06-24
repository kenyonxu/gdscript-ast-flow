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
addons/gdscript_util/
├── plugin.cfg                   # 插件配置 (v2.0.0)
├── plugin.gd                    # EditorPlugin 入口 (class_name: GDScriptUtil)
├── gds_bc_parser.gd             # [legacy] 3.4 字节码解析器 (class_name: GDScriptByteCodeParser)
├── gds_ast_parser.gd            # [legacy] 3.4 AST 解析器 (class_name: GDScriptASTParser)
├── gds_ast_nodes.gd             # [plan] Token.Type 枚举 + AST 节点类定义
├── gds_tokenizer.gd             # [plan] 词法分析器 (class_name: GDScriptTokenizer)
├── gds_parser.gd                # [plan] 语法分析器 (class_name: GDScriptParser)
├── gds_symbol_resolver.gd       # [plan] 符号解析器 (class_name: GDScriptSymbolResolver)
├── gds_analysis_result.gd       # [plan] 结果容器 (class_name: GDScriptAnalysisResult)
└── tests/
    └── test_parser.gd           # [plan] Phase 1 验收测试

docs/superpowers/
├── specs/
│   └── 2026-06-20-godot47-gdscript-parser-design.md   # 完整设计规范
└── plans/
    └── 2026-06-20-phase1-gdscript-parser.md           # Phase 1 实现计划
```

## 架构：三阶段管道

```
.gd 源码  →  [GDScriptTokenizer]  →  Token列表  →  [GDScriptParser]  →  AST  →  [GDScriptSymbolResolver]  →  AnalysisResult
```

- **Phase 1 (当前目标)**: 完成 Tokenizer + Parser，源码 → AST
- **Phase 2**: SymbolResolver，AST → 符号表 + 调用图 + 信号图 + DefUseChain
- **Phase 3**: EditorPlugin 完整集成 + 完整语法 + 性能优化

详细设计参考 `docs/superpowers/specs/2026-06-20-godot47-gdscript-parser-design.md`。
实现计划参考 `docs/superpowers/plans/2026-06-20-phase1-gdscript-parser.md`。

## 开发命令

本项目为 Godot 4.7 插件，没有传统 CLI 构建/测试命令。开发流程：

1. 在 Godot 4.7 编辑器中打开此项目作为 Godot 项目（需要 `project.godot` 文件）
2. 编辑 `addons/` 下的 `.gd` 文件
3. 通过编辑器 工具菜单 → "GDScript Analysis – Parse Current" 触发分析
4. 运行 `tests/test_parser.gd` 场景验证 10 个验收测试

## 语言

所有与用户的交互及代码注释应使用**中文**。
