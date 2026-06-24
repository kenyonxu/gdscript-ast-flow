# GDScript AST Flow

[![MIT License](https://img.shields.io/badge/license-MIT-green)](LICENSE.txt)
[![爱发电](https://img.shields.io/badge/赞助-爱发电-ff69b4?style=flat-square)](https://afdian.com/a/kai2045)
[![PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?style=flat-square&logo=paypal)](https://www.paypal.com/paypalme/kai2045)

📖 **文档**：[English](README.en.md) · [用户指南](addons/gdscript_util/docs/user_guide_cn.md) · [User Guide](addons/gdscript_util/docs/user_guide_en.md) · [开发者指南](addons/gdscript_util/docs/dev_guide_cn.md) · [Developer Guide](addons/gdscript_util/docs/dev_guide_en.md)

Godot 4.7 GDScript AST 解析 + 逻辑流分析工具。以 EditorPlugin 形式集成，支持信号连接追踪、方法调用图、变量定义-使用链分析、跨文件引用。

**作者**：原版 あるる / きのもと 結衣 @arlez80（Godot 3.x 字节码解析器） · 本版 kenyonxu（Godot 4.7 AST 重写）

---

## 能帮你做什么？

### 🎮 游戏开发者

- **重构前心中有数** — 改一个函数名之前，一眼看清谁在调用它、改了会影响到谁
- **调试信号地狱** — `health_changed` 到底在哪 emit 的？谁 connect 了？信号流面板把整条链路画给你看
- **追踪变量流向** — "这个变量的值什么时候被改了？" Def-Use 面板列出所有读写位置
- **读懂遗留代码** — 接手别人的项目，用项目扫描 + 调用图快速建立代码心智模型
- **导出给 AI 消费** — 一键导出 CodeGraph JSON，让 Claude/其他 AI 直接读懂你的代码结构

### 🔌 插件开发者

- **分析任何 GDScript 项目** — 作为其他插件的分析后端，读源码、跑管道、拿结构化结果
- **构建可视化编程工具** — 用调用图自动生成蓝图节点 + 连线
- **自动生成文档** — 遍历函数列表 + 调用关系，一键输出 API 文档
- **跨文件依赖分析** — 追踪 class_name 引用，理解大型插件/框架的模块耦合

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
