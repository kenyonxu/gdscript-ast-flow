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

1. 将 `addons/gdscript_ast/` 目录复制到你 Godot 项目的 `addons/` 目录下
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
