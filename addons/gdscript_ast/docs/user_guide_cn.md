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

**v2.2 新增**：
- **未使用函数高亮**：入度为 0 的函数灰色 + `[UNUSED]` 标注（`_` 前缀私有函数排除）
- **双击跳转**：双击 caller 顶层项 → 跳自身定义；双击 edge → 跳 callee 定义
- **跨文件 callee 跳转**：右键 `obj.method()` edge → Jump to Definition，经 type_table + class_registry 跳到外部类文件
- **signal emit/connect 跳转**：右键 `health_changed` edge → 跳 signal 定义（函数表查不到时回退查 signal_graph）
- **跨文件 callee 文件名**：跨文件 edge 显示 `[player.gd] → take_damage()`（type_table → class_registry 推断）

### Signal Flow

- 列出文件中所有 signal 声明
- 每个 signal 显示：声明行、emit 位置列表、connect 位置列表

**v2.2 新增**：
- **搜索栏**：顶部 LineEdit 实时过滤信号名
- **site 双击跳转 + 右键菜单**：双击 EMIT/CONNECT 行 → 跳源码；右键菜单（跳转 / 复制 `脚本:行` / 选中信号）
- **未连接信号高亮**：declared 但 0 emit + 0 connect → 灰色（`_` 前缀排除）
- **site 行粒度**：显示信号名 + 参数（emit）/ 回调（connect），格式如 `EMIT health_changed(100, 90) @L10 in attack()` / `CONNECT health_changed → _on_player_hit @L8`
- **跨文件类型名/文件名**：site 前缀 `[Player]`（type_table）或 `[player.gd]`（class_registry，需项目分析）

### Def-Use

- 列出文件中所有变量
- 每个变量显示：定义位置、读取位置列表、写入位置列表

**v2.2 新增**：
- **site 双击跳转 + 右键菜单**：双击 DEF/READ/WRITE 行 → 跳源码；右键菜单（跳转 / 复制 / 选中变量）
- **未使用变量分级高亮**：完全未用（0 read + 0 write）→ 灰色 + `UNUSED`；只写不读 → 品红 + `WRITE-ONLY`（`_` 前缀排除）
- **site 脚本来源**：site 行显示 `函数名() [脚本名.gd]`
- **参数显示 param**：参数 Kind 列显示 `param`（is_parameter 标志），区别于 `var/const`
- **类作用域显示**：类作用域变量的 enclosing_function 显示 `<class>`
- **跨文件变量追踪**（核心）：本文件定义的 field 被其他文件 `obj.field` 读写 → 青色行显示跨文件 site（如 `enemy.gd → attack()`）。需项目分析（VARIABLE_ACCESS cross edge）

### Project

- 显示项目扫描结果：文件列表 + 每个文件的跨文件引用数
- 展开文件可看到出向引用（→）和入向引用（←）

**v2.2 新增**：跨文件边现在包含 VARIABLE_ACCESS（`obj.field` 读写），出向/入向引用会显示跨文件变量访问。

### 公共 UI（v2.2 新增）

- **tab 旁文件名**：TabBar 右侧显示当前分析文件名（`clip_tabs=false` 让 5 个 tab 全部显示）
- **颜色图例**：文件名旁 `[?]` 按钮，点击 inline 展开/收起当前 tab 的颜色图例（色块 + 标签）；切换 tab 时图例内容自动更新

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

主屏 "Flow Visualizer" Tab 提供交互式图视图。

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
| 🔒 Lock | 锁定后点击/双击节点不跳转脚本编辑器（录屏/浏览时用）。绿=解锁，红=锁定 |

### 节点交互

- **点击节点** → 关联节点高亮，非关联节点淡化
- **双击节点** → 跳转到对应源码位置（锁定状态下只高亮不跳转）
- **图例** → 显示当前视图的颜色含义，随 Scope/Graph 切换自动更新

---

## 场景可视化（v2.1 新增）

场景模式可视化 `.tscn`/`.tres` 文件的结构 —— 节点树、脚本反查、信号连接图。

### 进入场景模式

1. 切到主屏 "Flow Visualizer" Tab
2. 顶部 toolbar 切换 mode：**[代码分析 | 场景]**
3. 选「场景」进入场景模式（三视角）

### 节点树视角

- **左栏**：场景列表（所有扫描到的 `.tscn`）
- **中间**：选中场景的节点树（可展开/折叠，挂脚本节点带 📜，instance 节点带 📦）
- **右栏**：选中节点的详情（type / script / groups / 信号连接）
- **点 script** → 跳转脚本编辑器
- **instance 节点**自动展开子场景结构（递归解析 `instance=ExtResource(...)`，继承 type/script + 合并子节点）

### 脚本反查视角

- **左栏**：脚本聚合列表（所有被场景引用的 `.gd`，按引用数排序）
- **右栏**：选中脚本的跨场景挂载点（哪些场景的哪些节点挂了它）
- **点挂载条目** → 跳节点树视角并定位该节点

### 信号图视角

- 节点间信号连接的 GraphEdit 图（同场景边蓝、跨场景边橙）
- **顶部下拉**：选单个场景只看该场景的连接（或「全部场景」）
- **中键拖动**平移、滚轮缩放
- **双击节点** → 跳节点树视角定位
- 顶部搜索框按信号名/节点名过滤

### 扫描配置（场景数据来源）

场景数据来自项目扫描。若场景列表空：
1. 菜单 **Project → Tools → GDScript AST Flow → Scan Settings...**
2. 勾选 **Enable Project Scan**
3. include 默认 `res://`（全项目），可在对话框调整；exclude 默认 `addons`
4. **include 优先于 exclude**（支持 `exclude res://addons` + `include res://addons/某插件`）

---

## 6. CodeGraph JSON 导出

导出结构化代码图谱供 AI agent 或外部工具消费。

1. 打开 Flow Visualizer Tab
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
