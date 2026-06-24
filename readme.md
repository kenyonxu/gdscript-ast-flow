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
